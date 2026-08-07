//
//  ConvertSheetInitialLoadTests.swift
//  OPSTests
//
//  Regression coverage for linked-client hydration order. A lead may carry a
//  client id but no address; the convert sheet must resolve that client before
//  it asks the server which project already belongs at the address.
//

import XCTest
@testable import OPS

final class ConvertSheetInitialLoadTests: XCTestCase {

    private enum StubError: Error {
        case unavailable
    }

    @MainActor
    func testLinkedClientResolutionFallsBackFromLocalStoreToRepository() async {
        var events: [String] = []

        let resolved = await ConvertToProjectSheet.resolveLinkedClientValue(
            clientId: " client-rose ",
            local: { id in
                events.append("local:\(id)")
                return nil as String?
            },
            remote: { id in
                events.append("remote:\(id)")
                return "2691 Galleon Way"
            }
        )

        XCTAssertEqual(resolved, "2691 Galleon Way")
        XCTAssertEqual(
            events,
            ["local:client-rose", "remote:client-rose"]
        )
    }

    @MainActor
    func testLocalLinkedClientPreventsAnUnnecessaryRepositoryRead() async {
        var remoteReadCount = 0

        let resolved = await ConvertToProjectSheet.resolveLinkedClientValue(
            clientId: "client-local",
            local: { _ in "LOCAL CLIENT" },
            remote: { _ in
                remoteReadCount += 1
                return "REMOTE CLIENT"
            }
        )

        XCTAssertEqual(resolved, "LOCAL CLIENT")
        XCTAssertEqual(remoteReadCount, 0)
    }

    @MainActor
    func testRepositoryFailureLeavesTheSheetAvailableWithoutInventingAClient() async {
        let resolved: String? = await ConvertToProjectSheet.resolveLinkedClientValue(
            clientId: "client-offline",
            local: { _ in nil },
            remote: { _ in throw StubError.unavailable }
        )

        XCTAssertNil(resolved)
    }

    @MainActor
    func testInitialLoadAppliesClientPrefillBeforeAuthoritativePreflight() async {
        var events: [String] = []
        var resolvedAddress: String?
        var visibleAddress = ""

        let recovered = await ConvertToProjectSheet.runInitialLoad(
            resolveLinkedClient: {
                events.append("resolve-client")
                resolvedAddress = "2691 Galleon Way"
            },
            applyAddressPrefill: {
                events.append("prefill")
                visibleAddress = resolvedAddress ?? ""
            },
            loadPreflight: {
                events.append("preflight:\(visibleAddress)")
                return false
            }
        )

        XCTAssertFalse(recovered)
        XCTAssertEqual(
            events,
            [
                "resolve-client",
                "prefill",
                "preflight:2691 Galleon Way",
            ]
        )
    }

    func testClientAddressAutomaticallyRechecksAddressRequiredExactlyOnce() {
        var gate = ConvertToProjectSheet.InitialClientAddressRecheckGate()

        XCTAssertTrue(
            gate.consume(
                creationBlocker: .addressRequired,
                address: "2691 Galleon Way",
                isFromClient: true
            )
        )
        XCTAssertFalse(
            gate.consume(
                creationBlocker: .addressRequired,
                address: "2691 Galleon Way",
                isFromClient: true
            ),
            "the automatic write-back/recheck must never recurse"
        )
    }

    func testAutomaticRecheckDoesNotConsumeTheGateForIneligibleAddresses() {
        var gate = ConvertToProjectSheet.InitialClientAddressRecheckGate()

        XCTAssertFalse(
            gate.consume(
                creationBlocker: .addressRequired,
                address: "   ",
                isFromClient: true
            )
        )
        XCTAssertFalse(
            gate.consume(
                creationBlocker: .projectReviewRequired,
                address: "2691 Galleon Way",
                isFromClient: true
            )
        )
        XCTAssertFalse(
            gate.consume(
                creationBlocker: .addressRequired,
                address: "2691 Galleon Way",
                isFromClient: false
            )
        )
        XCTAssertFalse(gate.hasAttempted)
    }
}
