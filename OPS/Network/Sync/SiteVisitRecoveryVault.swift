//
//  SiteVisitRecoveryVault.swift
//  OPS
//
//  Encrypted, phone-local custody for unsent site-visit packets that must
//  survive a forced logout. Archives are scoped to one exact user + company;
//  another account on the same phone cannot list, restore, or discard them.
//

import CryptoKit
import Foundation
import Security
import SwiftData

struct SiteVisitRecoveryIdentity: Equatable, Hashable {
    let userId: String
    let companyId: String

    init(userId: String, companyId: String) {
        self.userId = userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.companyId = companyId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

@MainActor
final class SiteVisitRecoveryVault {
    static let shared = SiteVisitRecoveryVault()

    struct EntrySummary: Equatable, Identifiable {
        let id: String
        let siteVisitId: String
        let reason: SiteVisitOrphanQuarantineReason?
        let createdAt: Date
        let capturedItemCount: Int
    }

    enum VaultError: Swift.Error, LocalizedError {
        case invalidKey
        case keychain(OSStatus)
        case corruptArchive
        case identityConflict(entity: String, id: String)

        var errorDescription: String? {
            switch self {
            case .invalidKey:
                return "The site visit recovery key is invalid."
            case .keychain(let status):
                return "The site visit recovery keychain failed (\(status))."
            case .corruptArchive:
                return "A protected site visit archive is damaged."
            case .identityConflict(let entity, let id):
                return "Protected \(entity) \(id) belongs to another company."
            }
        }
    }

    typealias KeyProvider = () throws -> Data
    typealias KeyDeleter = () -> Void
    typealias MediaURLResolver = (String) -> URL?

    private static let archiveVersion = 1
    private static let bundleFilename = "bundle.opsvault"
    private static let dedicatedKeychainService = "co.opsapp.ops.site-visit-recovery-v1"
    private static let dedicatedKeychainAccount = "vault-key"
    private static let unresolvedStatuses: Set<String> = [
        "pending", "inProgress", "failed", "parked",
    ]
    private static let archivableStatuses = unresolvedStatuses.union(["quarantined"])

    private let rootDirectory: URL
    private let keyProvider: KeyProvider
    private let keyDeleter: KeyDeleter?
    private let mediaURLResolver: MediaURLResolver
    private let fileManager: FileManager

    convenience init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        self.init(
            rootDirectory: support
                .appendingPathComponent("OPS", isDirectory: true)
                .appendingPathComponent("SiteVisitRecovery", isDirectory: true)
                .appendingPathComponent("v1", isDirectory: true),
            keyProvider: Self.loadOrCreateProductionKey,
            keyDeleter: Self.deleteProductionKey,
            mediaURLResolver: Self.productionMediaURL
        )
    }

    init(
        rootDirectory: URL,
        keyProvider: @escaping KeyProvider,
        keyDeleter: KeyDeleter? = nil,
        mediaURLResolver: @escaping MediaURLResolver,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.keyProvider = keyProvider
        self.keyDeleter = keyDeleter
        self.mediaURLResolver = mediaURLResolver
        self.fileManager = fileManager
    }

    /// Returns every same-company visit with local work that is not yet proven
    /// durable on the server. Missing-parent children are included deliberately.
    static func unsentVisitIds(
        in modelContext: ModelContext,
        companyId: String
    ) throws -> [String] {
        let company = canonical(companyId)
        guard !company.isEmpty else { return [] }
        var visitIds = Set<String>()

        for visit in try modelContext.fetch(FetchDescriptor<SiteVisit>()) where
            canonical(visit.companyId) == company
                && (visit.needsSync || visit.lastSyncedAt == nil)
        {
            visitIds.insert(canonical(visit.id))
        }
        for artifact in try modelContext.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()) where
            canonical(artifact.companyId) == company
                && (artifact.needsSync || artifact.lastSyncedAt == nil)
        {
            visitIds.insert(canonical(artifact.siteVisitId))
        }
        for answer in try modelContext.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()) where
            canonical(answer.companyId) == company
                && (answer.needsSync || answer.lastSyncedAt == nil)
        {
            visitIds.insert(canonical(answer.siteVisitId))
        }
        for draft in try modelContext.fetch(FetchDescriptor<SiteVisitIdentityDraft>()) where
            canonical(draft.companyId) == company
                && (draft.needsSync || draft.lastSyncedAt == nil)
        {
            visitIds.insert(canonical(draft.siteVisitId))
        }
        for operation in try modelContext.fetch(FetchDescriptor<SyncOperation>()) where
            unresolvedStatuses.contains(operation.status)
                && SiteVisitOutboundSync.isSiteVisitOperation(operation)
        {
            guard let payload = try? JSONDecoder().decode(
                SiteVisitSyncOperation.Payload.self,
                from: operation.payload
            ), canonical(payload.companyId) == company else { continue }
            visitIds.insert(canonical(payload.siteVisitId))
        }

