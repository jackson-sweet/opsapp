//
//  DeckDesignDrawingDataCacheTests.swift
//  OPSTests
//
//  Regression coverage for the pull-to-fullscreen watchdog crash. SwiftUI
//  re-evaluates deck availability throughout the pull gesture, so unchanged
//  persisted JSON must not be decoded again on every frame.
//

import XCTest
@testable import OPS

final class DeckDesignDrawingDataCacheTests: XCTestCase {

    func test_RepeatedReadsOfIdenticalJSON_decodeOnlyOnce() {
        let cache = DeckDrawingDataCache()
        var decodeCount = 0

        _ = cache.resolve(json: "stable-json") { _ in
            decodeCount += 1
            return DeckDrawingData()
        }
        _ = cache.resolve(json: "stable-json") { _ in
            decodeCount += 1
            return DeckDrawingData()
        }

        XCTAssertEqual(
            decodeCount,
            1,
            "an unchanged drawing must be decoded once across repeated SwiftUI body reads"
        )
    }

    func test_ReplacementJSON_invalidatesCachedDrawing() {
        let cache = DeckDrawingDataCache()
        var decodeCount = 0

        _ = cache.resolve(json: "first-json") { _ in
            decodeCount += 1
            return DeckDrawingData()
        }
        _ = cache.resolve(json: "replacement-json") { _ in
            decodeCount += 1
            return DeckDrawingData()
        }

        XCTAssertEqual(decodeCount, 2, "server replacements must never reuse stale geometry")
    }

    func test_DirectPersistedJSONReplacement_returnsFreshGeometry() {
        let triangle = makeClosedDrawing(vertexCount: 3)
        let square = makeClosedDrawing(vertexCount: 4)
        let design = DeckDesign(
            companyId: "test-company",
            projectId: "test-project",
            drawingDataJSON: triangle.toJSON()
        )

        XCTAssertEqual(design.drawingData.vertices.count, 3)

        // Sync applies server geometry directly to drawingDataJSON rather than
        // through the computed drawingData setter. The exact JSON cache key
        // must detect that path without requiring manual invalidation.
        design.drawingDataJSON = square.toJSON()

        XCTAssertEqual(design.drawingData.vertices.count, 4)
    }

    private func makeClosedDrawing(vertexCount: Int) -> DeckDrawingData {
        var drawing = DeckDrawingData()
        drawing.vertices = (0..<vertexCount).map { index in
            let angle = (Double(index) / Double(vertexCount)) * 2 * Double.pi
            return DeckVertex(
                id: "v\(index)",
                position: CGPoint(x: cos(angle) * 100, y: sin(angle) * 100)
            )
        }
        drawing.edges = (0..<vertexCount).map { index in
            DeckEdge(
                id: "e\(index)",
                startVertexId: "v\(index)",
                endVertexId: "v\((index + 1) % vertexCount)"
            )
        }
        drawing.scaleFactor = 1
        return drawing
    }
}
