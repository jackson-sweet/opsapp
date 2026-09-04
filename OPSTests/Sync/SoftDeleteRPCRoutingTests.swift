//
//  SoftDeleteRPCRoutingTests.swift
//  OPSTests
//
//  Contract for the tombstone split that keeps `deleted_at` off every PATCH to
//  clients / projects / project_tasks.
//
//  Two failures hide behind this one column. Setting it through PostgREST is
//  refused outright (42501 — the RESTRICTIVE SELECT policy is attached as a
//  WITH CHECK to any UPDATE whose WHERE needs read access), and clearing it
//  matches zero rows in silence, because the tombstoned row is already invisible
//  to the same policy. The first parked two client deletes on the founder's
//  phone; the second made every restore from Settings > Trash a no-op that
//  reported success. Bugs db15baf2, 2a55c78f.
//

import XCTest
import Supabase
@testable import OPS

final class SoftDeleteRPCRoutingTests: XCTestCase {

    private let tombstone = "2026-09-04T17:15:45Z"

    // MARK: - split

    func test_split_returnsDeleteAndStripsColumn_whenDeletedAtIsAString() {
        let (intent, remaining) = TombstoneFieldSplit.split(
            ["deleted_at": .string(tombstone)]
        )

        XCTAssertEqual(intent, .delete)
        XCTAssertTrue(
            remaining.isEmpty,
            "The tombstone column must never reach a PATCH — it is refused 42501."
        )
    }

    func test_split_returnsRestoreAndStripsColumn_whenDeletedAtIsNull() {
        let (intent, remaining) = TombstoneFieldSplit.split(["deleted_at": .null])

        XCTAssertEqual(intent, .restore)
        XCTAssertTrue(remaining.isEmpty)
    }

    func test_split_returnsNoneAndPassesFieldsThrough_whenDeletedAtAbsent() {
        let fields: [String: AnyJSON] = [
            "name": .string("Northline Builders"),
            "updated_at": .string(tombstone)
        ]

        let (intent, remaining) = TombstoneFieldSplit.split(fields)

        XCTAssertEqual(intent, .none)
        XCTAssertEqual(
            remaining,
            fields,
            "A payload with no tombstone must travel exactly as it arrived, updated_at included."
        )
    }

    func test_split_preservesEverySiblingField() {
        let (intent, remaining) = TombstoneFieldSplit.split([
            "deleted_at": .string(tombstone),
            "name": .string("Northline Builders"),
            "notes": .string("archived after the season"),
            "latitude": .double(49.2827)
        ])

        XCTAssertEqual(intent, .delete)
        XCTAssertEqual(remaining, [
            "name": .string("Northline Builders"),
            "notes": .string("archived after the season"),
            "latitude": .double(49.2827)
        ])
    }

    func test_split_dropsRedundantUpdatedAtAlongsideATombstone() {
        // Every RPC in this family bumps updated_at server-side, and the
        // repositories re-stamp their own on any PATCH they still send. Keeping
        // it could only produce an updated_at-only PATCH that says nothing.
        let (intent, remaining) = TombstoneFieldSplit.split([
            "deleted_at": .string(tombstone),
            "updated_at": .string(tombstone)
        ])

        XCTAssertEqual(intent, .delete)
        XCTAssertTrue(remaining.isEmpty)
    }

    func test_split_readsTheRealRestorePayloadShapeAsRestore() {
        // DataController.restoreTrash stages `["deleted_at": NSNull()]`, which
        // reaches the outbound engines through AnyJSONBridge. This is the exact
        // round trip — if NSNull ever stopped mapping to .null, restore would be
        // misread as a delete and tombstone the row the operator asked to keep.
        let bridged = AnyJSONBridge.payload(["deleted_at": NSNull()])

        let (intent, remaining) = TombstoneFieldSplit.split(bridged)

        XCTAssertEqual(intent, .restore)
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - steps (order is load-bearing)

    func test_steps_deleteSendsSiblingFieldsBeforeTheTombstone() {
        // Once the tombstone lands the row is invisible to the read policy the
        // UPDATE's USING clause consults, so a PATCH after it matches nothing
        // and SupabaseWriteGuard would park the operation as unaddressable.
        let steps = TombstoneFieldSplit.steps(for: [
            "deleted_at": .string(tombstone),
            "name": .string("Northline Builders")
        ])

        XCTAssertEqual(steps, [
            .patch(["name": .string("Northline Builders")]),
            .softDelete
        ])
    }

    func test_steps_restoreClearsTheTombstoneBeforeSendingSiblingFields() {
        // The mirror image: the row has to be visible again before a PATCH can
        // address it at all.
        let steps = TombstoneFieldSplit.steps(for: [
            "deleted_at": .null,
            "name": .string("Northline Builders")
        ])

        XCTAssertEqual(steps, [
            .restore,
            .patch(["name": .string("Northline Builders")])
        ])
    }

    func test_steps_tombstoneOnlyPayloadSendsNoPatchAtAll() {
        XCTAssertEqual(
            TombstoneFieldSplit.steps(for: ["deleted_at": .string(tombstone)]),
            [.softDelete]
        )
        XCTAssertEqual(
            TombstoneFieldSplit.steps(for: ["deleted_at": .null]),
            [.restore]
        )
    }

    func test_steps_untouchedPayloadStillSendsExactlyOnePatch() {
        // Everything that does not carry a tombstone must behave precisely as it
        // did before the split existed — including an empty payload, which the
        // repositories still send so their own updated_at stamp lands.
        XCTAssertEqual(
            TombstoneFieldSplit.steps(for: ["status": .string("active")]),
            [.patch(["status": .string("active")])]
        )
        XCTAssertEqual(
            TombstoneFieldSplit.steps(for: [:]),
            [.patch([:])]
        )
    }
}
