//
//  DesignToEstimateAdapterTests.swift
//  OPSTests
//
//  Unit coverage for the pure `generate(design:defaults:...)` API.
//  Mirrors the railing fixture shape from `ProductConfigurationResolverTests`.
//

import XCTest
@testable import OPS

final class DesignToEstimateAdapterTests: XCTestCase {

    // MARK: - Railing fixture (matches ProductConfigurationResolverTests pattern)

    /// Returns:
    ///  - the railing Product
    ///  - productOptions keyed by productId
    ///  - productOptionValues keyed by optionId
    ///  - productModifiers keyed by productId
    private func buildRailingFixture() -> (
        Product,
        [String: [ProductOption]],
        [String: [ProductOptionValue]],
        [String: [ProductPricingModifier]]
    ) {
        let railing = Product(
            id: "p_rail", companyId: "c1", name: "Custom Composite Railing",
            type: .material, kind: .good, basePrice: 48.00, pricingUnit: .linearFoot
        )

        let mountType = ProductOption(
            id: "o_mount_type", productId: "p_rail", name: "Mount Type",
            kind: .select, affectsPrice: false, affectsRecipe: true,
            defaultValue: "Topmount",
            optionDefaultSource: "$design.mount_type",
            sortOrder: 0
        )
        let mountSurface = ProductOption(
            id: "o_mount_surf", productId: "p_rail", name: "Mount Surface",
            kind: .select, affectsPrice: true, affectsRecipe: false,
            defaultValue: "Surface",
            optionDefaultSource: "$design.mount_surface",
            sortOrder: 1
        )
        let color = ProductOption(
            id: "o_color", productId: "p_rail", name: "Color",
            kind: .select, affectsPrice: false, affectsRecipe: true,
            defaultValue: "Black",
            optionDefaultSource: "$design.color",
            sortOrder: 2
        )
        let corners = ProductOption(
            id: "o_corners", productId: "p_rail", name: "Corners",
            kind: .integer, affectsPrice: false, affectsRecipe: true,
            defaultValue: "0",
            optionDefaultSource: "$design.corners_count",
            sortOrder: 3
        )

        let topmount = ProductOptionValue(id: "v_topmount", optionId: "o_mount_type", value: "Topmount")
        let sidemount = ProductOptionValue(id: "v_sidemount", optionId: "o_mount_type", value: "Sidemount")
        let surface = ProductOptionValue(id: "v_surface", optionId: "o_mount_surf", value: "Surface")
        let concrete = ProductOptionValue(id: "v_concrete", optionId: "o_mount_surf", value: "Concrete")
        let black = ProductOptionValue(id: "v_black", optionId: "o_color", value: "Black")
        let white = ProductOptionValue(id: "v_white", optionId: "o_color", value: "White")

        let concreteMod = ProductPricingModifier(
            productId: "p_rail", optionId: "o_mount_surf",
            triggerValueId: "v_concrete", modifierKind: .addPerUnit, amount: 5.00
        )

        return (
            railing,
            ["p_rail": [mountType, mountSurface, color, corners]],
            [
                "o_mount_type": [topmount, sidemount],
                "o_mount_surf": [surface, concrete],
                "o_color": [black, white],
                "o_corners": []
            ],
            ["p_rail": [concreteMod]]
        )
    }

    private func makeDesign(jsonString: String) -> DeckDesign {
        DeckDesign(companyId: "c1", drawingDataJSON: jsonString)
    }

    // MARK: - Tests

    func test_generate_emptyArray_whenComponentsMissing() {
        // Drawing JSON without a "components" key — the Deck Builder agent
        // hasn't landed the vocabulary yet. Adapter must no-op gracefully.
        let (railing, options, values, modifiers) = buildRailingFixture()
        let adapter = DesignToEstimateAdapter()
        let design = makeDesign(jsonString: "{}")

        let result = adapter.generate(
            design: design,
            defaults: [.railing: railing],
            productOptions: options,
            productOptionValues: values,
            productModifiers: modifiers
        )

        XCTAssertTrue(result.isEmpty)
    }

    func test_generate_emptyArray_whenNoDefaultProductForType() {
        // Drawing has a railing component but the company hasn't configured a
        // default Product for `railing` — skip silently, don't block estimate
        // creation, don't crash.
        let adapter = DesignToEstimateAdapter()
        let json = """
        {
          "components": [
            {
              "component_type": "railing",
              "metadata": { "linear_feet": 24 }
            }
          ]
        }
        """
        let design = makeDesign(jsonString: json)

        let result = adapter.generate(
            design: design,
            defaults: [:],   // no default product for railing
            productOptions: [:],
            productOptionValues: [:],
            productModifiers: [:]
        )

        XCTAssertTrue(result.isEmpty)
    }

