import Foundation
import SwiftData

/// Camera destination receipts describe local custody, never remote upload success.
@MainActor
enum StagedPhotoDestinations {
    typealias CurrentAccount = @Sendable () -> CaptureAccountIdentity?

    static func requireAccount(_ account: CaptureAccountIdentity, currentAccount: CurrentAccount = { CaptureAccountIdentity.current() }) throws {
        guard !Task.isCancelled, currentAccount() == account else { throw CancellationError() }
    }

    static func loadDraftCaptures(_ draft: ProjectPhotoFormDraft, store: DurableCaptureStore = .shared) async throws -> [RetainedCaptureRecovery] {
        let retained = try await store.retainedBatches(owner: draft.owner)
        var results: [RetainedCaptureRecovery] = []
        for id in Set(draft.batchIDs).union(retained.map(\.id)).sorted() {
            results.append(try await store.retainedRecovery(batchID: id, owner: draft.owner))
        }
        return results
    }
    /// The caller inserts this operation before saving its new Project, so
    /// termination cannot leave a photo draft pointing at an unqueued parent.
    static func ensureParentCreate(project: Project, dto: SupabaseProjectDTO, context: ModelContext) throws -> SyncOperation {
        guard dto.id.lowercased() == project.id.lowercased(), dto.companyId.lowercased() == project.companyId.lowercased() else { throw CaptureStagingError.invalidIdentity }
        let id = project.id.lowercased()
        let operations = try context.fetch(FetchDescriptor<SyncOperation>(predicate: #Predicate { $0.entityId == id && $0.entityType == "project" && $0.operationType == "create" }))
        if let existing = operations.first {
            let previous = try JSONDecoder().decode(SupabaseProjectDTO.self, from: existing.payload)
            guard previous.companyId.lowercased() == project.companyId.lowercased(), previous.id.lowercased() == id else { throw CaptureStagingError.invalidIdentity }
            return existing
        }
        let payload = try JSONEncoder().encode(dto)
        guard let fields = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw CaptureStagingError.writeFailed }
        let operation = SyncOperation(entityType: "project", entityId: id, operationType: "create", payload: payload, changedFields: Array(fields.keys), priority: 0)
        context.insert(operation)
        return operation
    }

    static func requireParentCustody(project: Project, context: ModelContext) throws {
        if project.lastSyncedAt != nil { return }
        let id = project.id.lowercased()
        let operations = try context.fetch(FetchDescriptor<SyncOperation>(predicate: #Predicate { $0.entityId == id && $0.entityType == "project" && $0.operationType == "create" }))
        guard operations.contains(where: { operation in
            guard let dto = try? JSONDecoder().decode(SupabaseProjectDTO.self, from: operation.payload) else { return false }
            return dto.id.lowercased() == id && dto.companyId.lowercased() == project.companyId.lowercased()
        }) else { throw CaptureStagingError.writeFailed }
    }

    /// A partially completed form transfer may already have a ProjectPhoto row.
    /// Discarding the remaining form draft must preserve those model-owned bytes.
    static func unclaimedDraftItems(_ batch: StagedCaptureBatch, context: ModelContext) throws -> Set<String> {
        let owned = ModelContext(context.container)
        var disposable = Set<String>()
        for item in batch.items {
            let id = item.id
            let rows = try owned.fetch(FetchDescriptor<ProjectPhoto>(predicate: #Predicate { $0.id == id }))
            if rows.isEmpty { disposable.insert(id) }
        }
        return disposable
    }

    /// A durable capture receipt names the destination it was shot for. A
    /// task-scoped batch appends `#task:<id>` so a batch recovered after the app
    /// died still knows which task it documents — the task cannot be re-derived
    /// from anything else once the camera screen is gone.
    static func owner(companyID: String, userID: String, kind: String, id: String, taskID: String? = nil) -> StagedCaptureOwner {
        var contextID = "\(kind):\(id.lowercased())"
        if let taskID = ProjectPhotoTaskLink.canonical(taskID) {
            contextID += "#task:\(taskID)"
        }
        return StagedCaptureOwner(companyID: companyID, userID: userID, contextID: contextID)
    }

    /// A project capture destination, read back out of a durable owner context.
    struct ProjectCaptureContext: Equatable {
        /// `project` or `project-draft`.
        let kind: String
        let projectID: String
        /// The task this batch documents, or nil for a whole-project batch.
        let taskID: String?

        var contextID: String {
            var value = "\(kind):\(projectID)"
            if let taskID { value += "#task:\(taskID)" }
            return value
        }
    }

    /// The inverse of `owner(companyID:userID:kind:id:taskID:)`. Returns nil for
    /// any context this screen does not own — a lead capture, a malformed
    /// journal, an empty id — so a foreign batch can never be accepted into a
    /// project.
    static func parseProjectContext(_ contextID: String) -> ProjectCaptureContext? {
        let lowered = contextID.lowercased()
        var head = lowered
        var taskID: String?
        if let marker = lowered.range(of: "#task:") {
            head = String(lowered[lowered.startIndex..<marker.lowerBound])
            let tail = String(lowered[marker.upperBound...])
            guard !tail.isEmpty, !tail.contains("#") else { return nil }
            taskID = tail
        }
        // Longest prefix first: `project:` is a prefix of nothing here, but
        // `project-draft:` must not be read as `project` + `-draft:…`.
        for kind in ["project-draft", "project"] {
            let prefix = "\(kind):"
            guard head.hasPrefix(prefix) else { continue }
            let projectID = String(head.dropFirst(prefix.count))
            guard !projectID.isEmpty else { return nil }
            return ProjectCaptureContext(kind: kind, projectID: projectID, taskID: taskID)
        }
        return nil
    }

    static func acceptProject(
        _ batch: StagedCaptureBatch, project: Project, userID: String,
        context: ModelContext, imageSyncManager: ImageSyncManager?, tutorialMode: Bool = false,
        taskID: String? = nil,
        activeUserID: () -> String = { UserDefaults.standard.string(forKey: "currentUserId") ?? "" },
        activeCompanyID: () -> String = { UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? "" }
    ) async -> Bool {
        let projectID = project.id
        let companyID = project.companyId
        guard !Task.isCancelled, activeUserID().lowercased() == userID.lowercased(),
              activeCompanyID().lowercased() == companyID.lowercased(),
              batch.owner.companyID == companyID.lowercased(), batch.owner.userID == userID.lowercased(),
              let destination = parseProjectContext(batch.owner.contextID),
              destination.projectID == projectID.lowercased() else { return false }
        // The receipt is the durable record of what this batch was shot for, so
        // it — not the caller — decides the link. A caller that states a task
        // must state the same one; a disagreement is an identity fault, exactly
        // like a mismatched project.
        let statedTaskID = ProjectPhotoTaskLink.canonical(taskID)
        guard statedTaskID == nil || statedTaskID == destination.taskID else { return false }
        let linkedTaskID = destination.taskID
        do {
            let owned = ModelContext(context.container)
            owned.autosaveEnabled = false
            let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectID && $0.companyId == companyID })
            guard let target = try owned.fetch(descriptor).first, !target.isDeleted else { return false }
            if destination.kind == "project-draft", !tutorialMode {
                try requireParentCustody(project: target, context: owned)
            }
            var urls = target.getProjectImages()
            var queued: [String] = []
            for item in batch.items {
                let id = item.id
                if let existing = try owned.fetch(FetchDescriptor<ProjectPhoto>(predicate: #Predicate { $0.id == id })).first {
                    guard existing.projectId == projectID, existing.companyId == companyID, existing.uploadedBy.lowercased() == userID.lowercased() else { return false }
                    // A replay never rewrites the task link: the photo may have
                    // been reassigned in the viewer since it was accepted, and
                    // that is a deliberate decision this path must not undo.
                    // A replay cannot resurrect a deliberately deleted photo.
                    if existing.deletedAt == nil && existing.url.hasPrefix("local://") { queued.append(existing.url) }
                    continue
                }
                let row = ProjectPhoto(id: id, projectId: projectID, companyId: companyID, url: item.localURL,
                    source: "in_progress", taskId: linkedTaskID, uploadedBy: userID,
                    takenAt: item.capturedAt, createdAt: item.capturedAt)
                row.needsSync = !tutorialMode
                owned.insert(row)
                if !urls.contains(item.localURL) { urls.append(item.localURL) }
                queued.append(item.localURL)
            }
            target.setProjectImageURLs(urls)
            try owned.save()
            // Refresh the displayed projection only after the transaction succeeds.
            project.setProjectImageURLs(urls)
            if !tutorialMode {
                for url in queued { imageSyncManager?.enqueueExistingLocalImage(localURL: url, projectId: projectID, companyId: companyID) }
                if let imageSyncManager { Task { await imageSyncManager.syncPendingImages() } }
            }
            return true
        } catch { return false }
    }

    static func recoverProject(project: Project, userID: String, context: ModelContext, imageSyncManager: ImageSyncManager?, tutorialMode: Bool = false) async throws {
        guard UserDefaults.standard.string(forKey: "currentUserId")?.lowercased() == userID.lowercased(),
              UserDefaults.standard.string(forKey: "currentUserCompanyId")?.lowercased() == project.companyId.lowercased() else { throw CaptureStagingError.invalidIdentity }
        // The two whole-project contexts always run, even with nothing on disk,
        // so retirement still settles a batch whose items were all acknowledged.
        // Task-scoped contexts cannot be enumerated that way — there is one per
        // task, and a batch whose task was since deleted has no live task to
        // derive it from — so they are read back off the journals themselves.
        var contextIDs: Set<String> = [
            "project:\(project.id.lowercased())",
            "project-draft:\(project.id.lowercased())"
        ]
        for contextID in try await DurableCaptureStore.shared.retainedContextIDs(companyID: project.companyId, userID: userID) {
            guard let parsed = parseProjectContext(contextID),
                  parsed.projectID == project.id.lowercased() else { continue }
            contextIDs.insert(parsed.contextID)
        }
        for contextID in contextIDs.sorted() {
            let owner = StagedCaptureOwner(companyID: project.companyId, userID: userID, contextID: contextID)
            try await retireDeliveredProjectCaptures(owner: owner, projectID: project.id, context: context)
            for batch in try await DurableCaptureStore.shared.recover(owner: owner) {
                guard await acceptProject(batch, project: project, userID: userID, context: context, imageSyncManager: imageSyncManager, tutorialMode: tutorialMode) else { throw CaptureStagingError.writeFailed }
                try await DurableCaptureStore.shared.acknowledge(batchID: batch.id, itemIDs: Set(batch.items.map(\.id)))
            }
        }
    }

    static func isRemoteURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let host = url.host, !host.isEmpty else { return false }
        return url.scheme == "https" || url.scheme == "http"
    }

    static func canonicalCaptureURL(for row: ProjectPhoto, receipts: [ProjectPhotoDTO]) -> String? {
        receipts.first {
            $0.id.lowercased() == row.id.lowercased() && $0.companyId.lowercased() == row.companyId.lowercased()
                && $0.projectId.lowercased() == row.projectId.lowercased() && $0.uploadedBy?.lowercased() == row.uploadedBy.lowercased()
                && $0.deletedAt == nil && isRemoteURL($0.url)
        }?.url
    }

    struct ProjectDelivery {
        let id: String
        let projectID: String
        let companyID: String
        let uploadedBy: String
        let localURL: String
        let remoteURL: String
    }

    /// Commit authoritative delivery in an owned context. A failed save cannot
    /// roll back unrelated screen edits or leave an unsaved remote URL visible.
    static func persistProjectDeliveries(_ deliveries: [ProjectDelivery], context: ModelContext,
        account: CaptureAccountIdentity, currentAccount: CurrentAccount = { CaptureAccountIdentity.current() },
        save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        try requireAccount(account, currentAccount: currentAccount)
        let owned = ModelContext(context.container)
        owned.autosaveEnabled = false
        for delivery in deliveries {
            let id = delivery.id, projectID = delivery.projectID, companyID = delivery.companyID
            guard companyID.lowercased() == account.companyID,
                  !delivery.localURL.hasPrefix("local://project_images/capture_") || delivery.uploadedBy.lowercased() == account.userID,
                  isRemoteURL(delivery.remoteURL),
                  let row = try owned.fetch(FetchDescriptor<ProjectPhoto>(predicate: #Predicate { $0.id == id })).first,
                  row.projectId == projectID, row.companyId == companyID, row.uploadedBy == delivery.uploadedBy,
                  row.deletedAt == nil, [delivery.localURL, delivery.remoteURL].contains(row.url),
                  let project = try owned.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectID && $0.companyId == companyID })).first else { throw CaptureStagingError.invalidIdentity }
            ImageSyncManager.healHandoffPhotoRow(row, remoteURL: delivery.remoteURL)
            var seen = Set<String>()
            project.setProjectImageURLs(project.getProjectImages().map { $0 == delivery.localURL ? delivery.remoteURL : $0 }.filter { seen.insert($0).inserted })
            project.lastSyncedAt = Date()
        }
        try requireAccount(account, currentAccount: currentAccount)
        try save(owned)
    }

    static func retireDeliveredProjectCaptures(owner: StagedCaptureOwner, projectID: String, context: ModelContext,
        store: DurableCaptureStore = .shared, currentAccount: @escaping CurrentAccount = { CaptureAccountIdentity.current() },
        readBatches: (@Sendable (StagedCaptureOwner) async throws -> [StagedCaptureBatch])? = nil) async throws {
        let account = CaptureAccountIdentity(companyID: owner.companyID, userID: owner.userID)
        try requireAccount(account, currentAccount: currentAccount)
        let batches: [StagedCaptureBatch]
        if let readBatches { batches = try await readBatches(owner) }
        else { batches = try await store.retainedBatches(owner: owner) }
        try requireAccount(account, currentAccount: currentAccount)
        let owned = ModelContext(context.container)
        var delivered = Set<String>()
        for item in batches.flatMap(\.items) {
            let id = item.id
            guard let row = try owned.fetch(FetchDescriptor<ProjectPhoto>(predicate: #Predicate { $0.id == id })).first,
                  row.companyId.lowercased() == owner.companyID, row.projectId == projectID,
                  row.uploadedBy.lowercased() == owner.userID, !row.needsSync, row.lastSyncedAt != nil,
                  row.deletedAt == nil, isRemoteURL(row.url) else { continue }
            delivered.insert(item.localURL)
        }
        try requireAccount(account, currentAccount: currentAccount)
        try await store.recordDelivered(localURLs: delivered, account: account)
    }

    static func persistLeadDelivery(_ dto: OpportunityDTO, opportunityID: String, companyID: String, remoteURL: String,
        context: ModelContext, save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        guard dto.id.lowercased() == opportunityID.lowercased(), dto.companyId.lowercased() == companyID.lowercased(),
              (dto.images ?? []).contains(remoteURL), isRemoteURL(remoteURL) else { throw CaptureStagingError.invalidIdentity }
        let owned = ModelContext(context.container)
        owned.autosaveEnabled = false
        guard let opportunity = try owned.fetch(FetchDescriptor<Opportunity>(predicate: #Predicate { $0.id == opportunityID && $0.companyId == companyID })).first else { throw CaptureStagingError.invalidIdentity }
        opportunity.images = dto.images ?? []
        try save(owned)
    }
}
