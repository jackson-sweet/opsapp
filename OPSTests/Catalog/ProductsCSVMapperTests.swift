//
//  ProductsCSVMapperTests.swift
//  OPSTests
//
//  Coverage for the parsed-rows → ProductsImportPayload mapper. Focus
//  is on the flat product structure (no family grouping), the typed
//  category/unit FK resolution, and the local validation layer that
//  runs before any network call.
//

import XCTest
@testable import OPS

final class ProductsCSVMapperTests: XCTestCase {

    private let categories: [(id: String, name: String)] = [
        (id: "cat-hardware", name: "Hardware"),
        (id: "cat-labor", name: "Labor"),
    ]
    private let units: [(id: String, display: String)] = [
        (id: "unit-ea", display: "ea"),
        (id: "unit-sqft", display: "sqft"),
        (id: "unit-hour", display: "hour"),
    ]

    private func defaultMapping() -> ProductsImportColumnMapping {
        var m = ProductsImportColumnMapping()
        m.name = "name"
        m.basePrice = "base_price"
        m.unitCost = "unit_cost"
        m.category = "category"
        m.unit = "unit"
        m.sku = "sku"
        m.description = "description"
        m.kind = "kind"
        m.type = "type"
        return m
    }

    // MARK: - Happy path

    func test_happyPath_buildsOneProductPerRow() throws {
        let rows: [[String: String]] = [
            ["name": "Composite deck install", "base_price": "25.00", "unit_cost": "12.00",
             "category": "Labor", "unit": "sqft", "sku": "DECK-INST",
             "description": "Per-sqft labor", "kind": "service", "type": "LABOR"],
            ["name": "Cedar 5/4x6 board", "base_price": "8.50", "unit_cost": "5.00",
             "category": "Hardware", "unit": "ea", "sku": "CDR-548",
             "description": "", "kind": "good", "type": "MATERIAL"],
            ["name": "Site visit", "base_price": "150", "unit_cost": "",
             "category": "", "unit": "hour", "sku": "",
             "description": "", "kind": "service", "type": "OTHER"],
        ]
        let result = ProductsCSVMapper.map(
            rows: rows,
            lineNumbers: [2, 3, 4],
            mapping: defaultMapping(),
            categories: categories,
            units: units
        )
        XCTAssertEqual(result.errors.count, 0, "errors: \(result.errors)")
        let payload = try XCTUnwrap(result.payload)
        XCTAssertEqual(payload.products.count, 3)

        let p0 = payload.products[0]
        XCTAssertEqual(p0.rowIndex, 0)
        XCTAssertEqual(p0.name, "Composite deck install")
        XCTAssertEqual(p0.basePrice, 25.0)
        XCTAssertEqual(p0.unitCost, 12.0)
        XCTAssertEqual(p0.categoryId, "cat-labor")
        XCTAssertEqual(p0.category, "Labor")
        XCTAssertEqual(p0.unitId, "unit-sqft")
        XCTAssertEqual(p0.unit, "sqft")
        XCTAssertEqual(p0.sku, "DECK-INST")
        XCTAssertEqual(p0.kind, "service")
        XCTAssertEqual(p0.type, "LABOR")
        XCTAssertEqual(p0.description, "Per-sqft labor")

        let p1 = payload.products[1]
        XCTAssertEqual(p1.categoryId, "cat-hardware")
        XCTAssertEqual(p1.unitId, "unit-ea")
        XCTAssertNil(p1.description, "blank description string should map to nil")

        let p2 = payload.products[2]
        XCTAssertNil(p2.unitCost, "blank unit_cost should map to nil")
        XCTAssertNil(p2.categoryId, "blank category should not error and remain nil")
        XCTAssertEqual(p2.unitId, "unit-hour")
        XCTAssertNil(p2.sku)

        XCTAssertEqual(result.productSourceLineNumbers, [2, 3, 4])
    }

    // MARK: - Required mapping

    func test_missingNameMapping_returnsError() {
        var m = ProductsImportColumnMapping()
        m.basePrice = "base_price"
        let result = ProductsCSVMapper.map(
            rows: [["name": "X", "base_price": "1"]],
            lineNumbers: [2],
            mapping: m,
            categories: [],
            units: []
        )
        XCTAssertNil(result.payload)
        XCTAssertTrue(result.errors.contains { $0.field == "name" })
    }

