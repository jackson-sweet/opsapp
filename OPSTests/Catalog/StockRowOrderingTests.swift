//
//  StockRowOrderingTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

final class StockRowOrderingTests: XCTestCase {

    private let companyId = "company_stock_tests"

    func testLowStockSortRanksCriticalThenWarningThenNormalThenNoThreshold() {
        let noThreshold = row(
            id: "v_no_threshold",
            familyName: "No Threshold",
            quantity: 0
        )
        let normalNearLine = row(
            id: "v_normal",
            familyName: "Normal",
            quantity: 25,
            warning: 20,
            critical: 5
        )
        let warning = row(
            id: "v_warning",
            familyName: "Warning",
            quantity: 15,
            warning: 20,
            critical: 5
        )
        let critical = row(
            id: "v_critical",
            familyName: "Critical",
            quantity: 3,
            warning: 20,
            critical: 5
        )

        let sorted = StockRowOrdering.sorted(
            [noThreshold, normalNearLine, warning, critical],
            mode: .lowStock
        )

        XCTAssertEqual(sorted.map(\.id), [
            "v_critical",
            "v_warning",
            "v_normal",
            "v_no_threshold"
        ])
    }

    func testThresholdTextUsesWarningReferenceBeforeCriticalFallback() {
        let warningBacked = row(
            id: "v_warning_backed",
            familyName: "Warning Backed",
            quantity: 75,
            warning: 100,
            critical: 10
        )
        let criticalFallback = row(
            id: "v_critical_fallback",
            familyName: "Critical Fallback",
            quantity: 5,
            warning: nil,
            critical: 20
        )

        XCTAssertEqual(warningBacked.thresholdPercentText, "75%")
        XCTAssertEqual(warningBacked.thresholdDeltaText, "-25")
        XCTAssertEqual(criticalFallback.thresholdPercentText, "25%")
        XCTAssertEqual(criticalFallback.thresholdDeltaText, "-15")
    }

    func testSearchTextIncludesFamilyDescriptionSkuUnitAndOptionValues() {
        let unit = CatalogUnit(
            id: "unit_box",
            companyId: companyId,
            display: "box",
            abbreviation: "bx"
        )
        let family = CatalogItem(
            id: "family_post",
            companyId: companyId,
            name: "Post Sleeve",
            defaultUnitId: unit.id
        )
        family.itemDescription = "field replacement sleeve"
        let variant = CatalogVariant(
            id: "variant_black_topmount",
            companyId: companyId,
            catalogItemId: family.id,
            sku: "OPS-BLK-TOP",
            quantity: 12
        )
        let color = CatalogOption(id: "option_color", catalogItemId: family.id, name: "Color", sortOrder: 0)
        let mount = CatalogOption(id: "option_mount", catalogItemId: family.id, name: "Mount", sortOrder: 1)
        let black = CatalogOptionValue(id: "value_black", optionId: color.id, value: "Black")
        let topmount = CatalogOptionValue(id: "value_topmount", optionId: mount.id, value: "Topmount")
        let row = EnrichedVariantRow(
            variant: variant,
            family: family,
            category: nil,
            unit: unit,
            tagIds: [],
            optionPairs: [(option: color, value: black), (option: mount, value: topmount)]
        )

        XCTAssertTrue(row.searchText.localizedCaseInsensitiveContains("Post Sleeve"))
        XCTAssertTrue(row.searchText.localizedCaseInsensitiveContains("field replacement"))
        XCTAssertTrue(row.searchText.localizedCaseInsensitiveContains("OPS-BLK-TOP"))
        XCTAssertTrue(row.searchText.localizedCaseInsensitiveContains("box"))
        XCTAssertTrue(row.searchText.localizedCaseInsensitiveContains("Black"))
        XCTAssertTrue(row.searchText.localizedCaseInsensitiveContains("Topmount"))
    }

