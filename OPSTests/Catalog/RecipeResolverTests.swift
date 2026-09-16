//
//  RecipeResolverTests.swift
//  OPSTests
//
//  Unit coverage for the pure recipe → catalog_variant pin resolver.
//

import XCTest
@testable import OPS

final class RecipeResolverTests: XCTestCase {

    // MARK: - Test 1: variant-pinned recipe row (catalog_variant_id set)

    func test_variantPinnedRow_resolvesDirectly() throws {
        let recipe = ProductMaterial(
            id: "m1",
            productId: "p_rail",
            catalogVariantId: "v1",
            quantityPerUnit: 1.05,
            unitId: "unit_lf",
            notes: "deck board"
        )
        let resolver = RecipeResolver()

        let result = try resolver.resolve(
            materials: [recipe],
            configuredOptions: [:],
            productOptionsById: [:],
            productOptionValuesById: [:],
            catalogVariants: [],
            catalogVariantOptionValues: [],
            catalogOptionValuesById: [:],
            catalogOptionsByItemId: [:],
            lineQuantity: 24
        )

        XCTAssertEqual(result.count, 1)
        let m = try XCTUnwrap(result.first)
        XCTAssertEqual(m.catalogVariantId, "v1")
        XCTAssertEqual(m.quantity, 1.05 * 24, accuracy: 0.001)
        XCTAssertEqual(m.unitId, "unit_lf")
        XCTAssertEqual(m.notes, "deck board")
    }

    // MARK: - Test 2: family-pinned via selector

    func test_familyPinnedRow_resolvesViaSelector() throws {
        // Family: Composite Board with one option axis "Color".
        // Variants: v_board_black, v_board_white.
        let familyOptionColor = CatalogOption(
            id: "co_color",
            catalogItemId: "f_board",
            name: "Color",
            sortOrder: 0
        )
        let cvBlack = CatalogOptionValue(id: "cv_black", optionId: "co_color", value: "Black")
        let cvWhite = CatalogOptionValue(id: "cv_white", optionId: "co_color", value: "White")

        let vBlack = CatalogVariant(
            id: "v_board_black", companyId: "c1", catalogItemId: "f_board"
        )
        let vWhite = CatalogVariant(
            id: "v_board_white", companyId: "c1", catalogItemId: "f_board"
        )
        let joinBlack = CatalogVariantOptionValue(
            variantId: "v_board_black", optionValueId: "cv_black"
        )
        let joinWhite = CatalogVariantOptionValue(
            variantId: "v_board_white", optionValueId: "cv_white"
        )

        // Product side: ProductOption "Color" with value Black (selected).
        let prodColor = ProductOption(
            id: "o_color", productId: "p_rail", name: "Color",
            kind: .select, affectsRecipe: true, sortOrder: 0
        )
        let pvBlack = ProductOptionValue(id: "v_pblack", optionId: "o_color", value: "Black")
        let pvWhite = ProductOptionValue(id: "v_pwhite", optionId: "o_color", value: "White")

        let recipe = ProductMaterial(
            id: "m1",
            productId: "p_rail",
            catalogVariantId: nil,
            catalogItemId: "f_board",
            variantSelectorJSON: #"{"color": "$option.color"}"#,
            quantityPerUnit: 1.0,
            unitId: nil,
            notes: nil
        )

        let resolver = RecipeResolver()
        let result = try resolver.resolve(
            materials: [recipe],
            configuredOptions: ["o_color": .selectId("v_pblack")],
            productOptionsById: ["o_color": prodColor],
            productOptionValuesById: ["v_pblack": pvBlack, "v_pwhite": pvWhite],
            catalogVariants: [vBlack, vWhite],
            catalogVariantOptionValues: [joinBlack, joinWhite],
            catalogOptionValuesById: ["cv_black": cvBlack, "cv_white": cvWhite],
            catalogOptionsByItemId: ["f_board": [familyOptionColor]],
            lineQuantity: 24
        )

        XCTAssertEqual(result.count, 1)
        let m = try XCTUnwrap(result.first)
        XCTAssertEqual(m.catalogVariantId, "v_board_black")
        XCTAssertEqual(m.quantity, 24, accuracy: 0.001)
    }

    // MARK: - Test 3: scaled-by-option replaces line quantity scaling

