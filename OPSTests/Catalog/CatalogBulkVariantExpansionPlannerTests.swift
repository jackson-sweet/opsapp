//
//  CatalogBulkVariantExpansionPlannerTests.swift
//  OPSTests
//
//  The planner is the safety boundary for previewing a multi-family variant
//  expansion. Every expectation below is hand-derived from a literal catalog.
//

import XCTest
@testable import OPS

final class CatalogBulkVariantExpansionPlannerTests: XCTestCase {
    private let color = CatalogBulkOptionSnapshot(
        id: "option-color",
        name: "Color",
        sortOrder: 0,
        values: [
            .init(id: "value-red", value: "Red", sortOrder: 0),
            .init(id: "value-blue", value: "Blue", sortOrder: 1)
        ]
    )

    private let mount = CatalogBulkOptionSnapshot(
        id: "option-mount",
        name: "Mount",
        sortOrder: 1,
        values: [
            .init(id: "value-top", value: "Top", sortOrder: 0)
        ]
    )

    private func variant(
        id: String,
        sku: String? = "SKU-1",
        quantity: Double = 7,
        price: Double? = 14,
        cost: Double? = 8,
        warning: Double? = 4,
        critical: Double? = 2,
        unitId: String? = "unit-each",
        optionValueIds: [String]
    ) -> CatalogBulkVariantSnapshot {
        CatalogBulkVariantSnapshot(
            id: id,
            sku: sku,
            quantity: quantity,
            priceOverride: price,
            unitCostOverride: cost,
            warningThreshold: warning,
            criticalThreshold: critical,
            unitId: unitId,
            isActive: true,
            optionValueIds: optionValueIds
        )
    }

    private func family(
        id: String = "family-rail",
        name: String = "Top Rail",
        options: [CatalogBulkOptionSnapshot]? = nil,
        variants: [CatalogBulkVariantSnapshot]? = nil
    ) -> CatalogBulkFamilySnapshot {
        CatalogBulkFamilySnapshot(
            id: id,
            name: name,
            options: options ?? [color],
            variants: variants ?? [variant(id: "variant-red", optionValueIds: ["value-red"])]
        )
    }

    private func preview(
        axis: String = "Top profile",
        existing: String = "Round top",
        newValues: [String] = ["Flat top"],
        families: [CatalogBulkFamilySnapshot]? = nil
    ) -> CatalogBulkVariantExpansionPreview {
        CatalogBulkVariantExpansionPlanner.makePreview(
            .init(
                axisName: axis,
                existingValue: existing,
                newValues: newValues,
                families: families ?? [family()]
            )
        )
    }

    func test_newAxis_labelsEverySourceAndCreatesOneZeroStockBlankSKUClonePerCombination() throws {
        let second = variant(
            id: "variant-blue",
            sku: "SKU-2",
            quantity: 11,
            price: 19,
            cost: 12,
            warning: 6,
            critical: 3,
            unitId: "unit-length",
            optionValueIds: ["value-blue"]
        )
        let result = preview(families: [family(variants: [
            variant(id: "variant-red", optionValueIds: ["value-red"]),
            second
        ])])

        XCTAssertTrue(result.blockers.isEmpty)
        XCTAssertEqual(result.existingVariantAssignmentCount, 2)
        XCTAssertEqual(result.newVariantCount, 2)

        let rail = try XCTUnwrap(result.familyPlans.first)
        XCTAssertNil(rail.targetOptionId)
        XCTAssertEqual(rail.existingAssignments.map(\.variantId), ["variant-blue", "variant-red"])

        let blueClone = try XCTUnwrap(rail.newVariants.first(where: { $0.sourceVariantId == "variant-blue" }))
        XCTAssertNil(blueClone.sku)
        XCTAssertEqual(blueClone.quantity, 0)
        XCTAssertEqual(blueClone.priceOverride, 19)
        XCTAssertEqual(blueClone.unitCostOverride, 12)
        XCTAssertEqual(blueClone.warningThreshold, 6)
        XCTAssertEqual(blueClone.criticalThreshold, 3)
        XCTAssertEqual(blueClone.unitId, "unit-length")
        XCTAssertEqual(blueClone.optionSelections, [
            .init(optionName: "Color", value: "Blue"),
            .init(optionName: "Top profile", value: "Flat top")
        ])
    }

    func test_existingAxis_clonesOnlyVariantsCarryingTheSelectedSourceValue() throws {
        let profile = CatalogBulkOptionSnapshot(
            id: "option-profile",
            name: "Top profile",
            sortOrder: 1,
            values: [
                .init(id: "value-round", value: "Round top", sortOrder: 0),
                .init(id: "value-flat", value: "Flat top", sortOrder: 1)
            ]
        )
        let result = preview(
            newValues: ["Square top"],
            families: [family(options: [color, profile], variants: [
                variant(id: "variant-round", optionValueIds: ["value-red", "value-round"]),
                variant(id: "variant-flat", optionValueIds: ["value-red", "value-flat"])
            ])]
        )

        XCTAssertTrue(result.blockers.isEmpty)
        XCTAssertEqual(result.existingVariantAssignmentCount, 0)
        XCTAssertEqual(result.newVariantCount, 1)
        let plan = try XCTUnwrap(result.familyPlans.first)
        XCTAssertEqual(plan.targetOptionId, "option-profile")
        XCTAssertEqual(plan.newVariants.map(\.sourceVariantId), ["variant-round"])
        XCTAssertEqual(plan.newVariants.first?.optionSelections, [
            .init(optionName: "Color", value: "Red"),
            .init(optionName: "Top profile", value: "Square top")
        ])
    }

