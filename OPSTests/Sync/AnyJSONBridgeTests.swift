//
//  AnyJSONBridgeTests.swift
//  OPSTests
//
//  Bug bb3c2b5c — outbound pushes flattened every JSON boolean to 0/1.
//  Payloads reach the push bridge as JSONSerialization output, where true/false
//  are CFBoolean instances that satisfy `as? Int`. A converter that matched Int
//  first turned every boolean into a number; native `boolean` columns coerced it
//  back, but inside `jsonb` blobs it stuck and broke strict Bool decodes.
//

import XCTest
import Supabase
@testable import OPS

final class AnyJSONBridgeTests: XCTestCase {

    /// The exact shape the bug produced: booleans arriving from
    /// `JSONSerialization` must stay booleans, at every nesting depth, without
    /// dragging honest numbers along with them.
    func test_serializedPayloadPreservesBooleansAtEveryDepth() throws {
        let source = """
        {"a":true,"b":false,"c":1,"d":0,"e":3.5,"f":"x","g":[true,0],"h":{"i":false}}
        """
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(source.utf8)
            ) as? [String: Any]
        )

        let fields = AnyJSONBridge.payload(payload)

        XCTAssertEqual(fields["a"], .bool(true))
        XCTAssertEqual(fields["b"], .bool(false))
        XCTAssertEqual(fields["c"], .integer(1))
        XCTAssertEqual(fields["d"], .integer(0))
        XCTAssertEqual(fields["e"], .double(3.5))
        XCTAssertEqual(fields["f"], .string("x"))
        XCTAssertEqual(fields["g"], .array([.bool(true), .integer(0)]))
        XCTAssertEqual(fields["h"], .object(["i": .bool(false)]))
    }

    /// The corruption proven in production: `drawing_data.vinylOrderSettings`
    /// stored `allowsDirectionalChanges` as a number on every row.
    func test_nestedDrawingBlobKeepsBooleanTyping() throws {
        let source = """
        {"drawing_data":{"vinylOrderSettings":{"allowsDirectionalChanges":true,
        "rollWidthInches":72},"config":{"gridVisible":false}}}
        """
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(source.utf8)
            ) as? [String: Any]
        )

        let fields = AnyJSONBridge.payload(payload)

        guard case .object(let drawing)? = fields["drawing_data"],
              case .object(let vinyl)? = drawing["vinylOrderSettings"],
              case .object(let config)? = drawing["config"] else {
            return XCTFail("drawing_data did not survive as nested objects")
        }
        XCTAssertEqual(vinyl["allowsDirectionalChanges"], .bool(true))
        XCTAssertEqual(vinyl["rollWidthInches"], .integer(72))
        XCTAssertEqual(config["gridVisible"], .bool(false))
    }

    /// The CFBoolean guard must not capture ordinary numbers: an NSNumber 1 is
    /// `as? Bool`-castable, and a fractional NSNumber must still reach `.double`.
    func test_numbersAreNotPromotedToBooleans() {
        XCTAssertEqual(AnyJSONBridge.json(NSNumber(value: 1)), .integer(1))
        XCTAssertEqual(AnyJSONBridge.json(NSNumber(value: 0)), .integer(0))
        XCTAssertEqual(AnyJSONBridge.json(NSNumber(value: 3.5)), .double(3.5))
        XCTAssertEqual(AnyJSONBridge.json(NSNumber(value: true)), .bool(true))
        XCTAssertEqual(AnyJSONBridge.json(NSNumber(value: false)), .bool(false))
    }

    /// Swift-native values (the non-serialized call sites) keep their mapping.
    func test_nativeSwiftValuesMapUnchanged() {
        XCTAssertEqual(AnyJSONBridge.json(true), .bool(true))
        XCTAssertEqual(AnyJSONBridge.json(false), .bool(false))
        XCTAssertEqual(AnyJSONBridge.json(7), .integer(7))
        XCTAssertEqual(AnyJSONBridge.json(2.25), .double(2.25))
        XCTAssertEqual(AnyJSONBridge.json("ops"), .string("ops"))
        XCTAssertEqual(AnyJSONBridge.json(NSNull()), .null)
    }
}
