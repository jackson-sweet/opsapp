// OPSTests/DeckBuilder/DeckBuilderMetricReadoutTests.swift

import CoreGraphics
import XCTest
@testable import OPS

final class DeckBuilderMetricReadoutTests: XCTestCase {
    private let emptyValue = "—"

    func testEmptySelectionUsesWholeDesignTotals() {
        let fixture = squareFixture()

        let result = DeckBuilderMetricReadout.build(
            drawingData: fixture.drawing,
            selection: SelectionState(),
            wholeArea: 14_400,
            wholeLength: 480
        )

        XCTAssertEqual(result.scope, .design)
        XCTAssertEqual(result.lengthText, "40'")
        XCTAssertEqual(result.areaText, "100 sq ft")
        XCTAssertTrue(result.shouldDisplay)
    }

    func testEdgeSelectionUsesSelectedLengthAndSuppressesWholeArea() {
        let fixture = squareFixture()
        var selection = SelectionState()
        selection.selectedEdgeIds = ["e1"]

        let result = DeckBuilderMetricReadout.build(
            drawingData: fixture.drawing,
            selection: selection,
            wholeArea: 14_400,
            wholeLength: 480
        )

        XCTAssertEqual(result.scope, .selection)
        XCTAssertEqual(result.lengthText, "8'")
        XCTAssertEqual(result.areaText, emptyValue)
        XCTAssertTrue(result.shouldDisplay)
    }

    func testSurfaceSelectionUsesSelectedAreaAndSuppressesWholeLength() {
        let fixture = squareFixture()
        var selection = SelectionState()
        selection.selectedSurfaceIds = [fixture.surfaceID]

        let result = DeckBuilderMetricReadout.build(
            drawingData: fixture.drawing,
            selection: selection,
            wholeArea: 14_400,
            wholeLength: 480
        )

        XCTAssertEqual(result.scope, .selection)
        XCTAssertEqual(result.lengthText, emptyValue)
        XCTAssertEqual(result.areaText, "100 sq ft")
    }

    func testMixedSelectionShowsBothSelectedTotals() {
        let fixture = squareFixture()
        var selection = SelectionState()
        selection.selectedEdgeIds = ["e1"]
        selection.selectedSurfaceIds = [fixture.surfaceID]

        let result = DeckBuilderMetricReadout.build(
            drawingData: fixture.drawing,
            selection: selection,
            wholeArea: 14_400,
            wholeLength: 480
        )

        XCTAssertEqual(result.scope, .selection)
        XCTAssertEqual(result.lengthText, "8'")
        XCTAssertEqual(result.areaText, "100 sq ft")
    }

    func testVertexOnlySelectionNeverLeaksWholeDesignTotals() {
        let fixture = squareFixture()
        var selection = SelectionState()
        selection.selectedVertexIds = ["v1"]

        let result = DeckBuilderMetricReadout.build(
            drawingData: fixture.drawing,
            selection: selection,
            wholeArea: 14_400,
            wholeLength: 480
        )

        XCTAssertEqual(result.scope, .selection)
        XCTAssertEqual(result.lengthText, emptyValue)
        XCTAssertEqual(result.areaText, emptyValue)
        XCTAssertTrue(result.shouldDisplay)
    }

    func testClearingSelectionImmediatelyRestoresWholeDesignTotals() {
        let fixture = squareFixture()
        var selection = SelectionState()
        selection.selectedEdgeIds = ["e1"]

        let selected = DeckBuilderMetricReadout.build(
            drawingData: fixture.drawing,
            selection: selection,
            wholeArea: 14_400,
            wholeLength: 480
        )
        selection.clear()
        let cleared = DeckBuilderMetricReadout.build(
            drawingData: fixture.drawing,
            selection: selection,
            wholeArea: 14_400,
            wholeLength: 480
        )

        XCTAssertEqual(selected.lengthText, "8'")
        XCTAssertEqual(cleared.lengthText, "40'")
        XCTAssertEqual(cleared.areaText, "100 sq ft")
        XCTAssertEqual(cleared.scope, .design)
    }

    func testSelectedGeometryEditImmediatelyChangesFallbackLength() {
        var fixture = squareFixture().drawing
        var selection = SelectionState()
        selection.selectedEdgeIds = ["e2"]

        let before = DeckBuilderMetricReadout.build(
            drawingData: fixture,
            selection: selection,
            wholeArea: 14_400,
            wholeLength: 480
        )
        fixture.vertices[2].position.y = 60
        let after = DeckBuilderMetricReadout.build(
            drawingData: fixture,
            selection: selection,
            wholeArea: 10_800,
            wholeLength: 420
        )

        XCTAssertEqual(before.lengthText, "10'")
        XCTAssertEqual(after.lengthText, "5'")
    }

    func testSelectedGeometryEditImmediatelyChangesSurfaceArea() {
        var fixture = squareFixture()
        var selection = SelectionState()
        selection.selectedSurfaceIds = [fixture.surfaceID]

        let before = DeckBuilderMetricReadout.build(
            drawingData: fixture.drawing,
            selection: selection,
            wholeArea: 14_400,
            wholeLength: 480
        )
        fixture.drawing.vertices[2].position.y = 60
        let after = DeckBuilderMetricReadout.build(
            drawingData: fixture.drawing,
            selection: selection,
            wholeArea: 10_800,
            wholeLength: 420
        )

        XCTAssertEqual(before.areaText, "100 sq ft")
        XCTAssertEqual(after.areaText, "75 sq ft")
    }

    func testMeasurementSystemChangeImmediatelyReformatsSelection() {
        var fixture = squareFixture()
        fixture.drawing.config.measurementSystem = .metric
        var selection = SelectionState()
        selection.selectedEdgeIds = ["e1"]
        selection.selectedSurfaceIds = [fixture.surfaceID]

        let result = DeckBuilderMetricReadout.build(
            drawingData: fixture.drawing,
            selection: selection,
            wholeArea: 14_400,
            wholeLength: 480
        )

        XCTAssertEqual(result.lengthText, "2.44 m")
        XCTAssertEqual(result.areaText, "9.3 m²")
    }

    func testEmptyOpenDesignDoesNotShowMetricChrome() {
        let result = DeckBuilderMetricReadout.build(
            drawingData: DeckDrawingData(),
            selection: SelectionState(),
            wholeArea: nil,
            wholeLength: nil
        )

        XCTAssertEqual(result.scope, .design)
        XCTAssertEqual(result.lengthText, emptyValue)
        XCTAssertEqual(result.areaText, emptyValue)
        XCTAssertFalse(result.shouldDisplay)
    }

    private func squareFixture() -> (drawing: DeckDrawingData, surfaceID: String) {
        var drawing = DeckDrawingData()
        drawing.scaleFactor = 1
        drawing.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120)),
        ]
        var firstEdge = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        firstEdge.dimension = 96
        drawing.edges = [
            firstEdge,
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]
        let surfaceID = try! XCTUnwrap(drawing.detectedSurfaces.first?.id)
        return (drawing, surfaceID)
    }
}
