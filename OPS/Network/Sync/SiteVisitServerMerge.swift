//
//  SiteVisitServerMerge.swift
//  OPS
//
//  Shared site-visit inbound merge used by both sync engines and Realtime.
//  Remote fields merge only when no durable local operation protects them;
//  remote tombstones and the server-owned activity id always converge.
//
//  Two hard rules keep this off the crash path that killed the backlog drain
//  (bug 3eef6ad7):
//
//  1. Every row lookup is a predicate-scoped, fetchLimit-1 fetch. A whole-table
//     fetch + in-memory id filter materializes and registers every site-visit
//     row in the actor's context on every echo, which — interleaved with the
//     drain's unique-id `context.transaction` saves — desynced the context's
//     registration map and hit a fatal "Duplicate registration attempt".
//  2. A merge that would change nothing opens no transaction at all. Realtime
//     echoes the very rows the drain just pushed, so most inbound work is
//     redundant; bumping `lastSyncedAt` alone forced a full save cycle per echo.
//

import Foundation
import SwiftData

struct SiteVisitMergeReport: Equatable {
    var inserted = 0
    var updated = 0
    /// Rows whose incoming snapshot matched local state exactly. These take no
    /// transaction and no write — a redundant echo must be free.
    var unchanged = 0
}

enum SiteVisitMergeError: Error, Equatable {
    case companyMismatch(expected: String, received: String)
    case orphanedChild(table: String, childId: String, siteVisitId: String)
    case ambiguousChecklistAnswers(
        siteVisitId: String,
        fieldId: String,
        answerIds: [String]
    )
    case unsafeChecklistAnswer(answerId: String, reason: String)
    case unsafeChecklistOperation(operationId: UUID, reason: String)
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

    private static let checklistUnresolvedStatuses: Set<String> = [
        "pending", "inProgress", "failed", "parked",
    ]

    /// Lifecycles that are finished with the row: nothing left to migrate, and
    /// never a collision. `declined` joins `completed` here because the operator
    /// explicitly stopped that send from PENDING WORK — canonicalization must
    /// treat it as settled rather than failing closed on an unknown status.
    private static let checklistResolvedStatuses: Set<String> = [
        "completed", "declined",
    ]

    /// What one row's merge resolved to. The write is deferred so the caller can
    /// decide whether a transaction is needed at all.
    private enum MergeOutcome {
        case unchanged
        case inserted(() -> Void)
        case updated(() -> Void)

        var requiresWrite: Bool {
            if case .unchanged = self { return false }
            return true
        }
    }

    private struct ChecklistLogicalIdentity: Hashable {
        let siteVisitId: String
        let fieldId: String
    }

    private static func apply(
        _ outcome: MergeOutcome,
        report: inout SiteVisitMergeReport
    ) {
        switch outcome {
        case .unchanged:
            report.unchanged += 1
        case .inserted(let write):
            write()
            report.inserted += 1
        case .updated(let write):
            write()
            report.updated += 1
        }
    }

