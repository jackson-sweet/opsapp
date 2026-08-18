//
//  TimeOffRequestNotificationTests.swift
//  OPSTests
//
//  Booking time off, and requesting it, must reach the rail through the narrow
//  server RPCs (`notify_time_off_booked`, `notify_time_off_requested`) — never
//  a client-side `notifications` insert. The 2026-07-15 notification-creation
//  hardening revoked app-role INSERT, so the seven direct inserts across
//  `UserEventSheet` and `TimeOffRequestSheet` 42501'd from 2026-07-17 onward:
//  every booking confirmation, every submission receipt, and every approver's
//  "review this" row went silently dead while the push still fired. Approvers
//  got a phone buzz pointing at a rail that had nothing in it.
//
//  Both sheets now dispatch through one shared seam,
//  `TimeOffRequestNotificationDispatcher`. The server owns recipients and rail
//  copy — it reads the `calendar_user_events` row the sheet just created and
//  derives the target, the requester, and the approver set from it. The client
//  keeps exactly one job: the OneSignal push, whose copy it still builds, aimed
//  at exactly the ids the server reports as having received NEW rows.
//
//  What these tests pin:
//    1. The event id crosses each seam verbatim. The server resolves everything
//       else from that id alone — a mangled or substituted id notifies nobody.
//    2. The booked push fires only when the server actually created the row AND
//       the target isn't the actor. A `noop` verdict means the row was already
//       there; a self-booking is already visible on the actor's own schedule.
//    3. The request push targets exactly the approver ids the server returned,
//       and an empty list means no push at all — the rail and the push can no
//       longer disagree about who heard about the request.
//    4. The client never contributes a recipient list. The on-behalf target row
//       is the server's business (`targetNotified`), and it must not pull a
//       push along with it.
//    5. A transport failure stays contained: the calendar row is already
//       written by the time this runs, so a failed rail row must never surface
//       to the caller, and must not poison later dispatches.
//

import XCTest
@testable import OPS

final class TimeOffRequestNotificationTests: XCTestCase {

    // MARK: - Spies

    /// Records every event id handed to the RPC seam and plays back a scripted
    /// server result. Both dispatch lanes are sequential, so plain storage is
    /// race-free.
    private final class TimeOffRequestRailSpy: TimeOffRequestNotifying {
        private(set) var bookedEventIds: [String] = []
        private(set) var requestedEventIds: [String] = []

        /// The server's verdict for the booked rail row: `created` or `noop`.
        var bookedVerdict = "created"
        /// Who the server reports as having received NEW rows for the request.
        var requestedFanout = NotificationRepository.TimeOffRequestFanout(
            approverUserIds: [],
            targetNotified: false
        )
        var failure: Error?

        func notifyTimeOffBooked(eventId: String) async throws -> String {
            bookedEventIds.append(eventId)
            if let failure {
                throw failure
            }
            return bookedVerdict
        }

        func notifyTimeOffRequested(
            eventId: String
        ) async throws -> NotificationRepository.TimeOffRequestFanout {
            requestedEventIds.append(eventId)
            if let failure {
                throw failure
            }
            return requestedFanout
        }
    }

    /// Records every push the dispatcher sends. `data` is `[String: Any]`, so
    /// the payload is flattened to the three keys the sheets actually set.
    private final class TimeOffRequestPushSpy: TimeOffRequestPushing {
        struct Send: Equatable {
            let userIds: [String]
            let title: String
            let body: String
            let type: String?
            let eventId: String?
            let screen: String?
        }

        private(set) var sends: [Send] = []

        func sendToUser(
            userId: String,
            title: String,
            body: String,
            data: [String: Any]?,
            imageUrl: String?
        ) async throws {
            record(userIds: [userId], title: title, body: body, data: data)
        }

        func sendToUsers(
            userIds: [String],
            title: String,
            body: String,
            data: [String: Any]?,
            imageUrl: String?
        ) async throws {
            record(userIds: userIds, title: title, body: body, data: data)
        }

        private func record(userIds: [String], title: String, body: String, data: [String: Any]?) {
            sends.append(
                Send(
                    userIds: userIds,
                    title: title,
                    body: body,
                    type: data?["type"] as? String,
                    eventId: data?["eventId"] as? String,
                    screen: data?["screen"] as? String
                )
            )
        }
    }

    // MARK: - Fixture

    private let eventId = "8c31889e-4f2a-4b71-9d33-0a17c5be6d42"
    private let targetUserId = "d2bc7743-91e5-4c06-a1f7-6b8093ee2a58"

