//
//  HistoricalSiteVisitSettlementEvidence.swift
//  OPS
//
//  Normalizes the phone queue/SwiftData graph and the freshly-read server
//  bundle into the pure historical-settlement policy. The completed-visit
//  fingerprint excludes only the rejected relationship intent and transport
//  bookkeeping; every durable captured field and child identity participates.
//

import CryptoKit
import Foundation
import SwiftData

@MainActor
enum HistoricalSiteVisitSettlementEvidenceFactory {
    static func phone(
        entry: HistoricalSiteVisitSettlementManifest.Entry,
        actorUserId: String,
        accessPolicy: LeadAccessPolicy,
        context: ModelContext
    ) throws -> HistoricalSiteVisitPhoneEvidence {
        let visitId = canonical(entry.visitId)
        let visits = try context.fetch(FetchDescriptor<SiteVisit>())
            .filter { canonical($0.id) == visitId }
        guard visits.count == 1, let visit = visits.first else {
            throw HistoricalSiteVisitSettlementError.invalidIdentity
        }

        let artifacts = try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
            .filter { canonical($0.siteVisitId) == visitId }
        let answers = try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())
            .filter { canonical($0.siteVisitId) == visitId }
        let drafts = try context.fetch(FetchDescriptor<SiteVisitIdentityDraft>())
            .filter { canonical($0.siteVisitId) == visitId }

        let targetId = canonicalOptional(visit.opportunityId)
        let opportunities = try context.fetch(FetchDescriptor<Opportunity>())
        let target = targetId.flatMap { id in
            let matches = opportunities.filter { canonical($0.id) == id }
            return matches.count == 1 ? matches[0] : nil
        }
        let canEditTarget = target.map {
            accessPolicy.can(.edit, assignedTo: $0.assignedTo)
        } ?? false

        let childRelationships = artifacts.map {
            HistoricalSiteVisitRelationshipEvidence(
                entityType: SyncEntityType.siteVisitArtifact.rawValue,
                entityId: canonical($0.id),
                siteVisitId: canonical($0.siteVisitId),
                companyId: canonical($0.companyId),
                opportunityId: canonicalOptional($0.opportunityId)
            )
        } + answers.map {
            HistoricalSiteVisitRelationshipEvidence(
                entityType: SyncEntityType.siteVisitChecklistAnswer.rawValue,
                entityId: canonical($0.id),
                siteVisitId: canonical($0.siteVisitId),
                companyId: canonical($0.companyId),
                opportunityId: canonicalOptional($0.opportunityId)
            )
        } + drafts.map {
            HistoricalSiteVisitRelationshipEvidence(
                entityType: SyncEntityType.siteVisitIdentityDraft.rawValue,
                entityId: canonical($0.id),
                siteVisitId: canonical($0.siteVisitId),
                companyId: canonical($0.companyId),
                opportunityId: canonicalOptional($0.opportunityId)
            )
        }

        let childKeys = Set(childRelationships.map {
            key(entityType: $0.entityType, entityId: $0.entityId)
        })
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
            .filter { operation in
                guard ["pending", "inProgress", "failed", "parked"].contains(operation.status),
                      SiteVisitOutboundSync.isSiteVisitOperation(operation) else {
                    return false
                }
                if operation.entityType == SyncEntityType.siteVisit.rawValue,
                   canonical(operation.entityId) == visitId {
                    return true
                }
                if childKeys.contains(
                    key(entityType: operation.entityType, entityId: operation.entityId)
                ) {
                    return true
                }
                guard let envelope = decode(operation) else { return false }
                return canonical(envelope.siteVisitId) == visitId
            }
            .map { operation in
                let envelope = decode(operation)
                return HistoricalSiteVisitOperationEvidence(
                    id: operation.id.uuidString.lowercased(),
                    entityType: operation.entityType,
                    entityId: canonical(operation.entityId),
                    operationType: operation.operationType,
                    status: operation.status,
                    companyId: canonical(envelope?.companyId ?? ""),
                    siteVisitId: canonical(envelope?.siteVisitId ?? ""),
                    envelopeEntityId: canonical(envelope?.entityId ?? ""),
                    changedFields: operation.getChangedFields().map(canonical)
                )
            }