    func test_scaledByOption_replacesLineQuantityScaling() throws {
        // Recipe: 1 cap per corner. Configured corners = 4. Line quantity = 24 lf.
        // Expected: 4 (NOT 4 * 24, NOT 1 * 24).
        let cornersOpt = ProductOption(
            id: "o_corners", productId: "p_rail", name: "Corners",
            kind: .integer, affectsRecipe: true, sortOrder: 0
        )

        let recipe = ProductMaterial(
            id: "m_cap",
            productId: "p_rail",
            catalogVariantId: "v_cap",
            quantityPerUnit: 1.0,
            scaledByOptionId: "o_corners"
        )

        let resolver = RecipeResolver()
        let result = try resolver.resolve(
            materials: [recipe],
            configuredOptions: ["o_corners": .integer(4)],
            productOptionsById: ["o_corners": cornersOpt],
            productOptionValuesById: [:],
            catalogVariants: [],
            catalogVariantOptionValues: [],
            catalogOptionValuesById: [:],
            catalogOptionsByItemId: [:],
            lineQuantity: 24
        )

        XCTAssertEqual(result.count, 1)
        let m = try XCTUnwrap(result.first)
        XCTAssertEqual(m.catalogVariantId, "v_cap")
        XCTAssertEqual(m.quantity, 4.0, accuracy: 0.001)
    }

    // MARK: - Test 3b: scaled line with a missing / non-integer count is zeroed

    /// A scaled recipe row whose option count was never written must NOT fall
    /// back to `quantity_per_unit × line quantity` (20 corner caps on a 20 lf
    /// run). It resolves to 0 and says why, mirroring the database resolver's
    /// `scaled_option_value_missing` warning.
    func test_scaledByOption_missingValue_zeroesQuantityAndWarns() throws {
        let recipe = ProductMaterial(
            id: "m_cap",
            productId: "p_rail",
            catalogVariantId: "v_cap",
            quantityPerUnit: 1.0,
            scaledByOptionId: "o_corners"
        )

        let result = try RecipeResolver().resolveDetailed(
            materials: [recipe],
            configuredOptions: [:],
            productOptionsById: [:],
            productOptionValuesById: [:],
            catalogVariants: [],
            catalogVariantOptionValues: [],
            catalogOptionValuesById: [:],
            catalogOptionsByItemId: [:],
            lineQuantity: 20
        )

        XCTAssertEqual(result.materials.count, 1)
        let m = try XCTUnwrap(result.materials.first)
        XCTAssertEqual(m.catalogVariantId, "v_cap")
        XCTAssertEqual(m.quantity, 0, accuracy: 0.000_001)
        XCTAssertEqual(result.warnings, [
            RecipeResolver.ResolverWarning(
                code: "scaled_option_value_missing",
                productMaterialId: "m_cap",
                productOptionId: "o_corners"
            )
        ])
    }

    func test_scaledByOption_booleanValue_zeroesQuantityAndWarns() throws {
        let recipe = ProductMaterial(
            id: "m_cap",
            productId: "p_rail",
            catalogVariantId: "v_cap",
            quantityPerUnit: 1.0,
            scaledByOptionId: "o_corners"
        )

        let result = try RecipeResolver().resolveDetailed(
            materials: [recipe],
            configuredOptions: ["o_corners": .boolean(true)],
            productOptionsById: [:],
            productOptionValuesById: [:],
            catalogVariants: [],
            catalogVariantOptionValues: [],
            catalogOptionValuesById: [:],
            catalogOptionsByItemId: [:],
            lineQuantity: 20
        )

        XCTAssertEqual(try XCTUnwrap(result.materials.first).quantity, 0, accuracy: 0.000_001)
        XCTAssertEqual(result.warnings.map(\.code), ["scaled_option_value_missing"])
    }

    func test_scaledByOption_selectValue_zeroesQuantityAndWarns() throws {
        let recipe = ProductMaterial(
            id: "m_cap",
            productId: "p_rail",
            catalogVariantId: "v_cap",
            quantityPerUnit: 1.0,
            scaledByOptionId: "o_corners"
        )

        let result = try RecipeResolver().resolveDetailed(
            materials: [recipe],
            configuredOptions: ["o_corners": .selectId("v_something")],
            productOptionsById: [:],
            productOptionValuesById: [:],
            catalogVariants: [],
            catalogVariantOptionValues: [],
            catalogOptionValuesById: [:],
            catalogOptionsByItemId: [:],
            lineQuantity: 20
        )

        XCTAssertEqual(try XCTUnwrap(result.materials.first).quantity, 0, accuracy: 0.000_001)
        XCTAssertEqual(result.warnings.map(\.productOptionId), ["o_corners"])
    }

