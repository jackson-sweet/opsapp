//
//  SiteVisitOrphanRecovery.swift
//  OPS
//
//  Rebuilds the missing parent row left by the legacy phone-only site-visit
//  flow before any child is allowed into the outbound queue.
//

import Foundation
import SwiftData

enum SiteVisitOrphanQuarantineReason: String, Codable, Equatable, Hashable {
    case foreignCompany = "foreign_company"
    case malformedIdentity = "malformed_identity"
    case ambiguousBinding = "ambiguous_binding"
}

struct SiteVisitOrphanQuarantine: Codable, Equatable, Identifiable {
    let id: String
    let userId: String?
    let companyId: String
    let siteVisitId: String
    let reason: SiteVisitOrphanQuarantineReason
    let childIds: [String]
    let createdAt: Date
}

@MainActor
enum SiteVisitOrphanRecovery {
    typealias QuarantineRecorder = (SiteVisitOrphanQuarantine) throws -> Void

    struct Result: Equatable {
        let reconstructedVisitIds: [String]
        let quarantinedIds: [String]
        let operationIds: [UUID]
    }

    private struct GroupKey: Hashable {
        let companyId: String
        let siteVisitId: String
    }

    private struct ChildEvidence {
        let id: String
        let companyId: String
        let siteVisitId: String
        let opportunityId: String?
        let createdBy: String?
        let eventAt: Date
        let address: String?
    }

    private struct CandidateGroup {
        let key: GroupKey
        let children: [ChildEvidence]
        let completionOperation: SyncOperation?
    }

    /// Runs safely before every outbound drain. The version marker is only an
    /// optimization elsewhere; correctness comes from re-scanning for missing
    /// parents, making this heal both one-time legacy data and later corruption.
    static func recover(
        in modelContext: ModelContext,
        activeUserId: String,
        activeCompanyId: String,
        quarantine: QuarantineRecorder
    ) throws -> Result {
        let activeCompany = canonicalText(activeCompanyId)
        let activeUser = canonicalUUID(activeUserId)
        guard !activeCompany.isEmpty else {
            return Result(reconstructedVisitIds: [], quarantinedIds: [], operationIds: [])
        }

        let visits = try modelContext.fetch(FetchDescriptor<SiteVisit>())
        let existingParentKeys = Set(visits.map {
            GroupKey(
                companyId: canonicalText($0.companyId),
                siteVisitId: canonicalText($0.id)
            )
        })
        let operations = try modelContext.fetch(FetchDescriptor<SyncOperation>())
        let groups = try missingParentGroups(
            in: modelContext,
            existingParentKeys: existingParentKeys,
            operations: operations
        )

        var reconstructable: [CandidateGroup] = []
        var quarantines: [SiteVisitOrphanQuarantine] = []

        for group in groups {
            let reason = quarantineReason(for: group, activeCompanyId: activeCompany)
            if let reason {
                let childUsers = Set(group.children.compactMap { canonicalUUID($0.createdBy) })
                let owner = group.key.companyId == activeCompany
                    ? activeUser
                    : (childUsers.count == 1 ? childUsers.first : activeUser)
                let record = SiteVisitOrphanQuarantine(
                    id: quarantineID(for: group.key, reason: reason),
                    userId: owner,
                    companyId: group.key.companyId,
                    siteVisitId: group.key.siteVisitId,
                    reason: reason,
                    childIds: group.children.map(\.id).sorted(),
                    createdAt: group.children.map(\.eventAt).min() ?? Date()
                )
                // Recording is deliberately before any reconstruction mutation.
                // A full disk/keychain failure therefore leaves every child in
                // place and aborts the sweep instead of silently consuming work.
                try quarantine(record)
                quarantines.append(record)
            } else {
                reconstructable.append(group)
            }
        }

        var reconstructed: [String] = []
        try modelContext.transaction {
            let quarantinedKeys = Set(quarantines.map {
                GroupKey(companyId: $0.companyId, siteVisitId: $0.siteVisitId)
            })
            for operation in operations where
                operationMatchesAny(operation, keys: quarantinedKeys)
            {
                operation.status = "quarantined"
                operation.lastError = "Protected on this phone pending identity review."
                operation.lastAttemptedAt = nil
            }
            for group in reconstructable.sorted(by: groupOrder) {
                guard !modelContextContainsParent(group.key, in: modelContext) else { continue }
                let eventAt = group.children.map(\.eventAt).min() ?? Date()
                let opportunities = uniqueCanonicalValues(group.children.map(\.opportunityId))
                let createdBy = group.children
                    .sorted { $0.eventAt < $1.eventAt }
                    .compactMap { canonicalUUID($0.createdBy) }
                    .first ?? activeUser
                let address = group.children
                    .sorted { $0.eventAt < $1.eventAt }
                    .compactMap { trimmedNil($0.address) }
                    .first
                let completionAt = group.completionOperation.map {
                    $0.completedAt ?? $0.createdAt
                }
                let visit = SiteVisit(
                    id: group.key.siteVisitId,
                    opportunityId: opportunities.first,
                    companyId: group.key.companyId,
                    status: completionAt == nil ? .inProgress : .completed,
                    scheduledAt: eventAt,
                    createdBy: createdBy,
                    createdAt: eventAt
                )
                visit.address = address
                visit.completedAt = completionAt
                visit.updatedAt = group.children.map(\.eventAt).max() ?? eventAt
                visit.needsSync = true
                modelContext.insert(visit)
                canonicalizeChildren(for: group.key, in: modelContext)
                reconstructed.append(group.key.siteVisitId)
            }
        }

        let queued = try SiteVisitPersistenceCoordinator(
            modelContext: modelContext,
            companyId: activeCompany
        ).recoverOrphanedWrites()

        return Result(
            reconstructedVisitIds: reconstructed.sorted(),
            quarantinedIds: quarantines.map(\.id).sorted(),
            operationIds: queued.operationIds
        )
    }

