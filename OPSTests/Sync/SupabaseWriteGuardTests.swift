//
//  SupabaseWriteGuardTests.swift
//  OPSTests
//
//  Zero-row PATCH detection (bug 2e58c85b) — the safety net under the create
//  barrier.
//
//  PostgREST answers a PATCH that matches no row with 200 and an empty body.
//  Every outbound field update dropped that response, so the queue retired the
//  operation as delivered and the operator's change disappeared without an
//  error, a park, or a row in PENDING WORK. The guard reads the response the
//  client was already asking for (`update` defaults to `return=representation`)
//  and turns "changed nothing" into a named, permanent, visible park.
//
//  What is asserted here: the verdict, its disposition, the state transition it
//  drives, and the words the operator reads. Also — just as important — the
//  cases that must NOT become failures: tombstone writes, whose visibility is
//  governed by the very column they set, and any response shape the guard
//  cannot read. Never park on a guess.
//

import SwiftData
import Supabase
import XCTest
@testable import OPS

@MainActor
final class SupabaseWriteGuardTests: XCTestCase {

    private let projectId = "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1"

    // MARK: - The verdict

    /// The bug, caught: the server changed nothing and says so with an empty
    /// representation.
    func test_requireAffectedRow_throwsWhenTheServerChangedNoRow() {
        XCTAssertThrowsError(
            try SupabaseWriteGuard.requireAffectedRow(
                response: Data("[]".utf8),
                table: "projects",
                id: projectId,
                fields: ["title": .string("Renamed")]
            )
        ) { error in
            guard case SyncError.serverRowMissing(let table, let id) = error else {
                return XCTFail("expected serverRowMissing, got \(error)")
            }
            XCTAssertEqual(table, "projects")
            XCTAssertEqual(id, projectId)
        }
    }

    /// A row came back — the write landed. Nothing to do.
    func test_requireAffectedRow_acceptsAnAffectedRow() throws {
        try SupabaseWriteGuard.requireAffectedRow(
            response: Data("[{\"id\":\"\(projectId)\"}]".utf8),
            table: "projects",
            id: projectId,
            fields: ["title": .string("Renamed")]
        )
    }

    /// A tombstone write crosses the visibility line several read policies draw
    /// at `deleted_at` (`user_can_view_task_columns` returns false the moment it
    /// is set). An empty representation there is not evidence the write missed,
    /// and parking a delete the operator already watched take effect locally
    /// would be a lie in the other direction.
    func test_requireAffectedRow_exemptsTombstoneWrites() throws {
        try SupabaseWriteGuard.requireAffectedRow(
            response: Data("[]".utf8),
            table: "project_tasks",
            id: projectId,
            fields: [
                "deleted_at": .string("2026-08-18T00:00:00Z"),
                "updated_at": .string("2026-08-18T00:00:00Z")
            ]
        )
    }

    /// Clearing `deleted_at` — a restore — crosses the same line in the other
    /// direction and is exempt for the same reason.
    func test_requireAffectedRow_exemptsRestoreWrites() throws {
        try SupabaseWriteGuard.requireAffectedRow(
            response: Data("[]".utf8),
            table: "project_tasks",
            id: projectId,
            fields: ["deleted_at": .null]
        )
    }

    /// An unreadable response is not a failure. This guard exists to stop
    /// silent loss, never to invent a loss from an unfamiliar shape.
    func test_requireAffectedRow_treatsUnreadableResponsesAsDelivered() throws {
        for body in ["", "{\"message\":\"ok\"}", "not json at all"] {
            try SupabaseWriteGuard.requireAffectedRow(
                response: Data(body.utf8),
                table: "projects",
                id: projectId,
                fields: ["title": .string("Renamed")]
            )
        }
    }

    // MARK: - Disposition and state transition

    /// With ordering fixed by the create barrier, a genuine zero-row PATCH means
    /// the row is deleted or RLS-invisible. Both are permanent: retrying
    /// re-answers the same nothing.
    func test_disposition_classifiesServerRowMissingAsPermanent() {
        XCTAssertEqual(
            SyncErrorClassifier.disposition(
                for: SyncError.serverRowMissing(table: "projects", id: projectId)
            ),
            .permanent
        )
    }

    /// Permanent means park immediately — visible and user-retryable — without
    /// burning a retry the operator would never see spent.
    func test_failurePolicy_parksAServerRowMissingWithoutConsumingRetryBudget() throws {
        let context = try makeContext()
        let operation = makeOp(in: context)
        let error = SyncError.serverRowMissing(table: "projects", id: projectId)

        let outcome = SyncOperationFailurePolicy.apply(
            SyncErrorClassifier.disposition(for: error),
            to: operation,
            errorDescription: error.localizedDescription
        )

        XCTAssertEqual(outcome, .parked)
        XCTAssertEqual(operation.status, "parked")
        XCTAssertEqual(operation.retryCount, 0)
        XCTAssertNil(operation.completedAt, "a missing row must never retire as delivered")
    }

