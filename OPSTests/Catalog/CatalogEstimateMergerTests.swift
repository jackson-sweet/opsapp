//
//  CatalogEstimateMergerTests.swift
//  OPSTests
//
//  Verifies the merge rule from deck-catalog spec § 4.5.1 — adapter
//  wins for component_types with a CompanyDefaultProduct, legacy fills
//  the gap, warnings always pass through.
//

import XCTest
@testable import OPS

final class CatalogEstimateMergerTests: XCTestCase {

    // MARK: - No defaults → legacy passes through unchanged

    func test_merge_noDefaults_legacyPassesThroughIntact() {
        let legacy = [
            legacyItem(name: "Composite Boards", category: "Surface", quantity: 144),
            legacyItem(name: "Picket Railing", category: "Railing", quantity: 48),
            legacyItem(name: "Picket Railing Posts", category: "Railing", quantity: 8),
            legacyItem(name: "Stair Treads", category: "Stairs", quantity: 7),
        ]
        let merged = CatalogEstimateMerger.merge(
            adapterItems: [],
            legacyItems: legacy,
            defaultsCovered: []
        )
        XCTAssertEqual(merged.count, legacy.count)
        XCTAssertEqual(merged.map(\.name), legacy.map(\.name))
    }

    // MARK: - Default for railing → legacy Railing dropped, adapter wins

    func test_merge_railingDefault_dropsLegacyRailing_keepsOthers() {
        let legacy = [
            legacyItem(name: "Composite Boards", category: "Surface", quantity: 144),
            legacyItem(name: "Picket Railing", category: "Railing", quantity: 48),
            legacyItem(name: "Picket Railing Posts", category: "Railing", quantity: 8),
            legacyItem(name: "Stair Treads", category: "Stairs", quantity: 7),
        ]
        let adapter = [
            enriched(productName: "Custom Composite Railing", unit: "linear ft", category: "Railing", quantity: 48, unitPrice: 53.0)
        ]
        let merged = CatalogEstimateMerger.merge(
            adapterItems: adapter,
            legacyItems: legacy,
            defaultsCovered: [.railing]
        )

        let names = merged.map(\.name)
        XCTAssertTrue(names.contains("Custom Composite Railing"), "Adapter row appears")
        XCTAssertFalse(names.contains("Picket Railing"), "Legacy Railing dropped")
        XCTAssertFalse(names.contains("Picket Railing Posts"), "Legacy Railing posts dropped")
        XCTAssertTrue(names.contains("Composite Boards"), "Surface untouched (no deck_board default)")
        XCTAssertTrue(names.contains("Stair Treads"), "Stairs untouched (no stair_set default)")
    }

    // MARK: - Stair_set default → drops Stairs + Connecting Stairs

    func test_merge_stairDefault_dropsStairsAndConnectingStairs() {
        let legacy = [
            legacyItem(name: "Stair Treads", category: "Stairs", quantity: 7),
            legacyItem(name: "Stair Stringers", category: "Stairs", quantity: 4),
            legacyItem(name: "Upper → Lower — Stair Treads", category: "Connecting Stairs", quantity: 9),
            legacyItem(name: "Composite Boards", category: "Surface", quantity: 144),
        ]
        let adapter = [
            enriched(productName: "Custom Stair Set", unit: "each", category: "Stairs", quantity: 1, unitPrice: 1200.0)
        ]
        let merged = CatalogEstimateMerger.merge(
            adapterItems: adapter,
            legacyItems: legacy,
            defaultsCovered: [.stairSet]
        )

        let names = merged.map(\.name)
        XCTAssertTrue(names.contains("Custom Stair Set"))
        XCTAssertFalse(names.contains("Stair Treads"))
        XCTAssertFalse(names.contains("Stair Stringers"))
        XCTAssertFalse(names.contains("Upper → Lower — Stair Treads"))
        XCTAssertTrue(names.contains("Composite Boards"))
    }

    // MARK: - Warnings always pass through

    func test_merge_warningPassesThrough_evenWhenCategoryDropped() {
        let warning = legacyItem(
            name: "Stairs (missing elevation)",
            category: "Stairs",
            quantity: 0,
            warning: "Set deck height — stair calculations require elevation."
        )
        let merged = CatalogEstimateMerger.merge(
            adapterItems: [enriched(productName: "Stair Set", unit: "each", category: "Stairs", quantity: 1)],
            legacyItems: [warning],
            defaultsCovered: [.stairSet]
        )
        XCTAssertEqual(merged.filter { $0.warning != nil }.count, 1, "Warning row survives even when its category is dropped")
    }

    // MARK: - Adapter snapshot fields preserved on merged row