    private static func missingParentGroups(
        in modelContext: ModelContext,
        existingParentKeys: Set<GroupKey>,
        operations: [SyncOperation]
    ) throws -> [CandidateGroup] {
        var evidence: [ChildEvidence] = []
        evidence += try modelContext.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
            .filter { $0.needsSync || $0.lastSyncedAt == nil }
            .map {
                ChildEvidence(
                    id: $0.id,
                    companyId: canonicalText($0.companyId),
                    siteVisitId: canonicalText($0.siteVisitId),
                    opportunityId: $0.opportunityId,
                    createdBy: $0.createdBy,
                    eventAt: min($0.capturedAt, $0.createdAt),
                    address: nil
                )
            }
        evidence += try modelContext.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())
            .filter { $0.needsSync || $0.lastSyncedAt == nil }
            .map {
                ChildEvidence(
                    id: $0.id,
                    companyId: canonicalText($0.companyId),
                    siteVisitId: canonicalText($0.siteVisitId),
                    opportunityId: $0.opportunityId,
                    createdBy: $0.createdBy,
                    eventAt: $0.createdAt,
                    address: nil
                )
            }
        evidence += try modelContext.fetch(FetchDescriptor<SiteVisitIdentityDraft>())
            .filter { $0.needsSync || $0.lastSyncedAt == nil }
            .map {
                ChildEvidence(
                    id: $0.id,
                    companyId: canonicalText($0.companyId),
                    siteVisitId: canonicalText($0.siteVisitId),
                    opportunityId: $0.opportunityId,
                    createdBy: $0.createdBy,
                    eventAt: min($0.createdAt, $0.updatedAt),
                    address: $0.address
                )
            }

