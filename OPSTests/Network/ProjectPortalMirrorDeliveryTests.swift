//
//  ProjectPortalMirrorDeliveryTests.swift
//  OPSTests
//
//  Bug 16d487c4 — three crew photos stranded on a phone behind a verdict that
//  was simply false.
//
//  WHAT HAPPENED. Jake (role `crew`, `photos.upload = all`, `projects.edit`
//  ungranted) saved 3 photos to a live job. S3 took all three. The client then
//  PATCHed the legacy `projects.project_images` CSV — an UPDATE gated by
//  RESTRICTIVE RLS on `projects.edit`, which he does not have — so it matched 0
//  rows. The client read "0 rows" as "the project does not exist server-side",
//  SKIPPED the canonical `project_photos` insert (gated only on project VIEW,
//  which he DID have and which would have succeeded), marked the tiles failed,
//  and auto-filed a bug claiming a live, undeleted job was absent. The photos
//  ended up recorded nowhere but that phone's local CSV.
//
//  WHAT IS PROVEN HERE. Delivery is canonical-first and no longer touches the
//  CSV at all — the server projects it now (migration cluster_j_02) — and every
//  failure verdict comes from something the server STATED, through the probe
//  seams below, rather than from an inference about a failed write:
//
//    * visible + refused    → loud, filed, and QUEUED. Never a false absence.
//    * invisible + active   → held, not shared, and NOT filed (a permission
//                             state is not a defect).
//    * invisible + deleted  → the tombstone applied locally, and NOT filed.
//    * invisible + absent   → filed once, and only then — with the create
//                             barrier still able to veto the claim.
//    * duplicate arbiter    → already mirrored; nothing failed at all.
//    * probe cannot answer  → queued. A probe that did not answer is not
//                             evidence, which is the whole lesson of this bug.
//
//  Every server call travels through a seam, so nothing here reaches S3,
//  PostgREST, or the live bug_reports triage queue.
//
//  Containers are retained for the case's lifetime: a ModelContext does not keep
//  its ModelContainer alive, and inserting into a context whose container has
//  been released traps inside SwiftData before the first assertion.
//

import SwiftData
import Supabase
import XCTest
@testable import OPS

@MainActor
final class ProjectPortalMirrorDeliveryTests: XCTestCase {

    // Lowercase throughout — Postgres uuid text is lowercase.
    private let projectId = "a0636b77-3545-43fb-b94b-5d95feff74e1"
    private let companyId = "a612edc0-5c18-4c4d-af97-55b9410dd077"
    private let uploaderId = "7a2c2a6e-434e-4320-be41-9c6367948375"
    private let photoURL = "https://ops-app-files-prod.s3.us-west-2.amazonaws.com/projects/p/a.jpg"

    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    // MARK: - Delivered

    func testDeliveredWhenTheCanonicalInsertLands() async throws {
        let harness = try makeHarness()
        let outcome = await harness.manager.deliverPortalMirror(
            urls: [photoURL],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )

        XCTAssertEqual(outcome, .delivered)
        XCTAssertTrue(outcome.isDelivered)
        XCTAssertNil(outcome.failedTileMessage, "A delivered photo has nothing to report")

        let rows = harness.inserter.rows
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.project_id, projectId)
        XCTAssertEqual(row.company_id, companyId)
        XCTAssertEqual(row.url, photoURL)
        XCTAssertEqual(row.uploaded_by, uploaderId)
        XCTAssertEqual(row.source, "in_progress")
        XCTAssertFalse(row.is_client_visible, "Photos start hidden; the crew opts each one in")

