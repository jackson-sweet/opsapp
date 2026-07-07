//
//  PhotoAnnotationMergePolicyTests.swift
//  OPSTests
//
//  Locks the inbound-merge rule that keeps a not-yet-synced local tombstone
//  alive through server "live row" echoes. Annotations have no SyncOperation
//  rows, so the generic acceptableFields/SyncFieldGuard protection never
//  applies to them — this predicate is their only defense. Prod 2026-06-24:
//  the soft-delete push was RLS-rejected, the next delta pull reverted the
//  pending tombstone, and the delete was silently lost forever
//  (bugs 452bab04/0415504f).
//

import XCTest
@testable import OPS

final class PhotoAnnotationMergePolicyTests: XCTestCase {

    private let tombstone = Date(timeIntervalSince1970: 1_750_000_000)
    private let serverTombstone = Date(timeIntervalSince1970: 1_750_000_500)

    func testPendingLocalTombstoneSurvivesLiveEcho() {
        XCTAssertTrue(
            PhotoAnnotationMergePolicy.shouldPreserveLocalTombstone(
                localNeedsSync: true,
                localDeletedAt: tombstone,
                incomingDeletedAt: nil
            )
        )
    }

    func testServerTombstoneAlwaysMerges() {
        // Convergence, not a clobber: once the server also says deleted,
        // normal merge applies (and the sweep can stand down).
        XCTAssertFalse(
            PhotoAnnotationMergePolicy.shouldPreserveLocalTombstone(
                localNeedsSync: true,
                localDeletedAt: tombstone,
                incomingDeletedAt: serverTombstone
            )
        )
    }

    func testSyncedLocalTombstoneDoesNotBlockMerge() {
        // needsSync == false means the local tombstone already reached the
        // server (or was inbound to begin with) — a live echo now reflects a
        // legitimate remote resurrection (e.g. upsert_markup_layer re-adding
        // a layer) and must merge.
        XCTAssertFalse(
            PhotoAnnotationMergePolicy.shouldPreserveLocalTombstone(
                localNeedsSync: false,
                localDeletedAt: tombstone,
                incomingDeletedAt: nil
            )
        )
    }

    func testLiveLocalRowNeverPreserves() {
        XCTAssertFalse(
            PhotoAnnotationMergePolicy.shouldPreserveLocalTombstone(
                localNeedsSync: true,
                localDeletedAt: nil,
                incomingDeletedAt: nil
            )
        )
        XCTAssertFalse(
            PhotoAnnotationMergePolicy.shouldPreserveLocalTombstone(
                localNeedsSync: false,
                localDeletedAt: nil,
                incomingDeletedAt: serverTombstone
            )
        )
    }
}
