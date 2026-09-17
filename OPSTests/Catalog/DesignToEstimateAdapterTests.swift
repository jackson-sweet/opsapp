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
    // MARK: - Canpro end-to-end: a drawing's run totals reach the line's counts

    /// The Canpro shape from `docs/superpowers/specs/canpro-recipe-rules.md`:
    /// a 20 ft picket rail run with one end on each side and one 90° corner.
    /// Counts are named after the measurement ("Left ends"), with NO
    /// `option_default_source` configured — the name match is what carries the
    /// drawing's totals onto the line, because no live product in production
    /// sets `option_default_source` at all.
    private func buildCanproRailFixture() -> (
        Product,
        [String: [ProductOption]],
        [String: [ProductOptionValue]],
        [String: [ProductPricingModifier]]
    ) {
        let railing = Product(
            id: "p_canpro_rail", companyId: "c1", name: "Picket Rail — Level",
            type: .material, kind: .good, basePrice: 70.00, pricingUnit: .linearFoot
        )
        let color = ProductOption(
            id: "o_color", productId: "p_canpro_rail", name: "Color",
            kind: .select, affectsPrice: false, affectsRecipe: true,
            defaultValue: "Black", optionDefaultSource: "$design.color", sortOrder: 0
        )
        let leftEnds = ProductOption(
            id: "o_left", productId: "p_canpro_rail", name: "Left ends",
            kind: .integer, affectsPrice: false, affectsRecipe: true,
            defaultValue: "0", optionDefaultSource: nil, sortOrder: 1
        )
        let rightEnds = ProductOption(
            id: "o_right", productId: "p_canpro_rail", name: "Right Ends",
            kind: .integer, affectsPrice: false, affectsRecipe: true,
            defaultValue: "0", optionDefaultSource: nil, sortOrder: 2
        )
        let corners = ProductOption(
            id: "o_corners", productId: "p_canpro_rail", name: "Corners",
            kind: .integer, affectsPrice: false, affectsRecipe: true,
            defaultValue: "0", optionDefaultSource: nil, sortOrder: 3
        )
        let offAngle = ProductOption(
            id: "o_45", productId: "p_canpro_rail", name: "45° corners",
            kind: .integer, affectsPrice: false, affectsRecipe: true,
            defaultValue: "0", optionDefaultSource: nil, sortOrder: 4
        )
        let black = ProductOptionValue(id: "v_black", optionId: "o_color", value: "Black")
        return (
            railing,
            ["p_canpro_rail": [color, leftEnds, rightEnds, corners, offAngle]],
            ["o_color": [black]],
            [:]
        )
    }

    func test_generate_canproRailingRun_carriesTakeoffCountsOntoTheLine() {
        let (railing, options, values, modifiers) = buildCanproRailFixture()
        let adapter = DesignToEstimateAdapter()
        // What RailingTakeoff emits for an L of two 10 ft runs meeting at one
        // 90° corner: 20 lf, one end each side, one corner, no 45s.
        let json = """
        {
          "components": [
            {
              "component_type": "railing",
              "metadata": {
                "linear_feet": 20,
                "left_ends": 1,
                "right_ends": 1,
                "corners": 1,
                "off_angle_corners": 0,
                "house_returns": 0,
                "color": "Black",
                "railing_type": "picket",
                "handedness_basis": "surface"
              }
            }
          ]
        }
        """
        let result = adapter.generate(
            design: makeDesign(jsonString: json),
            defaults: [.railing: railing],
            productOptions: options,
            productOptionValues: values,
            productModifiers: modifiers
        )

        XCTAssertEqual(result.count, 1)
        let item = result[0]
        XCTAssertEqual(item.quantity, 20, accuracy: 0.001, "line quantity is the run's linear feet")

        // Every count option carries the drawing's number as a JSON integer —
        // this is exactly what the demand resolver scales end posts, corner
        // sleeves and hardware by.
        let expected: [(String, Int)] = [("o_left", 1), ("o_right", 1), ("o_corners", 1), ("o_45", 0)]
        for (optionId, count) in expected {
            if case .integer(let n) = item.configuredOptions[optionId] {
                XCTAssertEqual(n, count, "\(optionId) should carry \(count)")
            } else {
                XCTFail("expected an integer count for \(optionId), got \(String(describing: item.configuredOptions[optionId]))")
            }
        }
        if case .selectId(let id) = item.configuredOptions["o_color"] {
            XCTAssertEqual(id, "v_black")
        } else { XCTFail("expected the colour to resolve to its option value id") }
    }

    // MARK: - Counts the drawing did not measure stay blank

    /// A count is the job's geometry. Acceptance refuses a blank count but cannot
    /// tell an injected 0 from a real one, so the adapter carries only what the
    /// drawing measured: a measured count (0 included) is set, anything the
    /// drawing did not measure is left off the line for the estimator to enter.

    private func canproRailing(metadata: String) -> DesignToEstimateAdapter.GeneratedLineItem? {
        let (railing, fixtureOptions, values, modifiers) = buildCanproRailFixture()
        var options = fixtureOptions
        let wallReturns = ProductOption(
            id: "o_wall", productId: "p_canpro_rail", name: "Wall returns",
            kind: .integer, affectsPrice: false, affectsRecipe: true,
            defaultValue: "0", optionDefaultSource: nil, sortOrder: 5
        )
        options["p_canpro_rail", default: []].append(wallReturns)
        let json = """
        { "components": [ { "component_type": "railing", "metadata": \(metadata) } ] }
        """
        return DesignToEstimateAdapter().generate(
            design: makeDesign(jsonString: json),
            defaults: [.railing: railing],
            productOptions: options,
            productOptionValues: values,
            productModifiers: modifiers
        ).first
    }

    func test_generate_measuredCountIsSet_measuredZeroIsZero_unmeasuredCountIsAbsent() throws {
        let item = try XCTUnwrap(canproRailing(metadata: """
        { "linear_feet": 20, "right_ends": 1, "corners": 0, "color": "Black" }
        """))

        XCTAssertEqual(item.configuredOptions["o_right"], .integer(1), "a measured count is carried")
        XCTAssertEqual(item.configuredOptions["o_corners"], .integer(0), "a measured 0 is a count")
        XCTAssertNil(item.configuredOptions["o_left"], "left_ends was not measured — blank, not 0")
        XCTAssertNil(item.configuredOptions["o_45"], "off_angle_corners was not measured — blank, not 0")
        XCTAssertNil(item.configuredOptions["o_wall"], "wall returns are never drawing-driven — blank, not 0")
        XCTAssertEqual(item.configuredOptions["o_color"], .selectId("v_black"))
    }

    func test_generate_neverFillsAnUnmeasuredCountFromItsCatalogueDefault() throws {
        let (railing, fixtureOptions, values, modifiers) = buildCanproRailFixture()
        var options = fixtureOptions
        options["p_canpro_rail"] = options["p_canpro_rail"]?.map { option in
            guard option.kind == .integer else { return option }
            return ProductOption(
                id: option.id, productId: option.productId, name: option.name,
                kind: .integer, affectsPrice: false, affectsRecipe: true,
                defaultValue: "1", optionDefaultSource: nil, sortOrder: option.sortOrder
            )
        }
        let json = """
        { "components": [ { "component_type": "railing", "metadata": { "linear_feet": 12 } } ] }
        """

        let item = try XCTUnwrap(DesignToEstimateAdapter().generate(
            design: makeDesign(jsonString: json),
            defaults: [.railing: railing],
            productOptions: options,
            productOptionValues: values,
            productModifiers: modifiers
        ).first)

        for optionId in ["o_left", "o_right", "o_corners", "o_45"] {
            XCTAssertNil(item.configuredOptions[optionId], "\(optionId) must not take its catalogue default")
        }
        // Select defaults still apply when the drawing is silent.
        XCTAssertEqual(item.configuredOptions["o_color"], .selectId("v_black"))
    }

    func test_generate_designSourcedCountIsBlank_whenTheDrawingOmitsIt() throws {
        let (railing, options, values, modifiers) = buildRailingFixture()
        let json = """
        {
          "components": [
            {
              "component_type": "railing",
              "metadata": { "linear_feet": 24, "color": "Black", "mount_type": "Topmount", "mount_surface": "Surface" }
            }
          ]
        }
        """

        let item = try XCTUnwrap(DesignToEstimateAdapter().generate(
            design: makeDesign(jsonString: json),
            defaults: [.railing: railing],
            productOptions: options,
            productOptionValues: values,
            productModifiers: modifiers
        ).first)

        XCTAssertNil(item.configuredOptions["o_corners"], "$design.corners_count absent — blank, not the default 0")
        XCTAssertEqual(item.resolvedOptionsLabel, "Topmount · Surface · Black")
    }

    func test_generate_readsAWholeCountInAnyNumericForm_andRejectsAnythingElse() throws {
        let item = try XCTUnwrap(canproRailing(metadata: """
        { "linear_feet": 20, "left_ends": "2", "right_ends": 1.0, "corners": 1.5, "off_angle_corners": true }
        """))

        XCTAssertEqual(item.configuredOptions["o_left"], .integer(2), "an integer string is a count")
        XCTAssertEqual(item.configuredOptions["o_right"], .integer(1), "a whole-valued number is a count")
        XCTAssertNil(item.configuredOptions["o_corners"], "1.5 is not a count — blank, never truncated")
        XCTAssertNil(item.configuredOptions["o_45"], "a boolean is not a count")
    }

    func test_generate_blankCountIsLeftOutOfTheSavedSnapshot() throws {
        let item = try XCTUnwrap(canproRailing(metadata: """
        { "linear_feet": 20, "left_ends": 0, "right_ends": 1, "corners": 0, "off_angle_corners": 0 }
        """))

        let raw = try XCTUnwrap(CatalogEstimateMerger.encodeConfiguredOptions(item.configuredOptions))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(raw.rawJSONString.utf8)) as? [String: Any]
        )
        XCTAssertNil(object["o_wall"], "an unmeasured count must not reach the line as 0")
        XCTAssertEqual((object["o_left"] as? NSNumber)?.intValue, 0)
    }

    func test_designMetadataKey_matchesCountOptionNamesCaseAndSpacingInsensitively() {
        XCTAssertEqual(DesignToEstimateAdapter.designMetadataKey(forIntegerOptionNamed: "Left ends"), "left_ends")
        XCTAssertEqual(DesignToEstimateAdapter.designMetadataKey(forIntegerOptionNamed: "  RIGHT   ENDS "), "right_ends")
        XCTAssertEqual(DesignToEstimateAdapter.designMetadataKey(forIntegerOptionNamed: "45° corners"), "off_angle_corners")
        XCTAssertEqual(DesignToEstimateAdapter.designMetadataKey(forIntegerOptionNamed: "Off-angle corners"), "off_angle_corners")
        // Wall returns is deliberately NOT drawing-driven: a return takes an
        // end post by default, and swapping in a wall bracket is the
        // estimator's call.
        XCTAssertNil(DesignToEstimateAdapter.designMetadataKey(forIntegerOptionNamed: "Wall returns"))
        XCTAssertNil(DesignToEstimateAdapter.designMetadataKey(forIntegerOptionNamed: "Pickets"))
    }

}