    static func merge(
        bundle: SiteVisitBundleDTO,
        into context: ModelContext,
        now: Date = Date()
    ) throws -> SiteVisitMergeReport {
        try validate(bundle: bundle, context: context)
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
        let outcome = try planMerge(visit: visit, in: context, now: now)
        guard outcome.requiresWrite else {
            report.unchanged += 1
            return report
        }
        try context.transaction {
            apply(outcome, report: &report)
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
        // Parent check and diff are pure reads, so a redundant echo resolves
        // without ever opening a transaction.
        try requireParent(
            artifact.siteVisitId,
            table: "site_visit_artifacts",
            childId: artifact.id,
            context: context
        )
        var report = SiteVisitMergeReport()
        let outcome = try planMerge(artifact: artifact, in: context, now: now)
        guard outcome.requiresWrite else {
            report.unchanged += 1
            return report
        }
        try context.transaction {
            apply(outcome, report: &report)
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
        try requireParent(
            checklistAnswer.siteVisitId,
            table: "site_visit_checklist_answers",
            childId: checklistAnswer.id,
            context: context
        )
        var report = SiteVisitMergeReport()
        let outcome = try planMerge(checklistAnswer: checklistAnswer, in: context, now: now)
        guard outcome.requiresWrite else {
            report.unchanged += 1
            return report
        }
        try context.transaction {
            apply(outcome, report: &report)
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
        try requireParent(
            identityDraft.siteVisitId,
            table: "site_visit_identity_drafts",
            childId: identityDraft.id,
            context: context
        )
        var report = SiteVisitMergeReport()
        let outcome = try planMerge(identityDraft: identityDraft, in: context, now: now)
        guard outcome.requiresWrite else {
            report.unchanged += 1
            return report
        }
        try context.transaction {
            apply(outcome, report: &report)
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
        apply(try planMerge(visit: dto, in: context, now: now), report: &report)
    }

    private static func planMerge(
        visit dto: SiteVisitDTO,
        in context: ModelContext,
        now: Date
    ) throws -> MergeOutcome {
        guard let existing = try fetchVisit(id: dto.id, in: context) else {
            return .inserted {
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
                model.bookedAt = dto.bookedAt
                model.reminderLeadMinutes = dto.reminderLeadMinutes
                model.appointmentHandoffId = dto.appointmentHandoffId
                model.appointmentKind = dto.appointmentKind
                model.appointmentTitle = dto.appointmentTitle
                model.appointmentLocation = dto.appointmentLocation
                model.updatedAt = dto.updatedAt
                model.deletedAt = dto.deletedAt
                model.lastSyncedAt = now
                model.needsSync = false
                context.insert(model)
            }
        }

        let isStale = existing.lastSyncedAt != nil
            && isOlder(dto.updatedAt, than: existing.updatedAt)
        let protection = try protectedFields(
            entityType: EntityType.visit,
            entityId: dto.id,
            modelNeedsSync: existing.needsSync,
            fallbackFields: parentMutableFields,
            context: context,
            now: now
        )
        let accept = { field in !isStale && protection.accepts(field) }
        let acceptsTombstone = dto.deletedAt != nil || accept("deleted_at")

        let changed =
            (accept("opportunity_id") && existing.opportunityId != dto.opportunityId)
            || (accept("project_id") && existing.projectId != dto.projectId)
            || (accept("project_ref") && existing.projectRef != dto.projectRef)
            || (accept("client_id") && existing.clientId != dto.clientId)
            || (accept("client_ref") && existing.clientRef != dto.clientRef)
            || (accept("scheduled_at") && existing.scheduledAt != dto.scheduledAt)
            || (accept("duration_minutes") && existing.durationMinutes != dto.durationMinutes)
            || (accept("assignee_ids") && existing.assigneeIds != dto.assigneeIds)
            || (accept("status") && existing.status != dto.status)
            || (accept("completed_at") && existing.completedAt != dto.completedAt)
            || (accept("notes") && existing.notes != dto.notes)
            || (accept("internal_notes") && existing.internalNotes != dto.internalNotes)
            || (accept("measurements") && existing.measurements != dto.measurements)
            || (accept("photos") && existing.photos != dto.photos)
            || (accept("calendar_event_id") && existing.calendarEventId != dto.calendarEventId)
            || (acceptsTombstone && existing.deletedAt != dto.deletedAt)
            || (!isStale && (
                existing.loggedActivityId != dto.activityId
                    || existing.bookedAt != dto.bookedAt
                    || existing.reminderLeadMinutes != dto.reminderLeadMinutes
                    || existing.appointmentHandoffId != dto.appointmentHandoffId
                    || existing.appointmentKind != dto.appointmentKind
                    || existing.appointmentTitle != dto.appointmentTitle
                    || existing.appointmentLocation != dto.appointmentLocation
                    || existing.createdBy != dto.createdBy
                    || (dto.createdAt.map { $0 != existing.createdAt } ?? false)
                    || existing.updatedAt != dto.updatedAt
            ))
            // A row that has never been marked synced must record that it now is.
            || existing.lastSyncedAt == nil
            || existing.needsSync != protection.hasLocalWork

        guard changed else { return .unchanged }

        return .updated {
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
            if acceptsTombstone {
                existing.deletedAt = dto.deletedAt
            }

            // These are server-owned reconciliation slots, never authored by a
            // normal local edit after the row exists. Booking state belongs
            // here: only the booking RPCs write booked_at/reminder_lead_minutes.
            if !isStale {
                existing.loggedActivityId = dto.activityId
                existing.bookedAt = dto.bookedAt
                existing.reminderLeadMinutes = dto.reminderLeadMinutes
                existing.appointmentHandoffId = dto.appointmentHandoffId
                existing.appointmentKind = dto.appointmentKind
                existing.appointmentTitle = dto.appointmentTitle
                existing.appointmentLocation = dto.appointmentLocation
                existing.createdBy = dto.createdBy
                if let createdAt = dto.createdAt { existing.createdAt = createdAt }
                existing.updatedAt = dto.updatedAt
            }
            existing.lastSyncedAt = now
            existing.needsSync = protection.hasLocalWork
        }
    }

    // MARK: - Artifact

    private static func merge(
        artifact dto: SiteVisitArtifactDTO,
        into context: ModelContext,
        now: Date,
        report: inout SiteVisitMergeReport
    ) throws {
        apply(try planMerge(artifact: dto, in: context, now: now), report: &report)
    }

    private static func planMerge(
        artifact dto: SiteVisitArtifactDTO,
        in context: ModelContext,
        now: Date
    ) throws -> MergeOutcome {
        let fields: Set<String> = [
            "opportunity_id", "kind", "source", "title", "body", "asset_url",
            "rendered_asset_url", "thumbnail_url", "dimensions", "deck_design_id",
            "included_in_project_review", "captured_at", "deleted_at",
        ]
        let dimensions = try dimensionsJSON(dto.dimensions)

        guard let existing = try fetchArtifact(id: dto.id, in: context) else {
            return .inserted {
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
                    dimensionsJSON: dimensions,
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
            }
        }

        let isStale = existing.lastSyncedAt != nil
            && isOlder(dto.updatedAt, than: existing.updatedAt)
        let protection = try protectedFields(
            entityType: EntityType.artifact,
            entityId: dto.id,
            modelNeedsSync: existing.needsSync,
            fallbackFields: fields,
            context: context,
            now: now
        )
        let accept = { field in !isStale && protection.accepts(field) }
        let acceptsTombstone = dto.deletedAt != nil || accept("deleted_at")

        let changed =
            (accept("opportunity_id") && existing.opportunityId != dto.opportunityId)
            || (accept("kind") && existing.kind != dto.kind)
            || (accept("source") && existing.source != dto.source)
            || (accept("title") && existing.title != dto.title)
            || (accept("body") && existing.body != dto.body)
            || (accept("asset_url") && existing.localAssetURL != dto.assetURL)
            || (accept("rendered_asset_url") && existing.renderedAssetURL != dto.renderedAssetURL)
            || (accept("thumbnail_url") && existing.thumbnailURL != dto.thumbnailURL)
            || (accept("dimensions") && existing.dimensionsJSON != dimensions)
            || (accept("deck_design_id") && existing.deckDesignId != dto.deckDesignId)
            || (accept("included_in_project_review")
                && existing.includedInProjectReview != dto.includedInProjectReview)
            || (accept("captured_at") && existing.capturedAt != dto.capturedAt)
            || (acceptsTombstone && existing.deletedAt != dto.deletedAt)
            || (!isStale && (
                existing.createdBy != dto.createdBy
                    || existing.createdAt != dto.createdAt
                    || existing.updatedAt != dto.updatedAt
            ))
            || existing.lastSyncedAt == nil
            || existing.needsSync != protection.hasLocalWork

        guard changed else { return .unchanged }

        return .updated {
            if accept("opportunity_id") { existing.opportunityId = dto.opportunityId }
            if accept("kind") { existing.kind = dto.kind }
            if accept("source") { existing.source = dto.source }
            if accept("title") { existing.title = dto.title }
            if accept("body") { existing.body = dto.body }
            if accept("asset_url") { existing.localAssetURL = dto.assetURL }
            if accept("rendered_asset_url") { existing.renderedAssetURL = dto.renderedAssetURL }
            if accept("thumbnail_url") { existing.thumbnailURL = dto.thumbnailURL }
            if accept("dimensions") { existing.dimensionsJSON = dimensions }
            if accept("deck_design_id") { existing.deckDesignId = dto.deckDesignId }
            if accept("included_in_project_review") {
                existing.includedInProjectReview = dto.includedInProjectReview
            }
            if accept("captured_at") { existing.capturedAt = dto.capturedAt }
            if acceptsTombstone { existing.deletedAt = dto.deletedAt }
            if !isStale {
                existing.createdBy = dto.createdBy
                existing.createdAt = dto.createdAt
                existing.updatedAt = dto.updatedAt
            }
            existing.lastSyncedAt = now
            existing.needsSync = protection.hasLocalWork
        }
    }

    // MARK: - Checklist answer

    private struct ChecklistOperationMigration {
        let operation: SyncOperation
        let payload: Data
    }

    private struct ChecklistAnswerResolution {
        let answer: SiteVisitChecklistAnswer?
        let canonicalId: String
        let operationMigrations: [ChecklistOperationMigration]

        var requiresIdentityMigration: Bool {
            guard let answer else { return false }
            return answer.id.lowercased() != canonicalId.lowercased()
        }

        func applyIdentityMigration() {
            guard requiresIdentityMigration, let answer else { return }
            answer.id = canonicalId.lowercased()
            for migration in operationMigrations {
                migration.operation.entityId = canonicalId.lowercased()
                migration.operation.payload = migration.payload
            }
        }
    }

    private static func resolveChecklistAnswer(
        _ dto: SiteVisitChecklistAnswerDTO,
        in context: ModelContext
    ) throws -> ChecklistAnswerResolution {
        let exact = try fetchAnswer(id: dto.id, in: context)
        if let exact {
            try requireCompany(exact.companyId, expected: dto.companyId)
            guard exact.siteVisitId.lowercased() == dto.siteVisitId.lowercased() else {
                throw SiteVisitMergeError.unsafeChecklistAnswer(
                    answerId: exact.id,
                    reason: "Canonical id belongs to a different site visit"
                )
            }
        }

        // A tombstone is identified only by its server id. The active logical
        // identity may now belong to a newer replacement answer and must not be
        // absorbed into an older deleted row.
        guard dto.deletedAt == nil else {
            return ChecklistAnswerResolution(
                answer: exact,
                canonicalId: dto.id,
                operationMigrations: []
            )
        }

        let logicalMatches = try fetchActiveAnswers(
            siteVisitId: dto.siteVisitId,
            fieldId: dto.fieldId,
            in: context
        )
        if logicalMatches.count > 1 {
            throw SiteVisitMergeError.ambiguousChecklistAnswers(
                siteVisitId: dto.siteVisitId,
                fieldId: dto.fieldId,
                answerIds: logicalMatches.map(\.id).sorted()
            )
        }

        if let exact {
            let conflicts = logicalMatches.filter {
                $0.id.lowercased() != exact.id.lowercased()
            }
            guard conflicts.isEmpty else {
                throw SiteVisitMergeError.ambiguousChecklistAnswers(
                    siteVisitId: dto.siteVisitId,
                    fieldId: dto.fieldId,
                    answerIds: ([exact.id] + conflicts.map(\.id)).sorted()
                )
            }
            return ChecklistAnswerResolution(
                answer: exact,
                canonicalId: dto.id,
                operationMigrations: []
            )
        }

        guard let logical = logicalMatches.first else {
            return ChecklistAnswerResolution(
                answer: nil,
                canonicalId: dto.id,
                operationMigrations: []
            )
        }
        try requireCompany(logical.companyId, expected: dto.companyId)
        let operationMigrations = try prepareChecklistOperationMigrations(
            from: logical.id,
            to: dto.id,
            companyId: dto.companyId,
            siteVisitId: dto.siteVisitId,
            context: context
        )
        return ChecklistAnswerResolution(
            answer: logical,
            canonicalId: dto.id,
            operationMigrations: operationMigrations
        )
    }

    private static func prepareChecklistOperationMigrations(
        from oldId: String,
        to canonicalId: String,
        companyId: String,
        siteVisitId: String,
        context: ModelContext
    ) throws -> [ChecklistOperationMigration] {
        let sourceOperations = try fetchChecklistOperations(
            answerId: oldId,
            in: context
        )
        if let unsafe = sourceOperations.first(where: {
            !checklistResolvedStatuses.contains($0.status)
                && !checklistUnresolvedStatuses.contains($0.status)
        }) {
            throw SiteVisitMergeError.unsafeChecklistOperation(
                operationId: unsafe.id,
                reason: "Unknown or quarantined operation lifecycle \(unsafe.status)"
            )
        }

        let unresolved = sourceOperations.filter {
            checklistUnresolvedStatuses.contains($0.status)
        }
        let targetOperations = try fetchChecklistOperations(
            answerId: canonicalId,
            in: context
        )
        if let collision = targetOperations.first(where: {
            !checklistResolvedStatuses.contains($0.status)
        }) {
            throw SiteVisitMergeError.unsafeChecklistOperation(
                operationId: collision.id,
                reason: "Canonical answer already has unresolved queue work"
            )
        }

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        return try unresolved.map { operation in
            guard ["create", "update", "delete"].contains(operation.operationType) else {
                throw SiteVisitMergeError.unsafeChecklistOperation(
                    operationId: operation.id,
                    reason: "Unexpected checklist operation type \(operation.operationType)"
                )
            }

            let envelope: SiteVisitSyncOperation.Payload
            do {
                envelope = try decoder.decode(
                    SiteVisitSyncOperation.Payload.self,
                    from: operation.payload
                )
            } catch {
                throw SiteVisitMergeError.unsafeChecklistOperation(
                    operationId: operation.id,
                    reason: "Operation payload is not a site-visit envelope"
                )
            }

            guard envelope.entityId.lowercased() == oldId.lowercased(),
                  envelope.siteVisitId.lowercased() == siteVisitId.lowercased(),
                  envelope.companyId.lowercased() == companyId.lowercased(),
                  envelope.completion == nil else {
                throw SiteVisitMergeError.unsafeChecklistOperation(
                    operationId: operation.id,
                    reason: "Operation routing does not match the local checklist answer"
                )
            }

            let replacement = SiteVisitSyncOperation.Payload(
                companyId: envelope.companyId,
                siteVisitId: envelope.siteVisitId,
                entityId: canonicalId
            )
            do {
                return ChecklistOperationMigration(
                    operation: operation,
                    payload: try encoder.encode(replacement)
                )
            } catch {
                throw SiteVisitMergeError.unsafeChecklistOperation(
                    operationId: operation.id,
                    reason: "Canonical operation payload could not be encoded"
                )
            }
        }
    }

    private static func merge(
        checklistAnswer dto: SiteVisitChecklistAnswerDTO,
        into context: ModelContext,
        now: Date,
        report: inout SiteVisitMergeReport
    ) throws {
        apply(try planMerge(checklistAnswer: dto, in: context, now: now), report: &report)
    }

    private static func planMerge(
        checklistAnswer dto: SiteVisitChecklistAnswerDTO,
        in context: ModelContext,
        now: Date
    ) throws -> MergeOutcome {
        let fields: Set<String> = [
            "opportunity_id", "site_visit_type_id", "field_id", "label", "kind",
            "required", "help_text", "sort_order", "answer_value", "deleted_at",
        ]

        let resolution = try resolveChecklistAnswer(dto, in: context)
        guard let existing = resolution.answer else {
            return .inserted {
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
            }
        }

        let isStale = existing.lastSyncedAt != nil
            && isOlder(dto.updatedAt, than: existing.updatedAt)
        let protection = try protectedFields(
            entityType: EntityType.checklistAnswer,
            entityId: existing.id,
            modelNeedsSync: existing.needsSync,
            fallbackFields: fields,
            context: context,
            now: now
        )
        let accept = { field in !isStale && protection.accepts(field) }
        let acceptsTombstone = dto.deletedAt != nil || accept("deleted_at")

        let changed =
            resolution.requiresIdentityMigration
            || (accept("opportunity_id") && existing.opportunityId != dto.opportunityId)
            || (accept("site_visit_type_id") && existing.siteVisitTypeId != dto.siteVisitTypeId)
            || (accept("field_id") && existing.fieldId != dto.fieldId)
            || (accept("label") && existing.label != dto.label)
            || (accept("kind") && existing.kind != dto.kind)
            || (accept("required") && existing.required != dto.required)
            || (accept("help_text") && existing.helpText != dto.helpText)
            || (accept("sort_order") && existing.sortOrder != dto.sortOrder)
            || (accept("answer_value") && existing.answerValue != dto.answerValue)
            || (acceptsTombstone && existing.deletedAt != dto.deletedAt)
            || (!isStale && (
                existing.createdBy != dto.createdBy
                    || existing.createdAt != dto.createdAt
                    || existing.updatedAt != dto.updatedAt
            ))
            || existing.lastSyncedAt == nil
            || existing.needsSync != protection.hasLocalWork

        guard changed else { return .unchanged }

        return .updated {
            resolution.applyIdentityMigration()
            if accept("opportunity_id") { existing.opportunityId = dto.opportunityId }
            if accept("site_visit_type_id") { existing.siteVisitTypeId = dto.siteVisitTypeId }
            if accept("field_id") { existing.fieldId = dto.fieldId }
            if accept("label") { existing.label = dto.label }
            if accept("kind") { existing.kind = dto.kind }
            if accept("required") { existing.required = dto.required }
            if accept("help_text") { existing.helpText = dto.helpText }
            if accept("sort_order") { existing.sortOrder = dto.sortOrder }
            // NOTE: this setter also stamps updatedAt/needsSync; the
            // server-owned reconciliation below deliberately overwrites both.
            if accept("answer_value") { existing.answerValue = dto.answerValue }
            if acceptsTombstone { existing.deletedAt = dto.deletedAt }
            if !isStale {
                existing.createdBy = dto.createdBy
                existing.createdAt = dto.createdAt
                existing.updatedAt = dto.updatedAt
            }
            existing.lastSyncedAt = now
            existing.needsSync = protection.hasLocalWork
        }
    }

    // MARK: - Identity draft

    private static func merge(
        identityDraft dto: SiteVisitIdentityDraftDTO,
        into context: ModelContext,
        now: Date,
        report: inout SiteVisitMergeReport
    ) throws {
        apply(try planMerge(identityDraft: dto, in: context, now: now), report: &report)
    }

    private static func planMerge(
        identityDraft dto: SiteVisitIdentityDraftDTO,
        in context: ModelContext,
        now: Date
    ) throws -> MergeOutcome {
        let fields: Set<String> = [
            "opportunity_id", "client_id", "sub_client_id", "client_name",
            "contact_name", "preferred_email", "additional_emails", "phone_number",
            "address", "notes", "last_committed_at", "deleted_at",
        ]

        guard let existing = try fetchDraft(id: dto.id, in: context) else {
            return .inserted {
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
            }
        }

        let isStale = existing.lastSyncedAt != nil
            && isOlder(dto.updatedAt, than: existing.updatedAt)
        let protection = try protectedFields(
            entityType: EntityType.identityDraft,
            entityId: dto.id,
            modelNeedsSync: existing.needsSync,
            fallbackFields: fields,
            context: context,
            now: now
        )
        let accept = { field in !isStale && protection.accepts(field) }
        let acceptsTombstone = dto.deletedAt != nil || accept("deleted_at")
        // The model's setter trims and drops empties, so compare against the
        // value the write would actually store.
        let normalizedEmails = dto.additionalEmails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let changed =
            (accept("opportunity_id") && existing.opportunityId != dto.opportunityId)
            || (accept("client_id") && existing.clientId != dto.clientId)
            || (accept("sub_client_id") && existing.subClientId != dto.subClientId)
            || (accept("client_name") && existing.clientName != dto.clientName)
            || (accept("contact_name") && existing.contactName != dto.contactName)
            || (accept("preferred_email") && existing.preferredEmail != dto.preferredEmail)
            || (accept("additional_emails") && existing.additionalEmails != normalizedEmails)
            || (accept("phone_number") && existing.phoneNumber != dto.phoneNumber)
            || (accept("address") && existing.address != dto.address)
            || (accept("notes") && existing.notes != dto.notes)
            || (accept("last_committed_at") && existing.lastCommittedAt != dto.lastCommittedAt)
            || (acceptsTombstone && existing.deletedAt != dto.deletedAt)
            || (!isStale && (
                existing.createdBy != dto.createdBy
                    || existing.createdAt != dto.createdAt
                    || existing.updatedAt != dto.updatedAt
            ))
            || existing.lastSyncedAt == nil
            || existing.needsSync != protection.hasLocalWork

        guard changed else { return .unchanged }

        return .updated {
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
            if acceptsTombstone { existing.deletedAt = dto.deletedAt }
            if !isStale {
                existing.createdBy = dto.createdBy
                existing.createdAt = dto.createdAt
                existing.updatedAt = dto.updatedAt
            }
            existing.lastSyncedAt = now
            existing.needsSync = protection.hasLocalWork
        }
    }

    // MARK: - Validation and field protection

    private static func validate(
        bundle: SiteVisitBundleDTO,
        context: ModelContext
    ) throws {
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
        try validateIncomingChecklistIdentities(bundle.checklistAnswers)
        for child in bundle.checklistAnswers {
            _ = try resolveChecklistAnswer(child, in: context)
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

        try validateIncomingChecklistIdentities(delta.checklistAnswers)
        for child in delta.checklistAnswers {
            _ = try resolveChecklistAnswer(child, in: context)
        }
    }

    private static func validateIncomingChecklistIdentities(
        _ answers: [SiteVisitChecklistAnswerDTO]
    ) throws {
        let activeByIdentity = Dictionary(
            grouping: answers.filter { $0.deletedAt == nil }
        ) {
            ChecklistLogicalIdentity(
                siteVisitId: $0.siteVisitId.lowercased(),
                fieldId: $0.fieldId
            )
        }
        for (identity, rows) in activeByIdentity where rows.count > 1 {
            throw SiteVisitMergeError.ambiguousChecklistAnswers(
                siteVisitId: identity.siteVisitId,
                fieldId: identity.fieldId,
                answerIds: rows.map(\.id).sorted()
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
        guard try fetchVisit(id: siteVisitId, in: context) != nil else {
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
    ) throws -> Protection {
        let lower = entityId.lowercased()
        let upper = entityId.uppercased()
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate {
                $0.entityType == entityType
                    && ($0.entityId == entityId || $0.entityId == lower || $0.entityId == upper)
            }
        )
        let operations = try context.fetch(descriptor)
        var protected = SyncFieldGuard.protectedFields(from: operations, now: now)
        let unresolvedOperations = operations.filter {
            checklistUnresolvedStatuses.contains($0.status)
        }
        let unresolved = !unresolvedOperations.isEmpty

        // A checklist packet remains the phone's durable source of truth until
        // the server accepts it or the operator explicitly discards it. Generic
        // field protection intentionally expires failed/parked writes after 60s;
        // checklist answers cannot use that expiry because the local value may
        // be the only copy of measurements or field notes.
        if entityType == EntityType.checklistAnswer {
            for operation in unresolvedOperations {
                let changedFields = operation.getChangedFields()
                protected.formUnion(
                    changedFields.isEmpty ? fallbackFields : Set(changedFields)
                )
            }
        }

        // Historical local writes may predate the durable operation queue. Do
        // not let the first inbound echo erase them; the orphan sweep will
        // synthesize the missing operation in the outbound task.
        if modelNeedsSync
            && (operations.isEmpty
                || (entityType == EntityType.checklistAnswer && !unresolved)) {
            protected.formUnion(fallbackFields)
        }
        return Protection(
            fields: protected,
            hasLocalWork: unresolved
                || (modelNeedsSync
                    && (operations.isEmpty
                        || (entityType == EntityType.checklistAnswer && !unresolved)))
        )
    }

    // MARK: - Single-row lookups
    //
    // Ids in this codebase are only ever all-lowercase (model inits lowercase,
    // and Postgres lowercases every uuid) or all-uppercase (`UUID().uuidString`),
    // so three candidates cover the space. There is deliberately NO table-scan
    // fallback — that is exactly the pattern that crashed the drain.

    private static func fetchVisit(
        id: String,
        in context: ModelContext
    ) throws -> SiteVisit? {
        let exact = id
        let lower = id.lowercased()
        let upper = id.uppercased()
        var descriptor = FetchDescriptor<SiteVisit>(
            predicate: #Predicate { $0.id == exact || $0.id == lower || $0.id == upper }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func fetchArtifact(
        id: String,
        in context: ModelContext
    ) throws -> SiteVisitCaptureArtifact? {
        let exact = id
        let lower = id.lowercased()
        let upper = id.uppercased()
        var descriptor = FetchDescriptor<SiteVisitCaptureArtifact>(
            predicate: #Predicate { $0.id == exact || $0.id == lower || $0.id == upper }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func fetchAnswer(
        id: String,
        in context: ModelContext
    ) throws -> SiteVisitChecklistAnswer? {
        let exact = id
        let lower = id.lowercased()
        let upper = id.uppercased()
        var descriptor = FetchDescriptor<SiteVisitChecklistAnswer>(
            predicate: #Predicate { $0.id == exact || $0.id == lower || $0.id == upper }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func fetchActiveAnswers(
        siteVisitId: String,
        fieldId: String,
        in context: ModelContext
    ) throws -> [SiteVisitChecklistAnswer] {
        let exactVisitId = siteVisitId
        let lowerVisitId = siteVisitId.lowercased()
        let upperVisitId = siteVisitId.uppercased()
        var descriptor = FetchDescriptor<SiteVisitChecklistAnswer>(
            predicate: #Predicate {
                ($0.siteVisitId == exactVisitId
                    || $0.siteVisitId == lowerVisitId
                    || $0.siteVisitId == upperVisitId)
                    && $0.fieldId == fieldId
                    && $0.deletedAt == nil
            }
        )
        // Two rows are already an unsafe ambiguity. A small bounded read keeps
        // realtime reconciliation from materializing the full checklist table.
        descriptor.fetchLimit = 2
        return try context.fetch(descriptor)
    }

    private static func fetchChecklistOperations(
        answerId: String,
        in context: ModelContext
    ) throws -> [SyncOperation] {
        let entityType = EntityType.checklistAnswer
        let exact = answerId
        let lower = answerId.lowercased()
        let upper = answerId.uppercased()
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate {
                $0.entityType == entityType
                    && ($0.entityId == exact
                        || $0.entityId == lower
                        || $0.entityId == upper)
            }
        )
        return try context.fetch(descriptor)
    }

    private static func fetchDraft(
        id: String,
        in context: ModelContext
    ) throws -> SiteVisitIdentityDraft? {
        let exact = id
        let lower = id.lowercased()
        let upper = id.uppercased()
        var descriptor = FetchDescriptor<SiteVisitIdentityDraft>(
            predicate: #Predicate { $0.id == exact || $0.id == lower || $0.id == upper }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
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
