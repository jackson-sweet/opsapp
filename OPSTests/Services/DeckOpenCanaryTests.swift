//
//  DeckOpenCanaryTests.swift
//  OPSTests
//
//  The persisted deck-open marker behind bug 2fa645a8.
//
//  A watchdog kill leaves nothing behind in-app — breadcrumbs are in-memory and
//  the process dies mid-transaction — so the four founder-phone DECK taps could
//  die again with no evidence. The canary is the fix for that: armed at the tap,
//  advanced as the screen makes progress, disarmed when it settles, and read
//  once at the next launch.
//
//  Everything that decides whether a marker becomes a bug_reports row is pinned
//  here: the decode, the 24-hour staleness cut-off (a marker that outlived a
//  reboot or a flat battery is not evidence), the read-and-clear (one report per
//  kill, never a loop), and the advanced phase surviving the round trip — that
//  phase is the whole diagnostic payload, naming how far the open got.
//
//  The store is hardwired to `UserDefaults.standard`, so the store-backed cases
//  clean up after themselves rather than pretending to inject one.
//

import XCTest
@testable import OPS

final class DeckOpenCanaryTests: XCTestCase {

    private let leadId = "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9"

    override func setUp() {
        super.setUp()
        DeckOpenCanary.disarm()
    }

    override func tearDown() {
        DeckOpenCanary.disarm()
        super.tearDown()
    }

    // MARK: - Pure state machine

    func testArmedDecodesItsOwnEncoding() throws {
        let armedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let marker = DeckOpenCanary.Armed(
            leadId: leadId,
            phase: .designResolved,
            armedAt: armedAt
        )

        let decoded = try XCTUnwrap(
            DeckOpenCanary.armed(from: JSONEncoder().encode(marker))
        )

        XCTAssertEqual(decoded, marker)
        XCTAssertEqual(decoded.phase, .designResolved)
    }

    func testArmedFromNilOrGarbageIsNil() {
        XCTAssertNil(DeckOpenCanary.armed(from: nil))
        XCTAssertNil(DeckOpenCanary.armed(from: Data("not a canary".utf8)))
    }

    /// A marker that outlived a reboot or a flat battery is not evidence of a
    /// hang. Under the cut-off it is; over it, it is discarded.
    func testEvidenceWindowEndsAtTwentyFourHours() {
        let armedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let marker = DeckOpenCanary.Armed(leadId: leadId, phase: .tapped, armedAt: armedAt)

        XCTAssertTrue(
            DeckOpenCanary.isEvidence(marker, now: armedAt.addingTimeInterval(23 * 3600 + 3_540)),
            "a marker 23h59m old is still evidence"
        )
        XCTAssertFalse(
            DeckOpenCanary.isEvidence(marker, now: armedAt.addingTimeInterval(24 * 3600 + 60)),
            "a marker 24h01m old is stale — the device rebooted, this is not a hang"
        )
    }

    // MARK: - Store round trip

    /// The diagnostic payload is the PHASE the open reached. Arming, advancing
    /// and taking the evidence must carry it through unchanged.
    func testTakeEvidenceReturnsTheAdvancedPhaseAndClearsTheMarker() throws {
        DeckOpenCanary.arm(leadId: leadId)
        DeckOpenCanary.advance(.screenAppeared)

        let evidence = try XCTUnwrap(
            DeckOpenCanary.takeEvidenceAtLaunch(),
            "an armed marker inside the evidence window must be returned"
        )
        XCTAssertEqual(evidence.leadId, leadId)
        XCTAssertEqual(evidence.phase, .screenAppeared)

        XCTAssertNil(
            DeckOpenCanary.takeEvidenceAtLaunch(),
            "the take must clear — a single kill files one row, not one per foreground"
        )
    }

    /// The settle path. Nothing is left behind for the next launch to find.
    func testDisarmLeavesNoEvidence() {
        DeckOpenCanary.arm(leadId: leadId)
        DeckOpenCanary.advance(.designResolved)
        DeckOpenCanary.disarm()

        XCTAssertNil(DeckOpenCanary.takeEvidenceAtLaunch())
    }

    /// Advancing without an armed marker is a no-op — a stray phase call must
    /// never manufacture evidence of a tap that never happened.
    func testAdvanceWithoutArmingDoesNothing() {
        DeckOpenCanary.advance(.designResolved)

        XCTAssertNil(DeckOpenCanary.takeEvidenceAtLaunch())
    }

    /// A stale marker is discarded AND cleared, so it can never be re-read on
    /// some later launch once it has aged out.
    func testStaleMarkerIsNeitherReturnedNorLeftBehind() throws {
        let stale = DeckOpenCanary.Armed(
            leadId: leadId,
            phase: .tapped,
            armedAt: Date().addingTimeInterval(-25 * 3600)
        )
        UserDefaults.standard.set(
            try JSONEncoder().encode(stale),
            forKey: DeckOpenCanary.defaultsKey
        )

        XCTAssertNil(
            DeckOpenCanary.takeEvidenceAtLaunch(),
            "a 25-hour-old marker is not evidence of a hang"
        )
        XCTAssertNil(
            UserDefaults.standard.data(forKey: DeckOpenCanary.defaultsKey),
            "the stale marker must be cleared, not left to be re-read next launch"
        )
    }
}
