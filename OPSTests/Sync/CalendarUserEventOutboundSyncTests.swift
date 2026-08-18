//
//  CalendarUserEventOutboundSyncTests.swift
//  OPSTests
//
//  Time off and personal events on the durable outbound queue (bug ef5a69e6).
//
//  Before this, every write to `calendar_user_events` was fire-and-forget from
//  the surface that made it. A failed create left a local row dirty with nothing
//  queued to push it, the sheet still reported success, and the approvers got a
//  push for a request that existed on exactly one phone. The recurring helpers
//  cleared `needsSync` after `try?` calls, so a failed edit reverted on the next
//  pull and a failed delete let the event come back.
//
//  These tests hold the three guarantees that replace that: the write is routed
//  through the queue, the dirty flag clears on nothing but a confirmed server
//  success, and the notification cannot leave the device ahead of the row it
//  announces. The repository is a spy — the queue's contract is what is under
//  test, never the network.
//

import SwiftData
import XCTest
@testable import OPS

/// Records what the queue asked the server to do. Failure is injectable so the
/// "nothing clears on failure" guarantee can be proven, not assumed.
private final class SpyCalendarRepository: CalendarUserEventRemoteWriting {
    enum Call: Equatable {
        case upsert(id: String)
        case update(id: String)
        case delete(id: String)
    }

    private(set) var calls: [Call] = []
    private(set) var lastUpsertColumns: [String: String] = [:]
    private(set) var lastUpdateFieldKeys: Set<String> = []
    var errorToThrow: Error?

    func upsertEvent(_ columns: [String: Any]) async throws {
        lastUpsertColumns = columns.mapValues { String(describing: $0) }
        calls.append(.upsert(id: (columns["id"] as? String) ?? ""))
        if let errorToThrow { throw errorToThrow }
    }

    func updateFields(_ eventId: String, fields: [String: Any]) async throws {
        lastUpdateFieldKeys = Set(fields.keys)
        calls.append(.update(id: eventId))
        if let errorToThrow { throw errorToThrow }
    }

    func softDelete(_ eventId: String) async throws {
        calls.append(.delete(id: eventId))
        if let errorToThrow { throw errorToThrow }
    }
}

@MainActor
final class CalendarUserEventOutboundSyncTests: XCTestCase {

    private let eventId = "3f1c8a6e-2b41-4d7a-9c33-6f0d51a2b7e4"
    private let companyId = "a612edc0-5c18-4c4d-af97-55b9410dd077"
    private let userId = "283d49df-90a1-4abb-b94c-3e9f17f02c0d"

    // MARK: - Payload

    /// The payload is the row. A create that carried a partial row would push
    /// an event the operator did not enter.
    func test_columns_carryTheWholeRow() throws {
        let context = try makeContext()
        let event = makeEvent(in: context)
        event.notes = "Back specialist"
        event.address = "12 Mill St"
        event.teamMemberIds = [userId]
        event.seriesId = "9d2a4c1b-5e63-4f18-8a70-2c5b91de4f03"

        let columns = CalendarUserEventOutboundSync.columns(of: event)

        XCTAssertEqual(columns["id"] as? String, eventId)
        XCTAssertEqual(columns["user_id"] as? String, userId)
        XCTAssertEqual(columns["company_id"] as? String, companyId)
        XCTAssertEqual(columns["type"] as? String, CalendarUserEventType.timeOff.rawValue)
        XCTAssertEqual(columns["status"] as? String, CalendarUserEventStatus.pending.rawValue)
        XCTAssertEqual(columns["notes"] as? String, "Back specialist")
        XCTAssertEqual(columns["address"] as? String, "12 Mill St")
        XCTAssertEqual(columns["team_member_ids"] as? [String], [userId])
        XCTAssertEqual(columns["all_day"] as? Bool, true)
        XCTAssertNotNil(columns["start_date"] as? String)
        XCTAssertNotNil(columns["end_date"] as? String)
        XCTAssertNotNil(columns["series_id"] as? String)

        XCTAssertTrue(
            Set(columns.keys).isSubset(of: CalendarUserEventOutboundSync.validColumns),
            "every key must be a real column — PostgREST rejects the whole statement over one unknown"
        )
    }

