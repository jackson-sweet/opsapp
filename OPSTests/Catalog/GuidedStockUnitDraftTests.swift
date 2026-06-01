//
//  GuidedStockUnitDraftTests.swift
//  OPSTests
//
//  TDD coverage for GuidedStockDraftBuilder.stockUnitDrafts(for:entry:):
//  - piece measurement: single each row, quantityValue == count.
//  - piece zero/nil: produces no row.
//  - length measurement: separate roll rows, offcut rows, mirrored quantity.
//  - area measurement: width propagated to all rows, area mirrored quantity.
//  - ids are deterministic across rebuilds.
//  - validateStockQuantities accepts builder output.
//

import XCTest
@testable import OPS

final class GuidedStockUnitDraftTests: XCTestCase {

    // MARK: - Helpers

    private func makeGroup(
        measurement: GuidedMeasurement,
        isSingleItem: Bool = true,
        lengthUnit: String = "ft",
        widthUnit: String = "ft"
    ) -> GuidedStructuredGroup {
        GuidedStructuredGroup(
            id: "grp-1",
            familyName: "Vinyl",
            memberItemIds: ["item-a"],
            isSingleItem: isSingleItem,
            attributes: [],
            measurement: measurement,
            lengthUnit: lengthUnit,
            widthUnit: widthUnit,
            stockEntries: [],
            product: GuidedProductAnswers(),
            isConfirmed: true
        )
    }

    // MARK: - Piece

