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

    // MARK: - Sync merge base (bug 9f4aeaf8)

    func test_storeDrawingData_leavesMergeBaseUntouched() {
        let design = DeckDesign(companyId: "c1", title: "T")
        design.syncedDrawingJSON = "{\"seed\":true}"

        var drawing = DeckDrawingData()
        drawing.scaleFactor = 1
        design.storeDrawingData(drawing, json: drawing.toJSON())

        XCTAssertEqual(
            design.syncedDrawingJSON,
            "{\"seed\":true}",
            "a local edit must not move the merge base — only a confirmed server agreement may"
        )
        XCTAssertTrue(design.hasUnsyncedDrawing)
    }

    func test_markDrawingSynced_movesMergeBaseToCurrentPayload() {
        let design = DeckDesign(companyId: "c1", title: "T")
        var drawing = DeckDrawingData()
        drawing.scaleFactor = 1
        design.storeDrawingData(drawing, json: drawing.toJSON())
        XCTAssertTrue(design.hasUnsyncedDrawing)

        design.markDrawingSynced()

        XCTAssertEqual(design.syncedDrawingJSON, design.drawingDataJSON)
        XCTAssertFalse(design.hasUnsyncedDrawing)
    }

    /// The first local write to a row that has never recorded a base seeds it
    /// with the payload being replaced — the last state the server and this
    /// device agreed on. Without this, a row edited after upgrading would have
    /// no content baseline and would depend on `needsSync`, which an inbound
    /// merge is free to clear.
    func test_storeDrawingData_seedsTheMergeBaseFromThePreEditPayload() {
        let serverPayload = makeClosedDrawing(vertexCount: 4).toJSON()
        let design = DeckDesign(companyId: "c1", title: "T", drawingDataJSON: serverPayload)
        XCTAssertNil(design.syncedDrawingJSON)

        var edited = makeClosedDrawing(vertexCount: 3)
        edited.scaleFactor = 1
        design.storeDrawingData(edited, json: edited.toJSON())

        XCTAssertEqual(
            design.syncedDrawingJSON,
            serverPayload,
            "the payload the edit replaced is the merge base"
        )
        XCTAssertTrue(design.hasUnsyncedDrawing)
    }

    /// An unknown merge base falls back to the only authorship signal such a
    /// row carries. A row merged in from the server holds the server's own
    /// content and must keep accepting inbound geometry; a row flagged for push
    /// holds local content and must be protected.
    func test_hasUnsyncedDrawing_withNoMergeBaseFollowsTheDirtyFlag() {
        let merged = DeckDesign(companyId: "c1", title: "T")
        XCTAssertNil(merged.syncedDrawingJSON)
        XCTAssertFalse(
            merged.hasUnsyncedDrawing,
            "a row with no base and no local write holds nothing the server has not confirmed"
        )

        merged.needsSync = true
        XCTAssertTrue(
            merged.hasUnsyncedDrawing,
            "a row flagged for push holds local content even with no recorded base"
        )
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
