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
}
