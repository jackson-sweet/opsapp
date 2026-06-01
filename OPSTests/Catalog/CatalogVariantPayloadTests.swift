//
//  CatalogVariantPayloadTests.swift
//  OPSTests
//
//  Regression coverage for variant edit payload construction.
//

import XCTest
@testable import OPS

final class CatalogVariantPayloadTests: XCTestCase {

    func testUpdatePayloadClearsSkuWhenFieldIsBlank() throws {
        let payload = CatalogVariantFormPayload.update(
            skuText: "   ",
            quantity: 4,
            priceOverride: nil,
            unitCostOverride: nil,
            warningThresholdText: "",
            criticalThresholdText: "",
            unitId: nil
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertTrue(json?.keys.contains("sku") == true)
        XCTAssertTrue(json?["sku"] is NSNull)
    }

    func testUpdatePayloadKeepsSkuWhenFieldHasValue() throws {
        let payload = CatalogVariantFormPayload.update(
            skuText: "  OPS-42  ",
            quantity: 4,
            priceOverride: nil,
            unitCostOverride: nil,
            warningThresholdText: "",
            criticalThresholdText: "",
            unitId: nil
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["sku"] as? String, "OPS-42")
    }
}