    func test_missingBasePriceMapping_returnsError() {
        var m = ProductsImportColumnMapping()
        m.name = "name"
        let result = ProductsCSVMapper.map(
            rows: [["name": "X", "base_price": "1"]],
            lineNumbers: [2],
            mapping: m,
            categories: [],
            units: []
        )
        XCTAssertNil(result.payload)
        XCTAssertTrue(result.errors.contains { $0.field == "base_price" })
    }

    func test_blankName_isFlagged() {
        let rows: [[String: String]] = [
            ["name": "", "base_price": "10"],
        ]
        var m = ProductsImportColumnMapping()
        m.name = "name"
        m.basePrice = "base_price"
        let result = ProductsCSVMapper.map(
            rows: rows, lineNumbers: [2],
            mapping: m, categories: [], units: []
        )
        XCTAssertNil(result.payload)
        XCTAssertEqual(result.errors.first?.field, "name")
    }

    func test_blankBasePrice_isFlaggedAsRequired() {
        let rows: [[String: String]] = [
            ["name": "Widget", "base_price": ""],
        ]
        var m = ProductsImportColumnMapping()
        m.name = "name"
        m.basePrice = "base_price"
        let result = ProductsCSVMapper.map(
            rows: rows, lineNumbers: [7],
            mapping: m, categories: [], units: []
        )
        XCTAssertNil(result.payload)
        let priceErrors = result.errors.filter { $0.field == "base_price" }
        XCTAssertEqual(priceErrors.count, 1)
        XCTAssertTrue(priceErrors[0].reason.contains("required"))
        XCTAssertTrue(priceErrors[0].reason.contains("7"))
    }

    func test_negativeBasePrice_isFlagged() {
        let rows: [[String: String]] = [
            ["name": "Widget", "base_price": "-5"],
        ]
        var m = ProductsImportColumnMapping()
        m.name = "name"
        m.basePrice = "base_price"
        let result = ProductsCSVMapper.map(
            rows: rows, lineNumbers: [2],
            mapping: m, categories: [], units: []
        )
        XCTAssertNil(result.payload)
        XCTAssertTrue(result.errors.contains {
            $0.field == "base_price" && $0.reason.contains("negative")
        })
    }

    // MARK: - FK fallbacks

