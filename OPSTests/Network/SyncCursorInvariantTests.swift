//
//  SyncCursorInvariantTests.swift
//  OPSTests
//
//  Regression coverage for the poisoned sync-cursor bug: a per-entity sync
//  failure must NOT advance that entity's last-pull cursor (advancing it strands
//  the entity's existing rows — future deltas only re-pull rows updated after the
//  cursor — which is how a single transient deck-sync failure left crew devices
//  unable to see ANY deck designs). The cursor-advance decision is centralized in
//  SyncEngine.cursorsToAdvance so the invariant is unit-testable here.
//

import XCTest
@testable import OPS

final class SyncCursorInvariantTests: XCTestCase {

    func test_cursorsToAdvance_advancesSucceededEntities() {
        let result = SyncEngine.cursorsToAdvance(
            [.project, .deckDesign, .client],
            excluding: []
        )
        XCTAssertEqual(result, [.project, .deckDesign, .client])
    }

    func test_cursorsToAdvance_excludesAFailedEntity() {
        let result = SyncEngine.cursorsToAdvance(
            [.project, .deckDesign, .client],
            excluding: [.deckDesign]
        )
        XCTAssertEqual(result, [.project, .client])
        XCTAssertFalse(result.contains(.deckDesign))
    }

    func test_cursorsToAdvance_excludesEveryFailedEntity_andPreservesOrder() {
        let result = SyncEngine.cursorsToAdvance(
            [.project, .deckDesign, .client, .invoice],
            excluding: [.project, .invoice]
        )
        XCTAssertEqual(result, [.deckDesign, .client])
    }

    // MARK: - One-time cursor recovery (poisoned 3.0.3 schedule cursors)

    /// Builds an isolated UserDefaults suite so the recovery gating can be
    /// exercised without touching the device's real `.standard` domain.
    private func makeDefaults(_ name: String) -> UserDefaults {
        let suite = "SyncCursorRecoveryTests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func test_runCursorRecovery_clearsListedCursors_onFirstRun() {
        let defaults = makeDefaults(#function)
        // Simulate poisoned cursors carried over from 3.0.3.
        defaults.set(Date(), forKey: "sync.lastPull.\(SyncEntityType.project.rawValue)")
        defaults.set(Date(), forKey: "sync.lastPull.\(SyncEntityType.projectTask.rawValue)")
        // An unrelated cursor must survive.
        defaults.set(Date(), forKey: "sync.lastPull.\(SyncEntityType.invoice.rawValue)")

        let didRun = SyncEngine.runCursorRecovery(
            key: "sync.scheduleCursorRecoveryV1",
            entities: [.project, .projectTask],
            defaults: defaults
        )

        XCTAssertTrue(didRun)
        XCTAssertNil(defaults.object(forKey: "sync.lastPull.\(SyncEntityType.project.rawValue)"))
        XCTAssertNil(defaults.object(forKey: "sync.lastPull.\(SyncEntityType.projectTask.rawValue)"))
        XCTAssertNotNil(defaults.object(forKey: "sync.lastPull.\(SyncEntityType.invoice.rawValue)"))
        XCTAssertTrue(defaults.bool(forKey: "sync.scheduleCursorRecoveryV1"))
    }

    func test_runCursorRecovery_runsExactlyOncePerDevice() {
        let defaults = makeDefaults(#function)

        let firstRun = SyncEngine.runCursorRecovery(
            key: "sync.scheduleCursorRecoveryV1",
            entities: [.project, .projectTask],
            defaults: defaults
        )
        XCTAssertTrue(firstRun)

        // A freshly-synced cursor written AFTER the one-time recovery must not
        // be wiped by a second configure() pass.
        let freshCursor = Date()
        defaults.set(freshCursor, forKey: "sync.lastPull.\(SyncEntityType.project.rawValue)")

        let secondRun = SyncEngine.runCursorRecovery(
            key: "sync.scheduleCursorRecoveryV1",
            entities: [.project, .projectTask],
            defaults: defaults
        )

        XCTAssertFalse(secondRun)
        XCTAssertNotNil(defaults.object(forKey: "sync.lastPull.\(SyncEntityType.project.rawValue)"))
    }
}
