//
//  TimeOffDecisionNotificationTests.swift
//  OPSTests
//
//  A time-off approve/deny must reach the requester's rail through the narrow
//  server RPC (`notify_time_off_decision`), never a direct `notifications`
//  insert — the 2026-07-15 notification-creation hardening revoked app-role
//  INSERT, so the legacy client-side insert 42501'd and the requester was
//  never told their request had been decided.
//
//  Only the dispatch step is exercised here. The full
//  `updateStatusWithNotification` writes the decision to PostgREST first (the
//  RPC reads that recorded state — type, status, and `reviewed_by` — and
//  refuses any actor who is not the row's recorded reviewer), so the method as
//  a whole is not testable without a network. `dispatchDecisionNotification`
//  is the honest seam: everything the client still decides about the rail row.
//
//  What these tests pin:
//    1. The event id crosses the seam verbatim. The server resolves the
//       recipient and renders the copy from that id alone — a mangled or
//       substituted id silently notifies nobody.
//    2. A transport failure stays contained. The decision is already persisted
//       by the time this runs, so a failed rail row must never surface to the
//       caller as an error, and must not poison later dispatches.
//
//  Constructing `CalendarUserEventRepository` is inert: `init` only stores
//  `SupabaseService.shared.client` (a client built from literal config) and
//  the company id — no request is issued until a query runs.
//

import XCTest
@testable import OPS

final class TimeOffDecisionNotificationTests: XCTestCase {

    // MARK: - Spy

    /// Records every event id handed to the RPC seam. Optionally throws, to
    /// prove the caller is not starved by a failed rail row.
    private final class TimeOffDecisionSpy: TimeOffDecisionNotifying {
        private(set) var eventIds: [String] = []
        var shouldFail = false

        func notifyTimeOffDecision(eventId: String) async throws -> String {
            eventIds.append(eventId)
            if shouldFail {
                throw URLError(.notConnectedToInternet)
            }
            return "created"
        }
    }

    private func makeRepository(spy: TimeOffDecisionSpy) -> CalendarUserEventRepository {
        let repository = CalendarUserEventRepository(companyId: "co-timeoff")
        repository.notifySyncer = spy
        return repository
    }

    // MARK: - 1. The event id crosses the seam verbatim

    func test_dispatchForwardsTheEventIdVerbatim() async {
        let spy = TimeOffDecisionSpy()
        let repository = makeRepository(spy: spy)
        let eventId = "8c31889e-4f2a-4b71-9d33-0a17c5be6d42"

        await repository.dispatchDecisionNotification(eventId: eventId)

        XCTAssertEqual(
            spy.eventIds,
            [eventId],
            "The server derives the recipient and the copy from this id alone — one call, forwarded unchanged"
        )
    }

    // MARK: - 2. A failed rail row stays contained

    func test_dispatchContainsATransportFailureAndKeepsWorking() async {
        let spy = TimeOffDecisionSpy()
        spy.shouldFail = true
        let repository = makeRepository(spy: spy)
        let failed = "1f0a5c62-77d4-4f8e-8b90-2c6e4a91d5b3"
        let recovered = "d2bc7743-91e5-4c06-a1f7-6b8093ee2a58"

        // No `try` — a rail failure must not be throwable at the caller, whose
        // approve/deny has already been persisted by the time this runs.
        await repository.dispatchDecisionNotification(eventId: failed)

        spy.shouldFail = false
        await repository.dispatchDecisionNotification(eventId: recovered)

        XCTAssertEqual(
            spy.eventIds,
            [failed, recovered],
            "The throw is swallowed at the seam: execution continues and the next decision still dispatches"
        )
    }
}
