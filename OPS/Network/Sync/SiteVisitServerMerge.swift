//
//  SiteVisitServerMerge.swift
//  OPS
//
//  Shared site-visit inbound merge used by both sync engines and Realtime.
//  Remote fields merge only when no durable local operation protects them;
//  remote tombstones and the server-owned activity id always converge.
//

import Foundation
import SwiftData

struct SiteVisitMergeReport: Equatable {
    var inserted = 0
    var updated = 0
}

enum SiteVisitMergeError: Error, Equatable {
    case companyMismatch(expected: String, received: String)
    case orphanedChild(table: String, childId: String, siteVisitId: String)
}

enum SiteVisitServerMerge {
    private enum EntityType {
        static let visit = "siteVisit"
        static let artifact = "siteVisitArtifact"
        static let checklistAnswer = "siteVisitChecklistAnswer"
        static let identityDraft = "siteVisitIdentityDraft"
    }

    private static let parentMutableFields: Set<String> = [
        "opportunity_id", "project_id", "project_ref", "client_id", "client_ref",
        "scheduled_at", "duration_minutes", "assignee_ids", "status", "completed_at",
        "notes", "internal_notes", "measurements", "photos", "calendar_event_id",
        "deleted_at",
    ]

    static func merge(
        bundle: SiteVisitBundleDTO,
        into context: ModelContext,
        now: Date = Date()
    ) throws -> SiteVisitMergeReport {
        try validate(bundle: bundle)
        var report = SiteVisitMergeReport()
        try context.transaction {
            try merge(visit: bundle.visit, into: context, now: now, report: &report)
            for draft in bundle.identityDrafts {
                try merge(identityDraft: draft, into: context, now: now, report: &report)
            }
            for answer in bundle.checklistAnswers {
                try merge(checklistAnswer: answer, into: context, now: now, report: &report)
            }
            for artifact in bundle.artifacts {
                try merge(artifact: artifact, into: context, now: now, report: &report)
            }
        }
        return report
    }

    static func merge(
        delta: SiteVisitDeltaBundleDTO,
        companyId: String,
        into context: ModelContext,
        now: Date = Date()
    ) throws -> SiteVisitMergeReport {
        let canonicalCompany = companyId.lowercased()

        // SwiftData's transaction closure does not discard inserted in-memory
        // models when the closure throws. Validate the complete dependency
        // graph before touching the context so one malformed late child cannot
        // leave an earlier parent staged for an unrelated future save.
        try validate(
            delta: delta,
            companyId: canonicalCompany,
            context: context
        )

        var report = SiteVisitMergeReport()
        try context.transaction {
            for visit in delta.visits {
                try merge(visit: visit, into: context, now: now, report: &report)
            }
            for draft in delta.identityDrafts {
                try requireParent(draft.siteVisitId, table: "site_visit_identity_drafts", childId: draft.id, context: context)
                try merge(identityDraft: draft, into: context, now: now, report: &report)
            }
            for answer in delta.checklistAnswers {
                try requireParent(answer.siteVisitId, table: "site_visit_checklist_answers", childId: answer.id, context: context)
                try merge(checklistAnswer: answer, into: context, now: now, report: &report)
            }
            for artifact in delta.artifacts {
                try requireParent(artifact.siteVisitId, table: "site_visit_artifacts", childId: artifact.id, context: context)
                try merge(artifact: artifact, into: context, now: now, report: &report)
            }
        }
        return report
    }

    /// Applies one realtime parent row through the exact same field-protection
    /// rules used by full and delta pulls.
    static func merge(
        visit: SiteVisitDTO,
        companyId: String,
        into context: ModelContext,
        now: Date = Date()
    ) throws -> SiteVisitMergeReport {
        try requireCompany(visit.companyId, expected: companyId)
        var report = SiteVisitMergeReport()
        try context.transaction {
            try merge(visit: visit, into: context, now: now, report: &report)
        }
        return report
    }

