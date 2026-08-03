//
//  ClientServerVisibilityTests.swift
//  OPSTests
//
//  Bug 13c66762 — clients are created local-first, so a lead that references a
//  brand-new one can reach `create_opportunity_guarded` before its client row
//  does, and the RPC rolls the whole transaction back with
//  `client_not_found_in_company`. This is the bounded wait that closes the gap.
//

import XCTest
@testable import OPS

final class ClientServerVisibilityTests: XCTestCase {

    func test_visibleOnFirstProbe_neverWaits() async {
        var probes = 0
        var backoffs = 0

        let outcome = await ClientServerVisibility.wait(
            clientId: "client-1",
            companyId: "company-1",
            probe: { _, _ in probes += 1 },
            backoff: { _ in backoffs += 1 },
            isOffline: { _ in false }
        )

        XCTAssertEqual(outcome, .visible)
        XCTAssertEqual(probes, 1, "a client the server already sees costs exactly one probe")
        XCTAssertEqual(backoffs, 0, "no waiting when the answer is available immediately")
    }

    func test_pollsUntilTheClientLands() async {
        var probes = 0
        var backoffs = 0

        let outcome = await ClientServerVisibility.wait(
            clientId: "client-1",
            companyId: "company-1",
            probe: { _, _ in
                probes += 1
                if probes < 3 { throw TestProbeError.notFound }
            },
            backoff: { _ in backoffs += 1 },
            isOffline: { _ in false }
        )

        XCTAssertEqual(outcome, .visible)
        XCTAssertEqual(probes, 3, "keeps probing while the client is still on its way up")
        XCTAssertEqual(backoffs, 2, "one wait between each pair of probes, none after the last")
    }

    func test_budgetExhaustedReportsNotVisible() async {
        var probes = 0
        var backoffs = 0

        let outcome = await ClientServerVisibility.wait(
            clientId: "client-1",
            companyId: "company-1",
            attempts: 4,
            probe: { _, _ in
                probes += 1
                throw TestProbeError.notFound
            },
            backoff: { _ in backoffs += 1 },
            isOffline: { _ in false }
        )

        XCTAssertEqual(outcome, .notVisible)
        XCTAssertEqual(probes, 4, "spends exactly the budget it was given")
        XCTAssertEqual(backoffs, 3, "never sleeps after the final probe")
    }

    func test_offlineStopsImmediatelyInsteadOfBurningTheBudget() async {
        var probes = 0
        var backoffs = 0

        let outcome = await ClientServerVisibility.wait(
            clientId: "client-1",
            companyId: "company-1",
            probe: { _, _ in
                probes += 1
                throw URLError(.notConnectedToInternet)
            },
            backoff: { _ in backoffs += 1 }
        )

        XCTAssertEqual(outcome, .offline)
        XCTAssertEqual(probes, 1, "with no signal the answer cannot change — stop asking")
        XCTAssertEqual(backoffs, 0)
    }

    func test_backoffGrowsAndIsCapped() {
        XCTAssertEqual(ClientServerVisibility.defaultBackoff(afterAttempt: 1), 0.25, accuracy: 0.0001)
        XCTAssertEqual(ClientServerVisibility.defaultBackoff(afterAttempt: 4), 1.0, accuracy: 0.0001)
        XCTAssertEqual(ClientServerVisibility.defaultBackoff(afterAttempt: 99), 1.5, accuracy: 0.0001)
    }

    private enum TestProbeError: Error {
        /// Deliberately worded so the offline classifier can NOT mistake it for
        /// a connectivity failure.
        case notFound
    }
}
