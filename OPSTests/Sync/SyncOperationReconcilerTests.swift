//
//  SyncOperationReconcilerTests.swift
//  OPSTests
//
//  Bug ba75732a — a "failure" that proves the server already holds the intended
//  end state is a lost confirmation, not a rejection.
//
//  Two verified classes park forever without this:
//
//  1. A site-visit photo CREATE that hits
//     project_photos_active_site_visit_url_key / _uidx. The opportunity
//     conversion RPC mirrors site-visit photos into project_photos inside the
//     same transaction that creates the project — under SERVER-generated ids,
//     with taken_at NULL and no thumbnails. The queued client create is then
//     born redundant: every attempt re-INSERTs, hits the dedupe index, and the
//     phone can neither insert nor link, because the row it wants exists under
//     an id it has never seen. 23505 classifies permanent, so it parks.
//  2. A projectTask UPDATE refused with task_not_found because the server task
//     is soft-deleted. The tombstone is the newer truth; the completion is moot.
//
//  What is proven here is everything that does not need PostgREST: the
//  detection contract (deliberately narrow — an unrelated 23505 must still
//  park), the local heal in both its shapes, the tombstone application, and the
//  parked-op selection that drives the launch sweep. The lookups those hang off
//  have no seam; the PM's device pass covers that leg.
//
//  Container retention is load-bearing: a `ModelContext` does not keep its
//  `ModelContainer` alive, and inserting into a context whose container has been
//  released traps inside SwiftData (uncatchable EXC_BREAKPOINT) before the first
//  assertion runs. Each container also gets an inert warm-up `SyncOperation`,
//  the house guard against a `#Predicate` fetch of a never-populated table.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class SyncOperationReconcilerTests: XCTestCase {

    // Lowercase throughout — Postgres uuid columns are lowercase and
    // `UUID().uuidString` is uppercase.
    private let projectId = "0a887c18-0000-4832-97f0-f302dcae2e9d"
    private let companyId = "9ea44d19-0dc8-4e0a-9f1f-8b7a1c5d2e63"
    private let siteVisitId = "437d5d2b-9506-4759-beb6-3ca69e57c499"
    private let uploaderId = "283d49df-90a1-4abb-b94c-3e9f17f02c0d"
    private let taskId = "a8ea0ef2-05f1-4977-bd88-add9fa95dd2b"
    private let localPhotoId = "5c1c7a6a-3f0e-4d1b-9a2c-0b6f4e8d1c33"
    private let serverPhotoId = "7e4d418e-6a0c-4ec6-865b-bef70bc57fe6"
    private let photoURL = "https://ops-media.s3.amazonaws.com/site-visits/finlayson-01.jpg"

    /// Verbatim from the parked ops' `lastError` on the reporting device.
    private let prodDuplicateError =
        "duplicate key value violates unique constraint \"project_photos_active_site_visit_url_key\""

    /// The portal-mirror arbiter (migration cluster_j_01) as PostgREST reports it.
    private let prodPortalMirrorDuplicateError =
        "duplicate key value violates unique constraint \"project_photos_active_project_url_uidx\""

    // MARK: - Detection

    func testDetectsBothSiteVisitDedupeArbiters() {
        XCTAssertTrue(SyncOperationReconcilers.isSiteVisitPhotoDuplicate(prodDuplicateError))
        XCTAssertTrue(
            SyncOperationReconcilers.isSiteVisitPhotoDuplicate(
                "duplicate key value violates unique constraint \"project_photos_active_site_visit_url_uidx\""
            ),
            "Both partial unique indexes arbitrate the same natural key"
        )
    }

    /// Deliberately narrow. A primary-key conflict is the OTHER idempotency
    /// path, and an unrelated 23505 is a real integrity problem a human should
    /// see — neither may be swallowed as a dedupe race.
    func testDoesNotDetectUnrelatedIntegrityViolations() {
        XCTAssertFalse(
            SyncOperationReconcilers.isSiteVisitPhotoDuplicate(
                "duplicate key value violates unique constraint \"project_photos_pkey\""
            )
        )
        XCTAssertFalse(
            SyncOperationReconcilers.isSiteVisitPhotoDuplicate(
                "duplicate key value violates unique constraint \"users_email_key\""
            )
        )
        XCTAssertFalse(
            SyncOperationReconcilers.isSiteVisitPhotoDuplicate(
                "new row violates row-level security policy for table \"project_photos\""
            )
        )
        XCTAssertFalse(SyncOperationReconcilers.isSiteVisitPhotoDuplicate(""))
    }

    /// The portal-mirror arbiter added by migration cluster_j_01. A create that
    /// loses to it is the same lost confirmation as the site-visit case: the
    /// server already holds the row, so the op adopts rather than parks.
    func testDetectsTheActiveProjectURLArbiter() {
        XCTAssertTrue(
            SyncOperationReconcilers.isActiveProjectPhotoURLDuplicate(
                "duplicate key value violates unique constraint \"project_photos_active_project_url_uidx\""
            )
        )
    }

    /// Narrow by the same doctrine as the site-visit matcher: only THIS index
    /// name. A pkey conflict is the other idempotency path and an unrelated
    /// 23505 is a real integrity problem a human must see.
    func testActiveProjectURLMatcherRejectsUnrelatedIntegrityViolations() {
        XCTAssertFalse(
            SyncOperationReconcilers.isActiveProjectPhotoURLDuplicate(
                "duplicate key value violates unique constraint \"project_photos_pkey\""
            )
        )
        XCTAssertFalse(
            SyncOperationReconcilers.isActiveProjectPhotoURLDuplicate(
                "duplicate key value violates unique constraint \"project_photos_active_site_visit_url_uidx\""
            ),
            "The site-visit arbiter has its own matcher; these must not alias"
        )
        XCTAssertFalse(
            SyncOperationReconcilers.isActiveProjectPhotoURLDuplicate(
                "duplicate key value violates unique constraint \"users_email_key\""
            )
        )
        XCTAssertFalse(
            SyncOperationReconcilers.isActiveProjectPhotoURLDuplicate(
                "new row violates row-level security policy for table \"project_photos\""
            )
        )
        XCTAssertFalse(SyncOperationReconcilers.isActiveProjectPhotoURLDuplicate(""))
    }

    func testDetectsTaskNotFound() {
        XCTAssertTrue(
            SyncOperationReconcilers.isTaskNotFound(
                "PostgrestError(code: P0001, message: task_not_found)"
            )
        )
        XCTAssertFalse(SyncOperationReconcilers.isTaskNotFound("permission denied for table project_tasks"))
        XCTAssertFalse(SyncOperationReconcilers.isTaskNotFound(""))
    }

    // MARK: - Live dispatch

    func testLiveDispatchMatchesOnlyTheTwoVerifiedShapes() {
        XCTAssertEqual(
            SyncOperationReconcilers.kind(
                operationType: "create",
                entityType: SyncEntityType.projectPhoto.rawValue,
                errorDescription: prodDuplicateError
            ),
            .duplicatePhotoCreate
        )
        XCTAssertEqual(
            SyncOperationReconcilers.kind(
                operationType: "update",
                entityType: SyncEntityType.projectTask.rawValue,
                errorDescription: "task_not_found"
            ),
            .taskTombstone
        )
        // Right error, wrong operation type.
        XCTAssertNil(
            SyncOperationReconcilers.kind(
                operationType: "update",
                entityType: SyncEntityType.projectPhoto.rawValue,
                errorDescription: prodDuplicateError
            )
        )
        // Right error, wrong entity.
        XCTAssertNil(
            SyncOperationReconcilers.kind(
                operationType: "update",
                entityType: SyncEntityType.projectNote.rawValue,
                errorDescription: "task_not_found"
            )
        )
        // Right shape, unexplained error — this must still park.
        XCTAssertNil(
            SyncOperationReconcilers.kind(
                operationType: "create",
                entityType: SyncEntityType.projectPhoto.rawValue,
                errorDescription: "permission denied for table project_photos"
            )
        )
    }

    /// The new arbiter routes through the SAME adopt flow as the site-visit
    /// one — the index is a second door onto one reconciliation, not a second
    /// reconciliation.
    func testLiveDispatchRoutesTheActiveProjectURLArbiterToAdoption() {
        XCTAssertEqual(
            SyncOperationReconcilers.kind(
                operationType: "create",
                entityType: SyncEntityType.projectPhoto.rawValue,
                errorDescription: prodPortalMirrorDuplicateError
            ),
            .duplicatePhotoCreate
        )
        // Right error, wrong operation type — an update is not this shape.
        XCTAssertNil(
            SyncOperationReconcilers.kind(
                operationType: "update",
                entityType: SyncEntityType.projectPhoto.rawValue,
                errorDescription: prodPortalMirrorDuplicateError
            )
        )
        // Right error, wrong entity.
        XCTAssertNil(
            SyncOperationReconcilers.kind(
                operationType: "create",
                entityType: SyncEntityType.projectNote.rawValue,
                errorDescription: prodPortalMirrorDuplicateError
            )
        )
    }

    // MARK: - Parked-op selection (the launch sweep)

    func testParkedSelectionPicksBothShapesAndTheLegacyPKClass() throws {
        let context = try makeContext()

        let photoOp = makeOperation(
            entityType: SyncEntityType.projectPhoto.rawValue,
            entityId: localPhotoId,
            operationType: "create",
            in: context
        )
        photoOp.status = "parked"
        photoOp.lastError = prodDuplicateError

        let taskOp = makeOperation(
            entityType: SyncEntityType.projectTask.rawValue,
            entityId: taskId,
            operationType: "update",
            in: context
        )
        taskOp.status = "parked"
        taskOp.lastError = "task_not_found"

        // Parked on an older build, before the PK-idempotency block could run.
        // The natural-key lookup resolves these too.
        let legacyPKOp = makeOperation(
            entityType: SyncEntityType.projectPhoto.rawValue,
            entityId: serverPhotoId,
            operationType: "create",
            in: context
        )
        legacyPKOp.status = "parked"
        legacyPKOp.lastError = "duplicate key value violates unique constraint \"project_photos_pkey\""

        try context.save()

        XCTAssertEqual(SyncOperationReconcilers.parkedKind(for: photoOp), .duplicatePhotoCreate)
        XCTAssertEqual(SyncOperationReconcilers.parkedKind(for: taskOp), .taskTombstone)
        XCTAssertEqual(SyncOperationReconcilers.parkedKind(for: legacyPKOp), .duplicatePhotoCreate)
    }

    /// The launch sweep must pick up a create parked on the portal-mirror
    /// arbiter too — including one parked by a build that shipped before the
    /// index existed. `parkedKind` inherits the widened live matcher, so this is
    /// the guard that the two never drift apart.
    func testParkedSelectionPicksThePortalMirrorArbiter() throws {
        let context = try makeContext()

        let mirrorOp = makeOperation(
            entityType: SyncEntityType.projectPhoto.rawValue,
            entityId: localPhotoId,
            operationType: "create",
            in: context
        )
        mirrorOp.status = "parked"
        mirrorOp.lastError = prodPortalMirrorDuplicateError
        try context.save()

        XCTAssertEqual(
            SyncOperationReconcilers.parkedKind(for: mirrorOp),
            .duplicatePhotoCreate
        )
    }

    /// Parked stays terminal for every other class — the sweep is targeted, not
    /// a blanket un-parking.
    func testParkedSelectionIgnoresUnrelatedFailures() throws {
        let context = try makeContext()

        let rlsOp = makeOperation(
            entityType: SyncEntityType.projectPhoto.rawValue,
            entityId: localPhotoId,
            operationType: "create",
            in: context
        )
        rlsOp.status = "parked"
        rlsOp.lastError = "new row violates row-level security policy"

        let noErrorOp = makeOperation(
            entityType: SyncEntityType.projectTask.rawValue,
            entityId: taskId,
            operationType: "update",
            in: context
        )
        noErrorOp.status = "parked"
        noErrorOp.lastError = nil

        // A task create is not the tombstone shape, whatever it says.
        let taskCreateOp = makeOperation(
            entityType: SyncEntityType.projectTask.rawValue,
            entityId: taskId,
            operationType: "create",
            in: context
        )
        taskCreateOp.status = "parked"
        taskCreateOp.lastError = "task_not_found"

        try context.save()

        XCTAssertNil(SyncOperationReconcilers.parkedKind(for: rlsOp))
        XCTAssertNil(SyncOperationReconcilers.parkedKind(for: noErrorOp))
        XCTAssertNil(SyncOperationReconcilers.parkedKind(for: taskCreateOp))
    }

    // MARK: - Photo heal, adopt shape

    /// Only the local-id row exists: it takes the server's identity in place, so
    /// the next inbound merge (which matches by id) recognises it instead of
    /// materialising a duplicate.
    func testAdoptsServerIdentityWhenNoTwinExists() throws {
        let context = try makeContext()
        let local = insertPhoto(id: localPhotoId, in: context)
        local.caption = "north elevation"
        local.takenAt = Date(timeIntervalSince1970: 1_756_000_000)
        local.needsSync = true
        let operation = makeOperation(
            entityType: SyncEntityType.projectPhoto.rawValue,
            entityId: localPhotoId,
            operationType: "create",
            in: context
        )
        try context.save()

        let patch = try SyncOperationReconcilers.adoptServerPhotoRow(
            localId: localPhotoId,
            server: SyncOperationReconcilers.ServerPhotoRow(id: serverPhotoId.uppercased()),
            in: context
        )
        SyncOperationReconcilers.markResolved(operation)
        try context.save()

        XCTAssertEqual(local.id, serverPhotoId, "Server ids are lowercase; the adopted id must be too")
        XCTAssertFalse(local.needsSync)
        XCTAssertNotNil(local.lastSyncedAt)
        XCTAssertEqual(operation.status, "completed")
        XCTAssertNotNil(operation.completedAt)
        XCTAssertNil(operation.lastError)

        // The conversion RPC leaves capture metadata empty; this device has it.
        XCTAssertEqual(patch["caption"], "north elevation")
        XCTAssertNotNil(patch["taken_at"])

        let all = try context.fetch(FetchDescriptor<ProjectPhoto>())
        XCTAssertEqual(all.count, 1, "Adopting must not create a second row")
    }

    // MARK: - Photo heal, twin-merge shape

    /// Inbound sync merges by id, so the server row may already be a SECOND
    /// local row beside the handoff row. The gallery must not show the photo
    /// twice: the server-id row survives, absorbs the metadata only this device
    /// has, and the orphan goes.
    func testMergesLocalTwinIntoTheServerRow() throws {
        let context = try makeContext()

        let local = insertPhoto(id: localPhotoId, in: context)
        local.caption = "north elevation"
        local.thumbnailURL = "https://ops-media.s3.amazonaws.com/thumbs/finlayson-01.jpg"
        local.renderedURL = "https://ops-media.s3.amazonaws.com/rendered/finlayson-01.jpg"
        local.takenAt = Date(timeIntervalSince1970: 1_756_000_000)
        local.needsSync = true

        // The server row as inbound sync materialised it: no capture metadata.
        let server = insertPhoto(id: serverPhotoId, in: context)
        XCTAssertNil(server.caption)

        let operation = makeOperation(
            entityType: SyncEntityType.projectPhoto.rawValue,
            entityId: localPhotoId,
            operationType: "create",
            in: context
        )
        try context.save()

        let patch = try SyncOperationReconcilers.adoptServerPhotoRow(
            localId: localPhotoId,
            server: SyncOperationReconcilers.ServerPhotoRow(id: serverPhotoId),
            in: context
        )
        SyncOperationReconcilers.markResolved(operation)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<ProjectPhoto>())
        XCTAssertEqual(rows.count, 1, "The orphan twin must be deleted, not left in the gallery")
        let survivor = try XCTUnwrap(rows.first)
        XCTAssertEqual(survivor.id, serverPhotoId, "The server identity wins")
        XCTAssertEqual(survivor.caption, "north elevation")
        XCTAssertEqual(survivor.thumbnailURL, local.thumbnailURL)
        XCTAssertEqual(survivor.renderedURL, local.renderedURL)
        XCTAssertNotNil(survivor.takenAt)
        XCTAssertFalse(survivor.needsSync)
        XCTAssertEqual(operation.status, "completed")

        XCTAssertEqual(patch["caption"], "north elevation")
        XCTAssertEqual(patch["thumbnail_url"], local.thumbnailURL)
        XCTAssertEqual(patch["rendered_url"], local.renderedURL)
        XCTAssertNotNil(patch["taken_at"])
    }

    /// The back-fill only sends what the server is actually missing — a server
    /// row that already has metadata is never overwritten by an older device.
    func testBackfillPatchSkipsColumnsTheServerAlreadyHolds() throws {
        let context = try makeContext()
        let local = insertPhoto(id: localPhotoId, in: context)
        local.caption = "device caption"
        local.thumbnailURL = "https://ops-media.s3.amazonaws.com/thumbs/finlayson-01.jpg"
        local.takenAt = Date(timeIntervalSince1970: 1_756_000_000)
        try context.save()

        let patch = try SyncOperationReconcilers.adoptServerPhotoRow(
            localId: localPhotoId,
            server: SyncOperationReconcilers.ServerPhotoRow(
                id: serverPhotoId,
                caption: "server caption",
                taken_at: "2026-08-28T19:37:16.195195+00:00",
                thumbnail_url: "https://ops-media.s3.amazonaws.com/thumbs/server.jpg"
            ),
            in: context
        )

        XCTAssertNil(patch["caption"])
        XCTAssertNil(patch["taken_at"])
        XCTAssertNil(patch["thumbnail_url"])
        XCTAssertTrue(patch.isEmpty, "Nothing local to add means nothing on the wire")
    }

    /// Local-only file paths are not URLs the server can serve — never send one.
    func testBackfillPatchRefusesLocalOnlyMediaPaths() throws {
        let context = try makeContext()
        let local = insertPhoto(id: localPhotoId, in: context)
        local.thumbnailURL = "local://thumb-abc"
        local.renderedURL = "file:///var/mobile/rendered.jpg"
        try context.save()

        let patch = try SyncOperationReconcilers.adoptServerPhotoRow(
            localId: localPhotoId,
            server: SyncOperationReconcilers.ServerPhotoRow(id: serverPhotoId),
            in: context
        )

        XCTAssertNil(patch["thumbnail_url"])
        XCTAssertNil(patch["rendered_url"])
    }

    /// A device that holds no row for the op still resolves cleanly — the photo
    /// is safe on the server either way, and the op must not park.
    func testHealIsHarmlessWhenTheDeviceHoldsNoRow() throws {
        let context = try makeContext()
        _ = makeOperation(
            entityType: SyncEntityType.projectPhoto.rawValue,
            entityId: localPhotoId,
            operationType: "create",
            in: context
        )
        try context.save()

        let patch = try SyncOperationReconcilers.adoptServerPhotoRow(
            localId: localPhotoId,
            server: SyncOperationReconcilers.ServerPhotoRow(id: serverPhotoId),
            in: context
        )

        XCTAssertTrue(patch.isEmpty)
    }

    // MARK: - Task tombstone

    func testTombstonesTheLocalTaskAndCompletesTheOperation() throws {
        let context = try makeContext()
        let task = ProjectTask(
            id: taskId,
            projectId: projectId,
            taskTypeId: "tt",
            companyId: companyId
        )
        task.needsSync = true
        context.insert(task)
        let operation = makeOperation(
            entityType: SyncEntityType.projectTask.rawValue,
            entityId: taskId,
            operationType: "update",
            in: context
        )
        try context.save()

        let deletedAt = try XCTUnwrap(SupabaseDate.parse("2026-08-28T19:37:16.195195+00:00"))
        let applied = try SyncOperationReconcilers.applyTaskTombstone(
            taskId: taskId,
            deletedAt: deletedAt,
            in: context
        )
        SyncOperationReconcilers.markResolved(operation)
        try context.save()

        XCTAssertTrue(applied)
        XCTAssertEqual(
            task.deletedAt?.timeIntervalSince1970 ?? 0,
            deletedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertFalse(task.needsSync, "The deletion is the newer truth; nothing is left to push")
        XCTAssertEqual(operation.status, "completed")
        XCTAssertNil(operation.lastError)
    }

    /// Already tombstoned locally, or never held at all: still a successful
    /// reconciliation, just nothing to change.
    func testTombstoneIsIdempotentAndSurvivesAMissingRow() throws {
        let context = try makeContext()
        let deletedAt = try XCTUnwrap(SupabaseDate.parse("2026-08-28T19:37:16.195195+00:00"))
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)

        let task = ProjectTask(
            id: taskId,
            projectId: projectId,
            taskTypeId: "tt",
            companyId: companyId
        )
        task.deletedAt = earlier
        context.insert(task)
        try context.save()

        XCTAssertFalse(
            try SyncOperationReconcilers.applyTaskTombstone(taskId: taskId, deletedAt: deletedAt, in: context)
        )
        XCTAssertEqual(
            task.deletedAt?.timeIntervalSince1970 ?? 0,
            earlier.timeIntervalSince1970,
            accuracy: 0.001,
            "An existing tombstone is not restamped"
        )

        XCTAssertFalse(
            try SyncOperationReconcilers.applyTaskTombstone(
                taskId: "1b1e4c7a-0000-4b0a-9f00-000000000000",
                deletedAt: deletedAt,
                in: context
            )
        )
    }

    // MARK: - Project tombstone

    /// The server deleted the job while this phone still held an edit for it.
    /// The tombstone is the newer truth: the project moves to trash here and
    /// stops trying to push.
    func testTombstonesTheLocalProject() throws {
        let context = try makeContext()
        let project = Project(id: projectId, title: "541 Prince Robert Ln", status: .inProgress)
        project.needsSync = true
        context.insert(project)
        try context.save()

        let deletedAt = try XCTUnwrap(SupabaseDate.parse("2026-08-28T19:37:16.195195+00:00"))
        let applied = try SyncOperationReconcilers.applyProjectTombstone(
            projectId: projectId,
            deletedAt: deletedAt,
            in: context
        )
        try context.save()

        XCTAssertTrue(applied)
        XCTAssertEqual(
            project.deletedAt?.timeIntervalSince1970 ?? 0,
            deletedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertFalse(project.needsSync, "The deletion is the newer truth; nothing is left to push")
    }

    /// Already tombstoned, or never held at all: still a successful
    /// reconciliation, just nothing to change. The first deletion time this
    /// phone learned is never restamped.
    func testProjectTombstoneIsIdempotentAndSurvivesAMissingRow() throws {
        let context = try makeContext()
        let deletedAt = try XCTUnwrap(SupabaseDate.parse("2026-08-28T19:37:16.195195+00:00"))
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)

        let project = Project(id: projectId, title: "541 Prince Robert Ln", status: .inProgress)
        project.deletedAt = earlier
        context.insert(project)
        try context.save()

        XCTAssertFalse(
            try SyncOperationReconcilers.applyProjectTombstone(
                projectId: projectId,
                deletedAt: deletedAt,
                in: context
            )
        )
        XCTAssertEqual(
            project.deletedAt?.timeIntervalSince1970 ?? 0,
            earlier.timeIntervalSince1970,
            accuracy: 0.001,
            "An existing tombstone is not restamped"
        )

        XCTAssertFalse(
            try SyncOperationReconcilers.applyProjectTombstone(
                projectId: "1b1e4c7a-0000-4b0a-9f00-000000000000",
                deletedAt: deletedAt,
                in: context
            ),
            "A device that holds no row for the project still reconciles cleanly"
        )
    }

    // MARK: - Project update row-verdict (bug 16d487c4)

    /// A zero-row project UPDATE stops being a conclusion and becomes a
    /// question. Detection keys on the typed error's own marker, so the
    /// reconciler and the copy layer read the same evidence.
    func testProjectUpdateRowVerdictIsDispatchedForZeroRowProjectUpdates() {
        let missing = SyncError
            .serverRowMissing(table: "projects", id: projectId)
            .localizedDescription

        XCTAssertEqual(
            SyncOperationReconcilers.kind(
                operationType: "update",
                entityType: SyncEntityType.project.rawValue,
                errorDescription: missing
            ),
            .projectUpdateRowVerdict
        )
        // A create is not this shape — it has its own idempotency paths.
        XCTAssertNil(
            SyncOperationReconcilers.kind(
                operationType: "create",
                entityType: SyncEntityType.project.rawValue,
                errorDescription: missing
            )
        )
        // A task update against a missing row is not the project verdict.
        XCTAssertNil(
            SyncOperationReconcilers.kind(
                operationType: "update",
                entityType: SyncEntityType.projectTask.rawValue,
                errorDescription: missing
            )
        )
        // Right shape, unrelated error — still parks.
        XCTAssertNil(
            SyncOperationReconcilers.kind(
                operationType: "update",
                entityType: SyncEntityType.project.rawValue,
                errorDescription: "permission denied for table projects"
            )
        )
    }

    /// This is what heals the ops already sitting on crew phones, parked by a
    /// build that shipped before the probes existed.
    func testParkedProjectUpdatesAreSelectedForTheVerdictSweep() throws {
        let context = try makeContext()
        let operation = makeOperation(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "update",
            in: context
        )
        operation.status = "parked"
        operation.lastError = SyncError
            .serverRowMissing(table: "projects", id: projectId)
            .localizedDescription
        try context.save()

        XCTAssertEqual(
            SyncOperationReconcilers.parkedKind(for: operation),
            .projectUpdateRowVerdict
        )
    }

    /// The edit-refused verdict keeps the op parked — nothing about it became
    /// sendable — but restates WHY, and in doing so removes itself from the
    /// sweep's sights. Without that, every launch would re-probe the same op
    /// forever.
    func testEditRefusedVerdictParksHonestlyAndDefeatsReDetection() throws {
        let context = try makeContext()
        let operation = makeOperation(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "update",
            in: context
        )
        operation.status = "parked"
        operation.lastError = SyncError
            .serverRowMissing(table: "projects", id: projectId)
            .localizedDescription
        try context.save()

        SyncOperationReconcilers.applyEditRefusedVerdict(operation, table: "projects")
        try context.save()

        XCTAssertEqual(operation.status, "parked", "The change still has not reached the server")
        XCTAssertNil(operation.completedAt, "Nothing was completed — only explained")
        let stored = try XCTUnwrap(operation.lastError)
        XCTAssertTrue(stored.contains(SyncError.serverEditRefusedMarker))
        XCTAssertFalse(stored.contains(SyncError.serverRowMissingMarker))
        XCTAssertTrue(stored.contains(projectId), "The verdict names the row it is about")

        XCTAssertNil(
            SyncOperationReconcilers.parkedKind(for: operation),
            "A resolved verdict must not be re-probed on every launch"
        )
        XCTAssertTrue(SyncStatusCopy.PendingWork.isEditRefused(operation.lastError))
    }

    // MARK: - project_server_state wire decoding

    /// PostgREST renders a text-returning function as a JSON string; an
    /// unquoted body is tolerated too, so a transport detail can never cost us
    /// the verdict. Anything else answers nil — and the caller then invents no
    /// verdict at all, which is the whole point of the probe.
    func testProjectServerStateDecodesEveryVerdictAndRefusesGarbage() {
        func decode(_ body: String) -> SyncOperationReconcilers.ProjectServerState? {
            SyncOperationReconcilers.projectServerState(from: Data(body.utf8))
        }

        XCTAssertEqual(decode("\"active\""), .active)
        XCTAssertEqual(decode("\"deleted\""), .deleted)
        XCTAssertEqual(decode("\"absent\""), .absent)
        XCTAssertEqual(decode("active"), .active, "An unquoted body still answers")
        XCTAssertEqual(decode("\n \"deleted\" \n"), .deleted)

        XCTAssertNil(decode(""))
        XCTAssertNil(decode("null"))
        XCTAssertNil(decode("{\"error\":\"boom\"}"))
        XCTAssertNil(decode("ACTIVE"), "The contract is lowercase; a near-miss is not evidence")
    }

    // MARK: - Parked share jobs (bug c3486912 residue)

    /// `shareParkedRetry.v1` resets every job the drain would NOT otherwise
    /// upload — `attempts >= maxAttempts`, covering BOTH the recovery-reporting
    /// state and the already-reported state where Jackson's two 08-19 photos
    /// sit. A job with budget left is never touched: resetting it would discard
    /// a real attempt history for no gain.
    ///
    /// The boundaries themselves are owned by
    /// `SharePhotoEndpointFailurePolicyTests`; what is asserted here is the
    /// selection predicate the one-shot heal is written against, so a later
    /// change to the ladder cannot silently widen or empty that reset. The flag
    /// and the App Group manifest write are device state — the PM's device pass
    /// covers those.
    func testParkedShareRetrySelectsEverySpentBudgetAndNothingElse() {
        let max = ShareUploadManifestStore.maxAttempts
        let selected: (Int) -> Bool = { ShareUploadCoordinator.actionForAttemptCount($0) != .upload }

        XCTAssertFalse(selected(0), "A fresh job keeps its untouched budget")
        XCTAssertFalse(selected(max - 1), "One attempt left is still a live job")
        XCTAssertTrue(selected(max), "Budget spent, recovery reported — reset it")
        XCTAssertTrue(selected(max + 1), "Already reported and never retried — the stranded case")
    }

    // MARK: - Fixtures

    @discardableResult
    private func insertPhoto(id: String, in context: ModelContext) -> ProjectPhoto {
        let photo = ProjectPhoto(
            id: id,
            projectId: projectId,
            companyId: companyId,
            url: photoURL,
            source: "site_visit",
            siteVisitId: siteVisitId,
            uploadedBy: uploaderId
        )
        context.insert(photo)
        return photo
    }

    @discardableResult
    private func makeOperation(
        entityType: String,
        entityId: String,
        operationType: String,
        in context: ModelContext
    ) -> SyncOperation {
        let operation = SyncOperation(
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            payload: Data("{}".utf8),
            changedFields: []
        )
        context.insert(operation)
        return operation
    }

    private func makeContainer() throws -> ModelContainer {
        // Resolved through OPSSchemaCurrent rather than a hand-listed subset:
        // Project carries @Relationship edges to Client / User / ProjectTask, and
        // a partial schema that omits any of them fails to build the container.
        let schema = Schema(versionedSchema: OPSSchemaCurrent.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Containers outlive the contexts they vend, for the whole test case.
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try makeContainer()
        retainedContainers.append(container)
        let context = container.mainContext
        // Inert warm-up row — a #Predicate fetch of SyncOperation traps against
        // a table that has never held one.
        makeOperation(
            entityType: SyncEntityType.projectPhoto.rawValue,
            entityId: "00000000-0000-0000-0000-000000000000",
            operationType: "create",
            in: context
        )
        try context.save()
        return context
    }
}
