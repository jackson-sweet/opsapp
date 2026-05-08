//
//  CSVParserTests.swift
//  OPSTests
//
//  Coverage for the RFC 4180-ish CSV parser used by the catalog
//  import flow. Focus is on the edge cases that real spreadsheets
//  produce: quoted fields, embedded commas + quotes, mixed line
//  endings, and the field-count / unterminated-quote error paths.
//

import XCTest
@testable import OPS

final class CSVParserTests: XCTestCase {

    func test_happyPath_parsesHeadersAndRows() throws {
        let csv = """
        family_name,sku,quantity
        Cedar 5/4x6,CDR-5-4-6,124
        Cedar 2x6,CDR-2-6,82
        """
        let r = try CSVParser.parse(csv)
        XCTAssertEqual(r.headers, ["family_name", "sku", "quantity"])
        XCTAssertEqual(r.rows.count, 2)
        XCTAssertEqual(r.rows[0]["family_name"], "Cedar 5/4x6")
        XCTAssertEqual(r.rows[0]["sku"], "CDR-5-4-6")
        XCTAssertEqual(r.rows[1]["quantity"], "82")
        XCTAssertEqual(r.lineNumbers, [2, 3])
    }

    func test_quotedFields_withEmbeddedComma_andEscapedQuote() throws {
        let csv = """
        name,description
        "Cedar, 5/4x6","Premium ""rough"" face"
        """
        let r = try CSVParser.parse(csv)
        XCTAssertEqual(r.rows.count, 1)
        XCTAssertEqual(r.rows[0]["name"], "Cedar, 5/4x6")
        XCTAssertEqual(r.rows[0]["description"], "Premium \"rough\" face")
    }

    func test_crlfLineEndings_workIdentically() throws {
        let csv = "a,b\r\n1,2\r\n3,4\r\n"
        let r = try CSVParser.parse(csv)
        XCTAssertEqual(r.headers, ["a", "b"])
        XCTAssertEqual(r.rows.count, 2)
        XCTAssertEqual(r.rows[0]["a"], "1")
        XCTAssertEqual(r.rows[1]["b"], "4")
    }

    func test_loneCRLineEndings_workIdentically() throws {
        let csv = "a,b\r1,2\r3,4"
        let r = try CSVParser.parse(csv)
        XCTAssertEqual(r.rows.count, 2)
        XCTAssertEqual(r.rows[1]["a"], "3")
    }

    func test_utf8BOM_isStripped() throws {
        let bom = "\u{FEFF}"
        let csv = "\(bom)a,b\n1,2\n"
        let r = try CSVParser.parse(csv)
        XCTAssertEqual(r.headers, ["a", "b"])
        XCTAssertEqual(r.rows.first?["a"], "1")
    }

    func test_emptyTrailingRow_isSkipped() throws {
        let csv = "a,b\n1,2\n\n"
        let r = try CSVParser.parse(csv)
        XCTAssertEqual(r.rows.count, 1)
    }

    func test_rowFieldCountMismatch_throws() {
        let csv = "a,b,c\n1,2\n"
        XCTAssertThrowsError(try CSVParser.parse(csv)) { error in
            guard let parseError = error as? CSVParseError,
                  case let .rowFieldCountMismatch(line, expected, actual) = parseError
            else { return XCTFail("expected rowFieldCountMismatch") }
            XCTAssertEqual(line, 2)
            XCTAssertEqual(expected, 3)
            XCTAssertEqual(actual, 2)
        }
    }

    func test_unterminatedQuote_throws() {
        let csv = "a,b\n\"oops,still going\n"
        XCTAssertThrowsError(try CSVParser.parse(csv)) { error in
            guard let parseError = error as? CSVParseError,
                  case .unterminatedQuote = parseError
            else { return XCTFail("expected unterminatedQuote") }
        }
    }

    func test_emptyInput_throws() {
        XCTAssertThrowsError(try CSVParser.parse("")) { error in
            guard let parseError = error as? CSVParseError,
                  case .empty = parseError
            else { return XCTFail("expected empty") }
        }
    }

    func test_headerWhitespace_isTrimmed() throws {
        let csv = "  family_name  ,quantity\nA,1\n"
        let r = try CSVParser.parse(csv)
        XCTAssertEqual(r.headers, ["family_name", "quantity"])
        XCTAssertEqual(r.rows[0]["family_name"], "A")
    }
}
