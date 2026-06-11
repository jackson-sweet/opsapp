//
//  GuidedCatalogSetupTierTests.swift
//  OPSTests
//
//  Pure tier-derivation math (base = lowest tier, add_flat deltas, default tier),
//  plus a resolver round-trip proving the written option/value/modifier shape
//  prices each tier exactly as the estimate builder will.
//

import XCTest
@testable import OPS

final class GuidedCatalogSetupTierTests: XCTestCase {

    private typealias TierSpec = GuidedCatalogSetupModel.TierSpec

    // MARK: - Derivation

    func test_tierSpec_baseIsLowest_deltasFromBase() throws {
        let tiers = ProductLineTiers(axisName: "Size", rows: [
            ProductTierRow(label: "Sedan", priceText: "180"),
            ProductTierRow(label: "SUV",   priceText: "230"),
            ProductTierRow(label: "Truck", priceText: "280"),
        ])
        let spec = TierSpec.derive(from: tiers, parseMoney: { Double($0) })!
        XCTAssertEqual(spec.axisName, "Size")
        XCTAssertEqual(spec.basePrice, 180, accuracy: 0.001)            // lowest tier
        XCTAssertEqual(spec.defaultLabel, "Sedan")                      // lowest tier label
        XCTAssertEqual(spec.values.map(\.label), ["Sedan", "SUV", "Truck"]) // entry order
        XCTAssertEqual(spec.values.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(spec.modifiers.count, 2)                         // non-default tiers only
        let suvDelta = try XCTUnwrap(spec.modifiers.first { $0.label == "SUV" }?.delta)
        let truckDelta = try XCTUnwrap(spec.modifiers.first { $0.label == "Truck" }?.delta)
        XCTAssertEqual(suvDelta, 50, accuracy: 0.001)
        XCTAssertEqual(truckDelta, 100, accuracy: 0.001)
    }

    func test_tierSpec_singleValidRow_returnsNil_degradesToFlat() {
        let tiers = ProductLineTiers(axisName: "Size", rows: [
            ProductTierRow(label: "Standard", priceText: "99"),
            ProductTierRow(label: "", priceText: ""),          // blank row dropped
        ])
        XCTAssertNil(TierSpec.derive(from: tiers, parseMoney: { Double($0) }))
    }

    func test_tierSpec_emptyAxisName_fallsBackToOption() {
        let tiers = ProductLineTiers(axisName: "  ", rows: [
            ProductTierRow(label: "A", priceText: "10"),
            ProductTierRow(label: "B", priceText: "20"),
        ])
        XCTAssertEqual(TierSpec.derive(from: tiers, parseMoney: { Double($0) })?.axisName, "Option")
    }

    func test_tierSpec_outOfOrderEntry_baseStillLowest() throws {
        let tiers = ProductLineTiers(axisName: "Grade", rows: [
            ProductTierRow(label: "Premium", priceText: "400"),
            ProductTierRow(label: "Basic",   priceText: "250"),
        ])
        let spec = TierSpec.derive(from: tiers, parseMoney: { Double($0) })!
        XCTAssertEqual(spec.basePrice, 250, accuracy: 0.001)
        XCTAssertEqual(spec.defaultLabel, "Basic")
        XCTAssertEqual(spec.modifiers.count, 1)                         // only Premium bumps up
        XCTAssertEqual(spec.modifiers.first?.label, "Premium")
        let premiumDelta = try XCTUnwrap(spec.modifiers.first?.delta)
        XCTAssertEqual(premiumDelta, 150, accuracy: 0.001)
    }

    // MARK: - Resolver round-trip (the estimate builder consumes the written shape)

    /// Builds the exact in-memory option/value/modifier graph `saveTieredProductLine`
    /// writes (base = lowest tier, one add_flat modifier per non-default tier, each
    /// pinned to its value id) and asserts `ProductConfigurationResolver` prices each
    /// tier exactly. This is the gate: setup-written tiers price correctly on estimates.
    func test_resolver_pricesEachTier_fromTierSpecShape() {
        let product = Product(id: "p", companyId: "c", name: "Full Detail",
                              basePrice: 180, pricingUnit: .flatRate)
        let option = ProductOption(id: "o", productId: "p", name: "Size", kind: .select,
                                   affectsPrice: true, required: true, defaultValue: "Sedan")
        let sedan = ProductOptionValue(id: "v1", optionId: "o", value: "Sedan", sortOrder: 0)
        let suv   = ProductOptionValue(id: "v2", optionId: "o", value: "SUV", sortOrder: 1)
        let truck = ProductOptionValue(id: "v3", optionId: "o", value: "Truck", sortOrder: 2)
        let mSUV   = ProductPricingModifier(productId: "p", optionId: "o", triggerValueId: "v2",
                                            modifierKind: .addFlat, amount: 50)
        let mTruck = ProductPricingModifier(productId: "p", optionId: "o", triggerValueId: "v3",
                                            modifierKind: .addFlat, amount: 100)
        let resolver = ProductConfigurationResolver()

        func price(_ valueId: String) -> Double {
            resolver.resolve(product: product, options: [option],
                             optionValues: [sedan, suv, truck], modifiers: [mSUV, mTruck],
                             configured: ["o": .selectId(valueId)]).unitPrice
        }
        XCTAssertEqual(price("v1"), 180, accuracy: 0.001) // Sedan = base, no modifier fires
        XCTAssertEqual(price("v2"), 230, accuracy: 0.001) // SUV   = base + 50
        XCTAssertEqual(price("v3"), 280, accuracy: 0.001) // Truck = base + 100

        // The chosen tier's label is what shows on the estimate row (T6).
        let label = resolver.resolve(product: product, options: [option],
            optionValues: [sedan, suv, truck], modifiers: [mSUV, mTruck],
            configured: ["o": .selectId("v2")]).label
        XCTAssertEqual(label, "SUV")
    }
}
