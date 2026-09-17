//
//  ProductOptionDefaultPolicyTests.swift
//  OPSTests
//
//  An integer count option has no default. A count is the job's geometry (end
//  posts, corners): the estimate editors never fill one from the catalogue and
//  acceptance refuses a blank one, so the option form must not offer a default
//  that nothing honours — and saving a count option clears any default it still
//  carries. Select and boolean options keep theirs. Mirrors ops-web's product
//  option form (2026-09-17).
//

import XCTest
@testable import OPS

final class ProductOptionDefaultPolicyTests: XCTestCase {

    func test_offersDefault_forSelectAndBoolean_neverForACount() {
        XCTAssertTrue(ProductOptionDefaultPolicy.offersDefault(for: .select))
        XCTAssertTrue(ProductOptionDefaultPolicy.offersDefault(for: .boolean))
        XCTAssertFalse(ProductOptionDefaultPolicy.offersDefault(for: .integer))
    }

    func test_savedDefault_clearsAnyDefaultOnACount() {
        for draft in ["1", "0", " 3 ", "", "abc"] {
            XCTAssertNil(
                ProductOptionDefaultPolicy.savedDefault(draft, kind: .integer),
                "a count option must save with no default, not \(draft)"
            )
        }
    }

    func test_savedDefault_keepsATrimmedDefaultForSelectAndBoolean() {
        XCTAssertEqual(ProductOptionDefaultPolicy.savedDefault("  Black ", kind: .select), "Black")
        XCTAssertEqual(ProductOptionDefaultPolicy.savedDefault("true", kind: .boolean), "true")
        XCTAssertNil(ProductOptionDefaultPolicy.savedDefault("   ", kind: .select))
    }

    func test_displayedDefault_hidesAStoredDefaultOnACount() {
        let count = ProductOption(productId: "p", name: "Left ends", kind: .integer, defaultValue: "1")
        let select = ProductOption(productId: "p", name: "Color", kind: .select, defaultValue: "Black")
        let blankSelect = ProductOption(productId: "p", name: "Mount", kind: .select, defaultValue: "  ")

        XCTAssertNil(ProductOptionDefaultPolicy.displayedDefault(for: count))
        XCTAssertEqual(ProductOptionDefaultPolicy.displayedDefault(for: select), "Black")
        XCTAssertNil(ProductOptionDefaultPolicy.displayedDefault(for: blankSelect))
    }

    /// The update PATCH must send `default_value: null` for a count, so a
    /// default already stored on the option is cleared, not left in place.
    func test_updateDTO_sendsAnExplicitNullDefault_forACount() throws {
        let dto = UpdateProductOptionDTO(
            name: "Left ends",
            kind: ProductOptionKind.integer.rawValue,
            affectsPrice: false,
            affectsRecipe: true,
            required: true,
            defaultValue: ProductOptionDefaultPolicy.savedDefault("1", kind: .integer),
            optionDefaultSource: nil,
            sortOrder: 50
        )

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(dto)) as? [String: Any]
        )
        XCTAssertTrue(body.keys.contains("default_value"), "the key must be present to clear the stored default")
        XCTAssertTrue(body["default_value"] is NSNull)
    }
}
