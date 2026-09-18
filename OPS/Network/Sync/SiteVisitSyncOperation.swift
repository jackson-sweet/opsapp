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
    static let discardOperationType = "siteVisitDiscard"
    static let stageOperationType = "siteVisitStageMove"

    struct Payload: Codable, Equatable {
        let companyId: String
        let siteVisitId: String
        let entityId: String
        let completion: SiteVisitCompletionPayload?
        let stageCommand: SiteVisitStageCommand?
        let writeCommand: SiteVisitWriteCommand?
        let discard: SiteVisitDiscardIntent?
        /// The deck a `deck_design` artifact points at. Carried so the queue
        /// can hold the artifact until that deck's own create has landed —
        /// `site_visit_artifacts.deck_design_id` is a foreign key (bug 6271078d).
        let deckDesignId: String?
        /// Set on a stopped send (parked or declined) when its record is edited
        /// on the phone afterwards; see `RestartMark`. Never sent to a server.
        let restartMark: RestartMark?

        /// Typing is local-only, so an edit made after a send stopped cannot
        /// restart it at the keystroke. The edit is recorded on the stopped
        /// send instead, as the stop it was made against: the send's status,
        /// last attempt and retry count. Saving the visit restarts the send only
        /// while that stop still stands — any later attempt, RETRY or decline
        /// changes one of them, so an edit the operator has since overruled, or
        /// a send has since carried, restarts nothing.
        struct RestartMark: Codable, Equatable {
            let status: String
            let lastAttemptedAt: Date?
            let retryCount: Int

            enum CodingKeys: String, CodingKey {
                case status
                case lastAttemptedAt = "last_attempted_at"
                case retryCount = "retry_count"
            }

            init(stoppedSend send: SyncOperation) {
                status = send.status
                lastAttemptedAt = send.lastAttemptedAt
                retryCount = send.retryCount
            }

            func stillStands(for send: SyncOperation) -> Bool {
                status == send.status
                    && lastAttemptedAt == send.lastAttemptedAt
                    && retryCount == send.retryCount
            }
        }

        enum CodingKeys: String, CodingKey {
            case companyId = "company_id"
            case siteVisitId = "site_visit_id"
            case entityId = "entity_id"
            case discard
            case completion
            case stageCommand = "stage_command"
            case writeCommand = "write_command"
            case deckDesignId = "deck_design_id"
            case restartMark = "restart_mark"
        }

        init(
            companyId: String,
            siteVisitId: String,
            entityId: String,
            completion: SiteVisitCompletionPayload? = nil,
            stageCommand: SiteVisitStageCommand? = nil,
            writeCommand: SiteVisitWriteCommand? = nil,
            discard: SiteVisitDiscardIntent? = nil,
            deckDesignId: String? = nil,
            restartMark: RestartMark? = nil
        ) {
            self.companyId = companyId.lowercased()
            self.siteVisitId = siteVisitId.lowercased()
            self.entityId = entityId.lowercased()
            self.completion = completion
            self.stageCommand = stageCommand
            self.writeCommand = writeCommand
            self.discard = discard
            self.deckDesignId = deckDesignId?.lowercased()
            self.restartMark = restartMark
        }

        /// This envelope with `mark` recorded (or cleared, for nil).
        func withRestartMark(_ mark: RestartMark?) -> Payload {
            Payload(
                companyId: companyId,
                siteVisitId: siteVisitId,
                entityId: entityId,
                completion: completion,
                stageCommand: stageCommand,
                writeCommand: writeCommand,
                discard: discard,
                deckDesignId: deckDesignId,
                restartMark: mark
            )
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
                "client_ref", "status", "notes", "internal_notes", "measurements",
                "photos", "deleted_at",
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
                entityId: artifact.id,
                deckDesignId: artifact.deckDesignId
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
        checklistAnswer(answer, forceChoiceProtocol: false)
    }

    static func checklistAnswer(_ answer: SiteVisitChecklistAnswer, forceChoiceProtocol: Bool) -> Specification {
        Specification(
            entityType: .siteVisitChecklistAnswer,
            entityId: answer.id.lowercased(),
            operationType: "siteVisitWrite",
            payload: Payload(
                companyId: answer.companyId,
                siteVisitId: answer.siteVisitId,
                entityId: answer.id,
                writeCommand: SiteVisitWriteModels.command(answer, forceChoiceProtocol: forceChoiceProtocol)
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