    /// Applies one realtime artifact only after its local parent exists. A
    /// child that beats its parent to the device is rejected and recovered by
    /// the next ordered delta pull instead of creating an orphan packet row.
    static func merge(
        artifact: SiteVisitArtifactDTO,
        companyId: String,
        into context: ModelContext,
        now: Date = Date()
    ) throws -> SiteVisitMergeReport {
        try requireCompany(artifact.companyId, expected: companyId)
        var report = SiteVisitMergeReport()
        try context.transaction {
            try requireParent(
                artifact.siteVisitId,
                table: "site_visit_artifacts",
                childId: artifact.id,
                context: context
            )
            try merge(artifact: artifact, into: context, now: now, report: &report)
        }
        return report
    }

    static func merge(
        checklistAnswer: SiteVisitChecklistAnswerDTO,
        companyId: String,
        into context: ModelContext,
        now: Date = Date()
    ) throws -> SiteVisitMergeReport {
        try requireCompany(checklistAnswer.companyId, expected: companyId)
        var report = SiteVisitMergeReport()
        try context.transaction {
            try requireParent(
                checklistAnswer.siteVisitId,
                table: "site_visit_checklist_answers",
                childId: checklistAnswer.id,
                context: context
            )
            try merge(
                checklistAnswer: checklistAnswer,
                into: context,
                now: now,
                report: &report
            )
        }
        return report
    }

    static func merge(
        identityDraft: SiteVisitIdentityDraftDTO,
        companyId: String,
        into context: ModelContext,
        now: Date = Date()
    ) throws -> SiteVisitMergeReport {
        try requireCompany(identityDraft.companyId, expected: companyId)
        var report = SiteVisitMergeReport()
        try context.transaction {
            try requireParent(
                identityDraft.siteVisitId,
                table: "site_visit_identity_drafts",
                childId: identityDraft.id,
                context: context
            )
            try merge(
                identityDraft: identityDraft,
                into: context,
                now: now,
                report: &report
            )
        }
        return report
    }

    // MARK: - Parent

    private static func merge(
        visit dto: SiteVisitDTO,
        into context: ModelContext,
        now: Date,
        report: inout SiteVisitMergeReport
    ) throws {
        if let existing = try fetch(SiteVisit.self, id: dto.id, in: context) {
            let isStale = existing.lastSyncedAt != nil
                && isOlder(dto.updatedAt, than: existing.updatedAt)
            let protection = protectedFields(
                entityType: EntityType.visit,
                entityId: dto.id,
                modelNeedsSync: existing.needsSync,
                fallbackFields: parentMutableFields,
                context: context,
                now: now
            )
            let accept = { field in !isStale && protection.accepts(field) }
            if accept("opportunity_id") { existing.opportunityId = dto.opportunityId }
            if accept("project_id") { existing.projectId = dto.projectId }
            if accept("project_ref") { existing.projectRef = dto.projectRef }
            if accept("client_id") { existing.clientId = dto.clientId }
            if accept("client_ref") { existing.clientRef = dto.clientRef }
            if accept("scheduled_at") { existing.scheduledAt = dto.scheduledAt }
            if accept("duration_minutes") { existing.durationMinutes = dto.durationMinutes }
            if accept("assignee_ids") { existing.assigneeIds = dto.assigneeIds }
            if accept("status") { existing.status = dto.status }
            if accept("completed_at") { existing.completedAt = dto.completedAt }
            if accept("notes") { existing.notes = dto.notes }
            if accept("internal_notes") { existing.internalNotes = dto.internalNotes }
            if accept("measurements") { existing.measurements = dto.measurements }
            if accept("photos") { existing.photos = dto.photos }
            if accept("calendar_event_id") { existing.calendarEventId = dto.calendarEventId }
            if dto.deletedAt != nil || accept("deleted_at") {
                existing.deletedAt = dto.deletedAt
            }

            // These are server-owned reconciliation slots, never authored by a
            // normal local edit after the row exists.
            if !isStale {
                existing.loggedActivityId = dto.activityId
                existing.createdBy = dto.createdBy
                if let createdAt = dto.createdAt { existing.createdAt = createdAt }
                existing.updatedAt = dto.updatedAt
            }
            existing.lastSyncedAt = now
            existing.needsSync = protection.hasLocalWork
            report.updated += 1
        } else {
            let model = SiteVisit(
                id: dto.id,
                opportunityId: dto.opportunityId,
                companyId: dto.companyId,
                projectId: dto.projectId,
                projectRef: dto.projectRef,
                clientId: dto.clientId,
                clientRef: dto.clientRef,
                status: dto.status,
                scheduledAt: dto.scheduledAt,
                durationMinutes: dto.durationMinutes,
                assigneeIds: dto.assigneeIds,
                createdBy: dto.createdBy,
                loggedActivityId: dto.activityId,
                createdAt: dto.createdAt ?? dto.scheduledAt
            )
            model.completedAt = dto.completedAt
            model.notes = dto.notes
            model.internalNotes = dto.internalNotes
            model.measurements = dto.measurements
            model.photos = dto.photos
            model.calendarEventId = dto.calendarEventId
            model.updatedAt = dto.updatedAt
            model.deletedAt = dto.deletedAt
            model.lastSyncedAt = now
            model.needsSync = false
            context.insert(model)
            report.inserted += 1
        }
    }