        let grouped = Dictionary(grouping: evidence) {
            GroupKey(companyId: $0.companyId, siteVisitId: $0.siteVisitId)
        }
        return grouped.compactMap { key, children in
            guard !existingParentKeys.contains(key) else { return nil }
            let completion = operations
                .filter { operation in
                    guard operation.operationType
                            == SiteVisitSyncOperation.completionOperationType,
                          let payload = try? JSONDecoder().decode(
                            SiteVisitSyncOperation.Payload.self,
                            from: operation.payload
                          ) else { return false }
                    return canonicalText(payload.companyId) == key.companyId
                        && canonicalText(payload.siteVisitId) == key.siteVisitId
                }
                .sorted { $0.createdAt < $1.createdAt }
                .last
            return CandidateGroup(
                key: key,
                children: children,
                completionOperation: completion
            )
        }
    }

    private static func quarantineReason(
        for group: CandidateGroup,
        activeCompanyId: String
    ) -> SiteVisitOrphanQuarantineReason? {
        if group.key.companyId != activeCompanyId { return .foreignCompany }
        guard !group.key.companyId.isEmpty,
              canonicalUUID(group.key.siteVisitId) != nil,
              group.children.allSatisfy({ canonicalUUID($0.id) != nil }) else {
            return .malformedIdentity
        }
        if uniqueCanonicalValues(group.children.map(\.opportunityId)).count > 1 {
            return .ambiguousBinding
        }
        return nil
    }

    private static func canonicalizeChildren(
        for key: GroupKey,
        in modelContext: ModelContext
    ) {
        let artifacts = (try? modelContext.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())) ?? []
        for child in artifacts where
            canonicalText(child.companyId) == key.companyId
                && canonicalText(child.siteVisitId) == key.siteVisitId
        {
            child.companyId = key.companyId
            child.siteVisitId = key.siteVisitId
        }
        let answers = (try? modelContext.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())) ?? []
        for child in answers where
            canonicalText(child.companyId) == key.companyId
                && canonicalText(child.siteVisitId) == key.siteVisitId
        {
            child.companyId = key.companyId
            child.siteVisitId = key.siteVisitId
        }
        let drafts = (try? modelContext.fetch(FetchDescriptor<SiteVisitIdentityDraft>())) ?? []
        for child in drafts where
            canonicalText(child.companyId) == key.companyId
                && canonicalText(child.siteVisitId) == key.siteVisitId
        {
            child.companyId = key.companyId
            child.siteVisitId = key.siteVisitId
        }
    }

    private static func modelContextContainsParent(
        _ key: GroupKey,
        in modelContext: ModelContext
    ) -> Bool {
        ((try? modelContext.fetch(FetchDescriptor<SiteVisit>())) ?? []).contains {
            canonicalText($0.companyId) == key.companyId
                && canonicalText($0.id) == key.siteVisitId
        }
    }

    private static func groupOrder(_ lhs: CandidateGroup, _ rhs: CandidateGroup) -> Bool {
        if lhs.key.companyId != rhs.key.companyId {
            return lhs.key.companyId < rhs.key.companyId
        }
        return lhs.key.siteVisitId < rhs.key.siteVisitId
    }

    private static func operationMatchesAny(
        _ operation: SyncOperation,
        keys: Set<GroupKey>
    ) -> Bool {
        guard SiteVisitOutboundSync.isSiteVisitOperation(operation),
              let payload = try? JSONDecoder().decode(
                SiteVisitSyncOperation.Payload.self,
                from: operation.payload
              ) else { return false }
        return keys.contains(
            GroupKey(
                companyId: canonicalText(payload.companyId),
                siteVisitId: canonicalText(payload.siteVisitId)
            )
        )
    }

    private static func uniqueCanonicalValues(_ values: [String?]) -> [String] {
        Array(Set(values.compactMap { canonicalUUID($0) })).sorted()
    }

    private static func quarantineID(
        for key: GroupKey,
        reason: SiteVisitOrphanQuarantineReason
    ) -> String {
        "site-visit-quarantine:\(reason.rawValue):\(key.companyId):\(key.siteVisitId)"
    }

    private static func canonicalText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func canonicalUUID(_ value: String?) -> String? {
        guard let value else { return nil }
        return UUID(uuidString: value.trimmingCharacters(in: .whitespacesAndNewlines))?
            .uuidString
            .lowercased()
    }

    private static func trimmedNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
