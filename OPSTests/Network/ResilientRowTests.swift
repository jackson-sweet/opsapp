//
//  ResilientRowTests.swift
//  OPSTests
//
//  Verifies that ResilientRow decoding drops a single undecodable row instead
//  of failing the whole batch — the guarantee that keeps one corrupt row from
//  blacking out an entire entity's inbound sync (the crew deck-blackout class).
//

import XCTest
@testable import OPS

final class ResilientRowTests: XCTestCase {

    private struct Sample: Codable, Equatable {
        let id: String
        let n: Int
    }

    private func decode(_ json: String) -> [Sample] {
        let data = Data(json.utf8)
        let rows = (try? JSONDecoder().decode([ResilientRow<Sample>].self, from: data)) ?? []
        return rows.compactMap(\.value)
    }

    func test_skipsACorruptRowAndKeepsTheValidOnes() {
        // Middle row has a type-mismatched `n` (string, not int) — it must drop,
        // and the two valid rows bracketing it must both survive in order.
        let json = """
        [
          {"id":"aaa","n":1},
          {"id":"bad","n":"not-an-int"},
          {"id":"bbb","n":2}
        ]
        """
        let result = decode(json)
        XCTAssertEqual(result, [Sample(id: "aaa", n: 1), Sample(id: "bbb", n: 2)])
    }

    func test_dropsARowMissingARequiredField() {
        let json = """
        [
          {"id":"aaa","n":1},
          {"id":"missing-n"},
          {"id":"bbb","n":2}
        ]
        """
        let result = decode(json)
        XCTAssertEqual(result.map(\.id), ["aaa", "bbb"])
    }

    func test_keepsEveryRowWhenAllAreValid() {
        let json = """
        [{"id":"aaa","n":1},{"id":"bbb","n":2},{"id":"ccc","n":3}]
        """
        XCTAssertEqual(decode(json).count, 3)
    }

    func test_returnsEmptyForAnEmptyArray() {
        XCTAssertEqual(decode("[]").count, 0)
    }

    func test_allRowsCorruptYieldsEmptyNotThrow() {
        let json = """
        [{"id":1,"n":"x"},{"nope":true}]
        """
        XCTAssertEqual(decode(json).count, 0)
    }
}