    func testVariantDisplayNameUsesFamilyAndOptionValuesBeforeSku() {
        let row = optionRow(
            id: "v_black_topmount",
            familyName: "Post Sleeve",
            sku: "OPS-BLK-TOP",
            options: [("Color", "Black"), ("Mount", "Topmount")]
        )

        XCTAssertEqual(row.variantLabel, "Black · Topmount")
        XCTAssertEqual(row.variantDisplayName, "Post Sleeve · Black · Topmount")
        XCTAssertTrue(row.searchText.localizedCaseInsensitiveContains("Post Sleeve · Black · Topmount"))
    }

    func testCategorySortOrdersByCategoryThenFamilyThenVariantLabel() {
        let posts = CatalogCategory(
            id: "cat_posts",
            companyId: companyId,
            name: "Posts",
            sortOrder: 0
        )
        let rail = CatalogCategory(
            id: "cat_rail",
            companyId: companyId,
            name: "Rail",
            sortOrder: 1
        )
        let uncategorized = categoryRow(
            id: "v_loose",
            familyName: "Loose Hardware",
            category: nil,
            options: []
        )
        let whitePost = categoryRow(
            id: "v_post_white",
            familyName: "Line Post",
            category: posts,
            options: [("Color", "White")]
        )
        let blackPost = categoryRow(
            id: "v_post_black",
            familyName: "Line Post",
            category: posts,
            options: [("Color", "Black")]
        )
        let railRow = categoryRow(
            id: "v_rail",
            familyName: "Top Rail",
            category: rail,
            options: [("Color", "Black")]
        )

        let sorted = StockRowOrdering.sorted(
            [uncategorized, railRow, whitePost, blackPost],
            mode: .category
        )

        XCTAssertEqual(sorted.map(\.id), [
            "v_post_black",
            "v_post_white",
            "v_rail",
            "v_loose"
        ])
    }

    func testAttributeFilterAxesMergeOptionValuesAcrossFamilies() {
        let blackTopmount = optionRow(
            id: "v_black_topmount",
            familyName: "Bracket A",
            options: [("Color", "Black"), ("Mounting Type", "Topmount")]
        )
        let whiteSidemount = optionRow(
            id: "v_white_sidemount",
            familyName: "Bracket B",
            options: [("Color", "White"), ("Mounting Type", "Sidemount")]
        )

        let axes = StockAttributeFiltering.axes(from: [whiteSidemount, blackTopmount])

        XCTAssertEqual(axes.map(\.display), ["Color", "Mounting Type"])
        XCTAssertEqual(axes[0].values.map(\.display), ["Black", "White"])
        XCTAssertEqual(axes[1].values.map(\.display), ["Sidemount", "Topmount"])
    }

    func testAttributeFilterRequiresEverySelectedAxis() {
        let blackTopmount = optionRow(
            id: "v_black_topmount",
            familyName: "Bracket A",
            options: [("Color", "Black"), ("Mounting Type", "Topmount")]
        )
        let blackSidemount = optionRow(
            id: "v_black_sidemount",
            familyName: "Bracket B",
            options: [("Color", "Black"), ("Mounting Type", "Sidemount")]
        )

        let selected = [
            StockTextKey.normalize("Color"): StockTextKey.normalize("Black"),
            StockTextKey.normalize("Mounting Type"): StockTextKey.normalize("Topmount")
        ]

        XCTAssertTrue(StockAttributeFiltering.matches(blackTopmount, selectedValueKeys: selected))
        XCTAssertFalse(StockAttributeFiltering.matches(blackSidemount, selectedValueKeys: selected))
    }

    func testQuantityAdjustmentPresetsAndGuards() {
        XCTAssertEqual(StockQuantityAdjustment.presetDeltas, [-100, -50, -10, -5, 5, 10, 50, 100])
        XCTAssertEqual(StockQuantityAdjustment.targetQuantity(current: 12, delta: 5), 17)
        XCTAssertNil(StockQuantityAdjustment.targetQuantity(current: 12, delta: -20))
        XCTAssertNil(StockQuantityAdjustment.targetQuantity(current: 12, delta: 0))
    }