    /// Clearing a field has to travel as an explicit null. Omitting the key
    /// leaves the old value in place, which reads to the operator as an edit
    /// that silently did not take.
    func test_editColumns_clearFieldsWithExplicitNulls() {
        let fields = CalendarUserEventOutboundSync.editColumns(
            title: "Dentist",
            notes: nil,
            allDay: false,
            teamMemberIds: nil,
            startDate: Date(timeIntervalSince1970: 1_770_000_000),
            endDate: Date(timeIntervalSince1970: 1_770_003_600),
            detachFromSeries: false
        )

        XCTAssertTrue(fields["notes"] is NSNull)
        XCTAssertTrue(fields["team_member_ids"] is NSNull)
        XCTAssertNil(fields["series_id"], "only a detaching edit touches the series")
    }

    /// "This event only" detaches in the same statement it edits — the old path
    /// spent a separate round trip, and a detach that landed while the edit did
    /// not left the row half-changed.
    func test_editColumns_detachFoldsIntoTheSameStatement() {
        let fields = CalendarUserEventOutboundSync.editColumns(
            title: "Dentist",
            notes: "Moved",
            allDay: false,
            teamMemberIds: [userId],
            startDate: Date(timeIntervalSince1970: 1_770_000_000),
            endDate: Date(timeIntervalSince1970: 1_770_003_600),
            detachFromSeries: true
        )

        XCTAssertTrue(fields["series_id"] is NSNull)
        XCTAssertEqual(fields["title"] as? String, "Dentist")
    }

    // MARK: - Execution