        return visitIds.filter { !$0.isEmpty }.sorted()
    }

    /// Takes protected custody before a non-interactive logout. All archives
    /// must land successfully before any original media is removed.
    @discardableResult
    func captureUnsentWork(
        from modelContext: ModelContext,
        userId: String,
        companyId: String,
        removeOriginalMedia: Bool
    ) throws -> Int {
        let identity = SiteVisitRecoveryIdentity(userId: userId, companyId: companyId)
        guard !identity.userId.isEmpty, !identity.companyId.isEmpty else { return 0 }
        let visitIds = try Self.unsentVisitIds(
            in: modelContext,
            companyId: identity.companyId
        )
        var archivedMedia = Set<String>()
        for visitId in visitIds {
            let archive = try makeArchive(
                id: "forced:\(identity.userId):\(identity.companyId):\(visitId)",
                identity: identity,
                siteVisitId: visitId,
                quarantineReason: nil,
                createdAt: Date(),
                childIds: nil,
                modelContext: modelContext
            )
            try write(archive)
            archivedMedia.formUnion(archive.media.map(\.localId))
        }

        if removeOriginalMedia {
            for localId in archivedMedia {
                guard let url = mediaURLResolver(localId) else { continue }
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
            }
        }
        return visitIds.count
    }

    /// Persists a quarantine record before the recovery sweep mutates anything.
    /// Repeating the same record replaces the same encrypted entry idempotently.
    func recordQuarantine(
        _ quarantine: SiteVisitOrphanQuarantine,
        from modelContext: ModelContext
    ) throws {
        let identity = SiteVisitRecoveryIdentity(
            userId: quarantine.userId ?? "__unknown__",
            companyId: quarantine.companyId
        )
        let archive = try makeArchive(
            id: quarantine.id,
            identity: identity,
            siteVisitId: Self.canonical(quarantine.siteVisitId),
            quarantineReason: quarantine.reason,
            createdAt: quarantine.createdAt,
            childIds: Set(quarantine.childIds.map(Self.canonical)),
            modelContext: modelContext
        )
        try write(archive)
    }

    func summaries(userId: String, companyId: String) -> [EntrySummary] {
        let identity = SiteVisitRecoveryIdentity(userId: userId, companyId: companyId)
        guard !identity.userId.isEmpty, !identity.companyId.isEmpty else { return [] }
        return readEntries().compactMap { entry in
            guard entry.archive.identity == identity else { return nil }
            return EntrySummary(
                id: entry.archive.id,
                siteVisitId: entry.archive.siteVisitId,
                reason: entry.archive.quarantineReason,
                createdAt: entry.archive.createdAt,
                capturedItemCount: entry.archive.artifacts.count
                    + entry.archive.answers.count
                    + entry.archive.drafts.count
            )
        }.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }

    /// Rehydrates only exact-identity, forced-logout entries (reason nil). Each
    /// entry is removed only after its media is restored and its SwiftData
    /// transaction commits.
    ///
    /// Quarantine entries (reason non-nil) are custody, not luggage: they ARE
    /// the packet PENDING WORK renders, and for `parentDeleted` there is no way
    /// to re-derive the reason locally after a restore dissolves the entry —
    /// the packet would vanish silently while its operations sit invisibly
    /// "quarantined". They leave the vault only through the operator's explicit
    /// discard (or, for identity-review reasons, the orphan sweep re-recording).
    @discardableResult
    func restore(
        into modelContext: ModelContext,
        userId: String,
        companyId: String
    ) throws -> Int {
        let identity = SiteVisitRecoveryIdentity(userId: userId, companyId: companyId)
        guard !identity.userId.isEmpty, !identity.companyId.isEmpty else { return 0 }
        let entries = readEntries()
            .filter {
                $0.archive.identity == identity
                    && $0.archive.quarantineReason == nil
            }
            .sorted { $0.archive.createdAt < $1.archive.createdAt }
        var restored = 0

        for entry in entries {
            try restoreMedia(for: entry)
            try modelContext.transaction {
                try restoreModels(from: entry.archive, into: modelContext)
            }
            try fileManager.removeItem(at: entry.directory)
            restored += 1
        }
        deleteKeyIfVaultIsEmpty()
        return restored
    }

    /// Explicit loss path used only after the operator chooses discard or the
    /// device account itself is deleted.
    func discardStoredWork(userId: String, companyId: String) throws {
        let identity = SiteVisitRecoveryIdentity(userId: userId, companyId: companyId)
        for entry in readEntries() where entry.archive.identity == identity {
            try fileManager.removeItem(at: entry.directory)
        }
        deleteKeyIfVaultIsEmpty()
    }

    func discardStoredEntry(
        id: String,
        userId: String,
        companyId: String
    ) throws {
        let identity = SiteVisitRecoveryIdentity(userId: userId, companyId: companyId)
        for entry in readEntries() where
            entry.archive.identity == identity && entry.archive.id == id
        {
            try fileManager.removeItem(at: entry.directory)
        }
        deleteKeyIfVaultIsEmpty()
    }

    /// Permanently discards one quarantined orphan after an explicit operator
    /// choice. The encrypted entry is the authority for identity and remains in
    /// place until the exact local source, quarantined operations, and media are
    /// all gone. A parent that later arrived from another device is never owned
    /// by this path and is deliberately preserved.
    @discardableResult
    func discardQuarantinedWork(
        id: String,
        userId: String,
        companyId: String,
        siteVisitId: String,
        from modelContext: ModelContext
    ) throws -> Bool {
        let identity = SiteVisitRecoveryIdentity(userId: userId, companyId: companyId)
        let visitId = Self.canonical(siteVisitId)
        guard !identity.userId.isEmpty,
              !identity.companyId.isEmpty,
              !visitId.isEmpty,
              let entry = readEntries().first(where: {
                  $0.archive.identity == identity
                      && $0.archive.id == id
                      && $0.archive.quarantineReason != nil
                      && Self.canonical($0.archive.siteVisitId) == visitId
              }) else { return false }

        let artifacts = try modelContext.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
            .filter {
                Self.canonical($0.companyId) == identity.companyId
                    && Self.canonical($0.siteVisitId) == visitId
            }
        let answers = try modelContext.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())
            .filter {
                Self.canonical($0.companyId) == identity.companyId
                    && Self.canonical($0.siteVisitId) == visitId
            }
        let drafts = try modelContext.fetch(FetchDescriptor<SiteVisitIdentityDraft>())
            .filter {
                Self.canonical($0.companyId) == identity.companyId
                    && Self.canonical($0.siteVisitId) == visitId
            }
        let operations = try modelContext.fetch(FetchDescriptor<SyncOperation>())
            .filter { operation in
                guard operation.status == "quarantined",
                      SiteVisitOutboundSync.isSiteVisitOperation(operation),
                      let payload = try? JSONDecoder().decode(
                        SiteVisitSyncOperation.Payload.self,
                        from: operation.payload
                      ) else { return false }
                return Self.canonical(payload.companyId) == identity.companyId
                    && Self.canonical(payload.siteVisitId) == visitId
            }
        let mediaIds = Set(
            artifacts.flatMap(Self.mediaLocalIds) + entry.archive.media.map(\.localId)
        )

        try modelContext.transaction {
            artifacts.forEach(modelContext.delete)
            answers.forEach(modelContext.delete)
            drafts.forEach(modelContext.delete)
            operations.forEach(modelContext.delete)
        }

        // If physical file removal fails, the archive remains. Retrying is safe
        // because its media manifest survives even after the SwiftData commit.
        for localId in mediaIds.sorted() {
            guard let url = mediaURLResolver(localId) else { continue }
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        try fileManager.removeItem(at: entry.directory)
        deleteKeyIfVaultIsEmpty()
        return true
    }

    /// Removes every visit-owned local file for one exact company after all
    /// unsent packets have either been vaulted or explicitly discarded. Synced
    /// rows are included so a different account cannot inherit orphaned bytes.
    func removeLiveMedia(
        in modelContext: ModelContext,
        companyId: String
    ) throws {
        let company = Self.canonical(companyId)
        let artifacts = try modelContext.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
        let localIds = Set(artifacts.filter {
            Self.canonical($0.companyId) == company
        }.flatMap(Self.mediaLocalIds))
        for localId in localIds {
            guard let url = mediaURLResolver(localId) else { continue }
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    // MARK: - Archive construction

    private struct StoredEntry {
        let directory: URL
        let archive: Archive
    }

    private struct Archive: Codable {
        let version: Int
        let id: String
        let identity: SiteVisitRecoveryIdentitySnapshot
        let siteVisitId: String
        let quarantineReason: SiteVisitOrphanQuarantineReason?
        let createdAt: Date
        let visit: VisitSnapshot?
        let artifacts: [ArtifactModelSnapshot]
        let answers: [AnswerModelSnapshot]
        let drafts: [DraftModelSnapshot]
        let operations: [OperationSnapshot]
        let media: [MediaSnapshot]
    }

    private struct SiteVisitRecoveryIdentitySnapshot: Codable, Equatable {
        let userId: String
        let companyId: String

        init(_ identity: SiteVisitRecoveryIdentity) {
            userId = identity.userId
            companyId = identity.companyId
        }

        static func == (
            lhs: SiteVisitRecoveryIdentitySnapshot,
            rhs: SiteVisitRecoveryIdentity
        ) -> Bool {
            lhs.userId == rhs.userId && lhs.companyId == rhs.companyId
        }
    }

    private struct VisitSnapshot: Codable {
        let id: String
        let opportunityId: String?
        let companyId: String
        let projectId: String?
        let projectRef: String?
        let clientId: String?
        let clientRef: String?
        let status: SiteVisitStatus
        let scheduledAt: Date?
        let durationMinutes: Int
        let assigneeIds: [String]
        let completedAt: Date?
        let notes: String?
        let internalNotes: String?
        let measurements: String?
        let photos: [String]
        let address: String?
        let assignedTo: String?
        let calendarEventId: String?
        let createdBy: String?
        let createdAt: Date
        let updatedAt: Date?
        let deletedAt: Date?
        let needsSync: Bool
        let lastSyncedAt: Date?
        let loggedActivityId: String?

        init(_ model: SiteVisit) {
            id = model.id; opportunityId = model.opportunityId; companyId = model.companyId
            projectId = model.projectId; projectRef = model.projectRef
            clientId = model.clientId; clientRef = model.clientRef; status = model.status
            scheduledAt = model.scheduledAt; durationMinutes = model.durationMinutes
            assigneeIds = model.assigneeIds; completedAt = model.completedAt; notes = model.notes
            internalNotes = model.internalNotes; measurements = model.measurements
            photos = model.photos; address = model.address; assignedTo = model.assignedTo
            calendarEventId = model.calendarEventId; createdBy = model.createdBy
            createdAt = model.createdAt; updatedAt = model.updatedAt; deletedAt = model.deletedAt
            needsSync = model.needsSync; lastSyncedAt = model.lastSyncedAt
            loggedActivityId = model.loggedActivityId
        }

        func makeModel() -> SiteVisit {
            let model = SiteVisit(
                id: id, opportunityId: opportunityId, companyId: companyId,
                projectId: projectId, projectRef: projectRef, clientId: clientId,
                clientRef: clientRef, status: status, scheduledAt: scheduledAt,
                durationMinutes: durationMinutes, assigneeIds: assigneeIds,
                createdBy: createdBy, loggedActivityId: loggedActivityId,
                createdAt: createdAt
            )
            apply(to: model)
            return model
        }

        func apply(to model: SiteVisit) {
            model.opportunityId = opportunityId; model.projectId = projectId
            model.projectRef = projectRef; model.clientId = clientId; model.clientRef = clientRef
            model.status = status; model.scheduledAt = scheduledAt
            model.durationMinutes = durationMinutes; model.assigneeIds = assigneeIds
            model.completedAt = completedAt; model.notes = notes; model.internalNotes = internalNotes
            model.measurements = measurements; model.photos = photos; model.address = address
            model.assignedTo = assignedTo; model.calendarEventId = calendarEventId
            model.createdBy = createdBy; model.createdAt = createdAt; model.updatedAt = updatedAt
            model.deletedAt = deletedAt; model.needsSync = needsSync
            model.lastSyncedAt = lastSyncedAt; model.loggedActivityId = loggedActivityId
        }
    }

    private struct ArtifactModelSnapshot: Codable {
        let id: String; let siteVisitId: String; let companyId: String
        let opportunityId: String?; let kind: SiteVisitCaptureArtifactKind
        let source: SiteVisitCaptureSource; let title: String?; let body: String?
        let localAssetURL: String?; let renderedAssetURL: String?; let thumbnailURL: String?
        let dimensionsJSON: String?; let deckDesignId: String?
        let includedInProjectReview: Bool; let capturedAt: Date; let createdBy: String?
        let createdAt: Date; let updatedAt: Date?; let deletedAt: Date?
        let needsSync: Bool; let lastSyncedAt: Date?

        init(_ model: SiteVisitCaptureArtifact) {
            id = model.id; siteVisitId = model.siteVisitId; companyId = model.companyId
            opportunityId = model.opportunityId; kind = model.kind; source = model.source
            title = model.title; body = model.body; localAssetURL = model.localAssetURL
            renderedAssetURL = model.renderedAssetURL; thumbnailURL = model.thumbnailURL
            dimensionsJSON = model.dimensionsJSON; deckDesignId = model.deckDesignId
            includedInProjectReview = model.includedInProjectReview; capturedAt = model.capturedAt
            createdBy = model.createdBy; createdAt = model.createdAt; updatedAt = model.updatedAt
            deletedAt = model.deletedAt; needsSync = model.needsSync; lastSyncedAt = model.lastSyncedAt
        }

        func makeModel() -> SiteVisitCaptureArtifact {
            let model = SiteVisitCaptureArtifact(
                id: id, siteVisitId: siteVisitId, companyId: companyId,
                opportunityId: opportunityId, kind: kind, source: source, title: title,
                body: body, localAssetURL: localAssetURL, renderedAssetURL: renderedAssetURL,
                thumbnailURL: thumbnailURL, dimensionsJSON: dimensionsJSON,
                deckDesignId: deckDesignId, includedInProjectReview: includedInProjectReview,
                capturedAt: capturedAt, createdBy: createdBy, createdAt: createdAt
            )
            apply(to: model)
            return model
        }

        func apply(to model: SiteVisitCaptureArtifact) {
            model.opportunityId = opportunityId; model.kind = kind; model.source = source
            model.title = title; model.body = body; model.localAssetURL = localAssetURL
            model.renderedAssetURL = renderedAssetURL; model.thumbnailURL = thumbnailURL
            model.dimensionsJSON = dimensionsJSON; model.deckDesignId = deckDesignId
            model.includedInProjectReview = includedInProjectReview; model.capturedAt = capturedAt
            model.createdBy = createdBy; model.createdAt = createdAt; model.updatedAt = updatedAt
            model.deletedAt = deletedAt; model.needsSync = needsSync; model.lastSyncedAt = lastSyncedAt
        }
    }

    private struct AnswerModelSnapshot: Codable {
        let id: String; let siteVisitId: String; let companyId: String
        let opportunityId: String?; let siteVisitTypeId: String?; let fieldId: String
        let label: String; let kind: SiteVisitFieldKind; let required: Bool
        let helpText: String?; let sortOrder: Int; let answerValueData: Data?
        let createdBy: String?; let createdAt: Date; let updatedAt: Date?
        let deletedAt: Date?; let needsSync: Bool; let lastSyncedAt: Date?

        init(_ model: SiteVisitChecklistAnswer) {
            id = model.id; siteVisitId = model.siteVisitId; companyId = model.companyId
            opportunityId = model.opportunityId; siteVisitTypeId = model.siteVisitTypeId
            fieldId = model.fieldId; label = model.label; kind = model.kind
            required = model.required; helpText = model.helpText; sortOrder = model.sortOrder
            answerValueData = model.answerValueData; createdBy = model.createdBy
            createdAt = model.createdAt; updatedAt = model.updatedAt; deletedAt = model.deletedAt
            needsSync = model.needsSync; lastSyncedAt = model.lastSyncedAt
        }

        func makeModel() -> SiteVisitChecklistAnswer {
            let model = SiteVisitChecklistAnswer(
                id: id, siteVisitId: siteVisitId, companyId: companyId,
                opportunityId: opportunityId, siteVisitTypeId: siteVisitTypeId,
                fieldId: fieldId, label: label, kind: kind, required: required,
                helpText: helpText, sortOrder: sortOrder, createdBy: createdBy,
                createdAt: createdAt
            )
            apply(to: model)
            return model
        }

        func apply(to model: SiteVisitChecklistAnswer) {
            model.opportunityId = opportunityId; model.siteVisitTypeId = siteVisitTypeId
            model.fieldId = fieldId; model.label = label; model.kind = kind
            model.required = required; model.helpText = helpText; model.sortOrder = sortOrder
            model.answerValueData = answerValueData; model.createdBy = createdBy
            model.createdAt = createdAt; model.updatedAt = updatedAt; model.deletedAt = deletedAt
            model.needsSync = needsSync; model.lastSyncedAt = lastSyncedAt
        }
    }

    private struct DraftModelSnapshot: Codable {
        let id: String; let siteVisitId: String; let companyId: String
        let opportunityId: String?; let clientId: String?; let subClientId: String?
        let searchText: String; let clientName: String; let contactName: String
        let preferredEmail: String; let additionalEmailsJSON: String; let phoneNumber: String
        let address: String; let notes: String; let createdBy: String?; let createdAt: Date
        let updatedAt: Date; let lastCommittedAt: Date?; let deletedAt: Date?
        let needsSync: Bool; let lastSyncedAt: Date?

        init(_ model: SiteVisitIdentityDraft) {
            id = model.id; siteVisitId = model.siteVisitId; companyId = model.companyId
            opportunityId = model.opportunityId; clientId = model.clientId; subClientId = model.subClientId
            searchText = model.searchText; clientName = model.clientName; contactName = model.contactName
            preferredEmail = model.preferredEmail; additionalEmailsJSON = model.additionalEmailsJSON
            phoneNumber = model.phoneNumber; address = model.address; notes = model.notes
            createdBy = model.createdBy; createdAt = model.createdAt; updatedAt = model.updatedAt
            lastCommittedAt = model.lastCommittedAt; deletedAt = model.deletedAt
            needsSync = model.needsSync; lastSyncedAt = model.lastSyncedAt
        }

        func makeModel() -> SiteVisitIdentityDraft {
            let model = SiteVisitIdentityDraft(
                id: id, siteVisitId: siteVisitId, companyId: companyId,
                opportunityId: opportunityId, clientId: clientId, subClientId: subClientId,
                searchText: searchText, clientName: clientName, contactName: contactName,
                preferredEmail: preferredEmail, additionalEmails: [], phoneNumber: phoneNumber,
                address: address, notes: notes, createdBy: createdBy, createdAt: createdAt
            )
            apply(to: model)
            return model
        }

        func apply(to model: SiteVisitIdentityDraft) {
            model.opportunityId = opportunityId; model.clientId = clientId; model.subClientId = subClientId
            model.searchText = searchText; model.clientName = clientName; model.contactName = contactName
            model.preferredEmail = preferredEmail; model.additionalEmailsJSON = additionalEmailsJSON
            model.phoneNumber = phoneNumber; model.address = address; model.notes = notes
            model.createdBy = createdBy; model.createdAt = createdAt; model.updatedAt = updatedAt
            model.lastCommittedAt = lastCommittedAt; model.deletedAt = deletedAt
            model.needsSync = needsSync; model.lastSyncedAt = lastSyncedAt
        }
    }

    private struct OperationSnapshot: Codable {
        let id: UUID; let entityType: String; let entityId: String; let operationType: String
        let payload: Data; let changedFields: String; let createdAt: Date; let retryCount: Int
        let lastAttemptedAt: Date?; let status: String; let lastError: String?
        let previousValues: Data?; let priority: Int; let requiresWiFi: Bool
        let dependsOnId: String?; let completedAt: Date?; let serverConfirmedAt: Date?

        init(_ model: SyncOperation) {
            id = model.id; entityType = model.entityType; entityId = model.entityId
            operationType = model.operationType; payload = model.payload
            changedFields = model.changedFields; createdAt = model.createdAt
            retryCount = model.retryCount; lastAttemptedAt = model.lastAttemptedAt
            status = model.status; lastError = model.lastError; previousValues = model.previousValues
            priority = model.priority; requiresWiFi = model.requiresWiFi
            dependsOnId = model.dependsOnId; completedAt = model.completedAt
            serverConfirmedAt = model.serverConfirmedAt
        }

        func makeModel() -> SyncOperation {
            let model = SyncOperation(
                entityType: entityType, entityId: entityId, operationType: operationType,
                payload: payload, changedFields: changedFields.isEmpty
                    ? [] : changedFields.components(separatedBy: ","),
                previousValues: previousValues, priority: priority, dependsOnId: dependsOnId
            )
            apply(to: model)
            return model
        }

        func apply(to model: SyncOperation) {
            model.id = id; model.entityType = entityType; model.entityId = entityId
            model.operationType = operationType; model.payload = payload
            model.changedFields = changedFields; model.createdAt = createdAt
            model.retryCount = retryCount; model.lastAttemptedAt = lastAttemptedAt
            model.status = status; model.lastError = lastError; model.previousValues = previousValues
            model.priority = priority; model.requiresWiFi = requiresWiFi
            model.dependsOnId = dependsOnId; model.completedAt = completedAt
            model.serverConfirmedAt = serverConfirmedAt
        }
    }

    private struct MediaSnapshot: Codable {
        let localId: String
        let encryptedFilename: String
    }

    private func makeArchive(
        id: String,
        identity: SiteVisitRecoveryIdentity,
        siteVisitId: String,
        quarantineReason: SiteVisitOrphanQuarantineReason?,
        createdAt: Date,
        childIds: Set<String>?,
        modelContext: ModelContext
    ) throws -> Archive {
        let visits = try modelContext.fetch(FetchDescriptor<SiteVisit>())
        let visit = visits.first {
            Self.canonical($0.companyId) == identity.companyId
                && Self.canonical($0.id) == siteVisitId
        }
        let artifacts = try modelContext.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
            .filter {
                Self.canonical($0.companyId) == identity.companyId
                    && Self.canonical($0.siteVisitId) == siteVisitId
                    && (childIds == nil || childIds!.contains(Self.canonical($0.id)))
            }
        let answers = try modelContext.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())
            .filter {
                Self.canonical($0.companyId) == identity.companyId
                    && Self.canonical($0.siteVisitId) == siteVisitId
                    && (childIds == nil || childIds!.contains(Self.canonical($0.id)))
            }
        let drafts = try modelContext.fetch(FetchDescriptor<SiteVisitIdentityDraft>())
            .filter {
                Self.canonical($0.companyId) == identity.companyId
                    && Self.canonical($0.siteVisitId) == siteVisitId
                    && (childIds == nil || childIds!.contains(Self.canonical($0.id)))
            }
        let operations = try modelContext.fetch(FetchDescriptor<SyncOperation>())
            .filter { operation in
                guard Self.archivableStatuses.contains(operation.status),
                      SiteVisitOutboundSync.isSiteVisitOperation(operation),
                      let payload = try? JSONDecoder().decode(
                        SiteVisitSyncOperation.Payload.self,
                        from: operation.payload
                      ) else { return false }
                return Self.canonical(payload.companyId) == identity.companyId
                    && Self.canonical(payload.siteVisitId) == siteVisitId
            }
        let mediaIds = Set(artifacts.flatMap(Self.mediaLocalIds)).sorted()
        let media = mediaIds.compactMap { localId -> MediaSnapshot? in
            guard let url = mediaURLResolver(localId),
                  fileManager.fileExists(atPath: url.path) else { return nil }
            return MediaSnapshot(
                localId: localId,
                encryptedFilename: Self.sha256(localId) + ".media"
            )
        }
        return Archive(
            version: Self.archiveVersion,
            id: id,
            identity: SiteVisitRecoveryIdentitySnapshot(identity),
            siteVisitId: siteVisitId,
            quarantineReason: quarantineReason,
            createdAt: createdAt,
            visit: visit.map(VisitSnapshot.init),
            artifacts: artifacts.map(ArtifactModelSnapshot.init),
            answers: answers.map(AnswerModelSnapshot.init),
            drafts: drafts.map(DraftModelSnapshot.init),
            operations: operations.map(OperationSnapshot.init),
            media: media
        )
    }

    // MARK: - Encrypted persistence

    private func write(_ archive: Archive) throws {
        try ensureRootDirectory()
        let key = try symmetricKey()
        let destination = rootDirectory.appendingPathComponent(
            Self.sha256("\(archive.identity.userId)|\(archive.identity.companyId)|\(archive.id)"),
            isDirectory: true
        )
        let temporary = rootDirectory.appendingPathComponent(
            ".tmp-\(UUID().uuidString)",
            isDirectory: true
        )
        try createProtectedDirectory(at: temporary)
        do {
            for media in archive.media {
                guard let sourceURL = mediaURLResolver(media.localId) else { continue }
                let plaintext = try Data(contentsOf: sourceURL)
                try encrypt(plaintext, with: key).write(
                    to: temporary.appendingPathComponent(media.encryptedFilename),
                    options: .atomic
                )
            }
            let encoded = try JSONEncoder().encode(archive)
            try encrypt(encoded, with: key).write(
                to: temporary.appendingPathComponent(Self.bundleFilename),
                options: .atomic
            )
            try protectContents(of: temporary)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func readEntries() -> [StoredEntry] {
        guard fileManager.fileExists(atPath: rootDirectory.path),
              let key = try? symmetricKey(),
              let directories = try? fileManager.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
              ) else { return [] }
        return directories.compactMap { directory in
            let bundleURL = directory.appendingPathComponent(Self.bundleFilename)
            guard let encrypted = try? Data(contentsOf: bundleURL),
                  let plaintext = try? decrypt(encrypted, with: key),
                  let archive = try? JSONDecoder().decode(Archive.self, from: plaintext),
                  archive.version == Self.archiveVersion else { return nil }
            return StoredEntry(directory: directory, archive: archive)
        }
    }

    private func restoreMedia(for entry: StoredEntry) throws {
        let key = try symmetricKey()
        for media in entry.archive.media {
            guard let destination = mediaURLResolver(media.localId) else { continue }
            let encryptedURL = entry.directory.appendingPathComponent(media.encryptedFilename)
            let plaintext = try decrypt(Data(contentsOf: encryptedURL), with: key)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try plaintext.write(to: destination, options: .atomic)
            try protect(destination)
        }
    }

    private func restoreModels(
        from archive: Archive,
        into modelContext: ModelContext
    ) throws {
        let company = archive.identity.companyId
        if let snapshot = archive.visit {
            let all = try modelContext.fetch(FetchDescriptor<SiteVisit>())
            if let existing = all.first(where: { Self.canonical($0.id) == Self.canonical(snapshot.id) }) {
                try validateCompany(existing.companyId, company, entity: "site visit", id: snapshot.id)
                snapshot.apply(to: existing)
            } else {
                modelContext.insert(snapshot.makeModel())
            }
        }
        let existingArtifacts = try modelContext.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
        for snapshot in archive.artifacts {
            if let existing = existingArtifacts.first(where: { Self.canonical($0.id) == Self.canonical(snapshot.id) }) {
                try validateCompany(existing.companyId, company, entity: "artifact", id: snapshot.id)
                snapshot.apply(to: existing)
            } else {
                modelContext.insert(snapshot.makeModel())
            }
        }
        let existingAnswers = try modelContext.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())
        for snapshot in archive.answers {
            if let existing = existingAnswers.first(where: { Self.canonical($0.id) == Self.canonical(snapshot.id) }) {
                try validateCompany(existing.companyId, company, entity: "answer", id: snapshot.id)
                snapshot.apply(to: existing)
            } else {
                modelContext.insert(snapshot.makeModel())
            }
        }
        let existingDrafts = try modelContext.fetch(FetchDescriptor<SiteVisitIdentityDraft>())
        for snapshot in archive.drafts {
            if let existing = existingDrafts.first(where: { Self.canonical($0.id) == Self.canonical(snapshot.id) }) {
                try validateCompany(existing.companyId, company, entity: "draft", id: snapshot.id)
                snapshot.apply(to: existing)
            } else {
                modelContext.insert(snapshot.makeModel())
            }
        }
        let existingOperations = try modelContext.fetch(FetchDescriptor<SyncOperation>())
        for snapshot in archive.operations {
            if let existing = existingOperations.first(where: { $0.id == snapshot.id }) {
                snapshot.apply(to: existing)
            } else {
                modelContext.insert(snapshot.makeModel())
            }
        }
    }

    private func validateCompany(
        _ candidate: String,
        _ expected: String,
        entity: String,
        id: String
    ) throws {
        guard Self.canonical(candidate) == expected else {
            throw VaultError.identityConflict(entity: entity, id: id)
        }
    }

    private func symmetricKey() throws -> SymmetricKey {
        let data = try keyProvider()
        guard data.count == 32 else { throw VaultError.invalidKey }
        return SymmetricKey(data: data)
    }

    private func encrypt(_ data: Data, with key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else {
            throw VaultError.corruptArchive
        }
        return combined
    }

    private func decrypt(_ data: Data, with key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
    }

    private func ensureRootDirectory() throws {
        try createProtectedDirectory(at: rootDirectory)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = rootDirectory
        try? mutableRoot.setResourceValues(values)
    }

    private func createProtectedDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try protect(url)
    }

    private func protectContents(of directory: URL) throws {
        try protect(directory)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files { try protect(file) }
    }

    private func protect(_ url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    private func deleteKeyIfVaultIsEmpty() {
        let remaining = (try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        if remaining.isEmpty { keyDeleter?() }
    }

    // MARK: - Production dependencies

    private static func loadOrCreateProductionKey() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dedicatedKeychainService,
            kSecAttrAccount as String: dedicatedKeychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return data }
        guard status == errSecItemNotFound else { throw VaultError.keychain(status) }

        var key = Data(count: 32)
        let randomStatus = key.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { throw VaultError.keychain(randomStatus) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dedicatedKeychainService,
            kSecAttrAccount as String: dedicatedKeychainAccount,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw VaultError.keychain(addStatus) }
        return key
    }

    private static func deleteProductionKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dedicatedKeychainService,
            kSecAttrAccount as String: dedicatedKeychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func productionMediaURL(_ localId: String) -> URL? {
        if localId.hasPrefix("local://project_images/") {
            return ImageFileManager.shared.getFileURL(for: localId)
        }
        if localId.hasPrefix("file://") { return URL(string: localId) }
        if localId.hasPrefix("/") { return URL(fileURLWithPath: localId) }
        return nil
    }

    private static func mediaLocalIds(_ artifact: SiteVisitCaptureArtifact) -> [String] {
        var values: [String] = [
            artifact.localAssetURL,
            artifact.renderedAssetURL,
            artifact.thumbnailURL,
        ].compactMap { value -> String? in
            guard let value, !SiteVisitMediaSyncManager.isRemoteURL(value) else { return nil }
            return value
        }
        if let json = artifact.dimensionsJSON,
           let expression = try? NSRegularExpression(
            pattern: #"local://project_images/[^\"\\\s]+"#
           ) {
            let range = NSRange(json.startIndex..., in: json)
            values += expression.matches(in: json, range: range).compactMap { match -> String? in
                guard let range = Range(match.range, in: json) else { return nil }
                return String(json[range])
            }
        }
        return Array(Set(values)).sorted()
    }

    private static func canonical(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