        return HistoricalSiteVisitPhoneEvidence(
            visitId: canonical(visit.id),
            companyId: canonical(visit.companyId),
            status: visit.status,
            deletedAt: visit.deletedAt,
            targetOpportunityId: targetId,
            targetOpportunityCompanyId: target.map { canonical($0.companyId) },
            targetOpportunityAssignedTo: target.flatMap { canonicalOptional($0.assignedTo) },
            targetOpportunityIsActive: target.map {
                $0.deletedAt == nil && $0.archivedAt == nil
            } ?? false,
            childRelationships: childRelationships,
            operations: operations,
            contentFingerprint: try HistoricalSiteVisitContentFingerprint.phone(
                visit: visit,
                artifacts: artifacts,
                answers: answers,
                drafts: drafts
            )
        )
    }

    static func capability(
        entry: HistoricalSiteVisitSettlementManifest.Entry,
        actorUserId: String,
        accessPolicy: LeadAccessPolicy,
        context: ModelContext
    ) throws -> HistoricalSiteVisitCapabilityEvidence {
        let visitId = canonical(entry.visitId)
        let visit = try context.fetch(FetchDescriptor<SiteVisit>())
            .first { canonical($0.id) == visitId }
        let target = visit?.opportunityId.flatMap { opportunityId in
            try? context.fetch(FetchDescriptor<Opportunity>())
                .first { canonical($0.id) == canonical(opportunityId) }
        }
        return HistoricalSiteVisitCapabilityEvidence(
            actorUserId: canonical(actorUserId),
            companyId: canonical(entry.companyId),
            canEditTargetOpportunity: target.map {
                $0.deletedAt == nil
                    && $0.archivedAt == nil
                    && canonical($0.companyId) == canonical(entry.companyId)
                    && accessPolicy.can(.edit, assignedTo: $0.assignedTo)
            } ?? false
        )
    }

    static func server(
        _ bundle: SiteVisitBundleDTO
    ) throws -> HistoricalSiteVisitServerEvidence {
        guard let updatedAt = bundle.visit.updatedAt else {
            throw HistoricalSiteVisitSettlementError.serverSnapshotChanged
        }
        let relationships = bundle.artifacts.map {
            HistoricalSiteVisitRelationshipEvidence(
                entityType: SyncEntityType.siteVisitArtifact.rawValue,
                entityId: canonical($0.id),
                siteVisitId: canonical($0.siteVisitId),
                companyId: canonical($0.companyId),
                opportunityId: canonicalOptional($0.opportunityId)
            )
        } + bundle.checklistAnswers.map {
            HistoricalSiteVisitRelationshipEvidence(
                entityType: SyncEntityType.siteVisitChecklistAnswer.rawValue,
                entityId: canonical($0.id),
                siteVisitId: canonical($0.siteVisitId),
                companyId: canonical($0.companyId),
                opportunityId: canonicalOptional($0.opportunityId)
            )
        } + bundle.identityDrafts.map {
            HistoricalSiteVisitRelationshipEvidence(
                entityType: SyncEntityType.siteVisitIdentityDraft.rawValue,
                entityId: canonical($0.id),
                siteVisitId: canonical($0.siteVisitId),
                companyId: canonical($0.companyId),
                opportunityId: canonicalOptional($0.opportunityId)
            )
        }
        return HistoricalSiteVisitServerEvidence(
            visitId: canonical(bundle.visit.id),
            companyId: canonical(bundle.visit.companyId),
            status: bundle.visit.status,
            opportunityId: canonicalOptional(bundle.visit.opportunityId),
            deletedAt: bundle.visit.deletedAt,
            updatedAt: updatedAt,
            childRelationships: relationships,
            contentFingerprint: try HistoricalSiteVisitContentFingerprint.server(bundle)
        )
    }

    private static func decode(_ operation: SyncOperation) -> SiteVisitSyncOperation.Payload? {
        try? JSONDecoder().decode(
            SiteVisitSyncOperation.Payload.self,
            from: operation.payload
        )
    }

    private static func key(entityType: String, entityId: String) -> String {
        "\(entityType)::\(canonical(entityId))"
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

private enum HistoricalSiteVisitContentFingerprint {
    private struct Packet: Codable {
        let visit: Visit
        let artifacts: [Artifact]
        let answers: [Answer]
        let drafts: [Draft]
    }

    private struct Visit: Codable {
        let id: String
        let companyId: String
        let scheduledAtMs: Int64?
        let durationMinutes: Int
        let assigneeIds: [String]
        let status: SiteVisitStatus
        let completedAtMs: Int64?
        let notes: String?
        let internalNotes: String?
        let measurements: String?
        let photos: [String]
        let calendarEventId: String?
        let bookedAtMs: Int64?
        let reminderLeadMinutes: Int?
        let createdBy: String?
        let createdAtMs: Int64?
        let deletedAtMs: Int64?
    }

    private struct Artifact: Codable {
        let id: String
        let siteVisitId: String
        let companyId: String
        let kind: SiteVisitCaptureArtifactKind
        let source: SiteVisitCaptureSource
        let title: String?
        let body: String?
        let assetURL: String?
        let renderedAssetURL: String?
        let thumbnailURL: String?
        let dimensionsJSON: String?
        let deckDesignId: String?
        let includedInProjectReview: Bool
        let capturedAtMs: Int64
        let createdBy: String?
        let createdAtMs: Int64
        let deletedAtMs: Int64?
    }

    private struct Answer: Codable {
        let id: String
        let siteVisitId: String
        let companyId: String
        let siteVisitTypeId: String?
        let fieldId: String
        let label: String
        let kind: SiteVisitFieldKind
        let required: Bool
        let helpText: String?
        let sortOrder: Int
        let answerValueJSON: String
        let createdBy: String?
        let createdAtMs: Int64
        let deletedAtMs: Int64?
    }

    private struct Draft: Codable {
        let id: String
        let siteVisitId: String
        let companyId: String
        let clientId: String?
        let subClientId: String?
        let clientName: String
        let contactName: String
        let preferredEmail: String
        let additionalEmails: [String]
        let phoneNumber: String
        let address: String
        let notes: String
        let createdBy: String?
        let lastCommittedAtMs: Int64?
        let createdAtMs: Int64
        let deletedAtMs: Int64?
    }

    static func phone(
        visit: SiteVisit,
        artifacts: [SiteVisitCaptureArtifact],
        answers: [SiteVisitChecklistAnswer],
        drafts: [SiteVisitIdentityDraft]
    ) throws -> String {
        let packet = Packet(
            visit: Visit(
                id: canonical(visit.id),
                companyId: canonical(visit.companyId),
                scheduledAtMs: milliseconds(visit.scheduledAt),
                durationMinutes: visit.durationMinutes,
                assigneeIds: visit.assigneeIds.map(canonical).sorted(),
                status: visit.status,
                completedAtMs: milliseconds(visit.completedAt),
                notes: visit.notes,
                internalNotes: visit.internalNotes,
                measurements: visit.measurements,
                photos: visit.photos,
                calendarEventId: canonicalOptional(visit.calendarEventId),
                bookedAtMs: milliseconds(visit.bookedAt),
                reminderLeadMinutes: visit.reminderLeadMinutes,
                createdBy: canonicalOptional(visit.createdBy),
                createdAtMs: milliseconds(visit.createdAt),
                deletedAtMs: milliseconds(visit.deletedAt)
            ),
            artifacts: try artifacts.map { artifact in
                Artifact(
                    id: canonical(artifact.id),
                    siteVisitId: canonical(artifact.siteVisitId),
                    companyId: canonical(artifact.companyId),
                    kind: artifact.kind,
                    source: artifact.source,
                    title: artifact.title,
                    body: artifact.body,
                    assetURL: remoteURL(artifact.localAssetURL),
                    renderedAssetURL: remoteURL(artifact.renderedAssetURL),
                    thumbnailURL: remoteURL(artifact.thumbnailURL),
                    dimensionsJSON: try canonicalJSON(artifact.dimensionsJSON),
                    deckDesignId: canonicalOptional(artifact.deckDesignId),
                    includedInProjectReview: artifact.includedInProjectReview,
                    capturedAtMs: milliseconds(artifact.capturedAt),
                    createdBy: canonicalOptional(artifact.createdBy),
                    createdAtMs: milliseconds(artifact.createdAt),
                    deletedAtMs: milliseconds(artifact.deletedAt)
                )
            }.sorted { $0.id < $1.id },
            answers: try answers.map { answer in
                Answer(
                    id: canonical(answer.id),
                    siteVisitId: canonical(answer.siteVisitId),
                    companyId: canonical(answer.companyId),
                    siteVisitTypeId: canonicalOptional(answer.siteVisitTypeId),
                    fieldId: answer.fieldId,
                    label: answer.label,
                    kind: answer.kind,
                    required: answer.required,
                    helpText: answer.helpText,
                    sortOrder: answer.sortOrder,
                    answerValueJSON: try canonicalJSONValue(answer.answerValue),
                    createdBy: canonicalOptional(answer.createdBy),
                    createdAtMs: milliseconds(answer.createdAt),
                    deletedAtMs: milliseconds(answer.deletedAt)
                )
            }.sorted { $0.id < $1.id },
            drafts: drafts.map { draft in
                Draft(
                    id: canonical(draft.id),
                    siteVisitId: canonical(draft.siteVisitId),
                    companyId: canonical(draft.companyId),
                    clientId: canonicalOptional(draft.clientId),
                    subClientId: canonicalOptional(draft.subClientId),
                    clientName: draft.clientName,
                    contactName: draft.contactName,
                    preferredEmail: draft.preferredEmail,
                    additionalEmails: draft.additionalEmails,
                    phoneNumber: draft.phoneNumber,
                    address: draft.address,
                    notes: draft.notes,
                    createdBy: canonicalOptional(draft.createdBy),
                    lastCommittedAtMs: milliseconds(draft.lastCommittedAt),
                    createdAtMs: milliseconds(draft.createdAt),
                    deletedAtMs: milliseconds(draft.deletedAt)
                )
            }.sorted { $0.id < $1.id }
        )
        return try digest(packet)
    }

    static func server(_ bundle: SiteVisitBundleDTO) throws -> String {
        let visit = bundle.visit
        let packet = Packet(
            visit: Visit(
                id: canonical(visit.id),
                companyId: canonical(visit.companyId),
                scheduledAtMs: milliseconds(visit.scheduledAt),
                durationMinutes: visit.durationMinutes,
                assigneeIds: visit.assigneeIds.map(canonical).sorted(),
                status: visit.status,
                completedAtMs: milliseconds(visit.completedAt),
                notes: visit.notes,
                internalNotes: visit.internalNotes,
                measurements: visit.measurements,
                photos: visit.photos,
                calendarEventId: canonicalOptional(visit.calendarEventId),
                bookedAtMs: milliseconds(visit.bookedAt),
                reminderLeadMinutes: visit.reminderLeadMinutes,
                createdBy: canonicalOptional(visit.createdBy),
                createdAtMs: milliseconds(visit.createdAt),
                deletedAtMs: milliseconds(visit.deletedAt)
            ),
            artifacts: try bundle.artifacts.map { artifact in
                Artifact(
                    id: canonical(artifact.id),
                    siteVisitId: canonical(artifact.siteVisitId),
                    companyId: canonical(artifact.companyId),
                    kind: artifact.kind,
                    source: artifact.source,
                    title: artifact.title,
                    body: artifact.body,
                    assetURL: artifact.assetURL,
                    renderedAssetURL: artifact.renderedAssetURL,
                    thumbnailURL: artifact.thumbnailURL,
                    dimensionsJSON: try canonicalJSON(artifact.dimensions),
                    deckDesignId: canonicalOptional(artifact.deckDesignId),
                    includedInProjectReview: artifact.includedInProjectReview,
                    capturedAtMs: milliseconds(artifact.capturedAt),
                    createdBy: canonicalOptional(artifact.createdBy),
                    createdAtMs: milliseconds(artifact.createdAt),
                    deletedAtMs: milliseconds(artifact.deletedAt)
                )
            }.sorted { $0.id < $1.id },
            answers: try bundle.checklistAnswers.map { answer in
                Answer(
                    id: canonical(answer.id),
                    siteVisitId: canonical(answer.siteVisitId),
                    companyId: canonical(answer.companyId),
                    siteVisitTypeId: canonicalOptional(answer.siteVisitTypeId),
                    fieldId: answer.fieldId,
                    label: answer.label,
                    kind: answer.kind,
                    required: answer.required,
                    helpText: answer.helpText,
                    sortOrder: answer.sortOrder,
                    answerValueJSON: try canonicalJSONValue(answer.answerValue),
                    createdBy: canonicalOptional(answer.createdBy),
                    createdAtMs: milliseconds(answer.createdAt),
                    deletedAtMs: milliseconds(answer.deletedAt)
                )
            }.sorted { $0.id < $1.id },
            drafts: bundle.identityDrafts.map { draft in
                Draft(
                    id: canonical(draft.id),
                    siteVisitId: canonical(draft.siteVisitId),
                    companyId: canonical(draft.companyId),
                    clientId: canonicalOptional(draft.clientId),
                    subClientId: canonicalOptional(draft.subClientId),
                    clientName: draft.clientName,
                    contactName: draft.contactName,
                    preferredEmail: draft.preferredEmail,
                    additionalEmails: draft.additionalEmails,
                    phoneNumber: draft.phoneNumber,
                    address: draft.address,
                    notes: draft.notes,
                    createdBy: canonicalOptional(draft.createdBy),
                    lastCommittedAtMs: milliseconds(draft.lastCommittedAt),
                    createdAtMs: milliseconds(draft.createdAt),
                    deletedAtMs: milliseconds(draft.deletedAt)
                )
            }.sorted { $0.id < $1.id }
        )
        return try digest(packet)
    }

    private static func digest<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let hash = SHA256.hash(data: try encoder.encode(value))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalJSON<T: Encodable>(_ value: T?) throws -> String? {
        guard let value else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(data: try encoder.encode(value), encoding: .utf8)
    }

    private static func canonicalJSONValue<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let result = String(data: try encoder.encode(value), encoding: .utf8) else {
            throw HistoricalSiteVisitSettlementError.completedContentMismatch
        }
        return result
    }

    private static func canonicalJSON(_ raw: String?) throws -> String? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        let object = try JSONSerialization.jsonObject(with: data)
        let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: canonical, encoding: .utf8)
    }

    private static func remoteURL(_ raw: String?) -> String? {
        guard let raw,
              let scheme = URLComponents(string: raw)?.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return raw
    }

    private static func milliseconds(_ date: Date?) -> Int64? {
        date.map(milliseconds)
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
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