    /// Unscaled lines keep line-quantity scaling and produce no warnings;
    /// `resolve` stays a source-compatible view over `resolveDetailed`.
    func test_unscaledLine_noWarnings_andResolveMatchesDetailed() throws {
        let recipe = ProductMaterial(
            id: "m_board",
            productId: "p_rail",
            catalogVariantId: "v_board",
            quantityPerUnit: 2.0
        )
        let resolver = RecipeResolver()
        let detailed = try resolver.resolveDetailed(
            materials: [recipe],
            configuredOptions: [:],
            productOptionsById: [:],
            productOptionValuesById: [:],
            catalogVariants: [],
            catalogVariantOptionValues: [],
            catalogOptionValuesById: [:],
            catalogOptionsByItemId: [:],
            lineQuantity: 7
        )
        let plain = try resolver.resolve(
            materials: [recipe],
            configuredOptions: [:],
            productOptionsById: [:],
            productOptionValuesById: [:],
            catalogVariants: [],
            catalogVariantOptionValues: [],
            catalogOptionValuesById: [:],
            catalogOptionsByItemId: [:],
            lineQuantity: 7
        )
        XCTAssertTrue(detailed.warnings.isEmpty)
        XCTAssertEqual(detailed.materials, plain)
        XCTAssertEqual(try XCTUnwrap(plain.first).quantity, 14, accuracy: 0.000_001)
    }

    // MARK: - configured_options decoder

    /// JSON `true` bridges to an NSNumber that `as? Int` happily reads as 1 —
    /// the decoder must see the CFBoolean first. Integral doubles are counts;
    /// non-integral doubles are not and stay absent (never truncated).
    func test_decodeConfiguredOptions_distinguishesBooleansAndRejectsFractions() {
        let decoded = ProductConfigurationResolver.decodeConfiguredOptions(
            #"{"a": true, "b": 1, "c": 2.0, "d": 2.5, "e": "val_1", "f": false, "g": 0}"#
        )
        XCTAssertEqual(decoded["a"], .boolean(true))
        XCTAssertEqual(decoded["b"], .integer(1))
        XCTAssertEqual(decoded["c"], .integer(2))
        XCTAssertNil(decoded["d"])
        XCTAssertEqual(decoded["e"], .selectId("val_1"))
        XCTAssertEqual(decoded["f"], .boolean(false))
        XCTAssertEqual(decoded["g"], .integer(0))
        XCTAssertEqual(decoded.count, 6)
    }

    func test_decodeConfiguredOptions_malformedJSON_isEmpty() {
        XCTAssertTrue(ProductConfigurationResolver.decodeConfiguredOptions("not json").isEmpty)
        XCTAssertTrue(ProductConfigurationResolver.decodeConfiguredOptions("[1, 2]").isEmpty)
    }

    // MARK: - Test 4: selector matches no variant → throws

    /// Family `f_board` has Color = Black AND Green declared at the family
    /// level (catalog_option_values), but only the Black variant actually
    /// exists. The recipe configured Color = Green → the resolver computes a
    /// non-empty required set, finds zero matching variants, and throws.
    /// (If the resolved value were absent from the family's option-values
    /// entirely, the required-set would be empty — the matcher would match
    /// every variant, picking one ambiguously. The throw path requires the
    /// value-name to exist on the family but the variant to be missing.)
    func test_throws_whenSelectorYieldsNoVariant() {
        let familyOptionColor = CatalogOption(
            id: "co_color", catalogItemId: "f_board", name: "Color", sortOrder: 0
        )
        let cvBlack = CatalogOptionValue(id: "cv_black", optionId: "co_color", value: "Black")
        let cvGreen = CatalogOptionValue(id: "cv_green", optionId: "co_color", value: "Green")

        // Only the Black variant exists — Green is on the family but has no SKU.
        let vBlack = CatalogVariant(
            id: "v_board_black", companyId: "c1", catalogItemId: "f_board"
        )
        let joinBlack = CatalogVariantOptionValue(
            variantId: "v_board_black", optionValueId: "cv_black"
        )

        let prodColor = ProductOption(
            id: "o_color", productId: "p_rail", name: "Color",
            kind: .select, affectsRecipe: true, sortOrder: 0
        )
        let pvGreen = ProductOptionValue(id: "v_pgreen", optionId: "o_color", value: "Green")

        let recipe = ProductMaterial(
            id: "m1",
            productId: "p_rail",
            catalogVariantId: nil,
            catalogItemId: "f_board",
            variantSelectorJSON: #"{"color": "$option.color"}"#,
            quantityPerUnit: 1.0
        )

        let resolver = RecipeResolver()
        XCTAssertThrowsError(
            try resolver.resolve(
                materials: [recipe],
                configuredOptions: ["o_color": .selectId("v_pgreen")],
                productOptionsById: ["o_color": prodColor],
                productOptionValuesById: ["v_pgreen": pvGreen],
                catalogVariants: [vBlack],
                catalogVariantOptionValues: [joinBlack],
                catalogOptionValuesById: ["cv_black": cvBlack, "cv_green": cvGreen],
                catalogOptionsByItemId: ["f_board": [familyOptionColor]],
                lineQuantity: 1
            )
        ) { error in
            guard case RecipeResolver.ResolverError.missingCatalogVariantForSelector(let itemId, _) = error else {
                XCTFail("expected missingCatalogVariantForSelector, got \(error)"); return
            }
            XCTAssertEqual(itemId, "f_board")
        }
    }
}