    func test_unknownCategory_isFlaggedWithLineNumber() {
        let rows: [[String: String]] = [
            ["name": "Mystery item", "base_price": "10", "category": "Mystery"],
        ]
        var m = ProductsImportColumnMapping()
        m.name = "name"
        m.basePrice = "base_price"
        m.category = "category"
        let result = ProductsCSVMapper.map(
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

    func test_categoryLookupIsCaseInsensitive() {
        let rows: [[String: String]] = [
            ["name": "Hammer", "base_price": "10", "category": "HARDWARE"],
        ]
        var m = ProductsImportColumnMapping()
        m.name = "name"
        m.basePrice = "base_price"
        m.category = "category"
        let result = ProductsCSVMapper.map(
            rows: rows, lineNumbers: [2],
            mapping: m, categories: categories, units: []
        )
        XCTAssertEqual(result.errors.count, 0, "errors: \(result.errors)")
        XCTAssertEqual(result.payload?.products.first?.categoryId, "cat-hardware")
        XCTAssertEqual(result.payload?.products.first?.category, "HARDWARE",
                       "legacy category text preserves original casing")
    }

    func test_unknownUnit_isFlagged() {
        let rows: [[String: String]] = [
            ["name": "Foo", "base_price": "10", "unit": "weirdunit"],
        ]
        var m = ProductsImportColumnMapping()
        m.name = "name"
        m.basePrice = "base_price"
        m.unit = "unit"
        let result = ProductsCSVMapper.map(
            rows: rows, lineNumbers: [2],
            mapping: m, categories: categories, units: units
        )
        XCTAssertNil(result.payload)
        XCTAssertTrue(result.errors.contains { $0.field == "unit" })
    }

    // MARK: - Embedded quotes / currency

    func test_currencyAndCommas_inNumericFields_areTolerated() throws {
        let rows: [[String: String]] = [
            ["name": "Bulk service", "base_price": "$1,200.50", "unit_cost": "$800"],
        ]
        var m = ProductsImportColumnMapping()
        m.name = "name"
        m.basePrice = "base_price"
        m.unitCost = "unit_cost"
        let result = ProductsCSVMapper.map(
            rows: rows, lineNumbers: [2],
            mapping: m, categories: [], units: []
        )
        XCTAssertEqual(result.errors.count, 0, "errors: \(result.errors)")
        XCTAssertEqual(result.payload?.products.first?.basePrice, 1200.50)
        XCTAssertEqual(result.payload?.products.first?.unitCost, 800)
    }

    func test_embeddedQuotes_preserveDescriptionContents() throws {
        // Simulates what CSVParser produces for a quoted field with
        // embedded quotes: `"Premium ""rough"" face"` -> `Premium "rough" face`.
        let rows: [[String: String]] = [
            ["name": "Cedar", "base_price": "8.50",
             "description": "Premium \"rough\" face, FSC certified"],
        ]
        var m = ProductsImportColumnMapping()
        m.name = "name"
        m.basePrice = "base_price"
        m.description = "description"
        let result = ProductsCSVMapper.map(
            rows: rows, lineNumbers: [2],
            mapping: m, categories: [], units: []
        )
        XCTAssertEqual(result.errors.count, 0)
        XCTAssertEqual(
            result.payload?.products.first?.description,
            "Premium \"rough\" face, FSC certified"
        )
    }

    // MARK: - Enum normalization

    func test_kindAndType_areNormalized() throws {
        let rows: [[String: String]] = [
            ["name": "Lower", "base_price": "1", "kind": "Service", "type": "labor"],
            ["name": "Upper", "base_price": "1", "kind": "GOOD", "type": "Material"],
        ]
        var m = ProductsImportColumnMapping()
        m.name = "name"
        m.basePrice = "base_price"
        m.kind = "kind"
        m.type = "type"
        let result = ProductsCSVMapper.map(
            rows: rows, lineNumbers: [2, 3],
            mapping: m, categories: [], units: []
        )
        XCTAssertEqual(result.errors.count, 0)
        XCTAssertEqual(result.payload?.products[0].kind, "service")
        XCTAssertEqual(result.payload?.products[0].type, "LABOR")
        XCTAssertEqual(result.payload?.products[1].kind, "good")
        XCTAssertEqual(result.payload?.products[1].type, "MATERIAL")
    }

    func test_invalidKindOrType_isFlagged() {
        let rows: [[String: String]] = [
            ["name": "X", "base_price": "1", "kind": "thing", "type": "ZZZ"],
        ]
        var m = ProductsImportColumnMapping()
        m.name = "name"
        m.basePrice = "base_price"
        m.kind = "kind"
        m.type = "type"
        let result = ProductsCSVMapper.map(
            rows: rows, lineNumbers: [2],
            mapping: m, categories: [], units: []
        )
        XCTAssertNil(result.payload)
        XCTAssertTrue(result.errors.contains { $0.field == "kind" })
        XCTAssertTrue(result.errors.contains { $0.field == "type" })
    }

    func test_isTaxable_acceptsTruthyAndFalsyForms() throws {
        let rows: [[String: String]] = [
            ["name": "A", "base_price": "1", "is_taxable": "true"],
            ["name": "B", "base_price": "1", "is_taxable": "no"],
            ["name": "C", "base_price": "1", "is_taxable": ""],
        ]
        var m = ProductsImportColumnMapping()
        m.name = "name"
        m.basePrice = "base_price"
        m.isTaxable = "is_taxable"
        let result = ProductsCSVMapper.map(
            rows: rows, lineNumbers: [2, 3, 4],
            mapping: m, categories: [], units: []
        )
        XCTAssertEqual(result.errors.count, 0)
        XCTAssertEqual(result.payload?.products[0].isTaxable, true)
        XCTAssertEqual(result.payload?.products[1].isTaxable, false)
        XCTAssertNil(result.payload?.products[2].isTaxable, "blank should be nil (server default)")
    }

    // MARK: - Auto-suggest

    func test_columnAutoSuggest_picksReasonableDefaults() {
        let headers = ["Name", "Description", "Base Price", "Unit Cost",
                       "Category", "Unit", "SKU", "Kind", "Type"]
        let m = ProductsImportColumnMapping.suggest(from: headers)
        XCTAssertEqual(m.name, "Name")
        XCTAssertEqual(m.description, "Description")
        XCTAssertEqual(m.basePrice, "Base Price")
        XCTAssertEqual(m.unitCost, "Unit Cost")
        XCTAssertEqual(m.category, "Category")
        XCTAssertEqual(m.unit, "Unit")
        XCTAssertEqual(m.sku, "SKU")
    }

    // MARK: - Empty input

    func test_emptyRows_areFlagged() {
        let result = ProductsCSVMapper.map(
            rows: [],
            lineNumbers: [],
            mapping: defaultMapping(),
            categories: categories,
            units: units
        )
        XCTAssertNil(result.payload)
        XCTAssertTrue(result.errors.contains { $0.field == "rows" })
    }
}
