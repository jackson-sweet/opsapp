//
//  CatalogSetupWorkflowValidationTests.swift
//  OPSTests
//
//  Tests for the guided-flow positive-quantity guard.
//  Advanced flow keeps its lenient max(0,…); these tests cover the stricter
//  CatalogSetupWorkflow.validateStockQuantities path that guided commits use.
//

import XCTest
@testable import OPS

final class CatalogSetupWorkflowValidationTests: XCTestCase {

    // MARK: - Helpers

    private func variant(qty: Double, enabled: Bool = true) -> CatalogSetupVariantDraft {
        CatalogSetupVariantDraft(
            optionValueIds: [],
            stockUnits: [CatalogSetupStockUnitDraft(quantityValue: qty)],
            isEnabled: enabled
        )
    }

    // MARK: - Zero quantity throws

    func test_validateStockQuantities_throwsOnZero() {
        let v = variant(qty: 0)
        let expectedId = v.stockUnits[0].id
        XCTAssertThrowsError(
            try CatalogSetupWorkflow.validateStockQuantities(variants: [v])
        ) { error in
            XCTAssertEqual(
                error as? CatalogSetupStockValidationError,
                .nonPositiveStockQuantity(stockUnitClientId: expectedId)
            )
        }
    }

    // MARK: - Negative quantity throws

    func test_validateStockQuantities_throwsOnNegative() {
        XCTAssertThrowsError(
            try CatalogSetupWorkflow.validateStockQuantities(variants: [variant(qty: -3)])
        )
    }

    // MARK: - Positive quantity passes

    func test_validateStockQuantities_passesOnPositive() {
        XCTAssertNoThrow(
            try CatalogSetupWorkflow.validateStockQuantities(variants: [variant(qty: 1)])
        )
    }

    func test_validateStockQuantities_passesOnFractionalPositive() {
        XCTAssertNoThrow(
            try CatalogSetupWorkflow.validateStockQuantities(variants: [variant(qty: 0.001)])
        )
    }

    // MARK: - Disabled variants are ignored

    func test_validateStockQuantities_ignoresDisabledVariants() {
        XCTAssertNoThrow(
            try CatalogSetupWorkflow.validateStockQuantities(variants: [variant(qty: 0, enabled: false)])
        )
    }

    // MARK: - Variant with no stock units passes

    func test_validateStockQuantities_passesWhenNoStockUnits() {
        XCTAssertNoThrow(
            try CatalogSetupWorkflow.validateStockQuantities(
                variants: [CatalogSetupVariantDraft(optionValueIds: [])]
            )
        )
    }

    // MARK: - Mixed: first violating unit is reported

    func test_validateStockQuantities_multipleVariants_throwsOnFirst() {
        let good = variant(qty: 5)
        let bad = variant(qty: 0)
        let expectedId = bad.stockUnits[0].id
        XCTAssertThrowsError(
            try CatalogSetupWorkflow.validateStockQuantities(variants: [good, bad])
        ) { error in
            XCTAssertEqual(
                error as? CatalogSetupStockValidationError,
                .nonPositiveStockQuantity(stockUnitClientId: expectedId)
            )
        }
    }
}
