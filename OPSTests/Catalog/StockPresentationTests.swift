//
//  StockPresentationTests.swift
//  OPSTests
//
//  Pins the operator job behind each Catalog Stock mode. These contracts keep
//  LIST, GRID, and TABLE from collapsing back into three arrangements of the
//  same card.
//

import XCTest
@testable import OPS

final class StockPresentationTests: XCTestCase {
    func testEachModeOwnsADistinctOperatorPurpose() {
        XCTAssertEqual(StockViewMode.list.operatorPurpose, .scan)
        XCTAssertEqual(StockViewMode.grid.operatorPurpose, .find)
        XCTAssertEqual(StockViewMode.table.operatorPurpose, .compare)

        XCTAssertEqual(Set(StockViewMode.allCases.map(\.operatorPurpose)).count, 3)
        XCTAssertEqual(StockViewMode.list.displayLabel, "LIST")
        XCTAssertEqual(StockViewMode.grid.displayLabel, "GRID")
        XCTAssertEqual(StockViewMode.table.displayLabel, "TABLE")
    }

    func testGridDensityHonorsDocumentedRangeAndProgressiveDisclosure() {
        XCTAssertEqual(StockGridDensity.clampedScale(0.2), 0.8)
        XCTAssertEqual(StockGridDensity.clampedScale(2.0), 1.5)

        XCTAssertEqual(StockGridDensity.layout(for: 0.8).columnCount, 3)
        XCTAssertFalse(StockGridDensity.layout(for: 0.8).showsSecondaryMetadata)

        XCTAssertEqual(StockGridDensity.layout(for: 1.0).columnCount, 2)
        XCTAssertTrue(StockGridDensity.layout(for: 1.0).showsSecondaryMetadata)

        XCTAssertEqual(StockGridDensity.layout(for: 1.5).columnCount, 1)
        XCTAssertTrue(StockGridDensity.layout(for: 1.5).showsSecondaryMetadata)

        XCTAssertEqual(StockGridDensity.adjustedScale(from: 0.8, towardLargerCards: true), 1.0)
        XCTAssertEqual(StockGridDensity.adjustedScale(from: 1.0, towardLargerCards: true), 1.5)
        XCTAssertEqual(StockGridDensity.adjustedScale(from: 1.5, towardLargerCards: true), 1.5)
        XCTAssertEqual(StockGridDensity.adjustedScale(from: 1.5, towardLargerCards: false), 1.0)
        XCTAssertEqual(StockGridDensity.adjustedScale(from: 1.0, towardLargerCards: false), 0.8)
    }

    func testTablePinsAuditColumnsAndStacksAtAccessibilitySizes() {
        XCTAssertEqual(StockTableLayout.presentation(isAccessibilitySize: false), .pinnedAuditColumns)
        XCTAssertEqual(StockTableLayout.presentation(isAccessibilitySize: true), .stackedRows)
    }

    func testTableFitsOneOrTwoOptionsBeforeMakingTheOptionBandScrollable() {
        XCTAssertEqual(StockTableOptionBandLayout.resolve(optionCount: 0), .empty)
        XCTAssertEqual(StockTableOptionBandLayout.resolve(optionCount: 1), .fitted)
        XCTAssertEqual(StockTableOptionBandLayout.resolve(optionCount: 2), .fitted)
        XCTAssertEqual(StockTableOptionBandLayout.resolve(optionCount: 3), .scrolling)

        XCTAssertEqual(StockTableOptionBandLayout.visibleColumnCount(optionCount: 0), 1)
        XCTAssertEqual(StockTableOptionBandLayout.visibleColumnCount(optionCount: 1), 1)
        XCTAssertEqual(StockTableOptionBandLayout.visibleColumnCount(optionCount: 2), 2)
        XCTAssertEqual(StockTableOptionBandLayout.visibleColumnCount(optionCount: 3), 2)

        let phoneViewport = CGFloat(137)
        let scrollingWidth = StockTableOptionBandLayout.scrollingColumnWidth(
            viewportWidth: phoneViewport
        )
        XCTAssertEqual(
            phoneViewport - (scrollingWidth * 2),
            OPSStyle.Layout.spacing3,
            accuracy: 0.001,
            "Three-plus option tables must expose a tokenized trailing peek"
        )
    }