    private func bookedPush(eventId: String) -> TimeOffRequestNotificationDispatcher.PushCopy {
        TimeOffRequestNotificationDispatcher.PushCopy(
            title: "Time Off Booked",
            body: "Marcus Hale booked you off for Aug 17 – Aug 19.",
            data: [
                "type": "time_off_booked",
                "eventId": eventId,
                "screen": "schedule"
            ]
        )
    }

    private func requestPush(eventId: String) -> TimeOffRequestNotificationDispatcher.PushCopy {
        TimeOffRequestNotificationDispatcher.PushCopy(
            title: "Time Off Request",
            body: "Marcus Hale requested time off: Aug 17 – Aug 19",
            data: [
                "type": "time_off_requested",
                "eventId": eventId,
                "screen": "schedule"
            ]
        )
    }

    // MARK: - 1. Booked — id forwarded verbatim, push aimed at the event's target

    func test_bookedDispatchForwardsTheEventIdVerbatimAndPushesTheTarget() async {
        let rail = TimeOffRequestRailSpy()
        rail.bookedVerdict = "created"
        let push = TimeOffRequestPushSpy()

        let verdict = await TimeOffRequestNotificationDispatcher.dispatchBooked(
            eventId: eventId,
            targetUserId: targetUserId,
            targetIsSelf: false,
            push: bookedPush(eventId: eventId),
            railSyncer: rail,
            pushSender: push
        )

        XCTAssertEqual(verdict, "created")
        XCTAssertEqual(
            rail.bookedEventIds,
            [eventId],
            "One server call, id unchanged — the server derives the recipient and the rail copy from it alone"
        )
        XCTAssertEqual(
            push.sends,
            [
                .init(
                    userIds: [targetUserId],
                    title: "Time Off Booked",
                    body: "Marcus Hale booked you off for Aug 17 – Aug 19.",
                    type: "time_off_booked",
                    eventId: eventId,
                    screen: "schedule"
                )
            ],
            "The push goes to the person the time off belongs to, carrying the sheet's copy untouched"
        )
    }

    // MARK: - 2. Booked — no push when the row already existed, or it's the actor's own

    func test_bookedDispatchSkipsThePushWhenTheServerKeptTheExistingRow() async {
        let rail = TimeOffRequestRailSpy()
        rail.bookedVerdict = "noop"
        let push = TimeOffRequestPushSpy()

        let verdict = await TimeOffRequestNotificationDispatcher.dispatchBooked(
            eventId: eventId,
            targetUserId: targetUserId,
            targetIsSelf: false,
            push: bookedPush(eventId: eventId),
            railSyncer: rail,
            pushSender: push
        )

        XCTAssertEqual(verdict, "noop")
        XCTAssertEqual(rail.bookedEventIds, [eventId], "The server is still asked — only it knows whether the row is new")
        XCTAssertTrue(
            push.sends.isEmpty,
            "Nothing new landed on the rail, so a buzz would announce nothing — a retried save must not re-buzz the crew"
        )
    }

    func test_bookedDispatchSkipsThePushWhenTheActorBookedTheirOwnTimeOff() async {
        let rail = TimeOffRequestRailSpy()
        rail.bookedVerdict = "created"
        let push = TimeOffRequestPushSpy()

        let verdict = await TimeOffRequestNotificationDispatcher.dispatchBooked(
            eventId: eventId,
            targetUserId: targetUserId,
            targetIsSelf: true,
            push: bookedPush(eventId: eventId),
            railSyncer: rail,
            pushSender: push
        )

        XCTAssertEqual(verdict, "created")
        XCTAssertEqual(rail.bookedEventIds, [eventId], "The confirmation row is still written — the actor sees it in their rail")
        XCTAssertTrue(
            push.sends.isEmpty,
            "You do not get pushed about the booking you just made on this phone"
        )
    }

    // MARK: - 3. Booked — a failed rail row stays contained

    func test_bookedDispatchContainsATransportFailureAndKeepsWorking() async {
        let rail = TimeOffRequestRailSpy()
        rail.failure = URLError(.notConnectedToInternet)
        let push = TimeOffRequestPushSpy()
        let recovered = "1f0a5c62-77d4-4f8e-8b90-2c6e4a91d5b3"

        // No `try` — the calendar row is already persisted by the time this
        // runs, so a failed rail row must not be throwable at the caller.
        let failedVerdict = await TimeOffRequestNotificationDispatcher.dispatchBooked(
            eventId: eventId,
            targetUserId: targetUserId,
            targetIsSelf: false,
            push: bookedPush(eventId: eventId),
            railSyncer: rail,
            pushSender: push
        )

        XCTAssertNil(failedVerdict, "A failed call has no verdict to report")
        XCTAssertTrue(
            push.sends.isEmpty,
            "The rail never got the row, so the push must not fire — a buzz pointing at an empty rail is the exact bug being fixed"
        )

        rail.failure = nil
        let recoveredVerdict = await TimeOffRequestNotificationDispatcher.dispatchBooked(
            eventId: recovered,
            targetUserId: targetUserId,
            targetIsSelf: false,
            push: bookedPush(eventId: recovered),
            railSyncer: rail,
            pushSender: push
        )

        XCTAssertEqual(recoveredVerdict, "created")
        XCTAssertEqual(
            rail.bookedEventIds,
            [eventId, recovered],
            "The throw is swallowed at the seam: the next booking still dispatches"
        )
        XCTAssertEqual(push.sends.count, 1, "Only the recovered booking pushed")
        XCTAssertEqual(push.sends.first?.eventId, recovered)
    }