        let filings = harness.reporter.filings
        XCTAssertTrue(filings.isEmpty, "Nothing failed, so nothing is filed")
    }

    /// The chokepoint never probes for a batch with nothing in it.
    func testEmptyBatchIsDeliveredWithoutTouchingTheServer() async throws {
        let harness = try makeHarness()
        let outcome = await harness.manager.deliverPortalMirror(
            urls: [],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )

        XCTAssertEqual(outcome, .delivered)
        let rows = harness.inserter.rows
        XCTAssertTrue(rows.isEmpty)
        let probes = harness.probe.visibilityChecks
        XCTAssertTrue(probes.isEmpty)
    }

    // MARK: - The regression itself: a crew-shaped denial

    /// THE bug. A refusal against a job this account CAN see is never an
    /// absence: it is filed loudly with its raw cause and the photos stay
    /// queued. The old path filed PROJECT_ROW_MISSING here and gave up.
    func testRefusalAgainstAVisibleProjectIsFiledAndQueuedNotDeclaredAbsent() async throws {
        let harness = try makeHarness()
        harness.inserter.setFailure(Self.permissionDenied)
        harness.probe.setVisible(true)

        let outcome = await harness.manager.deliverPortalMirror(
            urls: [photoURL],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )

        XCTAssertEqual(outcome, .retryQueued, "Delivery is retried, not written off")
        XCTAssertNil(outcome.failedTileMessage, "A queued mirror needs nothing from the operator")

        let filings = harness.reporter.filings
        XCTAssertEqual(filings.count, 1)
        let filing = try XCTUnwrap(filings.first)
        XCTAssertEqual(filing.errorCode, "PHOTO_PORTAL_INSERT_REFUSED")
        XCTAssertNotEqual(
            filing.errorCode,
            "PROJECT_ROW_MISSING",
            "The row is visible — claiming it is absent is the bug being fixed"
        )

        // The RPC is never consulted for a row the account can already see.
        let states = harness.probe.stateChecks
        XCTAssertTrue(states.isEmpty)

        // And the project is untouched: no tombstone, and the photo path no
        // longer drives project.needsSync at all (that flag was the observable
        // trace of the retired CSV PATCH).
        XCTAssertNil(harness.project.deletedAt)
        XCTAssertFalse(harness.project.needsSync)
    }

    // MARK: - Invisible: the server states which truth

    func testLiveButUnsharedProjectHoldsWithoutFilingAnything() async throws {
        let harness = try makeHarness()
        harness.inserter.setFailure(Self.permissionDenied)
        harness.probe.setVisible(false)
        harness.probe.setState(.active)

        let outcome = await harness.manager.deliverPortalMirror(
            urls: [photoURL],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )

        XCTAssertEqual(outcome, .heldNotShared)
        XCTAssertEqual(outcome.failedTileMessage, SyncStatusCopy.Photo.notShared)
        XCTAssertNotEqual(
            outcome.failedTileMessage,
            SyncStatusCopy.Photo.projectMissing,
            "The job still exists — the tile must not say it is gone"
        )

        let filings = harness.reporter.filings
        XCTAssertTrue(filings.isEmpty, "Losing access to a job is a permission state, not a defect")
        XCTAssertNil(harness.project.deletedAt, "An unshared job is not a deleted one")
    }

    func testDeletedProjectIsTombstonedLocallyAndNotFiled() async throws {
        let harness = try makeHarness()
        harness.inserter.setFailure(Self.permissionDenied)
        harness.probe.setVisible(false)
        harness.probe.setState(.deleted)

        let outcome = await harness.manager.deliverPortalMirror(
            urls: [photoURL],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )

        XCTAssertEqual(outcome, .heldProjectDeleted)
        XCTAssertEqual(outcome.failedTileMessage, SyncStatusCopy.Photo.projectMissing)
        XCTAssertNotNil(
            harness.project.deletedAt,
            "The server's tombstone is the newer truth — this phone applies it"
        )
        XCTAssertFalse(harness.project.needsSync, "Nothing is left to push for a deleted job")

        let filings = harness.reporter.filings
        XCTAssertTrue(filings.isEmpty, "A deleted job is normal lifecycle, not a bug")
    }

    /// The claim the old code made without evidence, now made only WITH it —
    /// and still only once.
    func testConfirmedAbsentProjectFilesExactlyOneMissingRowReport() async throws {
        let harness = try makeHarness()
        harness.inserter.setFailure(Self.permissionDenied)
        harness.probe.setVisible(false)
        harness.probe.setState(.absent)

        let outcome = await harness.manager.deliverPortalMirror(
            urls: [photoURL],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )

        XCTAssertEqual(outcome, .heldProjectAbsent)
        XCTAssertEqual(outcome.failedTileMessage, SyncStatusCopy.Photo.projectMissing)

        let filings = harness.reporter.filings
        XCTAssertEqual(filings.count, 1)
        let filing = try XCTUnwrap(filings.first)
        XCTAssertEqual(filing.errorCode, "PROJECT_ROW_MISSING")
        XCTAssertTrue(
            filing.summary.contains("confirmed absent"),
            "The summary must say the absence was verified, not assumed: \(filing.summary)"
        )
        XCTAssertTrue(filing.summary.contains(projectId))
    }

    /// A project whose own create has not landed yet is not missing — it just
    /// has not been sent. The barrier vetoes the claim before it is filed.
    func testAbsentProjectAwaitingItsOwnCreateIsQueuedNotFiled() async throws {
        let harness = try makeHarness()
        harness.inserter.setFailure(Self.permissionDenied)
        harness.probe.setVisible(false)
        harness.probe.setState(.absent)

        // The project's own create, still queued.
        let create = SyncOperation(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: Data("{}".utf8),
            changedFields: []
        )
        create.status = "pending"
        harness.context.insert(create)
        try harness.context.save()

        let outcome = await harness.manager.deliverPortalMirror(
            urls: [photoURL],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )

        XCTAssertEqual(outcome, .retryQueued)
        let filings = harness.reporter.filings
        XCTAssertTrue(filings.isEmpty, "A job that has not been sent yet is not a missing job")
    }

    // MARK: - Idempotency and unanswered probes

    /// The repair, another device, or an earlier retry got there first. The
    /// arbiter's name is the contract (migration cluster_j_01).
    func testDuplicateArbiterReadsAsAlreadyMirrored() async throws {
        let harness = try makeHarness()
        harness.inserter.setFailure(
            Self.duplicateViolation(constraint: "project_photos_active_project_url_uidx")
        )

        let outcome = await harness.manager.deliverPortalMirror(
            urls: [photoURL],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )

        XCTAssertEqual(outcome, .alreadyMirrored)
        XCTAssertTrue(outcome.isDelivered, "The portal can render it — that is what delivered means")
        XCTAssertNil(outcome.failedTileMessage)

        let filings = harness.reporter.filings
        XCTAssertTrue(filings.isEmpty)
        let probes = harness.probe.visibilityChecks
        XCTAssertTrue(probes.isEmpty, "Nothing failed, so nothing needs explaining")
    }

    /// An unrelated 23505 is a real integrity problem and must NOT be swallowed
    /// as idempotency — it goes to the probes like any other permanent refusal.
    func testUnrelatedDuplicateIsNotMistakenForTheArbiter() async throws {
        let harness = try makeHarness()
        harness.inserter.setFailure(
            Self.duplicateViolation(constraint: "project_photos_pkey")
        )
        harness.probe.setVisible(true)

        let outcome = await harness.manager.deliverPortalMirror(
            urls: [photoURL],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )

        XCTAssertNotEqual(outcome, .alreadyMirrored)
        XCTAssertEqual(outcome, .retryQueued)
        let filings = harness.reporter.filings
        XCTAssertEqual(filings.first?.errorCode, "PHOTO_PORTAL_INSERT_REFUSED")
    }

    func testTransientFailureQueuesWithoutProbingOrFiling() async throws {
        let harness = try makeHarness()
        harness.inserter.setFailure(URLError(.timedOut))

        let outcome = await harness.manager.deliverPortalMirror(
            urls: [photoURL],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )

        XCTAssertEqual(outcome, .retryQueued)
        let probes = harness.probe.visibilityChecks
        XCTAssertTrue(probes.isEmpty, "A timeout says nothing about the row; do not ask")
        let filings = harness.reporter.filings
        XCTAssertTrue(filings.isEmpty)
    }

    /// The lesson of the bug, stated as a test: a probe that cannot answer
    /// produces no verdict at all.
    func testFailedProbeNeverProducesAVerdict() async throws {
        let visibilityDown = try makeHarness()
        visibilityDown.inserter.setFailure(Self.permissionDenied)
        visibilityDown.probe.setVisibilityFailure(URLError(.notConnectedToInternet))

        let first = await visibilityDown.manager.deliverPortalMirror(
            urls: [photoURL],
            project: visibilityDown.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )
        XCTAssertEqual(first, .retryQueued)
        let firstFilings = visibilityDown.reporter.filings
        XCTAssertTrue(firstFilings.isEmpty)
        XCTAssertNil(visibilityDown.project.deletedAt)

        let stateDown = try makeHarness()
        stateDown.inserter.setFailure(Self.permissionDenied)
        stateDown.probe.setVisible(false)
        stateDown.probe.setStateFailure(URLError(.notConnectedToInternet))

        let second = await stateDown.manager.deliverPortalMirror(
            urls: [photoURL],
            project: stateDown.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )
        XCTAssertEqual(second, .retryQueued)
        let secondFilings = stateDown.reporter.filings
        XCTAssertTrue(secondFilings.isEmpty)
        XCTAssertNil(stateDown.project.deletedAt)
    }

    /// An answer this build does not recognize is not an answer.
    func testUnrecognizedServerStateQueues() async throws {
        let harness = try makeHarness()
        harness.inserter.setFailure(Self.permissionDenied)
        harness.probe.setVisible(false)
        harness.probe.setState(nil)

        let outcome = await harness.manager.deliverPortalMirror(
            urls: [photoURL],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )

        XCTAssertEqual(outcome, .retryQueued)
        let filings = harness.reporter.filings
        XCTAssertTrue(filings.isEmpty)
    }

    // MARK: - Fixtures

    struct Harness {
        let manager: ImageSyncManager
        let context: ModelContext
        let project: Project
        let inserter: RecordingMirrorInserter
        let probe: StubServerStateProbe
        let reporter: RecordingIncidentReporter
    }

    private func makeHarness() throws -> Harness {
        let schema = Schema(versionedSchema: OPSSchemaCurrent.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
            ]
        )
        retainedContainers.append(container)
        let context = container.mainContext

        // Inert warm-up row — a #Predicate fetch of SyncOperation traps against
        // a table that has never held one, and the create barrier fetches.
        let warmup = SyncOperation(
            entityType: SyncEntityType.projectPhoto.rawValue,
            entityId: "00000000-0000-0000-0000-000000000000",
            operationType: "create",
            payload: Data("{}".utf8),
            changedFields: []
        )
        context.insert(warmup)

        let project = Project(id: projectId, title: "541 Prince Robert Ln", status: .inProgress)
        project.companyId = companyId
        context.insert(project)
        try context.save()

        let manager = ImageSyncManager(modelContext: context, connectivity: ConnectivityManager())
        let inserter = RecordingMirrorInserter()
        let probe = StubServerStateProbe()
        let reporter = RecordingIncidentReporter()
        manager.portalMirrorInserter = inserter
        manager.projectServerStateProbe = probe
        manager.portalMirrorReporter = reporter

        return Harness(
            manager: manager,
            context: context,
            project: project,
            inserter: inserter,
            probe: probe,
            reporter: reporter
        )
    }

    /// The exact refusal shape a crew member's insert takes in production: a
    /// real PostgrestError carrying SQLSTATE 42501, which the classifier reads
    /// as permanent (class 42) and therefore routes to the truth probes.
    private static var permissionDenied: PostgrestError {
        PostgrestError(
            code: "42501",
            message: "new row violates row-level security policy for table \"project_photos\""
        )
    }

    /// A unique-violation as PostgREST reports it. SQLSTATE 23505 is class 23 —
    /// permanent — so anything the arbiter matcher does NOT claim still goes to
    /// the probes rather than being swallowed.
    private static func duplicateViolation(constraint: String) -> PostgrestError {
        PostgrestError(
            code: "23505",
            message: "duplicate key value violates unique constraint \"\(constraint)\""
        )
    }
}

