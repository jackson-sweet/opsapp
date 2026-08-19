//
//  SharePhotoCreateBarrierTests.swift
//  OPSTests
//
//  Photos shared into OPS must reach their job (bugs c3486912 / ca26fd7a).
//
//  THE INCIDENT (2026-08-19, founder's device). Two photos were attached to
//  project 7e4d418e — a job that existed only on that phone, its own create
//  never having reached the server. Every server write scoped to it failed or
//  lied:
//
//    project_photos INSERT  → 42501. The RLS policy
//        "project_photos insert requires project view" resolves through
//        private.current_user_can_view_project, which opens with
//        EXISTS (SELECT 1 FROM projects …) — unsatisfiable for a project the
//        server has never seen.
//    projects.project_images PATCH → 200 with an empty body. PostgREST answers
//        a PATCH that matches no row that way, so the gallery mirror "succeeded"
//        against nothing and cleared needsSync. A silent write-off.
//    /api/uploads/share-photo (the share extension's rail) → 404, which
//        `SharePhotoEndpointUploader.isTransient` calls permanent — correctly,
//        and context-free — so ten drains parked the share and spent the
//        operator a recovery notice for a job that would have landed on its own.
//
//  One defect, three faces: nothing ordered a photo write against its project's
//  create. Both photo rails write by REST, entirely outside the SyncOperation
//  queue, so `SyncCrossEntityDependency` — which already holds exactly this
//  race for queued work — was never consulted.
//
//  THE FIX, and what these tests lock down. Both rails now ask that same
//  barrier, over the same operations, through `hasUnresolvedCreate`. Held means
//  held: the photo waits on the device, costs no attempt and no retry budget,
//  and goes out once the create lands. Ordering stays the queue's job; the
//  failure classifier and the share rail's transient policy stay context-free.
//
//  Four groups:
//    A — the barrier predicate itself, over real SyncOperation rows.
//    B — the share rail's delegation (`holdsForUnresolvedProjectCreate`). It is
//        a thin forward on purpose, and that IS the architecture: the share rail
//        gets no bespoke notion of "is this project real". A future edit that
//        invents one fails here.
//    C — the in-app rail's wiring (`ImageSyncManager.projectAwaitsItsOwnCreate`)
//        over a real ModelContext. `saveImages` itself is not driven here: its
//        connectivity guard has no test seam (`isConnected` is a stored
//        `private(set)` property), so a fresh ConnectivityManager reports
//        offline and the test would pass vacuously through the offline branch
//        while proving nothing about the barrier.
//    D — the genuinely-invalid destination stays VISIBLE, never dropped: the
//        0-row PATCH verdict that drives the surfaced failure, and the copy
//        chokepoint that names it.
//
//  Containers are retained for the case's lifetime: a ModelContext does not keep
//  its ModelContainer alive, and inserting into a context whose container has
//  been released traps inside SwiftData (uncatchable EXC_BREAKPOINT) before the
//  first assertion.
//

import SwiftData
import Supabase
import XCTest
@testable import OPS

@MainActor
final class SharePhotoCreateBarrierTests: XCTestCase {

    // Lowercase throughout — Postgres uuid columns are lowercase while
    // `UUID().uuidString` is uppercase. The case test deliberately mixes.
    private let projectId = "7e4d418e-6a0c-4ec6-865b-bef70bc57fe6"
    private let otherProjectId = "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1"
    private let clientId = "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9"

    // MARK: - A. The barrier predicate

    /// Every status that means "the server does not have this row yet" holds the
    /// photo. `parked` is the one that mattered on the founder's device: a
    /// parked create never retries on its own, so a photo sent against it would
    /// have been rejected forever.
    func test_hasUnresolvedCreate_holdsForEveryUnresolvedCreateStatus() throws {
        for status in ["pending", "inProgress", "failed", "parked", "quarantined"] {
            let context = try makeContext()
            _ = makeOp(
                entityType: SyncEntityType.project.rawValue,
                entityId: projectId,
                operationType: "create",
                status: status,
                in: context
            )

            XCTAssertTrue(
                SyncCrossEntityDependency.hasUnresolvedCreate(
                    entityType: .project,
                    entityId: projectId,
                    in: try operations(in: context)
                ),
                "a \(status) project create must hold its photos"
            )
        }
    }