    // MARK: - Artifact

    private static func merge(
        artifact dto: SiteVisitArtifactDTO,
        into context: ModelContext,
        now: Date,
        report: inout SiteVisitMergeReport
    ) throws {
        let fields: Set<String> = [
            "opportunity_id", "kind", "source", "title", "body", "asset_url",
            "rendered_asset_url", "thumbnail_url", "dimensions", "deck_design_id",
            "included_in_project_review", "captured_at", "deleted_at",
        ]
        if let existing = try fetch(SiteVisitCaptureArtifact.self, id: dto.id, in: context) {
            let isStale = existing.lastSyncedAt != nil
                && isOlder(dto.updatedAt, than: existing.updatedAt)
            let protection = protectedFields(
                entityType: EntityType.artifact,
                entityId: dto.id,
                modelNeedsSync: existing.needsSync,
                fallbackFields: fields,
                context: context,
                now: now
            )
            let accept = { field in !isStale && protection.accepts(field) }
            if accept("opportunity_id") { existing.opportunityId = dto.opportunityId }
            if accept("kind") { existing.kind = dto.kind }
            if accept("source") { existing.source = dto.source }
            if accept("title") { existing.title = dto.title }
            if accept("body") { existing.body = dto.body }
            if accept("asset_url") { existing.localAssetURL = dto.assetURL }
            if accept("rendered_asset_url") { existing.renderedAssetURL = dto.renderedAssetURL }
            if accept("thumbnail_url") { existing.thumbnailURL = dto.thumbnailURL }
            if accept("dimensions") { existing.dimensionsJSON = try dimensionsJSON(dto.dimensions) }
            if accept("deck_design_id") { existing.deckDesignId = dto.deckDesignId }
            if accept("included_in_project_review") {
                existing.includedInProjectReview = dto.includedInProjectReview
            }
            if accept("captured_at") { existing.capturedAt = dto.capturedAt }
            if dto.deletedAt != nil || accept("deleted_at") { existing.deletedAt = dto.deletedAt }
            if !isStale {
                existing.createdBy = dto.createdBy
                existing.createdAt = dto.createdAt
                existing.updatedAt = dto.updatedAt
            }
            existing.lastSyncedAt = now
            existing.needsSync = protection.hasLocalWork
            report.updated += 1
        } else {
            let model = SiteVisitCaptureArtifact(
                id: dto.id,
                siteVisitId: dto.siteVisitId,
                companyId: dto.companyId,
                opportunityId: dto.opportunityId,
                kind: dto.kind,
                source: dto.source,
                title: dto.title,
                body: dto.body,
                localAssetURL: dto.assetURL,
                renderedAssetURL: dto.renderedAssetURL,
                thumbnailURL: dto.thumbnailURL,
                dimensionsJSON: try dimensionsJSON(dto.dimensions),
                deckDesignId: dto.deckDesignId,
                includedInProjectReview: dto.includedInProjectReview,
                capturedAt: dto.capturedAt,
                createdBy: dto.createdBy,
                createdAt: dto.createdAt
            )
            model.updatedAt = dto.updatedAt
            model.deletedAt = dto.deletedAt
            model.lastSyncedAt = now
            model.needsSync = false
            context.insert(model)
            report.inserted += 1
        }
    }

