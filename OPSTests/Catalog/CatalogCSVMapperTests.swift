//
//  CatalogCSVMapperTests.swift
//  OPSTests
//
//  Coverage for the parsed-rows → CatalogImportPayload mapper. Focus
//  is on the family grouping behaviour, the soft category/unit
//  resolution, and the local validation layer that runs before any
//  network call.
//

import XCTest
@testable import OPS

final class CatalogCSVMapperTests: XCTestCase {

    private let categories: [(id: String, name: String)] = [
        (id: "cat-decking", name: "Decking"),
        (id: "cat-railing", name: "Railing"),
    ]
    private let units: [(id: String, display: String)] = [
        (id: "unit-ea", display: "ea"),
        (id: "unit-ft", display: "ft"),
    ]

    private func defaultMapping() -> CatalogImportColumnMapping {
        var m = CatalogImportColumnMapping()
        m.familyName = "family_name"
        m.quantity = "quantity"
        m.sku = "sku"
        m.category = "category"
        m.defaultUnit = "unit"
        m.defaultPrice = "price"
        return m
    }

    func test_happyPath_groupsVariantsIntoFamilies() {
        let rows: [[String: String]] = [
            ["family_name": "Cedar 5/4x6", "sku": "CDR-8", "quantity": "12", "category": "Decking", "unit": "ea", "price": "8.50"],
            ["family_name": "Cedar 5/4x6", "sku": "CDR-10", "quantity": "8", "category": "Decking", "unit": "ea", "price": "8.50"],
            ["family_name": "Cedar 2x6", "sku": "CDR-2-8", "quantity": "5", "category": "Decking", "unit": "ea", "price": "12.00"],
        ]
        let result = CatalogCSVMapper.map(
            rows: rows,
            lineNumbers: [2, 3, 4],
            mapping: defaultMapping(),
            categories: categories,
            units: units
        )
        XCTAssertEqual(result.errors.count, 0)
        let payload = try? XCTUnwrap(result.payload)
        XCTAssertEqual(payload?.families.count, 2)
        XCTAssertEqual(payload?.variants.count, 3)
        XCTAssertEqual(payload?.variants[0].familyRowIndex, 0)
        XCTAssertEqual(payload?.variants[1].familyRowIndex, 0)
        XCTAssertEqual(payload?.variants[2].familyRowIndex, 1)
        XCTAssertEqual(payload?.families[0].categoryId, "cat-decking")
        XCTAssertEqual(payload?.families[0].defaultUnitId, "unit-ea")
        XCTAssertEqual(payload?.families[0].defaultPrice, 8.5)
    }

    func test_missingRequiredMapping_returnsError() {
        var m = CatalogImportColumnMapping()
        m.quantity = "quantity"
        let result = CatalogCSVMapper.map(
            rows: [["family_name": "X", "quantity": "1"]],
            lineNumbers: [2],
            mapping: m,
            categories: [],
            units: []
        )
        XCTAssertNil(result.payload)
        XCTAssertTrue(result.errors.contains { $0.field == "family_name" })
    }

    func test_blankFamilyName_isFlagged() {
        let rows: [[String: String]] = [
            ["family_name": "", "quantity": "1"],
        ]
        var m = CatalogImportColumnMapping()
        m.familyName = "family_name"
        m.quantity = "quantity"
        let result = CatalogCSVMapper.map(
            rows: rows, lineNumbers: [2],
            mapping: m, categories: [], units: []
        )
        XCTAssertNil(result.payload)
        XCTAssertEqual(result.errors.first?.field, "family_name")
    }

    func test_unknownCategory_isFlaggedWithLineNumber() {
        let rows: [[String: String]] = [
            ["family_name": "X", "quantity": "1", "category": "Mystery"],
        ]
        var m = CatalogImportColumnMapping()
        m.familyName = "family_name"
        m.quantity = "quantity"
        m.category = "category"
        let result = CatalogCSVMapper.map(
            rows: rows, lineNumbers: [42],
            mapping: m,
            categories: categories,
            units: units
        )
        XCTAssertNil(result.payload)
        let categoryErrors = result.errors.filter { $0.field == "category" }
        XCTAssertEqual(categoryErrors.count, 1)
        XCTAssertTrue(categoryErrors[0].reason.contains("42"))
        XCTAssertTrue(categoryErrors[0].reason.contains("Mystery"))
    }

    func test_negativeQuantity_isFlagged() {
        let rows: [[String: String]] = [
            ["family_name": "X", "quantity": "-5"],
        ]
        var m = CatalogImportColumnMapping()
        m.familyName = "family_name"
        m.quantity = "quantity"
        let result = CatalogCSVMapper.map(
            rows: rows, lineNumbers: [2],
            mapping: m, categories: [], units: []
        )
        XCTAssertNil(result.payload)
        XCTAssertTrue(result.errors.contains { $0.field == "quantity" })
    }

    func test_currencyAndCommas_inNumericFields_areTolerated() {
        let rows: [[String: String]] = [
            ["family_name": "X", "quantity": "1,200", "price": "$8.50"],
        ]
        var m = CatalogImportColumnMapping()
        m.familyName = "family_name"
        m.quantity = "quantity"
        m.defaultPrice = "price"
        let result = CatalogCSVMapper.map(
            rows: rows, lineNumbers: [2],
            mapping: m, categories: [], units: []
        )
        XCTAssertEqual(result.errors.count, 0)
        XCTAssertEqual(result.payload?.variants.first?.quantity, 1200)
        XCTAssertEqual(result.payload?.families.first?.defaultPrice, 8.5)
    }

    func test_categoryLookupIsCaseInsensitive() {
        let rows: [[String: String]] = [
            ["family_name": "X", "quantity": "1", "category": "DECKING"],
        ]
        var m = CatalogImportColumnMapping()
        m.familyName = "family_name"
        m.quantity = "quantity"
        m.category = "category"
        let result = CatalogCSVMapper.map(
            rows: rows, lineNumbers: [2],
            mapping: m, categories: categories, units: []
        )
        XCTAssertEqual(result.errors.count, 0)
        XCTAssertEqual(result.payload?.families.first?.categoryId, "cat-decking")
    }

    func test_columnAutoSuggest_picksReasonableDefaults() {
        let headers = ["Family Name", "SKU", "Qty", "Description", "Unit", "Price"]
        let m = CatalogImportColumnMapping.suggest(from: headers)
        XCTAssertEqual(m.familyName, "Family Name")
        XCTAssertEqual(m.sku, "SKU")
        XCTAssertEqual(m.quantity, "Qty")
        XCTAssertEqual(m.familyDescription, "Description")
        XCTAssertEqual(m.defaultUnit, "Unit")
        XCTAssertEqual(m.defaultPrice, "Price")
    }
}