    // MARK: - 4. Requested — the push targets exactly the ids the server returned

    func test_requestedDispatchPushesExactlyTheApproversTheServerReturned() async {
        let rail = TimeOffRequestRailSpy()
        rail.requestedFanout = .init(
            approverUserIds: ["approver-a", "approver-c"],
            targetNotified: true
        )
        let push = TimeOffRequestPushSpy()

        let pushed = await TimeOffRequestNotificationDispatcher.dispatchRequested(
            eventId: eventId,
            push: requestPush(eventId: eventId),
            railSyncer: rail,
            pushSender: push
        )

        XCTAssertEqual(
            rail.requestedEventIds,
            [eventId],
            "One server call, id unchanged — approvers, requester receipt and on-behalf row are all derived from it"
        )
        XCTAssertEqual(
            pushed,
            ["approver-a", "approver-c"],
            "The dispatcher reports back exactly what the server said it reached"
        )
        XCTAssertEqual(
            push.sends,
            [
                .init(
                    userIds: ["approver-a", "approver-c"],
                    title: "Time Off Request",
                    body: "Marcus Hale requested time off: Aug 17 – Aug 19",
                    type: "time_off_requested",
                    eventId: eventId,
                    screen: "schedule"
                )
            ],
            "Push targets are the server's returned ids verbatim — never a client-computed approver lookup — and the on-behalf target, whose row the server wrote, is not among them"
        )
    }

    // MARK: - 5. Requested — no approvers means no push at all

    func test_requestedDispatchSkipsThePushEntirelyWhenTheServerReturnedNoApprovers() async {
        let rail = TimeOffRequestRailSpy()
        // The one-person shop: the requester is the only approver, so the
        // server excludes them and reports nobody new — but it still wrote the
        // requester's own receipt and the on-behalf target row.
        rail.requestedFanout = .init(approverUserIds: [], targetNotified: true)
        let push = TimeOffRequestPushSpy()

        let pushed = await TimeOffRequestNotificationDispatcher.dispatchRequested(
            eventId: eventId,
            push: requestPush(eventId: eventId),
            railSyncer: rail,
            pushSender: push
        )

        XCTAssertEqual(rail.requestedEventIds, [eventId], "The rail rows are still the server's to write")
        XCTAssertTrue(pushed.isEmpty)
        XCTAssertTrue(
            push.sends.isEmpty,
            "No approver rows means no approver buzz — and the target's own row never drags a push along with it"
        )
    }

    // MARK: - 6. Requested — a failed rail row stays contained

    func test_requestedDispatchContainsATransportFailureAndKeepsWorking() async {
        let rail = TimeOffRequestRailSpy()
        rail.failure = URLError(.timedOut)
        rail.requestedFanout = .init(approverUserIds: ["approver-a"], targetNotified: false)
        let push = TimeOffRequestPushSpy()
        let recovered = "1f0a5c62-77d4-4f8e-8b90-2c6e4a91d5b3"

        let failedPush = await TimeOffRequestNotificationDispatcher.dispatchRequested(
            eventId: eventId,
            push: requestPush(eventId: eventId),
            railSyncer: rail,
            pushSender: push
        )

        XCTAssertTrue(failedPush.isEmpty, "No server verdict means no push targets — the client has no fallback recipient list")
        XCTAssertTrue(push.sends.isEmpty)

        rail.failure = nil
        let recoveredPush = await TimeOffRequestNotificationDispatcher.dispatchRequested(
            eventId: recovered,
            push: requestPush(eventId: recovered),
            railSyncer: rail,
            pushSender: push
        )

        XCTAssertEqual(recoveredPush, ["approver-a"])
        XCTAssertEqual(
            rail.requestedEventIds,
            [eventId, recovered],
            "The throw is swallowed at the seam: the next request in the batch still dispatches"
        )
        XCTAssertEqual(push.sends.map(\.userIds), [["approver-a"]], "Only the recovered request pushed")
    }
}
