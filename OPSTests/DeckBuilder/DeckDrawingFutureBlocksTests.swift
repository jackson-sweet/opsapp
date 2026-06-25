import XCTest
@testable import OPS

final class DeckDrawingFutureBlocksTests: XCTestCase {
    func testUnknownFutureBlocksRoundTripThroughDeckDrawingData() throws {
        let json = """
        {
          "vertices": [],
          "edges": [],
          "framing": {
            "version": 1,
            "members": [{"id": "j1", "kind": "joist", "span": 144}]
          },
          "parcelZoning": {
            "apn": "PID-123",
            "findings": [{"severity": "warning", "code": "REAR_SETBACK_CONCERN"}]
          },
          "codeOverlay": {
            "enabled": true,
            "findings": [{"elementId": "j1", "severity": "violation"}]
          },
          "rendering": {
            "engine": "realitykit",
            "preset": "client_hero"
          }
        }
        """

        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(json))
        let encoded = decoded.toJSON()

        XCTAssertTrue(encoded.contains("\"framing\""))
        XCTAssertTrue(encoded.contains("\"parcelZoning\""))
        XCTAssertTrue(encoded.contains("\"codeOverlay\""))
        XCTAssertTrue(encoded.contains("\"rendering\""))
        XCTAssertTrue(encoded.contains("REAR_SETBACK_CONCERN"))
    }
}