    func test_generate_oneLineItem_perComponent_withResolvedFields() {
        // Full happy path: railing component with metadata for every option.
        // Expected resolved unit price = 48 (base) + 5 (concrete modifier) = 53.
        // linear_feet = 24, so lineTotal = 53 * 24 = 1272.
        let (railing, options, values, modifiers) = buildRailingFixture()
        let adapter = DesignToEstimateAdapter()
        let json = """
        {
          "components": [
            {
              "component_type": "railing",
              "metadata": {
                "linear_feet": 24,
                "color": "Black",
                "mount_type": "Topmount",
                "mount_surface": "Concrete",
                "corners_count": 4
              }
            }
          ]
        }
        """
        let design = makeDesign(jsonString: json)

        let result = adapter.generate(
            design: design,
            defaults: [.railing: railing],
            productOptions: options,
            productOptionValues: values,
            productModifiers: modifiers
        )

        XCTAssertEqual(result.count, 1)
        let item = result[0]
        XCTAssertEqual(item.productId, "p_rail")
        XCTAssertEqual(item.quantity, 24, accuracy: 0.001)
        XCTAssertEqual(item.resolvedUnitPrice, 53.00, accuracy: 0.001)
        XCTAssertEqual(item.lineTotal, 1272.00, accuracy: 0.001)
        XCTAssertEqual(item.resolvedOptionsLabel, "Topmount · Concrete · Black · 4 corners")

        // Spot-check the configured map: each select-kind ProductOption should
        // be resolved to its matching ProductOptionValue id.
        if case .selectId(let id) = item.configuredOptions["o_mount_type"] {
            XCTAssertEqual(id, "v_topmount")
        } else { XCTFail("expected selectId for mount_type") }
        if case .selectId(let id) = item.configuredOptions["o_mount_surf"] {
            XCTAssertEqual(id, "v_concrete")
        } else { XCTFail("expected selectId for mount_surf") }
        if case .selectId(let id) = item.configuredOptions["o_color"] {
            XCTAssertEqual(id, "v_black")
        } else { XCTFail("expected selectId for color") }
        if case .integer(let n) = item.configuredOptions["o_corners"] {
            XCTAssertEqual(n, 4)
        } else { XCTFail("expected integer for corners") }
    }

    func test_generate_skipsComponent_whenComponentTypeUnknown() {
        // An unknown component_type ("alien") must be skipped silently — the
        // adapter is forward-compatible with vocabulary the iOS build doesn't
        // yet understand.
        let (railing, options, values, modifiers) = buildRailingFixture()
        let adapter = DesignToEstimateAdapter()
        let json = """
        {
          "components": [
            {
              "component_type": "alien",
              "metadata": { "linear_feet": 99 }
            },
            {
              "component_type": "railing",
              "metadata": {
                "linear_feet": 12,
                "color": "Black",
                "mount_type": "Topmount",
                "mount_surface": "Surface",
                "corners_count": 0
              }
            }
          ]
        }
        """
        let design = makeDesign(jsonString: json)

        let result = adapter.generate(
            design: design,
            defaults: [.railing: railing],
            productOptions: options,
            productOptionValues: values,
            productModifiers: modifiers
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].productId, "p_rail")
        XCTAssertEqual(result[0].quantity, 12, accuracy: 0.001)
        // Surface mount → no concrete modifier → base price 48 only.
        XCTAssertEqual(result[0].resolvedUnitPrice, 48.00, accuracy: 0.001)
    }

    // MARK: - Quantity unit coverage

    func test_generate_flatRateProduct_hasQuantityOne() {
        // A flat-rate product ignores metadata measurements and pegs quantity at 1.
        let permit = Product(
            id: "p_permit", companyId: "c1", name: "Permit Filing",
            type: .labor, kind: .service, basePrice: 250.0, pricingUnit: .flatRate
        )
        let adapter = DesignToEstimateAdapter()
        let json = """
        {
          "components": [
            { "component_type": "gate", "metadata": { "linear_feet": 4 } }
          ]
        }
        """
        let design = makeDesign(jsonString: json)

        let result = adapter.generate(
            design: design,
            defaults: [.gate: permit],
            productOptions: [:],
            productOptionValues: [:],
            productModifiers: [:]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].quantity, 1.0, accuracy: 0.001)
        XCTAssertEqual(result[0].lineTotal, 250.00, accuracy: 0.001)
    }
}