    // MARK: - Checklist answer

    private static func merge(
        checklistAnswer dto: SiteVisitChecklistAnswerDTO,
        into context: ModelContext,
        now: Date,
        report: inout SiteVisitMergeReport
    ) throws {
        let fields: Set<String> = [
            "opportunity_id", "site_visit_type_id", "field_id", "label", "kind",
            "required", "help_text", "sort_order", "answer_value", "deleted_at",
        ]
        if let existing = try fetch(SiteVisitChecklistAnswer.self, id: dto.id, in: context) {
            let isStale = existing.lastSyncedAt != nil
                && isOlder(dto.updatedAt, than: existing.updatedAt)
            let protection = protectedFields(
                entityType: EntityType.checklistAnswer,
                entityId: dto.id,
                modelNeedsSync: existing.needsSync,
                fallbackFields: fields,
                context: context,
                now: now
            )
            let accept = { field in !isStale && protection.accepts(field) }
            if accept("opportunity_id") { existing.opportunityId = dto.opportunityId }
            if accept("site_visit_type_id") { existing.siteVisitTypeId = dto.siteVisitTypeId }
            if accept("field_id") { existing.fieldId = dto.fieldId }
            if accept("label") { existing.label = dto.label }
            if accept("kind") { existing.kind = dto.kind }
            if accept("required") { existing.required = dto.required }
            if accept("help_text") { existing.helpText = dto.helpText }
            if accept("sort_order") { existing.sortOrder = dto.sortOrder }
            if accept("answer_value") { existing.answerValue = dto.answerValue }
            if dto.deletedAt != nil || accept("deleted_at") { existing.deletedAt = dto.deletedAt }
            if !isStale {
                existing.createdBy = dto.createdBy
                existing.createdAt = dto.createdAt
                existing.updatedAt = dto.updatedAt
            }
            existing.lastSyncedAt = now
            existing.needsSync = protection.hasLocalWork
            report.updated += 1
        } else {
            let model = SiteVisitChecklistAnswer(
                id: dto.id,
                siteVisitId: dto.siteVisitId,
                companyId: dto.companyId,
                opportunityId: dto.opportunityId,
                siteVisitTypeId: dto.siteVisitTypeId,
                fieldId: dto.fieldId,
                label: dto.label,
                kind: dto.kind,
                required: dto.required,
                helpText: dto.helpText,
                sortOrder: dto.sortOrder,
                answerValue: dto.answerValue,
                createdBy: dto.createdBy,
                createdAt: dto.createdAt
            )
            model.updatedAt = dto.updatedAt
            model.deletedAt = dto.deletedAt
            model.lastSyncedAt = now
            model.needsSync = false
            context.insert(model)
            report.inserted += 1
        }
    }

    // MARK: - Identity draft