    func testTableThresholdReferencePreservesTheExactLimitKind() {
        let warning = StockTableThresholdReference.resolve(warning: 100, critical: 20)
        XCTAssertEqual(warning?.kind, .warning)
        XCTAssertEqual(warning?.value, 100)
        XCTAssertEqual(warning?.kind.comparisonLabel, "VS WARN")

        let criticalFallback = StockTableThresholdReference.resolve(warning: nil, critical: 20)
        XCTAssertEqual(criticalFallback?.kind, .critical)
        XCTAssertEqual(criticalFallback?.value, 20)
        XCTAssertEqual(criticalFallback?.kind.comparisonLabel, "VS CRIT")

        XCTAssertNil(StockTableThresholdReference.resolve(warning: 0, critical: 0))
    }

    func testTableAccessibilityLabelIncludesUnitAndCriticalFallbackKind() {
        let family = CatalogItem(
            id: "family-critical",
            companyId: "company-critical",
            name: "Critical Fastener"
        )
        let unit = CatalogUnit(
            id: "unit-box",
            companyId: "company-critical",
            display: "box"
        )
        let variant = CatalogVariant(
            id: "variant-critical",
            companyId: "company-critical",
            catalogItemId: family.id,
            quantity: 5,
            criticalThreshold: 20,
            unitId: unit.id
        )
        let row = EnrichedVariantRow(
            variant: variant,
            family: family,
            category: nil,
            unit: unit,
            tagIds: [],
            optionPairs: []
        )

        XCTAssertEqual(
            StockTableAccessibility.rowLabel(row),
            "Critical Fastener, 5 box on hand, -15 versus critical limit 20, critical"
        )
    }

    func testGridRouteHandoffWaitsForDismissalAndConsumesExactlyOnce() {
        let family = CatalogItem(id: "family-route", companyId: "company-route", name: "Route Family")
        let variant = CatalogVariant(
            id: "variant-route",
            companyId: "company-route",
            catalogItemId: family.id,
            quantity: 1
        )
        let row = EnrichedVariantRow(
            variant: variant,
            family: family,
            category: nil,
            unit: nil,
            tagIds: [],
            optionPairs: []
        )
        var handoff = StockGridRouteHandoff()

        XCTAssertNil(handoff.takeAfterDismissal())
        handoff.stage(.adjust(row))
        XCTAssertEqual(handoff.pending, .adjust(row))
        XCTAssertEqual(handoff.takeAfterDismissal(), .adjust(row))
        XCTAssertNil(handoff.takeAfterDismissal())
    }

    func testCompareModeKeepsAValidFamilySelection() {
        XCTAssertEqual(
            StockTableSelection.resolve(current: "family-b", available: ["family-a", "family-b"]),
            "family-b"
        )
        XCTAssertEqual(
            StockTableSelection.resolve(current: "gone", available: ["family-a", "family-b"]),
            "family-a"
        )
        XCTAssertNil(StockTableSelection.resolve(current: "gone", available: []))
    }

    func testStockSearchMatchesAllQueryTermsRegardlessOfOrder() {
        XCTAssertTrue(StockSearch.matches("Tech Screws Black 5000", query: "black screw"))
        XCTAssertTrue(StockSearch.matches("Tech Screws Black 5000", query: "5000 tech"))
        XCTAssertFalse(StockSearch.matches("Tech Screws Black 5000", query: "white screw"))
        XCTAssertTrue(StockSearch.matches("Anything", query: "   "))
    }
}
