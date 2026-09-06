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

    static func owner(companyID: String, userID: String, kind: String, id: String) -> StagedCaptureOwner {
        StagedCaptureOwner(companyID: companyID, userID: userID, contextID: "\(kind):\(id.lowercased())")
    }

    static func acceptProject(
        _ batch: StagedCaptureBatch, project: Project, userID: String,
        context: ModelContext, imageSyncManager: ImageSyncManager?, tutorialMode: Bool = false,
        activeUserID: () -> String = { UserDefaults.standard.string(forKey: "currentUserId") ?? "" },
        activeCompanyID: () -> String = { UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? "" }
    ) async -> Bool {
        let projectID = project.id
        let companyID = project.companyId
        guard !Task.isCancelled, activeUserID().lowercased() == userID.lowercased(),
              activeCompanyID().lowercased() == companyID.lowercased(),
              batch.owner.companyID == companyID.lowercased(), batch.owner.userID == userID.lowercased(),
              ["project:\(projectID.lowercased())", "project-draft:\(projectID.lowercased())"].contains(batch.owner.contextID) else { return false }
        do {
            let owned = ModelContext(context.container)
            owned.autosaveEnabled = false
            let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectID && $0.companyId == companyID })
            guard let target = try owned.fetch(descriptor).first, !target.isDeleted else { return false }
            if batch.owner.contextID.hasPrefix("project-draft:"), !tutorialMode {
                try requireParentCustody(project: target, context: owned)
            }
            var urls = target.getProjectImages()
            var queued: [String] = []
            for item in batch.items {
                let id = item.id
                if let existing = try owned.fetch(FetchDescriptor<ProjectPhoto>(predicate: #Predicate { $0.id == id })).first {
                    guard existing.projectId == projectID, existing.companyId == companyID, existing.uploadedBy.lowercased() == userID.lowercased() else { return false }
                    // A replay cannot resurrect a deliberately deleted photo.
                    if existing.deletedAt == nil && existing.url.hasPrefix("local://") { queued.append(existing.url) }
                    continue
                }
                let row = ProjectPhoto(id: id, projectId: projectID, companyId: companyID, url: item.localURL,
                    source: "in_progress", uploadedBy: userID, takenAt: item.capturedAt, createdAt: item.capturedAt)
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
        for kind in ["project", "project-draft"] {
            let owner = owner(companyID: project.companyId, userID: userID, kind: kind, id: project.id)
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
