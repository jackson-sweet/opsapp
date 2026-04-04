// OPS/OPSTests/DeckBuilder/AccuracyModelTests.swift

import XCTest
@testable import OPS

final class AccuracyModelTests: XCTestCase {

    func testEstimateAccuracy_shortDistance() {
        XCTAssertEqual(AccuracyModel.estimateAccuracy(distanceMeters: 0.5), 1.0)
        XCTAssertEqual(AccuracyModel.estimateAccuracy(distanceMeters: 2.0), 1.5)
    }

    func testEstimateAccuracy_mediumDistance() {
        XCTAssertEqual(AccuracyModel.estimateAccuracy(distanceMeters: 5.0), 2.5)
        XCTAssertEqual(AccuracyModel.estimateAccuracy(distanceMeters: 12.0), 3.0)
    }

    func testEstimateAccuracy_longDistance() {
        XCTAssertEqual(AccuracyModel.estimateAccuracy(distanceMeters: 20.0), 4.0)
    }

    func testFormatAccuracy_imperial_inches() {
        // 192" (16') at ±3% = ±5.76" ≈ "±6\""
        let result = AccuracyModel.formatAccuracy(dimensionInches: 192, accuracyPercent: 3.0)
        XCTAssertEqual(result, "±6\"")
    }

    func testFormatAccuracy_imperial_feet() {
        // 480" (40') at ±4% = ±19.2" > 12" → "±1.6'"
        let result = AccuracyModel.formatAccuracy(dimensionInches: 480, accuracyPercent: 4.0)
        XCTAssertEqual(result, "±1.6'")
    }

    func testAreaAccuracy_twoEdges() {
        let acc = AccuracyModel.areaAccuracy(edgeAccuracies: [(288, 3.0), (192, 3.0)])
        XCTAssertEqual(acc, 6.0) // ±6% for area
    }

    func testPerimeterAccuracy_uniform() {
        // All edges same accuracy → perimeter accuracy = same
        let acc = AccuracyModel.perimeterAccuracy(edgeAccuracies: [(288, 3.0), (192, 3.0), (288, 3.0), (192, 3.0)])
        XCTAssertEqual(acc, 3.0, accuracy: 0.01)
    }

    func testPostCountError() {
        // 192" at ±3% with 60" spacing: nominal = 4 posts, max = 198" → 4 posts. Error = 0
        let error = AccuracyModel.postCountError(edgeLengthInches: 192, accuracyPercent: 3.0, maxSpacing: 60)
        XCTAssertLessThanOrEqual(error, 1)
    }

    func testAllEdgesVerified_true() {
        var data = DeckDrawingData()
        var edge = DeckEdge(startVertexId: "a", endVertexId: "b")
        edge.accuracyPercent = nil
        data.edges = [edge]
        XCTAssertTrue(AccuracyModel.allEdgesVerified(data))
    }

    func testAllEdgesVerified_false() {
        var data = DeckDrawingData()
        var edge = DeckEdge(startVertexId: "a", endVertexId: "b")
        edge.accuracyPercent = 3.0
        data.edges = [edge]
        XCTAssertFalse(AccuracyModel.allEdgesVerified(data))
    }
}
