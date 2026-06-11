//
//  GuidedCatalogSetupVariantTests.swift
//  OPSTests
//
//  Pure matrix derivation (clean axes, cartesian product, cap) and the shared
//  CatalogVariantLabeler (option-value labels, SKU + family fallbacks).
//

import XCTest
@testable import OPS

final class GuidedCatalogSetupVariantTests: XCTestCase {

    // MARK: - Axis sanitization + matrix

    func test_cleanAxes_dropsBlankAndDuplicateValues() {
        var draft = AssemblyMaterialDraft(name: "Top rail")
        draft.axes = [AssemblyMaterialAxis(name: "Color", values: ["Black", "", "black", "White"])]
        let clean = draft.cleanAxes
        XCTAssertEqual(clean.count, 1)
        XCTAssertEqual(clean[0].name, "Color")
        XCTAssertEqual(clean[0].values, ["Black", "White"])   // blank + case-insensitive dup dropped, order kept
    }

    func test_variantCombos_cartesianProduct_axis1Outer() {
        var draft = AssemblyMaterialDraft(name: "Membrane")
        draft.axes = [AssemblyMaterialAxis(name: "Color", values: ["Tan", "Gray", "Slate"]),
                      AssemblyMaterialAxis(name: "Thickness", values: ["45mil", "60mil"])]
        XCTAssertEqual(draft.variantComboCount, 6)
        let combos = draft.variantCombos
        XCTAssertEqual(combos.count, 6)
        XCTAssertEqual(combos.first, ["Tan", "45mil"])
        XCTAssertEqual(combos.last, ["Slate", "60mil"])
    }

    func test_variantComboCount_singleAxis() {
        var draft = AssemblyMaterialDraft(name: "Top rail")
        draft.axes = [AssemblyMaterialAxis(name: "Color", values: ["Black", "White"])]
        XCTAssertEqual(draft.variantComboCount, 2)
        XCTAssertEqual(draft.variantCombos, [["Black"], ["White"]])
    }

    func test_noUsableAxes_whenAxisNameBlank() {
        var draft = AssemblyMaterialDraft(name: "Screws")
        draft.axes = [AssemblyMaterialAxis(name: "  ", values: ["Black"])]
        XCTAssertFalse(draft.hasUsableAxes)
        XCTAssertEqual(draft.variantComboCount, 1)
        XCTAssertEqual(draft.variantCombos, [[]])   // no axes → one empty combo
    }

    func test_deckRail_24VariantMatrix() {
        var draft = AssemblyMaterialDraft(name: "Vinyl membrane")
        draft.axes = [
            AssemblyMaterialAxis(name: "Color", values: (1...12).map { "C\($0)" }),
            AssemblyMaterialAxis(name: "Thickness", values: ["45mil", "60mil"]),
        ]
        XCTAssertEqual(draft.variantComboCount, 24)               // 12 × 2 — the audit's vinyl matrix
        XCTAssertLessThanOrEqual(draft.variantComboCount, AssemblyMaterialDraft.maxVariants)
    }

    // MARK: - Variant labeler

    func test_variantLabeler_composesOptionValues_inSortOrder() {
        let family = CatalogItem(id: "f", companyId: "c", name: "Top rail")
        let color = CatalogOption(id: "o1", catalogItemId: "f", name: "Color", sortOrder: 0)
        let thickness = CatalogOption(id: "o2", catalogItemId: "f", name: "Thickness", sortOrder: 1)
        let black = CatalogOptionValue(id: "v1", optionId: "o1", value: "Black", sortOrder: 0)
        let sixty = CatalogOptionValue(id: "v2", optionId: "o2", value: "60mil", sortOrder: 1)
        let variant = CatalogVariant(id: "var", companyId: "c", catalogItemId: "f")
        let links = [CatalogVariantOptionValue(variantId: "var", optionValueId: "v1"),
                     CatalogVariantOptionValue(variantId: "var", optionValueId: "v2")]

        let label = CatalogVariantLabeler.label(for: variant, families: [family],
            options: [color, thickness], optionValues: [black, sixty], variantOptionValues: links)
        XCTAssertEqual(label, "Top rail · Black · 60mil")
    }

    func test_variantLabeler_fallsBackToSku_thenFamily() {
        let family = CatalogItem(id: "f", companyId: "c", name: "Top rail")
        let withSku = CatalogVariant(id: "v1", companyId: "c", catalogItemId: "f", sku: "TR-001")
        let bare = CatalogVariant(id: "v2", companyId: "c", catalogItemId: "f")
        XCTAssertEqual(CatalogVariantLabeler.label(for: withSku, families: [family],
            options: [], optionValues: [], variantOptionValues: []), "Top rail · TR-001")
        XCTAssertEqual(CatalogVariantLabeler.label(for: bare, families: [family],
            options: [], optionValues: [], variantOptionValues: []), "Top rail")
    }
}
