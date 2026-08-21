//
//  HistoricalSiteVisitSettlementPolicy.swift
//  OPS
//
//  A pure, fail-closed policy for the five pre-incident unlinked visits found
//  during the P1-15 phone/server audit. This is intentionally NOT part of the
//  normal SyncEngine: no sweep, retry button, timer, or bulk queue path can
//  invoke historical settlement.
//

import CryptoKit
import Foundation

enum HistoricalSiteVisitSettlementOutcome: String, Codable, Equatable {
    case recoverActiveLink = "recover_active_link"
    case settleCompletedHistory = "settle_completed_history"
}

struct HistoricalSiteVisitSettlementManifest: Equatable {
    struct Entry: Equatable {
        let visitId: String
        let companyId: String
        let expectedServerStatus: SiteVisitStatus
        let expectedServerUpdatedAt: Date
        let outcome: HistoricalSiteVisitSettlementOutcome
    }

    let entries: [Entry]

    func entry(for visitId: String) -> Entry? {
        let id = Self.canonical(visitId)
        return entries.first { Self.canonical($0.visitId) == id }
    }

    /// Immutable scope discovered by the read-only 2026-08-21 audit. The
    /// server timestamps are compare-and-set guards, not freshness claims:
    /// any later server change invalidates the plan and requires a new audit.
    static let preIncidentUnlinkedVisits = HistoricalSiteVisitSettlementManifest(
        entries: [
            Entry(
                visitId: "984c6847-2ac6-4bf3-a56e-9eb08f120fdf",
                companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
                expectedServerStatus: .inProgress,
                expectedServerUpdatedAt: Date(timeIntervalSince1970: 1_782_777_347.205),
                outcome: .recoverActiveLink
            ),
            Entry(
                visitId: "b1e9cea3-4c1a-4247-8a1f-c21aa721bbe2",
                companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
                expectedServerStatus: .inProgress,
                expectedServerUpdatedAt: Date(timeIntervalSince1970: 1_782_833_444.428),
                outcome: .recoverActiveLink
            ),
            Entry(
                visitId: "0de1fc17-61d8-4b23-8534-27f7a529b1ce",
                companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
                expectedServerStatus: .inProgress,
                expectedServerUpdatedAt: Date(timeIntervalSince1970: 1_785_348_969.540),
                outcome: .recoverActiveLink
            ),
            Entry(
                visitId: "df4016c4-6269-49d1-aec2-76e7934600c2",
                companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
                expectedServerStatus: .completed,
                expectedServerUpdatedAt: Date(timeIntervalSince1970: 1_786_483_614.811_711),
                outcome: .settleCompletedHistory
            ),
            Entry(
                visitId: "4e73b982-c7ad-4303-9f1f-680b26edc10e",
                companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
                expectedServerStatus: .scheduled,
                expectedServerUpdatedAt: Date(timeIntervalSince1970: 1_786_484_612.560),
                outcome: .recoverActiveLink
            ),
        ]
    )

