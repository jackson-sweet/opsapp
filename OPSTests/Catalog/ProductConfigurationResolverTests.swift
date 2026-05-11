//
//  ProductConfigurationResolverTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

final class ProductConfigurationResolverTests: XCTestCase {

    private func buildFixture() -> (Product, [ProductOption], [ProductOptionValue], [ProductPricingModifier]) {
        let railing = Product(
            id: "p_rail", companyId: "c1", name: "Custom Composite Railing",
            type: .material, kind: .good, basePrice: 48.00, pricingUnit: .linearFoot
        )

        let mountType = ProductOption(id: "o_mount_type", productId: "p_rail", name: "Mount Type",
                                      kind: .select, affectsPrice: false, affectsRecipe: true,
                                      defaultValue: "Topmount", sortOrder: 0)
        let mountSurface = ProductOption(id: "o_mount_surf", productId: "p_rail", name: "Mount Surface",
                                          kind: .select, affectsPrice: true, affectsRecipe: false,
                                          defaultValue: "Surface", sortOrder: 1)
        let color = ProductOption(id: "o_color", productId: "p_rail", name: "Color",
                                   kind: .select, affectsPrice: false, affectsRecipe: true,
                                   defaultValue: "Black", sortOrder: 2)
        let corners = ProductOption(id: "o_corners", productId: "p_rail", name: "Corners",
                                     kind: .integer, affectsPrice: false, affectsRecipe: true,
                                     defaultValue: "0", sortOrder: 3)

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
            [mountType, mountSurface, color, corners],
            [topmount, sidemount, surface, concrete, black, white],
            [concreteMod]
        )
    }

    func test_unitPrice_includesModifiers() {
        let (railing, options, values, modifiers) = buildFixture()
        let resolver = ProductConfigurationResolver()

        let configured: [String: ProductConfigurationResolver.OptionValue] = [
            "o_mount_type": .selectId("v_topmount"),
            "o_mount_surf": .selectId("v_concrete"),
            "o_color": .selectId("v_black"),
            "o_corners": .integer(4)
        ]

        let resolution = resolver.resolve(
            product: railing, options: options, optionValues: values,
            modifiers: modifiers, configured: configured
        )

        XCTAssertEqual(resolution.unitPrice, 53.00, accuracy: 0.001)
    }

    func test_unitPrice_baseOnlyWhenNoModifiersTriggered() {
        let (railing, options, values, modifiers) = buildFixture()
        let resolver = ProductConfigurationResolver()
        let configured: [String: ProductConfigurationResolver.OptionValue] = [
            "o_mount_type": .selectId("v_topmount"),
            "o_mount_surf": .selectId("v_surface"),
            "o_color": .selectId("v_black"),
            "o_corners": .integer(0)
        ]
        let resolution = resolver.resolve(
            product: railing, options: options, optionValues: values,
            modifiers: modifiers, configured: configured
        )
        XCTAssertEqual(resolution.unitPrice, 48.00, accuracy: 0.001)
    }

    func test_label_compactlyDescribesConfiguration() {
        let (railing, options, values, modifiers) = buildFixture()
        let resolver = ProductConfigurationResolver()
        let configured: [String: ProductConfigurationResolver.OptionValue] = [
            "o_mount_type": .selectId("v_topmount"),
            "o_mount_surf": .selectId("v_concrete"),
            "o_color": .selectId("v_black"),
            "o_corners": .integer(4)
        ]
        let r = resolver.resolve(
            product: railing, options: options, optionValues: values,
            modifiers: modifiers, configured: configured
        )
        XCTAssertEqual(r.label, "Topmount · Concrete · Black · 4 corners")
    }
}