    func test_executeIfHandled_routesCreateToAnIdempotentUpsert() async throws {
        let spy = SpyCalendarRepository()
        let handled = try await CalendarUserEventOutboundSync.executeIfHandled(
            entityType: SyncEntityType.calendarUserEvent.rawValue,
            operationType: "create",
            entityId: eventId,
            payload: ["id": eventId, "title": "Time Off Request"],
            companyId: companyId,
            repositoryFactory: { _ in spy }
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(spy.calls, [.upsert(id: eventId)])
    }

    func test_executeIfHandled_routesUpdateAndDelete() async throws {
        let updateSpy = SpyCalendarRepository()
        _ = try await CalendarUserEventOutboundSync.executeIfHandled(
            entityType: SyncEntityType.calendarUserEvent.rawValue,
            operationType: "update",
            entityId: eventId,
            payload: ["title": "Dentist"],
            companyId: companyId,
            repositoryFactory: { _ in updateSpy }
        )
        XCTAssertEqual(updateSpy.calls, [.update(id: eventId)])

        let deleteSpy = SpyCalendarRepository()
        _ = try await CalendarUserEventOutboundSync.executeIfHandled(
            entityType: SyncEntityType.calendarUserEvent.rawValue,
            operationType: "delete",
            entityId: eventId,
            payload: ["id": eventId],
            companyId: companyId,
            repositoryFactory: { _ in deleteSpy }
        )
        XCTAssertEqual(deleteSpy.calls, [.delete(id: eventId)])
    }

    /// Local routing keys must never reach PostgREST — one unknown column
    /// rejects the whole statement, and the notification is the biggest one.
    func test_executeIfHandled_stripsLocalOnlyPayloadKeys() async throws {
        let spy = SpyCalendarRepository()
        _ = try await CalendarUserEventOutboundSync.executeIfHandled(
            entityType: SyncEntityType.calendarUserEvent.rawValue,
            operationType: "create",
            entityId: eventId,
            payload: [
                "id": eventId,
                "title": "Time Off Request",
                CalendarUserEventOutboundSync.notificationKey: ["kind": "requested"],
                "needs_sync": true
            ],
            companyId: companyId,
            repositoryFactory: { _ in spy }
        )

        XCTAssertNil(spy.lastUpsertColumns[CalendarUserEventOutboundSync.notificationKey])
        XCTAssertNil(spy.lastUpsertColumns["needs_sync"])
        XCTAssertEqual(spy.lastUpsertColumns["title"], "Time Off Request")
    }

    /// Anything this subsystem does not own falls through untouched.
    func test_executeIfHandled_declinesForeignEntityTypes() async throws {
        let spy = SpyCalendarRepository()
        let handled = try await CalendarUserEventOutboundSync.executeIfHandled(
            entityType: SyncEntityType.project.rawValue,
            operationType: "update",
            entityId: eventId,
            payload: [:],
            companyId: companyId,
            repositoryFactory: { _ in spy }
        )

        XCTAssertFalse(handled)
        XCTAssertTrue(spy.calls.isEmpty)
    }

    /// An operation type nobody wrote a handler for is a client bug that a retry
    /// cannot fix — it throws a permanent error so the op parks and is seen.
    func test_executeIfHandled_throwsPermanentlyForAnUnknownOperation() async {
        let spy = SpyCalendarRepository()
        do {
            _ = try await CalendarUserEventOutboundSync.executeIfHandled(
                entityType: SyncEntityType.calendarUserEvent.rawValue,
                operationType: "linkOpportunity",
                entityId: eventId,
                payload: [:],
                companyId: companyId,
                repositoryFactory: { _ in spy }
            )
            XCTFail("an unhandled operation type must not report success")
        } catch {
            XCTAssertEqual(SyncErrorClassifier.disposition(for: error), .permanent)
        }
        XCTAssertTrue(spy.calls.isEmpty)
    }

    /// A failed write throws, so the queue's own retry/park policy owns it —
    /// which is the entire point of moving off `try?`.
    func test_executeIfHandled_propagatesTheServerFailure() async {
        let spy = SpyCalendarRepository()
        spy.errorToThrow = SyncError.networkUnavailable
        do {
            _ = try await CalendarUserEventOutboundSync.executeIfHandled(
                entityType: SyncEntityType.calendarUserEvent.rawValue,
                operationType: "create",
                entityId: eventId,
                payload: ["id": eventId],
                companyId: companyId,
                repositoryFactory: { _ in spy }
            )
            XCTFail("a failed write must not be swallowed — that was the bug")
        } catch {
            XCTAssertEqual(SyncErrorClassifier.disposition(for: error), .transient)
        }
    }

    // MARK: - Confirmed-success bookkeeping

    /// The dirty flag is what holds the inbound merge off a locally-edited row.
    /// It clears on exactly one thing: the operation completing.
    func test_clearNeedsSyncOnCompletion_clearsOnlyTheDeliveredRow() throws {
        let context = try makeContext()
        let delivered = makeEvent(in: context)
        let untouched = makeEvent(id: "6b0e2f37-9a15-4c88-b0d2-71c4e9a5d602", in: context)

        try CalendarUserEventOutboundSync.clearNeedsSyncOnCompletion(
            for: makeOp(operationType: "create", in: context),
            in: context
        )

        XCTAssertFalse(delivered.needsSync)
        XCTAssertNotNil(delivered.lastSyncedAt)
        XCTAssertTrue(untouched.needsSync, "a sibling event's write has not landed")
    }

    /// The completion hook runs for every operation in the queue; it must do
    /// nothing at all for work that is not a calendar event.
    func test_clearNeedsSyncOnCompletion_ignoresForeignOperations() throws {
        let context = try makeContext()
        let event = makeEvent(in: context)

        try CalendarUserEventOutboundSync.clearNeedsSyncOnCompletion(
            for: makeOp(
                entityType: SyncEntityType.project.rawValue,
                operationType: "update",
                in: context
            ),
            in: context
        )

        XCTAssertTrue(event.needsSync)
    }

    /// Id casing varies with which side wrote the row; a case-sensitive match
    /// would leave the row dirty forever and re-queue it on every launch.
    func test_clearNeedsSyncOnCompletion_matchesIdsCaseInsensitively() throws {
        let context = try makeContext()
        let event = makeEvent(in: context)
        let operation = makeOp(operationType: "create", in: context)
        operation.entityId = eventId.uppercased()

        try CalendarUserEventOutboundSync.clearNeedsSyncOnCompletion(
            for: operation,
            in: context
        )

        XCTAssertFalse(event.needsSync)
    }

    // MARK: - Launch backfill

    /// The exact wreckage the old path left: a dirty row with no operation
    /// anywhere that would ever push it.
    func test_strandedEvents_findsDirtyRowsWithNothingQueued() throws {
        let context = try makeContext()
        let stranded = makeEvent(in: context)

        XCTAssertEqual(
            CalendarUserEventOutboundSync.strandedEvents([stranded], operations: []).map(\.id),
            [stranded.id]
        )
    }

    /// A live operation means the queue is already on it — queueing a second
    /// one would double-push every event on every launch.
    func test_strandedEvents_skipsRowsAlreadyCoveredByALiveOperation() throws {
        let context = try makeContext()
        let event = makeEvent(in: context)

        for status in ["pending", "inProgress", "failed", "parked"] {
            let operation = makeOp(operationType: "create", in: context)
            operation.status = status
            XCTAssertTrue(
                CalendarUserEventOutboundSync
                    .strandedEvents([event], operations: [operation]).isEmpty,
                "an operation in status \(status) is the queue already doing its job"
            )
        }
    }

    /// A completed operation that left the row dirty is not coverage — it is
    /// the symptom. Queue the write again.
    func test_strandedEvents_treatsACompletedOperationAsNoCoverage() throws {
        let context = try makeContext()
        let event = makeEvent(in: context)
        let operation = makeOp(operationType: "create", in: context)
        operation.status = "completed"

        XCTAssertEqual(
            CalendarUserEventOutboundSync
                .strandedEvents([event], operations: [operation]).map(\.id),
            [event.id]
        )
    }

    /// A clean row is not work.
    func test_strandedEvents_ignoresRowsThatAreAlreadySynced() throws {
        let context = try makeContext()
        let event = makeEvent(in: context)
        event.needsSync = false

        XCTAssertTrue(
            CalendarUserEventOutboundSync.strandedEvents([event], operations: []).isEmpty
        )
    }

    /// A stranded tombstone needs its delete pushed, not its content.
    func test_recoveryOperationType_sendsATombstoneAsADelete() throws {
        let context = try makeContext()
        let live = makeEvent(in: context)
        let tombstoned = makeEvent(id: "6b0e2f37-9a15-4c88-b0d2-71c4e9a5d602", in: context)
        tombstoned.deletedAt = Date()

        XCTAssertEqual(CalendarUserEventOutboundSync.recoveryOperationType(for: live), "create")
        XCTAssertEqual(CalendarUserEventOutboundSync.recoveryOperationType(for: tombstoned), "delete")
    }

    // MARK: - The notification that waits for the server

    /// The notification survives the operation store as data, so an app kill
    /// between submit and delivery loses neither the request nor the telling.
    func test_notification_roundTripsThroughTheOperationPayload() throws {
        let context = try makeContext()
        let event = makeEvent(in: context)
        let notification = CalendarUserEventOutboundSync.TimeOffNotification(
            kind: .requested,
            companyId: companyId,
            requesterId: userId,
            requesterName: "Jackson Sweet",
            targetUserId: userId,
            targetName: "Jackson Sweet",
            eventTitle: "Time Off Request",
            startDate: Date(timeIntervalSince1970: 1_770_000_000),
            endDate: Date(timeIntervalSince1970: 1_770_086_400)
        )

        var payload = CalendarUserEventOutboundSync.columns(of: event)
        payload[CalendarUserEventOutboundSync.notificationKey] = try encoded(notification)

        // Survives the JSON round trip the SyncOperation store performs.
        let data = try JSONSerialization.data(withJSONObject: payload)
        let restored = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(
            CalendarUserEventOutboundSync.decodeNotification(from: restored),
            notification
        )
    }

    /// Most calendar work carries no notification, and a payload without one
    /// must not be read as a malformed anything.
    func test_notification_absentFromAnOrdinaryPayload() throws {
        let context = try makeContext()
        let payload = CalendarUserEventOutboundSync.columns(of: makeEvent(in: context))
        XCTAssertNil(CalendarUserEventOutboundSync.decodeNotification(from: payload))
    }

    /// The date range the crew reads in the rail and the push.
    func test_dateRange_readsAsOneDayOrASpan() {
        let start = Date(timeIntervalSince1970: 1_770_000_000)
        let sameDay = CalendarUserEventOutboundSync.dateRange(
            startDate: start,
            endDate: start.addingTimeInterval(3600)
        )
        XCTAssertFalse(sameDay.contains("–"), "one day is one date, not a range")

        let span = CalendarUserEventOutboundSync.dateRange(
            startDate: start,
            endDate: start.addingTimeInterval(3 * 86_400)
        )
        XCTAssertTrue(span.contains("–"))
    }

    // MARK: - Helpers

    private func encoded(
        _ notification: CalendarUserEventOutboundSync.TimeOffNotification
    ) throws -> [String: Any] {
        let data = try JSONEncoder().encode(notification)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @discardableResult
    private func makeEvent(
        id: String? = nil,
        in context: ModelContext
    ) -> CalendarUserEvent {
        let event = CalendarUserEvent(
            id: id ?? eventId,
            userId: userId,
            companyId: companyId,
            type: .timeOff,
            title: "Time Off Request",
            startDate: Date(timeIntervalSince1970: 1_770_000_000),
            endDate: Date(timeIntervalSince1970: 1_770_086_400),
            allDay: true
        )
        event.status = CalendarUserEventStatus.pending.rawValue
        event.needsSync = true
        context.insert(event)
        return event
    }

    @discardableResult
    private func makeOp(
        entityType: String = SyncEntityType.calendarUserEvent.rawValue,
        operationType: String,
        in context: ModelContext
    ) -> SyncOperation {
        let op = SyncOperation(
            entityType: entityType,
            entityId: eventId,
            operationType: operationType,
            payload: Data("{}".utf8),
            changedFields: ["id"]
        )
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
        let schema = Schema([CalendarUserEvent.self, SyncOperation.self, PhotoAnnotation.self])
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
