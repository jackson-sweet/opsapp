// OPSTests/DeckBuilder/VinylOrderRecordTests.swift
//
// Coverage for the vinyl ORDER RECORD: what the operator actually ordered (or
// pulled from the shop) is what gets frozen, what reaches the project marker,
// and what the activity feed says.
//
// The behaviour under test is the whole point of the change — the bulk path used
// to freeze the calculator's numbers and silently discard everything the
// operator had written on the way through the wizard.

import CoreGraphics
import Supabase
import XCTest
@testable import OPS

@MainActor
final class VinylOrderRecordTests: XCTestCase {

    // MARK: - Fixtures

    /// A materials list with real purchased cuts (12'×20' rect, one house edge).
    /// Mirrors `DeckMaterialsOrderServiceTests.rectMaterials` so both suites
    /// exercise the same geometry.
    private func rectMaterials() -> DeckMaterialsList {
        let p = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 144, y: 0),
            CGPoint(x: 144, y: 240),
            CGPoint(x: 0, y: 240)
        ]
        let input = VinylOrderSurfaceInput(
            id: "s1", label: "Main", levelName: nil, positions: p, scaleFactor: 1.0,
            edges: [
                VinylOrderSurfaceEdge(
                    id: "e4", start: p[3], end: p[0], edgeType: .houseEdge, label: nil,
                    startVertexId: "v4", endVertexId: "v1", isParapet: false, dimensionInches: 240
                )
            ]
        )
        return DeckMaterialsEngine.compute(
            vinylInputs: [input],
            allDetectedFacesByLevel: [],
            settings: DeckMaterialsSettings(),
            vinylSettings: .default
        )
    }

    private func snapshot(
        disposition: VinylOrderDisposition = .supplier,
        cutGroups: [DeckMaterialsSnapshot.CutGroup] = [],
        dripSticks: Int = 0,
        clipSticks: Int = 0,
        ninetySticks: Int = 0,
        glueBuckets: Int = 0,
        sharedConsumables: [VinylSharedConsumable]? = nil,
        orderMode: VinylOrderMode = .cutList,
        orderedRollCount: Int? = nil,
        po: String? = nil,
        color: String = "Slate Grey"
    ) -> DeckMaterialsSnapshot {
        DeckMaterialsSnapshot(
            orderedAt: Date(timeIntervalSince1970: 1_760_000_000),
            orderedBy: "user-1",
            settings: DeckMaterialsSettings(),
            vinylSettings: .default,
            vinylColor: color,
            vinylOrderedSqFt: 260,
            vinylSurfaceAreaSqFt: 240,
            cutGroups: cutGroups,
            dripEdgeFeet: 20,
            dripSticks: dripSticks,
            clipFeet: 20,
            clipSticks: clipSticks,
            ninetyFeet: 20,
            ninetySticks: ninetySticks,
            glueAreaSqFt: 240,
            glueBuckets: glueBuckets,
            vinylSurfaceCount: 1,
            orderMode: orderMode,
            fullRollLengthFeet: 75,
            orderedRollCount: orderedRollCount,
            po: po,
            disposition: disposition,
            sharedConsumables: sharedConsumables
        )
    }

    // MARK: - Activity entry shape

    /// The exact shape Jackson specified, including the shared-consumable
    /// parenthetical that names the other jobs.
    func testActivityBodyMatchesRequestedShape() throws {
        let record = VinylOrderActivityNote.Record(
            disposition: .supplier,
            color: nil,
            po: nil,
            vinylLines: ["2 @ 9.5'", "3 @ 10.5'"],
            consumables: [
                VinylSharedConsumable(kind: .ninetyFlash, count: 3, sharedWith: ["12 Oak St"]),
                VinylSharedConsumable(kind: .glue, count: 1, sharedWith: ["12 Oak St"])
            ],
            orderedAt: Date()
        )

        let built = try XCTUnwrap(VinylOrderActivityNote.build(record))

        XCTAssertEqual(
            built.content,
            """
            Vinyl ordered:
            - 2 @ 9.5'
            - 3 @ 10.5'
            - 3 tubes 90 flash (shared with 12 Oak St)
            - 1 bucket glue (shared with 12 Oak St)
            """
        )
    }

    /// Singular vs plural units, and an unshared line carrying no parenthetical.
    func testConsumableLinePluralisesAndOnlyMarksSharedLines() {
        XCTAssertEqual(
            VinylSharedConsumable(kind: .glue, count: 1).activityLine,
            "1 bucket glue"
        )
        XCTAssertEqual(
            VinylSharedConsumable(kind: .glue, count: 2).activityLine,
            "2 buckets glue"
        )
        XCTAssertEqual(
            VinylSharedConsumable(kind: .dripEdge, count: 2, sharedWith: ["A", "B"]).activityLine,
            "2 tubes drip edge (shared with A, B)"
        )
    }

    func testShopDispositionLeadsWithPullWording() throws {
        let record = VinylOrderActivityNote.Record(
            disposition: .shop,
            vinylLines: ["2 @ 9.5'"],
            consumables: [],
            orderedAt: Date()
        )
        let built = try XCTUnwrap(VinylOrderActivityNote.build(record))
        XCTAssertTrue(built.content.hasPrefix("Vinyl pulled from shop:"), built.content)
    }

    /// A shop pull that obtained nothing still records the fact — the answer to
    /// "did anyone deal with this?" is worth a feed row.
    func testEmptyShopRecordStillProducesAnEntry() throws {
        let record = VinylOrderActivityNote.Record(
            disposition: .shop,
            vinylLines: [],
            consumables: [],
            orderedAt: Date()
        )
        let built = try XCTUnwrap(VinylOrderActivityNote.build(record))
        XCTAssertEqual(built.content, "Vinyl pulled from shop. Nothing ordered.")
    }

    func testPOAndColorRideOnTheEntry() throws {
        let record = VinylOrderActivityNote.Record(
            disposition: .supplier,
            color: "  Slate Grey  ",
            po: " PO-77 ",
            vinylLines: ["1 @ 8'"],
            consumables: [],
            orderedAt: Date()
        )
        let built = try XCTUnwrap(VinylOrderActivityNote.build(record))
        XCTAssertEqual(
            built.content,
            """
            Vinyl ordered:
            - Slate Grey
            - 1 @ 8'
            PO PO-77
            """
        )
    }

    /// The structured payload the feed card renders survives a round trip.
    func testMetadataRoundTripsThroughJSON() throws {
        let record = VinylOrderActivityNote.Record(
            disposition: .shop,
            color: "Slate",
            po: "PO-9",
            vinylLines: ["2 @ 9.5'"],
            consumables: [VinylSharedConsumable(kind: .clip, count: 4, sharedWith: ["Maple Rd"])],
            orderedAt: Date()
        )
        let built = try XCTUnwrap(VinylOrderActivityNote.build(record))
        let decoded = try XCTUnwrap(VinylOrderActivityMetadata(json: built.metadataJSON))

        XCTAssertEqual(decoded.disposition, .shop)
        XCTAssertEqual(decoded.color, "Slate")
        XCTAssertEqual(decoded.po, "PO-9")
        XCTAssertEqual(decoded.vinylLines, ["2 @ 9.5'"])
        XCTAssertEqual(decoded.consumables.count, 1)
        XCTAssertEqual(decoded.consumables.first?.value, "4 TUBES")
        XCTAssertEqual(decoded.consumables.first?.sharedWith, ["Maple Rd"])
        XCTAssertEqual(
            decoded.consumables.first?.sharedSupportLine,
            "SHARED WITH MAPLE RD"
        )
    }

    func testMetadataDecodeIsNilForANoteWithoutStructuredPayload() {
        XCTAssertNil(VinylOrderActivityMetadata(json: nil))
        XCTAssertNil(VinylOrderActivityMetadata(json: "not json"))
    }

    // MARK: - Snapshot → record derivation

    /// With nothing shared, the record is this job's own confirmed counts, and
    /// zero-count lines never claim a purchase that did not happen.
    func testOrderedConsumablesDeriveFromOwnCountsWhenNothingShared() {
        let s = snapshot(dripSticks: 3, clipSticks: 0, ninetySticks: 2, glueBuckets: 1)
        let kinds = s.orderedConsumables.map(\.kind)

        XCTAssertEqual(kinds, [.dripEdge, .ninetyFlash, .glue])
        XCTAssertTrue(s.orderedConsumables.allSatisfy { !$0.isShared })
        XCTAssertEqual(s.orderedConsumables.first?.recordValue, "3 TUBES")
    }

    /// A bulk order's purchased lines are authoritative — the shared count is
    /// reported as bought, never divided into a per-job fraction.
    func testSharedConsumablesOverrideDerivedCountsAndKeepTheSharedTotal() {
        let s = snapshot(
            dripSticks: 8,
            sharedConsumables: [
                VinylSharedConsumable(kind: .ninetyFlash, count: 3, sharedWith: ["A", "B", "C"])
            ]
        )
        XCTAssertEqual(s.orderedConsumables.count, 1)
        XCTAssertEqual(s.orderedConsumables.first?.kind, .ninetyFlash)
        XCTAssertEqual(s.orderedConsumables.first?.count, 3)
        XCTAssertEqual(s.orderedConsumables.first?.sharedWith, ["A", "B", "C"])
    }

    func testOrderedVinylLinesReadCutGroupsInCutListMode() {
        let s = snapshot(cutGroups: [
            .init(surfaceLabel: "Main", count: 2, lengthInches: 114, rollWidthInches: 72),
            .init(surfaceLabel: "Main", count: 0, lengthInches: 60, rollWidthInches: 72)
        ])
        // The zero-count group drops: an order never bought it.
        XCTAssertEqual(s.orderedVinylLines.count, 1)
        XCTAssertTrue(s.orderedVinylLines[0].hasPrefix("2 @ "), s.orderedVinylLines[0])
    }

    func testOrderedVinylLinesReadWholeRollsInRollMode() {
        let s = snapshot(orderMode: .fullRolls, orderedRollCount: 3)
        XCTAssertEqual(s.orderedVinylLines.count, 1)
        XCTAssertTrue(s.orderedVinylLines[0].hasPrefix("3 rolls @ 75'"), s.orderedVinylLines[0])
    }

    // MARK: - Codable: additive fields, legacy fallback

    /// A snapshot written before the disposition existed decodes as a supplier
    /// order — which is what every historic record in fact was.
    func testLegacySnapshotWithoutDispositionDecodesAsSupplier() throws {
        let legacy = """
        {"orderedAt": 760000000, "settings": {}, "vinylColor": "Slate",
         "vinylOrderedSqFt": 100, "vinylSurfaceAreaSqFt": 90, "cutGroups": [],
         "dripEdgeFeet": 0, "dripSticks": 0, "clipFeet": 0, "clipSticks": 0,
         "ninetyFeet": 0, "ninetySticks": 0, "glueAreaSqFt": 0, "glueBuckets": 0,
         "vinylSurfaceCount": 1}
        """
        let decoded = try JSONDecoder().decode(
            DeckMaterialsSnapshot.self,
            from: XCTUnwrap(legacy.data(using: .utf8))
        )
        XCTAssertEqual(decoded.disposition, .supplier)
        XCTAssertNil(decoded.sharedConsumables)
    }

    func testSnapshotRoundTripsDispositionAndSharedConsumables() throws {
        let original = snapshot(
            disposition: .shop,
            sharedConsumables: [VinylSharedConsumable(kind: .glue, count: 2, sharedWith: ["A"])]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DeckMaterialsSnapshot.self, from: data)

        XCTAssertEqual(decoded.disposition, .shop)
        XCTAssertEqual(decoded.sharedConsumables?.first?.count, 2)
        XCTAssertEqual(decoded.sharedConsumables?.first?.sharedWith, ["A"])
    }

    // MARK: - Zeroing

    func testZeroedClearsEveryQuantityAndReportsItself() {
        let confirmation = DeckMaterialsOrderConfirmation(
            orderMode: .fullRolls,
            fullRollLengthFeet: 75,
            vinylOrderedSqFt: 260,
            rollCount: 3,
            dripSticks: 4,
            clipSticks: 5,
            ninetySticks: 6,
            glueBuckets: 7
        )
        XCTAssertFalse(confirmation.isZeroed)

        let zeroed = confirmation.zeroed()
        XCTAssertTrue(zeroed.isZeroed)
        // Mode and roll length are settings, not quantities — they survive.
        XCTAssertEqual(zeroed.orderMode, .fullRolls)
        XCTAssertEqual(zeroed.fullRollLengthFeet, 75)
    }

    // MARK: - Marker payload

    /// The compatibility decision that protects every already-installed build:
    /// a shop pull still writes `ordered`, so the job never re-surfaces on the
    /// procurement board — the new column carries the distinction.
    func testMarkerFieldsKeepStatusOrderedForShopAndRecordTheSource() {
        let fields = DeckMaterialsOrderService.markerFields(
            userId: "user-1",
            at: Date(),
            disposition: .shop,
            color: "Slate",
            po: nil
        )
        XCTAssertEqual(
            fields[ProjectVinylOrderFields.status],
            .string(ProjectVinylOrderStatus.ordered.rawValue)
        )
        XCTAssertEqual(fields[ProjectVinylOrderFields.source], .string("shop"))
        XCTAssertEqual(fields[ProjectVinylOrderFields.po], .null)
    }

    func testMarkerFieldsRecordSupplierSource() {
        let fields = DeckMaterialsOrderService.markerFields(
            userId: "user-1",
            at: Date(),
            disposition: .supplier,
            color: nil,
            po: "PO-3"
        )
        XCTAssertEqual(fields[ProjectVinylOrderFields.source], .string("supplier"))
        XCTAssertEqual(fields[ProjectVinylOrderFields.color], .null)
        XCTAssertEqual(fields[ProjectVinylOrderFields.po], .string("PO-3"))
    }

    func testDispositionFallsBackToSupplierForUnknownColumnValues() {
        XCTAssertEqual(VinylOrderDisposition.fromColumnValue(nil), .supplier)
        XCTAssertEqual(VinylOrderDisposition.fromColumnValue("nonsense"), .supplier)
        XCTAssertEqual(VinylOrderDisposition.fromColumnValue(" SHOP "), .shop)
    }

    // MARK: - Bulk item → confirmation (the record of what the operator wrote)

    private func bulkItem(
        disposition: VinylOrderDisposition = .supplier,
        sharedConsumables: [VinylSharedConsumable] = [],
        sqFtOverride: Int? = nil,
        rollsOverride: Int? = nil,
        settings: DeckMaterialsSettings = DeckMaterialsSettings()
    ) -> VinylBulkMarkItem {
        VinylBulkMarkItem(
            projectId: "p1",
            design: nil,
            materials: nil,
            settings: settings,
            vinylSettings: .default,
            color: nil,
            po: nil,
            projectTitle: "Job A",
            disposition: disposition,
            sharedConsumables: sharedConsumables,
            orderedSqFtOverride: sqFtOverride,
            orderedRollsOverride: rollsOverride
        )
    }

    /// Untouched page ⇒ the calculator's number is what gets frozen.
    func testBulkConfirmationUsesCalculatedQuantityWhenOperatorDidNotOverride() {
        let materials = rectMaterials()
        let confirmation = bulkItem().confirmation(from: materials)

        XCTAssertEqual(confirmation.vinylOrderedSqFt, materials.vinylPlan.totalOrderedSqFt)
        XCTAssertEqual(confirmation.disposition, .supplier)
    }

    /// The bug: the operator's number must be what is recorded.
    func testBulkConfirmationRecordsTheOperatorsOverriddenQuantity() {
        let materials = rectMaterials()
        let calculated = materials.vinylPlan.totalOrderedSqFt
        let confirmation = bulkItem(sqFtOverride: calculated + 55).confirmation(from: materials)

        XCTAssertEqual(confirmation.vinylOrderedSqFt, calculated + 55)
        XCTAssertTrue(
            confirmation.differs(
                fromCalculated: .calculated(from: materials, settings: DeckMaterialsSettings())
            )
        )
    }

    /// The other half of the bug: consumables the operator confirmed on the send
    /// page used to reach the supplier text and then evaporate.
    func testBulkConfirmationRecordsPurchasedConsumablesOverTheCalculation() {
        let materials = rectMaterials()
        let item = bulkItem(sharedConsumables: [
            VinylSharedConsumable(kind: .ninetyFlash, count: 3, sharedWith: ["Job B"]),
            VinylSharedConsumable(kind: .glue, count: 1, sharedWith: ["Job B"])
        ])
        let confirmation = item.confirmation(from: materials)

        XCTAssertEqual(confirmation.ninetySticks, 3)
        XCTAssertEqual(confirmation.glueBuckets, 1)
        XCTAssertEqual(confirmation.sharedConsumables.count, 2)
        XCTAssertEqual(confirmation.sharedConsumables.first?.sharedWith, ["Job B"])
    }

    /// A shop-sourced job bought nothing, however large its calculation was.
    func testBulkConfirmationZeroesEveryQuantityForAShopPull() {
        let materials = rectMaterials()
        let confirmation = bulkItem(disposition: .shop).confirmation(from: materials)

        XCTAssertTrue(confirmation.isZeroed)
        XCTAssertEqual(confirmation.disposition, .shop)
        XCTAssertTrue(confirmation.sharedConsumables.isEmpty)
    }

    func testBulkConfirmationAppliesRollOverrideInRollMode() {
        var settings = DeckMaterialsSettings()
        settings.orderMode = .fullRolls
        let materials = rectMaterials()
        let confirmation = bulkItem(rollsOverride: 9, settings: settings)
            .confirmation(from: materials)

        XCTAssertEqual(confirmation.rollCount, 9)
        XCTAssertEqual(confirmation.orderMode, .fullRolls)
    }
}