// MARK: - Seams

/// Records every canonical insert and can be told to refuse. An `actor` so the
/// manager's async calls record without a data race.
@MainActor
final class RecordingMirrorInserter: ProjectPhotoMirrorInserting {
    private(set) var rows: [ProjectPhotoMirrorRow] = []
    private var failure: Error?

    func setFailure(_ error: Error?) { failure = error }

    func insertProjectPhotoRows(_ rows: [ProjectPhotoMirrorRow]) async throws {
        if let failure { throw failure }
        self.rows.append(contentsOf: rows)
    }
}

/// States what the server would say, and records what was asked.
@MainActor
final class StubServerStateProbe: ProjectServerStateProbing {
    private(set) var visibilityChecks: [String] = []
    private(set) var stateChecks: [String] = []
    private var visible = true
    private var state: SyncOperationReconcilers.ProjectServerState?
    private var visibilityFailure: Error?
    private var stateFailure: Error?

    func setVisible(_ value: Bool) { visible = value }
    func setState(_ value: SyncOperationReconcilers.ProjectServerState?) { state = value }
    func setVisibilityFailure(_ error: Error?) { visibilityFailure = error }
    func setStateFailure(_ error: Error?) { stateFailure = error }

    func isProjectVisible(projectId: String) async throws -> Bool {
        visibilityChecks.append(projectId)
        if let visibilityFailure { throw visibilityFailure }
        return visible
    }

    func projectServerState(
        projectId: String
    ) async throws -> SyncOperationReconcilers.ProjectServerState? {
        stateChecks.append(projectId)
        if let stateFailure { throw stateFailure }
        return state
    }
}

/// Captures filings instead of writing bug_reports rows. A test must never file
/// a ticket at the live triage queue.
@MainActor
final class RecordingIncidentReporter: PortalMirrorIncidentReporting {
    struct Filing: Equatable {
        let errorCode: String
        let summary: String
    }

    private(set) var filings: [Filing] = []

    func reportPortalMirrorIncident(
        errorCode: String,
        summary: String,
        metadata: [String: Any]
    ) async {
        filings.append(Filing(errorCode: errorCode, summary: summary))
    }
}