    /// The happy path, and the delivery half of "held, then delivered": once the
    /// create is confirmed the barrier lifts, and the very next drain sends the
    /// photo it was holding.
    func test_hasUnresolvedCreate_releasesOnceTheCreateCompletes() throws {
        let context = try makeContext()
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            status: "pending",
            in: context
        )

        XCTAssertTrue(
            SyncCrossEntityDependency.hasUnresolvedCreate(
                entityType: .project,
                entityId: projectId,
                in: try operations(in: context)
            ),
            "precondition: the photo is held while the create is queued"
        )

        create.status = "completed"
        create.completedAt = Date()

        XCTAssertFalse(
            SyncCrossEntityDependency.hasUnresolvedCreate(
                entityType: .project,
                entityId: projectId,
                in: try operations(in: context)
            ),
            "a completed create must release the photo it was holding"
        )
    }

    /// The ordinary case — a project that synced normally records no create op
    /// at all — must not be held. A barrier that held everything would stop
    /// every photo in the app.
    func test_hasUnresolvedCreate_doesNotHoldWhenNoCreateIsQueued() throws {
        let context = try makeContext()
        // Unrelated traffic only: another project's create, and an update to
        // this one. Neither is this project's own create.
        _ = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: otherProjectId,
            operationType: "create",
            status: "pending",
            in: context
        )
        _ = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "update",
            status: "pending",
            in: context
        )

        XCTAssertFalse(
            SyncCrossEntityDependency.hasUnresolvedCreate(
                entityType: .project,
                entityId: projectId,
                in: try operations(in: context)
            )
        )
    }

    /// `UUID().uuidString` is uppercase; Postgres uuid columns are lowercase. A
    /// case-sensitive match would miss the blocking create and ship the photo
    /// straight into the 42501 the barrier exists to prevent.
    func test_hasUnresolvedCreate_matchesIdsCaseInsensitively() throws {
        let context = try makeContext()
        _ = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId.uppercased(),
            operationType: "create",
            status: "pending",
            in: context
        )

        XCTAssertTrue(
            SyncCrossEntityDependency.hasUnresolvedCreate(
                entityType: .project,
                entityId: projectId.lowercased(),
                in: try operations(in: context)
            )
        )
    }

    /// Ids are unique per table, not globally. A client create carrying the same
    /// id must not hold a project's photos.
    func test_hasUnresolvedCreate_doesNotMatchAcrossEntityTypes() throws {
        let context = try makeContext()
        _ = makeOp(
            entityType: SyncEntityType.client.rawValue,
            entityId: projectId,
            operationType: "create",
            status: "pending",
            in: context
        )

        XCTAssertFalse(
            SyncCrossEntityDependency.hasUnresolvedCreate(
                entityType: .project,
                entityId: projectId,
                in: try operations(in: context)
            )
        )
    }

    /// An empty destination is not a dependency. Treating "" as an id would hold
    /// real work behind a project that does not exist.
    func test_hasUnresolvedCreate_ignoresAnEmptyDestinationId() throws {
        let context = try makeContext()
        _ = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: "",
            operationType: "create",
            status: "pending",
            in: context
        )

        XCTAssertFalse(
            SyncCrossEntityDependency.hasUnresolvedCreate(
                entityType: .project,
                entityId: "",
                in: try operations(in: context)
            )
        )
    }

    // MARK: - B. The share rail delegates to the barrier

    /// The incident's share half: a photo shared into a job whose create is
    /// parked is HELD, not attempted. Before the fix this reached
    /// /api/uploads/share-photo, took a 404, and burned one of ten attempts
    /// toward a permanent park.
    func test_shareRail_holdsWhenTheDestinationProjectCreateIsUnresolved() throws {
        let context = try makeContext()
        _ = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            status: "parked",
            in: context
        )

        XCTAssertTrue(
            ShareUploadCoordinator.holdsForUnresolvedProjectCreate(
                projectId: projectId,
                operations: try operations(in: context)
            )
        )
    }

    /// Happy path unchanged: an ordinary share, against a project the server
    /// already has, is never held.
    func test_shareRail_doesNotHoldForAProjectTheServerAlreadyHas() throws {
        let context = try makeContext()
        _ = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            status: "completed",
            completedAt: Date(),
            in: context
        )

        XCTAssertFalse(
            ShareUploadCoordinator.holdsForUnresolvedProjectCreate(
                projectId: projectId,
                operations: try operations(in: context)
            )
        )
    }

    /// The share rail must not invent its own answer. Same inputs, same verdict
    /// as the barrier every queued write consults — across every status.
    func test_shareRail_verdictIsAlwaysTheBarriersVerdict() throws {
        for status in ["pending", "inProgress", "failed", "parked", "quarantined", "completed"] {
            let context = try makeContext()
            _ = makeOp(
                entityType: SyncEntityType.project.rawValue,
                entityId: projectId,
                operationType: "create",
                status: status,
                in: context
            )
            let ops = try operations(in: context)

            XCTAssertEqual(
                ShareUploadCoordinator.holdsForUnresolvedProjectCreate(
                    projectId: projectId,
                    operations: ops
                ),
                SyncCrossEntityDependency.hasUnresolvedCreate(
                    entityType: .project,
                    entityId: projectId,
                    in: ops
                ),
                "the share rail must not diverge from the barrier (status: \(status))"
            )
        }
    }

    // MARK: - C. The in-app rail is wired to the same barrier

    /// `ImageSyncManager` asks the barrier about the project the photo is
    /// actually being attached to, over the real outbound queue. This is the
    /// gate that keeps a note-attached photo out of the 42501 that auto-filed
    /// bug ca26fd7a.
    func test_imageSyncManager_holdsPhotosForAProjectWhoseCreateIsQueued() throws {
        let context = try makeContext()
        _ = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            status: "pending",
            in: context
        )
        try context.save()

        let manager = ImageSyncManager(
            modelContext: context,
            connectivity: ConnectivityManager()
        )

        XCTAssertTrue(manager.projectAwaitsItsOwnCreate(projectId))
    }

    /// Happy path unchanged: a project the server already has does not hold its
    /// photos, so the normal upload path runs exactly as before.
    func test_imageSyncManager_doesNotHoldForASyncedProject() throws {
        let context = try makeContext()
        _ = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: otherProjectId,
            operationType: "create",
            status: "pending",
            in: context
        )
        try context.save()

        let manager = ImageSyncManager(
            modelContext: context,
            connectivity: ConnectivityManager()
        )

        // A different project's create is queued; this one's is not.
        XCTAssertFalse(manager.projectAwaitsItsOwnCreate(projectId))
    }

    /// No queue at all — a fresh install, or a manager built without a context —
    /// must not hold every photo in the app.
    func test_imageSyncManager_doesNotHoldWithoutAModelContext() {
        let manager = ImageSyncManager(
            modelContext: nil,
            connectivity: ConnectivityManager()
        )

        XCTAssertFalse(manager.projectAwaitsItsOwnCreate(projectId))
    }

    // MARK: - D. A genuinely invalid destination is surfaced, never dropped

    /// The silent write-off, caught. With the create barrier removing the common
    /// cause, a PATCH that STILL matches no row means the project row is not
    /// addressable at all — deleted server-side, or invisible under RLS. The
    /// guard turns PostgREST's 200-with-empty-body into a typed failure instead
    /// of a cleared `needsSync`.
    func test_zeroRowProjectPatch_isAFailureNotASuccess() {
        XCTAssertThrowsError(
            try SupabaseWriteGuard.requireAffectedRow(
                response: Data("[]".utf8),
                table: "projects",
                id: projectId,
                fields: ["project_images": .array([.string("https://example.com/a.jpg")])]
            )
        ) { error in
            guard let syncError = error as? SyncError,
                  case .serverRowMissing(let table, let id) = syncError else {
                return XCTFail("expected serverRowMissing, got \(error)")
            }
            XCTAssertEqual(table, "projects")
            XCTAssertEqual(id, projectId)
        }
    }

    /// The same write against a real row stays a success — the guard must not
    /// invent a failure and strand photos that landed fine.
    func test_projectPatchThatMatchedARow_staysASuccess() {
        XCTAssertNoThrow(
            try SupabaseWriteGuard.requireAffectedRow(
                response: Data("[{\"id\":\"\(projectId)\"}]".utf8),
                table: "projects",
                id: projectId,
                fields: ["project_images": .array([.string("https://example.com/a.jpg")])]
            )
        )
    }

    /// A job that is gone and a portal mirror that will retry are different
    /// events and must not share words: one never resolves, the other resolves
    /// itself. Identical copy would tell an operator to keep waiting for
    /// something that is never coming.
    func test_photoCopy_separatesTheRetryableFromTheGone() {
        let retryable = SyncStatusCopy.Photo.portalMirrorPending
        let gone = SyncStatusCopy.Photo.projectMissing

        XCTAssertNotEqual(retryable, gone)

        // The gone line must still promise the operator the bytes are on the
        // phone — that is the whole guarantee this fix exists to keep, and the
        // one thing a failed tile must never leave in doubt.
        XCTAssertTrue(gone.lowercased().contains("safe on this phone"))

        // OPS register: no shouting anywhere in the photo rail.
        for line in [retryable, gone] {
            XCTAssertFalse(line.contains("!"), "no exclamation points: \(line)")
            XCTAssertFalse(line.isEmpty)
        }
    }

    // MARK: - Helpers

    /// Predicate-free on purpose: a `#Predicate` fetch of `SyncOperation` traps
    /// (uncatchable EXC_BREAKPOINT) against a table that has never held a row,
    /// which is exactly the shape every one of these tests starts from.
    private func operations(in context: ModelContext) throws -> [SyncOperation] {
        try context.fetch(FetchDescriptor<SyncOperation>())
    }

    private func makeOp(
        entityType: String,
        entityId: String,
        operationType: String,
        status: String = "pending",
        completedAt: Date? = nil,
        in context: ModelContext
    ) -> SyncOperation {
        let payload: [String: Any] = ["id": entityId, "client_id": clientId]
        let op = SyncOperation(
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            payload: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8),
            changedFields: Array(payload.keys)
        )
        op.status = status
        op.completedAt = completedAt
        context.insert(op)
        return op
    }

    private func makeContainer() throws -> ModelContainer {
        // SyncOperation alone: nothing here reads a Project row. Group C builds
        // an `ImageSyncManager` against this context, but the path under test
        // (`projectAwaitsItsOwnCreate`) fetches only the outbound queue, and
        // pulling `Project` in would drag its `Client` / `User` relationships
        // into the schema for no assertion's benefit.
        let schema = Schema([SyncOperation.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Containers outlive the contexts they vend, for the whole test case. A
    /// `ModelContext` does not keep its container alive, and inserting into a
    /// context whose container has been released traps inside SwiftData
    /// (uncatchable EXC_BREAKPOINT) — every test would die before its first
    /// assertion, and the log would blame the assertions.
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try makeContainer()
        retainedContainers.append(container)
        return container.mainContext
    }
}