    func test_merge_adapterRowCarriesConfiguredOptionsAndResolvedFields() {
        let raw = DesignToEstimateAdapter.GeneratedLineItem(
            productId: "p_rail",
            componentType: .railing,
            quantity: 24,
            configuredOptions: ["o_color": .selectId("v_black")],
            resolvedUnitPrice: 53.0,
            resolvedOptionsLabel: "Topmount · Concrete · Black · 4 corners",
            lineTotal: 1272.0
        )
        let adapter = [
            CatalogEstimateMerger.EnrichedAdapterItem(
                raw: raw,
                productName: "Custom Composite Railing",
                productDescription: nil,
                unit: "linear ft",
                category: "Railing",
                taskTypeId: "tt_railing"
            )
        ]
        let merged = CatalogEstimateMerger.merge(
            adapterItems: adapter,
            legacyItems: [],
            defaultsCovered: [.railing]
        )

        XCTAssertEqual(merged.count, 1)
        let row = merged[0]
        XCTAssertEqual(row.resolvedUnitPrice, 53.0)
        XCTAssertEqual(row.resolvedOptionsLabel, "Topmount · Concrete · Black · 4 corners")
        XCTAssertNotNil(row.configuredOptions)
        if case .selectId(let id) = row.configuredOptions?["o_color"] {
            XCTAssertEqual(id, "v_black")
        } else { XCTFail("expected selectId for color in configuredOptions") }
    }

    // MARK: - Drop set computation

    func test_legacyCategoriesToDrop_railingDefault_dropsRailingOnly() {
        let drop = CatalogEstimateMerger.legacyCategoriesToDrop(forDefaults: [.railing])
        XCTAssertEqual(drop, ["Railing"])
    }

    func test_legacyCategoriesToDrop_stairDefault_dropsBothStairBuckets() {
        let drop = CatalogEstimateMerger.legacyCategoriesToDrop(forDefaults: [.stairSet])
        XCTAssertEqual(drop, ["Stairs", "Connecting Stairs"])
    }

    func test_legacyCategoriesToDrop_postSetDefault_dropsRailingBucket() {
        let drop = CatalogEstimateMerger.legacyCategoriesToDrop(forDefaults: [.postSet])
        XCTAssertEqual(drop, ["Railing"])
    }

    func test_legacyCategoriesToDrop_gateDefault_dropsNothing() {
        let drop = CatalogEstimateMerger.legacyCategoriesToDrop(forDefaults: [.gate])
        XCTAssertTrue(drop.isEmpty, "Gates have no dedicated legacy category to drop")
    }

    // MARK: - Sort order is contiguous across the merged result

    func test_merge_sortOrderIsContiguous() {
        let legacy = [
            legacyItem(name: "A", category: "Other", quantity: 1),
            legacyItem(name: "B", category: "Other", quantity: 1),
        ]
        let adapter = [
            enriched(productName: "X", unit: "each", category: "Railing", quantity: 1),
            enriched(productName: "Y", unit: "each", category: "Railing", quantity: 1),
        ]
        let merged = CatalogEstimateMerger.merge(
            adapterItems: adapter,
            legacyItems: legacy,
            defaultsCovered: [.railing]
        )
        XCTAssertEqual(merged.map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertEqual(merged.map(\.name), ["X", "Y", "A", "B"], "Adapter rows precede legacy")
    }

    // MARK: - Helpers

    private func legacyItem(
        name: String,
        category: String,
        quantity: Double,
        warning: String? = nil
    ) -> EstimateGeneratorService.GeneratedLineItem {
        var item = EstimateGeneratorService.GeneratedLineItem(
            name: name,
            description: nil,
            type: .material,
            quantity: quantity,
            unit: category == "Surface" ? "sq ft" : (category == "Railing" ? "linear ft" : "each"),
            unitPrice: 0,
            productId: nil,
            taskTypeId: nil,
            category: category,
            sortOrder: 0,
            isOptional: false
        )
        item.warning = warning
        return item
    }

    private func enriched(
        productName: String,
        unit: String,
        category: String,
        componentType: DesignComponentType = .railing,
        quantity: Double = 1,
        unitPrice: Double = 0
    ) -> CatalogEstimateMerger.EnrichedAdapterItem {
        let raw = DesignToEstimateAdapter.GeneratedLineItem(
            productId: "p_\(productName.lowercased().replacingOccurrences(of: " ", with: "_"))",
            componentType: componentType,
            quantity: quantity,
            configuredOptions: [:],
            resolvedUnitPrice: unitPrice,
            resolvedOptionsLabel: "",
            lineTotal: unitPrice * quantity
        )
        return CatalogEstimateMerger.EnrichedAdapterItem(
            raw: raw,
            productName: productName,
            productDescription: nil,
            unit: unit,
            category: category,
            taskTypeId: nil
        )
    }
}