    private static func merge(
        identityDraft dto: SiteVisitIdentityDraftDTO,
        into context: ModelContext,
        now: Date,
        report: inout SiteVisitMergeReport
    ) throws {
        let fields: Set<String> = [
            "opportunity_id", "client_id", "sub_client_id", "client_name",
            "contact_name", "preferred_email", "additional_emails", "phone_number",
            "address", "notes", "last_committed_at", "deleted_at",
        ]
        if let existing = try fetch(SiteVisitIdentityDraft.self, id: dto.id, in: context) {
            let isStale = existing.lastSyncedAt != nil
                && isOlder(dto.updatedAt, than: existing.updatedAt)
            let protection = protectedFields(
                entityType: EntityType.identityDraft,
                entityId: dto.id,
                modelNeedsSync: existing.needsSync,
                fallbackFields: fields,
                context: context,
                now: now
            )
            let accept = { field in !isStale && protection.accepts(field) }
            if accept("opportunity_id") { existing.opportunityId = dto.opportunityId }
            if accept("client_id") { existing.clientId = dto.clientId }
            if accept("sub_client_id") { existing.subClientId = dto.subClientId }
            if accept("client_name") { existing.clientName = dto.clientName }
            if accept("contact_name") { existing.contactName = dto.contactName }
            if accept("preferred_email") { existing.preferredEmail = dto.preferredEmail }
            if accept("additional_emails") { existing.additionalEmails = dto.additionalEmails }
            if accept("phone_number") { existing.phoneNumber = dto.phoneNumber }
            if accept("address") { existing.address = dto.address }
            if accept("notes") { existing.notes = dto.notes }
            if accept("last_committed_at") { existing.lastCommittedAt = dto.lastCommittedAt }
            if dto.deletedAt != nil || accept("deleted_at") { existing.deletedAt = dto.deletedAt }
            if !isStale {
                existing.createdBy = dto.createdBy
                existing.createdAt = dto.createdAt
                existing.updatedAt = dto.updatedAt
            }
            existing.lastSyncedAt = now
            existing.needsSync = protection.hasLocalWork
            report.updated += 1
        } else {
            let model = SiteVisitIdentityDraft(
                id: dto.id,
                siteVisitId: dto.siteVisitId,
                companyId: dto.companyId,
                opportunityId: dto.opportunityId,
                clientId: dto.clientId,
                subClientId: dto.subClientId,
                searchText: "",
                clientName: dto.clientName,
                contactName: dto.contactName,
                preferredEmail: dto.preferredEmail,
                additionalEmails: dto.additionalEmails,
                phoneNumber: dto.phoneNumber,
                address: dto.address,
                notes: dto.notes,
                createdBy: dto.createdBy,
                createdAt: dto.createdAt
            )
            model.updatedAt = dto.updatedAt
            model.lastCommittedAt = dto.lastCommittedAt
            model.deletedAt = dto.deletedAt
            model.lastSyncedAt = now
            model.needsSync = false
            context.insert(model)
            report.inserted += 1
        }
    }

    // MARK: - Validation and field protection

    private static func validate(bundle: SiteVisitBundleDTO) throws {
        let companyId = bundle.visit.companyId
        for child in bundle.identityDrafts {
            try validateChild(
                childCompanyId: child.companyId,
                childVisitId: child.siteVisitId,
                childId: child.id,
                table: "site_visit_identity_drafts",
                parent: bundle.visit,
                companyId: companyId
            )
        }
        for child in bundle.checklistAnswers {
            try validateChild(
                childCompanyId: child.companyId,
                childVisitId: child.siteVisitId,
                childId: child.id,
                table: "site_visit_checklist_answers",
                parent: bundle.visit,
                companyId: companyId
            )
        }
        for child in bundle.artifacts {
            try validateChild(
                childCompanyId: child.companyId,
                childVisitId: child.siteVisitId,
                childId: child.id,
                table: "site_visit_artifacts",
                parent: bundle.visit,
                companyId: companyId
            )
        }
    }

    private static func validate(
        delta: SiteVisitDeltaBundleDTO,
        companyId: String,
        context: ModelContext
    ) throws {
        for visit in delta.visits {
            try requireCompany(visit.companyId, expected: companyId)
        }
        for child in delta.identityDrafts {
            try requireCompany(child.companyId, expected: companyId)
        }
        for child in delta.checklistAnswers {
            try requireCompany(child.companyId, expected: companyId)
        }
        for child in delta.artifacts {
            try requireCompany(child.companyId, expected: companyId)
        }

        let incomingParentIds = Set(delta.visits.map(\.id))
        let localParentIds = Set(
            try context.fetch(FetchDescriptor<SiteVisit>())
                .filter { $0.companyId.lowercased() == companyId }
                .map { $0.id.lowercased() }
        )
        let validParentIds = incomingParentIds.union(localParentIds)

        for child in delta.identityDrafts where !validParentIds.contains(child.siteVisitId) {
            throw SiteVisitMergeError.orphanedChild(
                table: "site_visit_identity_drafts",
                childId: child.id,
                siteVisitId: child.siteVisitId
            )
        }
        for child in delta.checklistAnswers where !validParentIds.contains(child.siteVisitId) {
            throw SiteVisitMergeError.orphanedChild(
                table: "site_visit_checklist_answers",
                childId: child.id,
                siteVisitId: child.siteVisitId
            )
        }
        for child in delta.artifacts where !validParentIds.contains(child.siteVisitId) {
            throw SiteVisitMergeError.orphanedChild(
                table: "site_visit_artifacts",
                childId: child.id,
                siteVisitId: child.siteVisitId
            )
        }
    }

