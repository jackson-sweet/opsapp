//
//  SiteVisitSyncOperation.swift
//  OPS
//
//  Typed, save-free operation specifications for the site-visit queue.
//  Outbound sync resolves the current SwiftData snapshot; this envelope only
//  carries durable routing, tenancy, dependency, and completion intent.
//

import Foundation

enum SiteVisitSyncOperation {
    static let completionOperationType = "siteVisitComplete"
    static let mediaOperationType = "siteVisitMediaUpload"

    struct Payload: Codable, Equatable {
        let companyId: String
        let siteVisitId: String
        let entityId: String
        let completion: SiteVisitCompletionPayload?

        enum CodingKeys: String, CodingKey {
            case companyId = "company_id"
            case siteVisitId = "site_visit_id"
            case entityId = "entity_id"
            case completion
        }

        init(
            companyId: String,
            siteVisitId: String,
            entityId: String,
            completion: SiteVisitCompletionPayload? = nil
        ) {
            self.companyId = companyId.lowercased()
            self.siteVisitId = siteVisitId.lowercased()
            self.entityId = entityId.lowercased()
            self.completion = completion
        }
    }

    struct Specification: Equatable {
        let entityType: SyncEntityType
        let entityId: String
        let operationType: String
        let payload: Payload
        let changedFields: [String]
        let priority: Int

        var isCompletion: Bool {
            operationType == completionOperationType
        }
    }

    static func parent(_ visit: SiteVisit) -> Specification {
        Specification(
            entityType: .siteVisit,
            entityId: visit.id.lowercased(),
            operationType: operationType(
                deletedAt: visit.deletedAt,
                lastSyncedAt: visit.lastSyncedAt
            ),
            payload: Payload(
                companyId: visit.companyId,
                siteVisitId: visit.id,
                entityId: visit.id
            ),
            changedFields: [
                "opportunity_id", "project_id", "project_ref", "client_id",
                "client_ref", "scheduled_at", "duration_minutes", "assignee_ids",
                "status", "completed_at", "notes", "internal_notes", "measurements",
                "photos", "activity_id", "calendar_event_id", "deleted_at",
            ],
            priority: 0
        )
    }

    static func artifact(_ artifact: SiteVisitCaptureArtifact) -> Specification {
        Specification(
            entityType: .siteVisitArtifact,
            entityId: artifact.id.lowercased(),
            operationType: operationType(
                deletedAt: artifact.deletedAt,
                lastSyncedAt: artifact.lastSyncedAt
            ),
            payload: Payload(
                companyId: artifact.companyId,
                siteVisitId: artifact.siteVisitId,
                entityId: artifact.id
            ),
            changedFields: [
                "opportunity_id", "kind", "source", "title", "body", "asset_url",
                "rendered_asset_url", "thumbnail_url", "dimensions", "deck_design_id",
                "included_in_project_review", "captured_at", "deleted_at",
            ],
            priority: 1
        )
    }

    static func checklistAnswer(_ answer: SiteVisitChecklistAnswer) -> Specification {
        Specification(
            entityType: .siteVisitChecklistAnswer,
            entityId: answer.id.lowercased(),
            operationType: operationType(
                deletedAt: answer.deletedAt,
                lastSyncedAt: answer.lastSyncedAt
            ),
            payload: Payload(
                companyId: answer.companyId,
                siteVisitId: answer.siteVisitId,
                entityId: answer.id
            ),
            changedFields: [
                "opportunity_id", "site_visit_type_id", "field_id", "label", "kind",
                "required", "help_text", "sort_order", "answer_value", "deleted_at",
            ],
            priority: 1
        )
    }

    static func identityDraft(_ draft: SiteVisitIdentityDraft) -> Specification {
        Specification(
            entityType: .siteVisitIdentityDraft,
            entityId: draft.id.lowercased(),
            operationType: operationType(
                deletedAt: draft.deletedAt,
                lastSyncedAt: draft.lastSyncedAt
            ),
            payload: Payload(
                companyId: draft.companyId,
                siteVisitId: draft.siteVisitId,
                entityId: draft.id
            ),
            changedFields: [
                "opportunity_id", "client_id", "sub_client_id", "client_name",
                "contact_name", "preferred_email", "additional_emails", "phone_number",
                "address", "notes", "last_committed_at", "deleted_at",
            ],
            priority: 1
        )
    }

    static func media(_ artifact: SiteVisitCaptureArtifact) -> Specification {
        Specification(
            entityType: .siteVisitArtifact,
            entityId: artifact.id.lowercased(),
            operationType: mediaOperationType,
            payload: Payload(
                companyId: artifact.companyId,
                siteVisitId: artifact.siteVisitId,
                entityId: artifact.id
            ),
            changedFields: [
                "asset_url", "rendered_asset_url", "thumbnail_url",
            ],
            priority: 1
        )
    }

    static func completion(_ visit: SiteVisit) -> Specification {
        Specification(
            entityType: .siteVisit,
            entityId: visit.id.lowercased(),
            operationType: completionOperationType,
            payload: Payload(
                companyId: visit.companyId,
                siteVisitId: visit.id,
                entityId: visit.id,
                completion: SiteVisitCompletionPayload(
                    notes: visit.notes,
                    measurements: visit.measurements,
                    photos: visit.photos,
                    internalNotes: visit.internalNotes
                )
            ),
            changedFields: [
                "status", "completed_at", "notes", "measurements", "photos",
                "internal_notes", "activity_id",
            ],
            priority: 0
        )
    }

    private static func operationType(
        deletedAt: Date?,
        lastSyncedAt: Date?
    ) -> String {
        if deletedAt != nil { return "delete" }
        return lastSyncedAt == nil ? "create" : "update"
    }
}