    /// The description carries the one stable phrase every string-only surface
    /// downstream keys off. If this drifts, the copy layer and the parked
    /// release both stop recognizing the case.
    func test_serverRowMissingDescriptionCarriesTheStableMarker() {
        let description = SyncError
            .serverRowMissing(table: "projects", id: projectId)
            .localizedDescription
            .lowercased()

        XCTAssertTrue(description.contains(SyncError.serverRowMissingMarker))
        XCTAssertTrue(description.contains("projects"))
        XCTAssertTrue(description.contains(projectId))
    }

    // MARK: - What the operator reads

    /// A deleted record is a different event from a rejected write and gets
    /// different words — "retry" is not the answer when the record is gone.
    func test_pendingWorkCopy_namesAMissingRecordRatherThanARejection() {
        let missing = SyncStatusCopy.PendingWork.statusLine(
            statusRaw: "parked",
            lastError: SyncError
                .serverRowMissing(table: "projects", id: projectId)
                .localizedDescription,
            secondsUntilRetry: nil
        )
        XCTAssertEqual(missing.text, SyncStatusCopy.PendingWork.missingRow)
        XCTAssertEqual(missing.tone, .stuck)

        let rejected = SyncStatusCopy.PendingWork.statusLine(
            statusRaw: "parked",
            lastError: "new row violates check constraint \"projects_title_check\"",
            secondsUntilRetry: nil
        )
        XCTAssertEqual(rejected.text, SyncStatusCopy.PendingWork.parkedRow,
                       "every other park keeps the rejection line")
    }

    /// The detail block follows the same split, so the sheet never tells the
    /// operator a record was refused when it was deleted.
    func test_pendingWorkCopy_detailBlockSplitsMissingRecordFromRejection() {
        let missing = SyncStatusCopy.PendingWork.parkedDetail(
            lastError: SyncError
                .serverRowMissing(table: "projects", id: projectId)
                .localizedDescription
        )
        XCTAssertEqual(missing.label, SyncStatusCopy.PendingWork.missingRowDetailLabel)
        XCTAssertEqual(missing.body, SyncStatusCopy.PendingWork.missingRowDetailBody)

        let rejected = SyncStatusCopy.PendingWork.parkedDetail(lastError: "42501 denied")
        XCTAssertEqual(rejected.label, SyncStatusCopy.PendingWork.parkedDetailLabel)

        let unknown = SyncStatusCopy.PendingWork.parkedDetail(lastError: nil)
        XCTAssertEqual(unknown.label, SyncStatusCopy.PendingWork.parkedDetailLabel,
                       "no error text is not evidence of a deletion")
    }

    /// The notifications panel speaks the same vocabulary. It used to answer
    /// "waiting to sync" for a parked op — telling the operator to keep waiting
    /// for a retry that was never coming.
    func test_panelCopy_reportsParkedWorkAsStuckRatherThanWaiting() {
        let state = SyncStatusCopy.status(
            status: "parked",
            retryCount: 0,
            canRetry: true,
            rawError: SyncError
                .serverRowMissing(table: "projects", id: projectId)
                .localizedDescription
        )
        XCTAssertEqual(state.text, SyncStatusCopy.PendingWork.missingRow)
        XCTAssertEqual(state.tone, .stuck)
    }

    // MARK: - Self-heal

    /// A zero-row park stamped BEFORE the row's own create landed was the
    /// ordering gap, not a deletion — the create barrier hands it back.
    func test_parkedRelease_returnsZeroRowParkWhoseOwnCreateLandedAfterward() throws {
        let context = try makeContext()
        let attemptedAt = Date(timeIntervalSince1970: 1_770_000_000)

        let parked = makeOp(
            operationType: "update",
            status: "parked",
            lastError: SyncError
                .serverRowMissing(table: "projects", id: projectId)
                .localizedDescription,
            lastAttemptedAt: attemptedAt,
            in: context
        )
        let create = makeOp(
            operationType: "create",
            status: "completed",
            completedAt: attemptedAt.addingTimeInterval(90),
            in: context
        )

        XCTAssertEqual(
            SyncCrossEntityDependency
                .parkedOperationsReleasableByCompletedCreates(in: [parked, create])
                .map(\.id),
            [parked.id],
            "the row exists now — the zero-row verdict was ordering, not deletion"
        )
    }

    // MARK: - Helpers

    @discardableResult
    private func makeOp(
        operationType: String = "update",
        status: String = "pending",
        lastError: String? = nil,
        lastAttemptedAt: Date? = nil,
        completedAt: Date? = nil,
        in context: ModelContext
    ) -> SyncOperation {
        let op = SyncOperation(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: operationType,
            payload: Data("{}".utf8),
            changedFields: ["title"]
        )
        op.status = status
        op.lastError = lastError
        op.lastAttemptedAt = lastAttemptedAt
        op.completedAt = completedAt
        context.insert(op)
        return op
    }

    /// Containers outlive the contexts they vend, for the whole test case — a
    /// `ModelContext` does not keep its container alive, and inserting into a
    /// context whose container has been released traps inside SwiftData.
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([SyncOperation.self, PhotoAnnotation.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
            ]
        )
        retainedContainers.append(container)
        return container.mainContext
    }
}