    func test_existingOptionAndValues_areReusedCaseInsensitivelyInsteadOfDuplicated() throws {
        let profile = CatalogBulkOptionSnapshot(
            id: "option-profile",
            name: "  TOP PROFILE ",
            sortOrder: 1,
            values: [
                .init(id: "value-round", value: " ROUND TOP ", sortOrder: 0),
                .init(id: "value-flat", value: "FLAT TOP", sortOrder: 1)
            ]
        )
        let result = preview(
            axis: "top profile",
            existing: "round top",
            newValues: ["flat top", "Square top"],
            families: [family(options: [color, profile], variants: [
                variant(id: "variant-round", optionValueIds: ["value-red", "value-round"]),
                variant(id: "variant-flat", optionValueIds: ["value-red", "value-flat"])
            ])]
        )

        XCTAssertTrue(result.blockers.isEmpty)
        let plan = try XCTUnwrap(result.familyPlans.first)
        XCTAssertEqual(plan.targetOptionId, "option-profile")
        XCTAssertEqual(plan.resolvedExistingValueId, "value-round")
        XCTAssertEqual(plan.resolvedNewValueIds["flat top"], "value-flat")
        XCTAssertEqual(plan.skippedExistingCombinationCount, 1)
        XCTAssertEqual(plan.newVariants.count, 1)
        XCTAssertEqual(plan.newVariants.first?.newValue, "Square top")
    }

    func test_invalidNamesAndDuplicateRequestedValues_blockReview() {
        let blankAxis = preview(axis: "   ")
        XCTAssertEqual(blankAxis.blockers.map(\.code), ["axis_name_required"])

        let blankExisting = preview(existing: "\n")
        XCTAssertEqual(blankExisting.blockers.map(\.code), ["existing_value_required"])

        let duplicates = preview(newValues: ["Flat top", " flat TOP "])
        XCTAssertEqual(duplicates.blockers.map(\.code), ["duplicate_new_value"])

        let sameAsExisting = preview(newValues: ["ROUND TOP"])
        XCTAssertEqual(sameAsExisting.blockers.map(\.code), ["new_value_matches_existing"])
    }

    func test_incompletePinsMultiplePinsAndDuplicateSignatures_blockUnsafeFamilies() {
        let incomplete = preview(families: [family(
            options: [color, mount],
            variants: [variant(id: "variant-red", optionValueIds: ["value-red"])]
        )])
        XCTAssertEqual(incomplete.blockers.map(\.code), ["incomplete_variant_options"])

        let twoColorPins = preview(families: [family(
            variants: [variant(id: "variant-multi", optionValueIds: ["value-red", "value-blue"])]
        )])
        XCTAssertEqual(twoColorPins.blockers.map(\.code), ["multiple_values_for_option"])

        let duplicateSignature = preview(families: [family(variants: [
            variant(id: "variant-a", optionValueIds: ["value-red"]),
            variant(id: "variant-b", optionValueIds: ["value-red"])
        ])])
        XCTAssertEqual(duplicateSignature.blockers.map(\.code), ["duplicate_variant_signature"])
    }

    func test_noRealAddition_blocksApply() {
        let profile = CatalogBulkOptionSnapshot(
            id: "option-profile",
            name: "Top profile",
            sortOrder: 1,
            values: [
                .init(id: "value-round", value: "Round top", sortOrder: 0),
                .init(id: "value-flat", value: "Flat top", sortOrder: 1)
            ]
        )
        let result = preview(families: [family(options: [color, profile], variants: [
            variant(id: "variant-round", optionValueIds: ["value-red", "value-round"]),
            variant(id: "variant-flat", optionValueIds: ["value-red", "value-flat"])
        ])])

        XCTAssertEqual(result.newVariantCount, 0)
        XCTAssertEqual(result.blockers.map(\.code), ["no_variants_to_add"])
    }

    func test_mixedFamilies_haveStableOrderingAndExactTotals() {
        let result = preview(families: [
            family(id: "family-z", name: "Z Rail"),
            family(id: "family-a", name: "A End Cap")
        ])

        XCTAssertTrue(result.blockers.isEmpty)
        XCTAssertEqual(result.familyPlans.map(\.familyId), ["family-a", "family-z"])
        XCTAssertEqual(result.familyCount, 2)
        XCTAssertEqual(result.existingVariantAssignmentCount, 2)
        XCTAssertEqual(result.newVariantCount, 2)
    }

    func test_sourceFingerprint_changesWhenCloneRelevantSourceStateChanges() throws {
        let original = preview()
        let changedQuantity = preview(families: [family(variants: [
            variant(id: "variant-red", quantity: 8, optionValueIds: ["value-red"])
        ])])
        let changedPins = preview(families: [family(variants: [
            variant(id: "variant-red", optionValueIds: ["value-blue"])
        ])])

        let originalFingerprint = try XCTUnwrap(original.familyPlans.first?.sourceFingerprint)
        XCTAssertNotEqual(originalFingerprint, changedQuantity.familyPlans.first?.sourceFingerprint)
        XCTAssertNotEqual(originalFingerprint, changedPins.familyPlans.first?.sourceFingerprint)
    }
}