    func test_piece_singleRow_quantityIsCount() {
        let group = makeGroup(measurement: .piece)
        let entry = GuidedStockEntry(variantKey: "v1", pieceCount: 5)

        let drafts = GuidedStockDraftBuilder.stockUnitDrafts(for: group, entry: entry)

        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].unitKind,      .each)
        XCTAssertEqual(drafts[0].status,        .full)
        XCTAssertEqual(drafts[0].quantityValue, 5)

        let mirrored = CatalogSetupWorkflow.mirroredQuantity(for: drafts)
        XCTAssertEqual(mirrored, 5, accuracy: 0.001)
    }

    func test_piece_zeroCount_producesNoRow() {
        let group = makeGroup(measurement: .piece)
        let entry = GuidedStockEntry(variantKey: "v1", pieceCount: 0)

        let drafts = GuidedStockDraftBuilder.stockUnitDrafts(for: group, entry: entry)

        XCTAssertTrue(drafts.isEmpty, "Zero piece count must produce no stock-unit row")
    }

    func test_piece_nilCount_producesNoRow() {
        let group = makeGroup(measurement: .piece)
        let entry = GuidedStockEntry(variantKey: "v1", pieceCount: nil)

        let drafts = GuidedStockDraftBuilder.stockUnitDrafts(for: group, entry: entry)

        XCTAssertTrue(drafts.isEmpty, "Nil piece count must produce no stock-unit row")
    }

    // MARK: - Length — full rolls as separate rows

    func test_length_rollsAreSeparateRows_andSumLength() throws {
        let group = makeGroup(measurement: .length)
        let entry = GuidedStockEntry(
            variantKey: "v2",
            fullUnitLength: 75,
            fullUnitCount: 3
        )

        let drafts = GuidedStockDraftBuilder.stockUnitDrafts(for: group, entry: entry)

        XCTAssertEqual(drafts.count, 3, "Three full units → three separate roll rows")
        for draft in drafts {
            XCTAssertEqual(draft.unitKind,      .roll)
            XCTAssertEqual(draft.status,        .full)
            XCTAssertEqual(draft.quantityValue, 1, accuracy: 0.001)
            let remaining = try XCTUnwrap(draft.remainingLengthValue)
            XCTAssertEqual(remaining, 75, accuracy: 0.001)
        }

        // Aggregate: 3 rows × 75 ft remaining = 225 ft.
        let mirrored = CatalogSetupWorkflow.mirroredQuantity(for: drafts)
        XCTAssertEqual(mirrored, 225, accuracy: 0.001)
    }

    func test_length_offcutsAddPartialRows() {
        let group = makeGroup(measurement: .length)
        let entry = GuidedStockEntry(
            variantKey: "v3",
            fullUnitLength: 75,
            fullUnitCount: 2,
            offcutLengths: [22, 10]
        )

        let drafts = GuidedStockDraftBuilder.stockUnitDrafts(for: group, entry: entry)

        XCTAssertEqual(drafts.count, 4, "2 rolls + 2 offcuts = 4 rows")

        let rolls   = drafts.filter { $0.unitKind == .roll }
        let offcuts = drafts.filter { $0.unitKind == .offcut }
        XCTAssertEqual(rolls.count,   2)
        XCTAssertEqual(offcuts.count, 2)

        for offcut in offcuts {
            XCTAssertEqual(offcut.status, .partial)
            XCTAssertEqual(offcut.quantityValue, 1, accuracy: 0.001)
        }

        // Mirrored = (75×2) + 22 + 10 = 182 ft.
        let mirrored = CatalogSetupWorkflow.mirroredQuantity(for: drafts)
        XCTAssertEqual(mirrored, 182, accuracy: 0.001)
    }

    func test_length_zeroFullUnitLength_producesNoRolls() {
        let group = makeGroup(measurement: .length)
        let entry = GuidedStockEntry(variantKey: "v4", fullUnitLength: 0, fullUnitCount: 5)

        let drafts = GuidedStockDraftBuilder.stockUnitDrafts(for: group, entry: entry)

        XCTAssertTrue(drafts.isEmpty, "Zero length must produce no roll rows")
    }

    func test_length_zeroOffcutEntry_isSkipped() {
        let group = makeGroup(measurement: .length)
        let entry = GuidedStockEntry(
            variantKey: "v5",
            fullUnitLength: 50,
            fullUnitCount: 1,
            offcutLengths: [0, 15, 0]
        )

        let drafts = GuidedStockDraftBuilder.stockUnitDrafts(for: group, entry: entry)

        // 1 roll + 1 real offcut (two zero offcuts are skipped).
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts.filter { $0.unitKind == .offcut }.count, 1)
    }

    // MARK: - Area — width propagated; area aggregate

    func test_area_setsWidth_andRows() throws {
        let group = makeGroup(measurement: .area)
        let entry = GuidedStockEntry(
            variantKey: "v6",
            fullUnitWidth: 6,
            fullUnitLength: 75,
            fullUnitCount: 2,
            offcutLengths: [22]
        )

        let drafts = GuidedStockDraftBuilder.stockUnitDrafts(for: group, entry: entry)

        XCTAssertEqual(drafts.count, 3, "2 rolls + 1 offcut = 3 rows")

        for draft in drafts {
            let width = try XCTUnwrap(draft.widthValue, "All area rows must carry the full-unit width")
            XCTAssertEqual(width, 6, accuracy: 0.001)
        }

        // .roll and .offcut both have isDimensionalAreaStock == true.
        // Aggregate: (75 × 6 × 2) + (22 × 6) = 900 + 132 = 1032 sq ft.
        let mirrored = CatalogSetupWorkflow.mirroredQuantity(for: drafts)
        XCTAssertEqual(mirrored, 1032, accuracy: 0.001,
                       "Area aggregate = sum of (remainingLength × width) per row")
    }

    // MARK: - Deterministic ids

    func test_ids_deterministic() {
        let group = makeGroup(measurement: .length)
        let entry = GuidedStockEntry(
            variantKey: "myVariant",
            fullUnitLength: 100,
            fullUnitCount: 2,
            offcutLengths: [30]
        )

        let first  = GuidedStockDraftBuilder.stockUnitDrafts(for: group, entry: entry).map(\.id)
        let second = GuidedStockDraftBuilder.stockUnitDrafts(for: group, entry: entry).map(\.id)

        XCTAssertEqual(first, second, "Draft ids must be identical across repeated builds")

        // Spot-check expected id format.
        XCTAssertEqual(first[0], "myVariant::roll::0")
        XCTAssertEqual(first[1], "myVariant::roll::1")
        XCTAssertEqual(first[2], "myVariant::offcut::0")
    }

    // MARK: - validateStockQuantities accepts builder output

    func test_validateStockQuantities_acceptsBuilderOutput() throws {
        let group = makeGroup(measurement: .length)
        let entry = GuidedStockEntry(
            variantKey: "v7",
            fullUnitLength: 75,
            fullUnitCount: 2,
            offcutLengths: [22]
        )

        let stockDrafts = GuidedStockDraftBuilder.stockUnitDrafts(for: group, entry: entry)

        // Wrap in an enabled variant (matching the guided-commit code path).
        let variant = CatalogSetupVariantDraft(
            id: "var-1",
            optionValueIds: [],
            stockUnits: stockDrafts,
            isEnabled: true
        )

        // validateStockQuantities must not throw: all quantities are 1 > 0.
        XCTAssertNoThrow(
            try CatalogSetupWorkflow.validateStockQuantities(variants: [variant]),
            "Builder output must satisfy stock quantity validation"
        )
    }
}