    private static func canonical(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct HistoricalSiteVisitRelationshipEvidence: Codable, Equatable {
    let entityType: String
    let entityId: String
    let siteVisitId: String
    let companyId: String
    let opportunityId: String?
}

struct HistoricalSiteVisitOperationEvidence: Codable, Equatable {
    let id: String
    let entityType: String
    let entityId: String
    let operationType: String
    let status: String
    let companyId: String
    let siteVisitId: String
    let envelopeEntityId: String
    let changedFields: [String]

    func replacing(status: String) -> Self {
        Self(
            id: id,
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            status: status,
            companyId: companyId,
            siteVisitId: siteVisitId,
            envelopeEntityId: envelopeEntityId,
            changedFields: changedFields
        )
    }
}

struct HistoricalSiteVisitPhoneEvidence: Equatable {
    let visitId: String
    let companyId: String
    let status: SiteVisitStatus
    let deletedAt: Date?
    let targetOpportunityId: String?
    let targetOpportunityCompanyId: String?
    let targetOpportunityAssignedTo: String?
    let targetOpportunityIsActive: Bool
    let childRelationships: [HistoricalSiteVisitRelationshipEvidence]
    let operations: [HistoricalSiteVisitOperationEvidence]
    let contentFingerprint: String?

    func replacing(
        visitId: String? = nil,
        childRelationships: [HistoricalSiteVisitRelationshipEvidence]? = nil,
        operations: [HistoricalSiteVisitOperationEvidence]? = nil
    ) -> Self {
        Self(
            visitId: visitId ?? self.visitId,
            companyId: companyId,
            status: status,
            deletedAt: deletedAt,
            targetOpportunityId: targetOpportunityId,
            targetOpportunityCompanyId: targetOpportunityCompanyId,
            targetOpportunityAssignedTo: targetOpportunityAssignedTo,
            targetOpportunityIsActive: targetOpportunityIsActive,
            childRelationships: childRelationships ?? self.childRelationships,
            operations: operations ?? self.operations,
            contentFingerprint: contentFingerprint
        )
    }
}

struct HistoricalSiteVisitServerEvidence: Equatable {
    let visitId: String
    let companyId: String
    let status: SiteVisitStatus
    let opportunityId: String?
    let deletedAt: Date?
    let updatedAt: Date
    let childRelationships: [HistoricalSiteVisitRelationshipEvidence]
    let contentFingerprint: String?

    func replacing(
        opportunityId: String? = nil,
        updatedAt: Date? = nil
    ) -> Self {
        Self(
            visitId: visitId,
            companyId: companyId,
            status: status,
            opportunityId: opportunityId ?? self.opportunityId,
            deletedAt: deletedAt,
            updatedAt: updatedAt ?? self.updatedAt,
            childRelationships: childRelationships,
            contentFingerprint: contentFingerprint
        )
    }
}

struct HistoricalSiteVisitCapabilityEvidence: Equatable {
    let actorUserId: String
    let companyId: String
    let canEditTargetOpportunity: Bool
}

struct HistoricalSiteVisitSettlementPlan: Codable, Equatable {
    let visitId: String
    let companyId: String
    let actorUserId: String
    let targetOpportunityId: String
    let targetOpportunityAssignedTo: String?
    let expectedServerStatus: SiteVisitStatus
    let expectedServerUpdatedAt: Date
    let outcome: HistoricalSiteVisitSettlementOutcome
    let operationIds: [String]
    let contentFingerprint: String?
    let approvalDigest: String

    var permitsServerMutation: Bool {
        outcome == .recoverActiveLink
    }
}

struct HistoricalSiteVisitSettlementApproval: Codable, Equatable {
    let approvalDigest: String
    let actorUserId: String
    let companyId: String
    let visitId: String
    let targetOpportunityId: String
    let outcome: HistoricalSiteVisitSettlementOutcome
    let approvedAt: Date

    func replacing(targetOpportunityId: String) -> Self {
        Self(
            approvalDigest: approvalDigest,
            actorUserId: actorUserId,
            companyId: companyId,
            visitId: visitId,
            targetOpportunityId: targetOpportunityId,
            outcome: outcome,
            approvedAt: approvedAt
        )
    }
}

enum HistoricalSiteVisitSettlementError: Error, Equatable {
    case visitOutsideManifest
    case companyMismatch
    case invalidIdentity
    case statusMismatch
    case localVisitDeleted
    case targetOpportunityUnavailable
    case capabilityDenied
    case phoneRelationshipConflict
    case missingQueueEvidence
    case malformedQueueEvidence
    case operationInFlight
    case serverAlreadyLinked
    case serverRelationshipConflict
    case serverSnapshotChanged
    case completedContentMismatch
    case approvalMismatch
    case auditConflict
    case serverMutationForbidden
}

enum HistoricalSiteVisitSettlementPolicy {
    private static let settleableStatuses: Set<String> = ["pending", "failed", "parked"]
    private static let permittedOperationTypes: Set<String> = [
        "create", "update", SiteVisitSyncOperation.completionOperationType,
        SiteVisitSyncOperation.mediaOperationType,
    ]
    private static let permittedEntityTypes: Set<String> = [
        SyncEntityType.siteVisit.rawValue,
        SyncEntityType.siteVisitArtifact.rawValue,
        SyncEntityType.siteVisitChecklistAnswer.rawValue,
        SyncEntityType.siteVisitIdentityDraft.rawValue,
    ]

    static func plan(
        manifest: HistoricalSiteVisitSettlementManifest,
        phone: HistoricalSiteVisitPhoneEvidence,
        server: HistoricalSiteVisitServerEvidence,
        capability: HistoricalSiteVisitCapabilityEvidence
    ) throws -> HistoricalSiteVisitSettlementPlan {
        guard let entry = manifest.entry(for: phone.visitId) else {
            throw HistoricalSiteVisitSettlementError.visitOutsideManifest
        }

        let visitId = canonical(entry.visitId)
        let companyId = canonical(entry.companyId)
        let actorUserId = canonical(capability.actorUserId)
        guard isUUID(visitId),
              isUUID(actorUserId),
              !companyId.isEmpty,
              canonical(phone.visitId) == visitId,
              canonical(server.visitId) == visitId else {
            throw HistoricalSiteVisitSettlementError.invalidIdentity
        }
        guard canonical(phone.companyId) == companyId,
              canonical(server.companyId) == companyId,
              canonical(capability.companyId) == companyId else {
            throw HistoricalSiteVisitSettlementError.companyMismatch
        }
        guard phone.status == entry.expectedServerStatus,
              server.status == entry.expectedServerStatus else {
            throw HistoricalSiteVisitSettlementError.statusMismatch
        }
        guard phone.deletedAt == nil else {
            throw HistoricalSiteVisitSettlementError.localVisitDeleted
        }
        guard server.deletedAt == nil else {
            throw HistoricalSiteVisitSettlementError.serverSnapshotChanged
        }
        guard server.updatedAt == entry.expectedServerUpdatedAt else {
            throw HistoricalSiteVisitSettlementError.serverSnapshotChanged
        }
        guard server.opportunityId == nil else {
            throw HistoricalSiteVisitSettlementError.serverAlreadyLinked
        }

        guard let rawTarget = phone.targetOpportunityId,
              isUUID(rawTarget),
              phone.targetOpportunityIsActive,
              canonical(phone.targetOpportunityCompanyId ?? "") == companyId else {
            throw HistoricalSiteVisitSettlementError.targetOpportunityUnavailable
        }
        let targetId = canonical(rawTarget)
        guard capability.canEditTargetOpportunity else {
            throw HistoricalSiteVisitSettlementError.capabilityDenied
        }

        guard phone.childRelationships.allSatisfy({ relationship in
            canonical(relationship.siteVisitId) == visitId
                && canonical(relationship.companyId) == companyId
                && canonical(relationship.opportunityId ?? "") == targetId
                && permittedEntityTypes.contains(relationship.entityType)
                && relationship.entityType != SyncEntityType.siteVisit.rawValue
                && isUUID(relationship.entityId)
        }) else {
            throw HistoricalSiteVisitSettlementError.phoneRelationshipConflict
        }
        guard server.childRelationships.allSatisfy({ relationship in
            canonical(relationship.siteVisitId) == visitId
                && canonical(relationship.companyId) == companyId
                && relationship.opportunityId == nil
                && permittedEntityTypes.contains(relationship.entityType)
                && relationship.entityType != SyncEntityType.siteVisit.rawValue
                && isUUID(relationship.entityId)
        }) else {
            throw HistoricalSiteVisitSettlementError.serverRelationshipConflict
        }

        guard !phone.operations.isEmpty else {
            throw HistoricalSiteVisitSettlementError.missingQueueEvidence
        }
        if phone.operations.contains(where: { $0.status == "inProgress" }) {
            throw HistoricalSiteVisitSettlementError.operationInFlight
        }
        let childKeys = Set(phone.childRelationships.map {
            operationKey(entityType: $0.entityType, entityId: $0.entityId)
        })
        guard phone.operations.allSatisfy({ operation in
            isUUID(operation.id)
                && permittedEntityTypes.contains(operation.entityType)
                && permittedOperationTypes.contains(operation.operationType)
                && settleableStatuses.contains(operation.status)
                && canonical(operation.companyId) == companyId
                && canonical(operation.siteVisitId) == visitId
                && canonical(operation.envelopeEntityId) == canonical(operation.entityId)
                && (
                    operation.entityType == SyncEntityType.siteVisit.rawValue
                        ? canonical(operation.entityId) == visitId
                        : childKeys.contains(
                            operationKey(
                                entityType: operation.entityType,
                                entityId: operation.entityId
                            )
                        )
                )
        }) else {
            throw HistoricalSiteVisitSettlementError.malformedQueueEvidence
        }
        guard Set(phone.operations.map { canonical($0.id) }).count == phone.operations.count,
              phone.operations.contains(where: {
                  $0.changedFields.map(canonical).contains("opportunity_id")
              }) else {
            throw HistoricalSiteVisitSettlementError.missingQueueEvidence
        }

        let contentFingerprint: String?
        switch entry.outcome {
        case .recoverActiveLink:
            guard entry.expectedServerStatus == .scheduled
                    || entry.expectedServerStatus == .inProgress else {
                throw HistoricalSiteVisitSettlementError.statusMismatch
            }
            contentFingerprint = nil

        case .settleCompletedHistory:
            guard entry.expectedServerStatus == .completed,
                  let phoneFingerprint = phone.contentFingerprint,
                  !phoneFingerprint.isEmpty,
                  phoneFingerprint == server.contentFingerprint else {
                throw HistoricalSiteVisitSettlementError.completedContentMismatch
            }
            contentFingerprint = phoneFingerprint
        }

        let operationIds = phone.operations.map { canonical($0.id) }.sorted()
        let preimage = ApprovalPreimage(
            visitId: visitId,
            companyId: companyId,
            actorUserId: actorUserId,
            targetOpportunityId: targetId,
            targetOpportunityAssignedTo: canonicalOptional(phone.targetOpportunityAssignedTo),
            expectedServerStatus: entry.expectedServerStatus,
            expectedServerUpdatedAt: entry.expectedServerUpdatedAt,
            outcome: entry.outcome,
            operationIds: operationIds,
            contentFingerprint: contentFingerprint
        )
        let digest = try fingerprint(preimage)
        return HistoricalSiteVisitSettlementPlan(
            visitId: visitId,
            companyId: companyId,
            actorUserId: actorUserId,
            targetOpportunityId: targetId,
            targetOpportunityAssignedTo: canonicalOptional(phone.targetOpportunityAssignedTo),
            expectedServerStatus: entry.expectedServerStatus,
            expectedServerUpdatedAt: entry.expectedServerUpdatedAt,
            outcome: entry.outcome,
            operationIds: operationIds,
            contentFingerprint: contentFingerprint,
            approvalDigest: digest
        )
    }

    static func validate(
        _ approval: HistoricalSiteVisitSettlementApproval,
        for plan: HistoricalSiteVisitSettlementPlan
    ) throws {
        guard approval.approvalDigest == plan.approvalDigest,
              canonical(approval.actorUserId) == plan.actorUserId,
              canonical(approval.companyId) == plan.companyId,
              canonical(approval.visitId) == plan.visitId,
              canonical(approval.targetOpportunityId) == plan.targetOpportunityId,
              approval.outcome == plan.outcome else {
            throw HistoricalSiteVisitSettlementError.approvalMismatch
        }
    }

    private struct ApprovalPreimage: Codable {
        let visitId: String
        let companyId: String
        let actorUserId: String
        let targetOpportunityId: String
        let targetOpportunityAssignedTo: String?
        let expectedServerStatus: SiteVisitStatus
        let expectedServerUpdatedAt: Date
        let outcome: HistoricalSiteVisitSettlementOutcome
        let operationIds: [String]
        let contentFingerprint: String?
    }

    private static func fingerprint<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = SHA256.hash(data: try encoder.encode(value))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func operationKey(entityType: String, entityId: String) -> String {
        "\(entityType)::\(canonical(entityId))"
    }

    private static func isUUID(_ value: String) -> Bool {
        UUID(uuidString: canonical(value)) != nil
    }

    private static func canonical(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func canonicalOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = canonical(value)
        return result.isEmpty ? nil : result
    }
}