    private static func validateChild(
        childCompanyId: String,
        childVisitId: String,
        childId: String,
        table: String,
        parent: SiteVisitDTO,
        companyId: String
    ) throws {
        guard childCompanyId == companyId else {
            throw SiteVisitMergeError.companyMismatch(
                expected: companyId,
                received: childCompanyId
            )
        }
        guard childVisitId == parent.id else {
            throw SiteVisitMergeError.orphanedChild(
                table: table,
                childId: childId,
                siteVisitId: childVisitId
            )
        }
    }

    private static func requireCompany(
        _ received: String,
        expected: String
    ) throws {
        let canonicalExpected = expected.lowercased()
        guard received.lowercased() == canonicalExpected else {
            throw SiteVisitMergeError.companyMismatch(
                expected: canonicalExpected,
                received: received.lowercased()
            )
        }
    }

    private static func requireParent(
        _ siteVisitId: String,
        table: String,
        childId: String,
        context: ModelContext
    ) throws {
        guard try fetch(SiteVisit.self, id: siteVisitId, in: context) != nil else {
            throw SiteVisitMergeError.orphanedChild(
                table: table,
                childId: childId,
                siteVisitId: siteVisitId
            )
        }
    }

    private struct Protection {
        let fields: Set<String>
        let hasLocalWork: Bool

        func accepts(_ field: String) -> Bool {
            !fields.contains(field)
        }
    }

    private static func protectedFields(
        entityType: String,
        entityId: String,
        modelNeedsSync: Bool,
        fallbackFields: Set<String>,
        context: ModelContext,
        now: Date
    ) -> Protection {
        let lower = entityId.lowercased()
        let upper = entityId.uppercased()
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate {
                $0.entityType == entityType
                    && ($0.entityId == entityId || $0.entityId == lower || $0.entityId == upper)
            }
        )
        let operations = (try? context.fetch(descriptor)) ?? []
        var protected = SyncFieldGuard.protectedFields(from: operations, now: now)
        let unresolved = operations.contains {
            ["pending", "inProgress", "failed", "parked"].contains($0.status)
        }

        // Historical local writes may predate the durable operation queue. Do
        // not let the first inbound echo erase them; the orphan sweep will
        // synthesize the missing operation in the outbound task.
        if modelNeedsSync && operations.isEmpty {
            protected.formUnion(fallbackFields)
        }
        return Protection(
            fields: protected,
            hasLocalWork: unresolved || (modelNeedsSync && operations.isEmpty)
        )
    }

    private static func fetch<Model: PersistentModel>(
        _ type: Model.Type,
        id: String,
        in context: ModelContext
    ) throws -> Model? where Model: Identifiable, Model.ID == String {
        let lower = id.lowercased()
        let upper = id.uppercased()
        return try context.fetch(FetchDescriptor<Model>()).first {
            $0.id == id || $0.id == lower || $0.id == upper
        }
    }

    private static func dimensionsJSON(_ dimensions: DimensionsData?) throws -> String? {
        guard let dimensions else { return nil }
        let data = try DimensionsData.jsonEncoder.encode(dimensions)
        return String(data: data, encoding: .utf8)
    }

    private static func isOlder(_ incoming: Date?, than current: Date?) -> Bool {
        guard let incoming, let current else { return false }
        return incoming < current
    }
}