    func testQuantityAdjustmentSupportsExactAndCustomAmounts() {
        XCTAssertEqual(StockQuantityAdjustment.exactQuantity(from: "37", current: 12), 37)
        XCTAssertEqual(StockQuantityAdjustment.exactQuantity(from: "1,250.5", current: 12), 1250.5)
        XCTAssertNil(StockQuantityAdjustment.exactQuantity(from: "-1", current: 12))
        XCTAssertNil(StockQuantityAdjustment.exactQuantity(from: "12", current: 12))

        XCTAssertEqual(StockQuantityAdjustment.customTargetQuantity(from: "37", sign: 1, current: 12), 49)
        XCTAssertEqual(StockQuantityAdjustment.customTargetQuantity(from: "17", sign: -1, current: 50), 33)
        XCTAssertEqual(StockQuantityAdjustment.customTargetQuantity(from: "-17", sign: -1, current: 50), 33)
        XCTAssertNil(StockQuantityAdjustment.customTargetQuantity(from: "17", sign: -1, current: 12))
        XCTAssertNil(StockQuantityAdjustment.customTargetQuantity(from: "0", sign: 1, current: 12))
    }

    private func row(
        id: String,
        familyName: String,
        quantity: Double,
        warning: Double? = nil,
        critical: Double? = nil
    ) -> EnrichedVariantRow {
        let family = CatalogItem(
            id: "family_\(id)",
            companyId: companyId,
            name: familyName,
            defaultWarningThreshold: warning,
            defaultCriticalThreshold: critical
        )
        let variant = CatalogVariant(
            id: id,
            companyId: companyId,
            catalogItemId: family.id,
            quantity: quantity
        )
        return EnrichedVariantRow(
            variant: variant,
            family: family,
            category: nil,
            unit: nil,
            tagIds: [],
            optionPairs: []
        )
    }

    private func optionRow(
        id: String,
        familyName: String,
        sku: String? = nil,
        options: [(name: String, value: String)]
    ) -> EnrichedVariantRow {
        let family = CatalogItem(
            id: "family_\(id)",
            companyId: companyId,
            name: familyName
        )
        let variant = CatalogVariant(
            id: id,
            companyId: companyId,
            catalogItemId: family.id,
            sku: sku,
            quantity: 12
        )
        let pairs = options.enumerated().map { index, optionValue in
            let option = CatalogOption(
                id: "option_\(id)_\(index)",
                catalogItemId: family.id,
                name: optionValue.name,
                sortOrder: index
            )
            let value = CatalogOptionValue(
                id: "value_\(id)_\(index)",
                optionId: option.id,
                value: optionValue.value
            )
            return (option: option, value: value)
        }
        return EnrichedVariantRow(
            variant: variant,
            family: family,
            category: nil,
            unit: nil,
            tagIds: [],
            optionPairs: pairs
        )
    }

    private func categoryRow(
        id: String,
        familyName: String,
        category: CatalogCategory?,
        options: [(name: String, value: String)]
    ) -> EnrichedVariantRow {
        let family = CatalogItem(
            id: "family_\(id)",
            companyId: companyId,
            name: familyName,
            categoryId: category?.id
        )
        let variant = CatalogVariant(
            id: id,
            companyId: companyId,
            catalogItemId: family.id,
            quantity: 12
        )
        let pairs = options.enumerated().map { index, optionValue in
            let option = CatalogOption(
                id: "option_\(id)_\(index)",
                catalogItemId: family.id,
                name: optionValue.name,
                sortOrder: index
            )
            let value = CatalogOptionValue(
                id: "value_\(id)_\(index)",
                optionId: option.id,
                value: optionValue.value
            )
            return (option: option, value: value)
        }
        return EnrichedVariantRow(
            variant: variant,
            family: family,
            category: category,
            unit: nil,
            tagIds: [],
            optionPairs: pairs
        )
    }
}
