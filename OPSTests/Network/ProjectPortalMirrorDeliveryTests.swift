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
    private let otherPhotoURL = "https://ops-app-files-prod.s3.us-west-2.amazonaws.com/projects/p/b.jpg"

    private var retainedContainers: [ModelContainer] = []

    /// UserDefaults is process-global. The queues live there, and so does the
    /// operator id — a leftover from either would be read by the next manager's
    /// init and quietly change what these tests measure, or leak into a sibling
    /// suite. Cleared going in, restored going out.
    private var savedUserId: String?

    override func setUp() {
        super.setUp()
        savedUserId = UserDefaults.standard.string(forKey: "currentUserId")
        clearQueues()
    }

    override func tearDown() {
        clearQueues()
        if let savedUserId {
            UserDefaults.standard.set(savedUserId, forKey: "currentUserId")
        } else {
            UserDefaults.standard.removeObject(forKey: "currentUserId")
        }
        retainedContainers.removeAll()
        super.tearDown()
    }

    private func clearQueues() {
        UserDefaults.standard.removeObject(forKey: ImageSyncManager.pendingPortalMirrorsKey)
        UserDefaults.standard.removeObject(forKey: "pendingImageUploads")
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

    /// Bug bf2a75fb — the server saying it could not resolve the caller to a
    /// company is NOT a missing project. Before the probe was hardened this
    /// case answered `absent`, which filed a false PROJECT_ROW_MISSING report
    /// and dropped the queued mirror for good against a live job. It must
    /// queue, and it must file nothing.
    func testUnknownVerdictQueuesTheMirrorAndFilesNothing() async throws {
        let harness = try makeHarness()
        harness.inserter.setFailure(Self.permissionDenied)
        harness.probe.setVisible(false)
        harness.probe.setState(.unknown)

        let outcome = await harness.manager.deliverPortalMirror(
            urls: [photoURL],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )

        XCTAssertEqual(outcome, .retryQueued)
        XCTAssertTrue(
            harness.reporter.filings.isEmpty,
            "An unidentified caller is not evidence that the job is gone"
        )
        XCTAssertNil(
            harness.project.deletedAt,
            "An unknown verdict must never tombstone the job locally"
        )
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

    // MARK: - The durable queue (bug 16d487c4)
    //
    // The missing persistence. A failed or skipped portal insert used to leave
    // NO record that delivery was still owed, so nothing retried it — and the
    // tile copy promising "It'll retry automatically" was simply false on the
    // online path.

    func testQueuedMirrorSurvivesARestart() async throws {
        let harness = try makeHarness()
        harness.inserter.setFailure(URLError(.timedOut))

        let outcome = await harness.manager.deliverPortalMirror(
            urls: [photoURL],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress",
            takenAt: Date(timeIntervalSince1970: 1_756_000_000)
        )
        XCTAssertEqual(outcome, .retryQueued)

        let queued = harness.manager.getPendingPortalMirrors()
        XCTAssertEqual(queued.count, 1)
        let entry = try XCTUnwrap(queued.first)
        XCTAssertEqual(entry.url, photoURL)
        XCTAssertEqual(entry.projectId, projectId)
        XCTAssertEqual(entry.companyId, companyId)
        XCTAssertEqual(entry.uploadedBy, uploaderId)
        XCTAssertEqual(entry.source, "in_progress")
        XCTAssertEqual(entry.takenAt.timeIntervalSince1970, 1_756_000_000, accuracy: 0.001)

        // A fresh manager over the same UserDefaults is the restart.
        let reloaded = ImageSyncManager(
            modelContext: harness.context,
            connectivity: ConnectivityManager()
        )
        XCTAssertEqual(
            reloaded.getPendingPortalMirrors(),
            queued,
            "An app restart must not decide whether a photo reaches the portal"
        )
        XCTAssertTrue(reloaded.hasQueuedDeliveryWork, "The retry must still be armed after a restart")
    }

    func testTheSamePhotoIsNeverQueuedTwice() async throws {
        let harness = try makeHarness()
        harness.inserter.setFailure(URLError(.timedOut))

        for _ in 0..<3 {
            _ = await harness.manager.deliverPortalMirror(
                urls: [photoURL],
                project: harness.project,
                uploadedBy: uploaderId,
                source: "in_progress"
            )
        }

        XCTAssertEqual(harness.manager.getPendingPortalMirrors().count, 1)
    }

    /// Each verdict either keeps the debt or settles it — and the two that
    /// settle it do so for opposite reasons.
    func testQueueTransitionsMatchTheVerdict() async throws {
        // Delivered clears the debt a transient failure recorded.
        let delivered = try makeHarness()
        delivered.inserter.setFailure(URLError(.timedOut))
        _ = await delivered.manager.deliverPortalMirror(
            urls: [photoURL], project: delivered.project,
            uploadedBy: uploaderId, source: "in_progress"
        )
        XCTAssertEqual(delivered.manager.getPendingPortalMirrors().count, 1)
        delivered.inserter.setFailure(nil)
        _ = await delivered.manager.deliverPortalMirror(
            urls: [photoURL], project: delivered.project,
            uploadedBy: uploaderId, source: "in_progress"
        )
        XCTAssertTrue(delivered.manager.getPendingPortalMirrors().isEmpty)
        XCTAssertFalse(delivered.manager.hasQueuedDeliveryWork)

        // Held-not-shared KEEPS the debt: an assignment can be handed back.
        let unshared = try makeHarness()
        unshared.inserter.setFailure(Self.permissionDenied)
        unshared.probe.setVisible(false)
        unshared.probe.setState(.active)
        _ = await unshared.manager.deliverPortalMirror(
            urls: [photoURL], project: unshared.project,
            uploadedBy: uploaderId, source: "in_progress"
        )
        XCTAssertEqual(
            unshared.manager.getPendingPortalMirrors().count, 1,
            "Access can come back; the photo should land the moment it does"
        )

        // Confirmed absent DROPS it: the bug is filed and a 30s loop against a
        // project the server says is not there helps nobody.
        let absent = try makeHarness()
        absent.inserter.setFailure(Self.permissionDenied)
        absent.probe.setVisible(false)
        absent.probe.setState(.absent)
        _ = await absent.manager.deliverPortalMirror(
            urls: [photoURL], project: absent.project,
            uploadedBy: uploaderId, source: "in_progress"
        )
        XCTAssertTrue(absent.manager.getPendingPortalMirrors().isEmpty)
    }

    /// A deleted job takes its whole queue with it — mirrors AND the bytes
    /// waiting to upload into it.
    func testDeletedProjectDropsEveryQueuedItemForThatJob() async throws {
        let harness = try makeHarness()
        harness.inserter.setFailure(URLError(.timedOut))
        _ = await harness.manager.deliverPortalMirror(
            urls: [photoURL, otherPhotoURL],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )
        XCTAssertEqual(harness.manager.getPendingPortalMirrors().count, 2)

        harness.inserter.setFailure(Self.permissionDenied)
        harness.probe.setVisible(false)
        harness.probe.setState(.deleted)
        let outcome = await harness.manager.deliverPortalMirror(
            urls: [photoURL, otherPhotoURL],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress"
        )

        XCTAssertEqual(outcome, .heldProjectDeleted)
        XCTAssertTrue(harness.manager.getPendingPortalMirrors().isEmpty)
        XCTAssertFalse(harness.manager.hasQueuedDeliveryWork)
        XCTAssertNotNil(harness.project.deletedAt)
    }

    /// The drain re-offers owed rows and settles them — with no pending upload
    /// in sight, which is exactly the shape the online path leaves behind.
    func testDrainRedeliversOwedRowsAndKeepsTheirCaptureTime() async throws {
        let harness = try makeHarness()
        let capturedAt = Date(timeIntervalSince1970: 1_756_000_000)
        harness.inserter.setFailure(URLError(.timedOut))
        _ = await harness.manager.deliverPortalMirror(
            urls: [photoURL],
            project: harness.project,
            uploadedBy: uploaderId,
            source: "in_progress",
            takenAt: capturedAt
        )
        XCTAssertEqual(harness.manager.getPendingPortalMirrors().count, 1)

        harness.inserter.setFailure(nil)
        await harness.manager.drainPendingPortalMirrors()

        XCTAssertTrue(
            harness.manager.getPendingPortalMirrors().isEmpty,
            "A drain pass with no pending uploads must still deliver owed rows"
        )
        let rows = harness.inserter.rows
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.url, photoURL)
        XCTAssertEqual(
            row.taken_at,
            ISO8601DateFormatter().string(from: capturedAt),
            "A retry must not rewrite when the photo was taken"
        )
    }

    /// Two batches for the same project, captured at different moments, must
    /// stay separate batches — a redelivered row is byte-identical to the one
    /// first attempted.
    func testDrainReconstructsTheOriginalBatches() async throws {
        let harness = try makeHarness()
        let firstCapture = Date(timeIntervalSince1970: 1_756_000_000)
        let secondCapture = Date(timeIntervalSince1970: 1_756_009_999)
        harness.inserter.setFailure(URLError(.timedOut))
        _ = await harness.manager.deliverPortalMirror(
            urls: [photoURL], project: harness.project,
            uploadedBy: uploaderId, source: "in_progress", takenAt: firstCapture
        )
        _ = await harness.manager.deliverPortalMirror(
            urls: [otherPhotoURL], project: harness.project,
            uploadedBy: uploaderId, source: "completion", takenAt: secondCapture
        )
        XCTAssertEqual(harness.manager.getPendingPortalMirrors().count, 2)

        harness.inserter.setFailure(nil)
        await harness.manager.drainPendingPortalMirrors()

        XCTAssertTrue(harness.manager.getPendingPortalMirrors().isEmpty)
        let rows = harness.inserter.rows
        XCTAssertEqual(rows.count, 2)
        let byURL = Dictionary(uniqueKeysWithValues: rows.map { ($0.url, $0) })
        let first = try XCTUnwrap(byURL[photoURL])
        let second = try XCTUnwrap(byURL[otherPhotoURL])
        XCTAssertEqual(first.source, "in_progress")
        XCTAssertEqual(second.source, "completion")
        XCTAssertEqual(first.taken_at, ISO8601DateFormatter().string(from: firstCapture))
        XCTAssertEqual(second.taken_at, ISO8601DateFormatter().string(from: secondCapture))
    }

    /// A drain with no local row for the project keeps the debt rather than
    /// dropping it — the project may still arrive from an authoritative pull.
    func testDrainKeepsDebtWhenTheProjectIsNotOnThisDeviceYet() async throws {
        let harness = try makeHarness()
        harness.inserter.setFailure(URLError(.timedOut))
        _ = await harness.manager.deliverPortalMirror(
            urls: [photoURL], project: harness.project,
            uploadedBy: uploaderId, source: "in_progress"
        )

        harness.context.delete(harness.project)
        try harness.context.save()

        harness.inserter.setFailure(nil)
        await harness.manager.drainPendingPortalMirrors()

        XCTAssertEqual(
            harness.manager.getPendingPortalMirrors().count, 1,
            "Dropping the debt here would be the silent write-off this queue exists to end"
        )
    }

    /// The timer's liveness predicate, which is what actually decides whether a
    /// stranded photo ever gets another chance.
    func testRetryStaysArmedWhileAnyDeliveryIsOwed() async throws {
        let harness = try makeHarness()
        XCTAssertFalse(harness.manager.hasQueuedDeliveryWork, "Nothing owed at rest")

        harness.inserter.setFailure(URLError(.timedOut))
        _ = await harness.manager.deliverPortalMirror(
            urls: [photoURL], project: harness.project,
            uploadedBy: uploaderId, source: "in_progress"
        )
        XCTAssertTrue(
            harness.manager.hasQueuedDeliveryWork,
            "An owed portal row keeps the retry armed even with zero pending uploads"
        )

        harness.inserter.setFailure(nil)
        _ = await harness.manager.deliverPortalMirror(
            urls: [photoURL], project: harness.project,
            uploadedBy: uploaderId, source: "in_progress"
        )
        XCTAssertFalse(harness.manager.hasQueuedDeliveryWork)
    }

    func testClearingPendingUploadsAlsoClearsOwedPortalRows() async throws {
        let harness = try makeHarness()
        harness.inserter.setFailure(URLError(.timedOut))
        _ = await harness.manager.deliverPortalMirror(
            urls: [photoURL], project: harness.project,
            uploadedBy: uploaderId, source: "in_progress"
        )
        XCTAssertTrue(harness.manager.hasQueuedDeliveryWork)

        harness.manager.clearAllPendingUploads()

        XCTAssertTrue(harness.manager.getPendingPortalMirrors().isEmpty)
        XCTAssertFalse(
            harness.manager.hasQueuedDeliveryWork,
            "Clearing must not leave the 30s timer running for work the operator dismissed"
        )
    }

    // MARK: - Pre-drain settle

    /// Before uploading bytes for a job, the drain asks whether the job still
    /// exists. A local tombstone answers for free — no probe at all.
    func testLocallyTombstonedProjectSettlesWithoutAskingTheServer() async throws {
        let harness = try makeHarness()
        harness.project.deletedAt = Date()
        try harness.context.save()

        let settled = await harness.manager.projectIsSettledAsDeleted(harness.project)

        XCTAssertTrue(settled)
        XCTAssertTrue(
            harness.probe.stateChecks.isEmpty,
            "This phone already knows; asking again is wasted traffic"
        )
    }

    /// A server tombstone settles the job AND is applied locally, so the next
    /// pass is free.
    func testServerTombstoneSettlesAndIsAppliedLocally() async throws {
        let harness = try makeHarness()
        harness.probe.setState(.deleted)

        let settled = await harness.manager.projectIsSettledAsDeleted(harness.project)

        XCTAssertTrue(settled)
        XCTAssertNotNil(harness.project.deletedAt)
        XCTAssertEqual(harness.probe.stateChecks, [projectId])
    }

    /// Everything that is NOT a stated deletion leaves the queue alone. The
    /// queue is a photo's last record — it is never dropped on a guess.
    func testNothingButAStatedDeletionSettlesTheQueue() async throws {
        // `.unknown` is in this list on purpose (bug bf2a75fb): the server
        // saying it could not identify the caller must never settle anything.
        for state in [
            SyncOperationReconcilers.ProjectServerState.active,
            .absent,
            .unknown,
        ] {
            let harness = try makeHarness()
            harness.probe.setState(state)
            let settled = await harness.manager.projectIsSettledAsDeleted(harness.project)
            XCTAssertFalse(settled, "\(state.rawValue) is not a deletion")
            XCTAssertNil(harness.project.deletedAt)
        }

        let unrecognized = try makeHarness()
        unrecognized.probe.setState(nil)
        let unrecognizedSettled = await unrecognized.manager
            .projectIsSettledAsDeleted(unrecognized.project)
        XCTAssertFalse(unrecognizedSettled)

        let offline = try makeHarness()
        offline.probe.setStateFailure(URLError(.notConnectedToInternet))
        let offlineSettled = await offline.manager.projectIsSettledAsDeleted(offline.project)
        XCTAssertFalse(offlineSettled, "A probe that could not answer is not a deletion")
        XCTAssertNil(offline.project.deletedAt)
    }

    // MARK: - Launch backfill sweep (heals the reported photos)

    /// The exact strand shape: an https URL in this device's gallery with no
    /// server CSV entry and no canonical row. Nothing else looks like that.
    func testStrandedPhotoIsDetectedAndQueuedForDelivery() async throws {
        let harness = try makeHarness(currentUserId: uploaderId)
        harness.project.setProjectImageURLs([photoURL, otherPhotoURL])
        try harness.context.save()
        harness.reader.projectImages = [projectId: []]
        harness.reader.photoURLs = [:]

        await harness.manager.reconcileStrandedPortalMirrors()

        let queued = harness.manager.getPendingPortalMirrors()
        XCTAssertEqual(Set(queued.map(\.url)), [photoURL, otherPhotoURL])
        let entry = try XCTUnwrap(queued.first)
        XCTAssertEqual(entry.projectId, projectId)
        XCTAssertEqual(entry.companyId, companyId)
        XCTAssertEqual(entry.uploadedBy, uploaderId)
        XCTAssertEqual(entry.source, "in_progress")
        XCTAssertTrue(harness.manager.hasQueuedDeliveryWork)
    }

    /// A legacy photo lives in the server CSV, and an already-delivered one has
    /// a canonical row. Neither is stranded, and re-delivering either would
    /// double-tile someone's gallery.
    func testAlreadyDeliveredPhotosAreNeverQueued() async throws {
        let harness = try makeHarness(currentUserId: uploaderId)
        let legacyURL = "https://ops-app-files-prod.s3.us-west-2.amazonaws.com/projects/p/legacy.jpg"
        harness.project.setProjectImageURLs([legacyURL, photoURL, otherPhotoURL])
        try harness.context.save()
        harness.reader.projectImages = [projectId: [legacyURL]]
        harness.reader.photoURLs = [projectId: [photoURL]]

        await harness.manager.reconcileStrandedPortalMirrors()

        let queued = harness.manager.getPendingPortalMirrors().map(\.url)
        XCTAssertEqual(queued, [otherPhotoURL], "Only the genuinely undelivered photo is owed")
    }

    /// Local-only placeholders have no bytes on S3 to mirror — the upload queue
    /// owns those.
    func testLocalPlaceholdersAreNotTreatedAsStranded() async throws {
        let harness = try makeHarness(currentUserId: uploaderId)
        harness.project.setProjectImageURLs(["local://pending-a", "local://pending-b"])
        try harness.context.save()
        harness.reader.projectImages = [projectId: []]

        await harness.manager.reconcileStrandedPortalMirrors()

        XCTAssertTrue(harness.manager.getPendingPortalMirrors().isEmpty)
    }

    /// A project this account cannot see is absent from the RLS-filtered read.
    /// Queueing an insert against it would only manufacture a rejection.
    func testInvisibleProjectIsSkipped() async throws {
        let harness = try makeHarness(currentUserId: uploaderId)
        harness.project.setProjectImageURLs([photoURL])
        try harness.context.save()
        harness.reader.projectImages = [:]   // RLS returned nothing for it

        await harness.manager.reconcileStrandedPortalMirrors()

        XCTAssertTrue(harness.manager.getPendingPortalMirrors().isEmpty)
    }

    func testSweepRunsOnlyOncePerLaunch() async throws {
        let harness = try makeHarness(currentUserId: uploaderId)
        harness.project.setProjectImageURLs([photoURL])
        try harness.context.save()
        harness.reader.projectImages = [projectId: []]

        await harness.manager.reconcileStrandedPortalMirrors()
        await harness.manager.reconcileStrandedPortalMirrors()

        XCTAssertEqual(harness.reader.projectImageReads, 1, "Network-bound and settled — ask once")
        XCTAssertEqual(harness.manager.getPendingPortalMirrors().count, 1)
    }

    /// An incomplete answer must never be mistaken for "nothing was stranded".
    func testFailedReadLeavesTheSweepArmedForTheNextPass() async throws {
        let harness = try makeHarness(currentUserId: uploaderId)
        harness.project.setProjectImageURLs([photoURL])
        try harness.context.save()
        harness.reader.failure = URLError(.notConnectedToInternet)

        await harness.manager.reconcileStrandedPortalMirrors()
        XCTAssertTrue(harness.manager.getPendingPortalMirrors().isEmpty)

        harness.reader.failure = nil
        harness.reader.projectImages = [projectId: []]
        await harness.manager.reconcileStrandedPortalMirrors()

        XCTAssertEqual(
            harness.manager.getPendingPortalMirrors().count, 1,
            "The retry must still find the strand once the network is back"
        )
    }

    /// With no operator id there is nothing honest to attribute the photo to,
    /// and the insert would be refused anyway.
    func testSweepDoesNothingWithoutAnOperator() async throws {
        let harness = try makeHarness(currentUserId: nil)
        harness.project.setProjectImageURLs([photoURL])
        try harness.context.save()
        harness.reader.projectImages = [projectId: []]

        await harness.manager.reconcileStrandedPortalMirrors()

        XCTAssertTrue(harness.manager.getPendingPortalMirrors().isEmpty)
        XCTAssertEqual(harness.reader.projectImageReads, 0)
    }

    /// A trashed job is not backfilled — its photos belong to the trash with it.
    func testDeletedProjectsAreNotBackfilled() async throws {
        let harness = try makeHarness(currentUserId: uploaderId)
        harness.project.setProjectImageURLs([photoURL])
        harness.project.deletedAt = Date()
        try harness.context.save()
        harness.reader.projectImages = [projectId: []]

        await harness.manager.reconcileStrandedPortalMirrors()

        XCTAssertTrue(harness.manager.getPendingPortalMirrors().isEmpty)
    }

    // MARK: - Fixtures

    struct Harness {
        let manager: ImageSyncManager
        let context: ModelContext
        let project: Project
        let inserter: RecordingMirrorInserter
        let probe: StubServerStateProbe
        let reporter: RecordingIncidentReporter
        let reader: StubStrandedMirrorReader
    }

    private func makeHarness(currentUserId: String? = nil) throws -> Harness {
        if let currentUserId {
            UserDefaults.standard.set(currentUserId, forKey: "currentUserId")
        } else {
            UserDefaults.standard.removeObject(forKey: "currentUserId")
        }
        return try buildHarness()
    }

    private func buildHarness() throws -> Harness {
        // Several cases build more than one harness. Each manager loads the
        // queue from UserDefaults at init, so without this a sibling harness's
        // enqueue would leak in and the case would measure the wrong thing.
        clearQueues()

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
        let reader = StubStrandedMirrorReader()
        manager.portalMirrorInserter = inserter
        manager.projectServerStateProbe = probe
        manager.portalMirrorReporter = reporter
        manager.strandedMirrorReader = reader

        return Harness(
            manager: manager,
            context: context,
            project: project,
            inserter: inserter,
            probe: probe,
            reporter: reporter,
            reader: reader
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

/// States what the server holds, and counts what was asked — the once-per-launch
/// guarantee is only observable as "it did not ask twice".
@MainActor
final class StubStrandedMirrorReader: StrandedPortalMirrorReading {
    var projectImages: [String: [String]] = [:]
    var photoURLs: [String: Set<String>] = [:]
    var failure: Error?
    private(set) var projectImageReads = 0
    private(set) var photoURLReads = 0

    func serverProjectImages(projectIds: [String]) async throws -> [String: [String]] {
        projectImageReads += 1
        if let failure { throw failure }
        return projectImages.filter { projectIds.contains($0.key) }
    }

    func serverPhotoURLs(projectIds: [String]) async throws -> [String: Set<String>] {
        photoURLReads += 1
        if let failure { throw failure }
        return photoURLs.filter { projectIds.contains($0.key) }
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
