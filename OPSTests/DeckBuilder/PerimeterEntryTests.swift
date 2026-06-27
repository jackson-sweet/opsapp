// OPS/OPSTests/DeckBuilder/PerimeterEntryTests.swift

import CoreGraphics
import XCTest
@testable import OPS

@MainActor
final class PerimeterEntryTests: XCTestCase {

    func testAbsoluteDirectionEndpointUsesPrescaleFallbackBeforeCalibration() {
        let start = CGPoint(x: 100, y: 100)

        let endpoint = PerimeterEntryGeometry.endpoint(
            from: start,
            direction: .right,
            lengthInches: 72,
            scaleFactor: nil,
            incomingAngleDegrees: nil,
            fallbackScale: DeckBuilderViewModel.prescaleFallbackScale
        )

        XCTAssertEqual(endpoint.x, 244, accuracy: 0.0001)
        XCTAssertEqual(endpoint.y, 100, accuracy: 0.0001)
    }

    func testRelativeLeftNinetyUsesIncomingHeading() {
        let start = CGPoint(x: 100, y: 100)

        let endpoint = PerimeterEntryGeometry.endpoint(
            from: start,
            direction: .left90,
            lengthInches: 120,
            scaleFactor: 1,
            incomingAngleDegrees: 0,
            fallbackScale: DeckBuilderViewModel.prescaleFallbackScale
        )

        XCTAssertEqual(endpoint.x, 100, accuracy: 0.0001)
        XCTAssertEqual(endpoint.y, -20, accuracy: 0.0001)
    }

    func testImperialDraftNormalizesOverflowInches() {
        let draft = PerimeterLengthDraft.imperial(feet: 2, inches: 48, sixteenths: 0)
        let components = draft.imperialComponents

        XCTAssertEqual(draft.totalInches, 72, accuracy: 0.0001)
        XCTAssertEqual(components.feet, 6)
        XCTAssertEqual(components.inches, 0)
        XCTAssertEqual(components.sixteenths, 0)
    }

    func testCommitStoresManualDimensionAndContinuesFromNewEndpoint() throws {
        var data = DeckDrawingData()
        data.config.snappingEnabled = false
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 100, y: 100))
        ]

        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        viewModel.beginPerimeterEntry(fromVertexId: "v1")
        viewModel.selectPerimeterDirection(.right)
        viewModel.updatePerimeterLength(.imperial(feet: 6, inches: 0, sixteenths: 0))

        XCTAssertTrue(viewModel.commitPerimeterLength())

        let edge = try XCTUnwrap(viewModel.drawingData.edges.first)
        let endpoint = try XCTUnwrap(viewModel.findVertex(byId: edge.endVertexId))
        XCTAssertEqual(edge.startVertexId, "v1")
        XCTAssertEqual(edge.dimension ?? -1, 72, accuracy: 0.0001)
        XCTAssertEqual(edge.dimensionSource, .manual)
        XCTAssertEqual(endpoint.position.x, 244, accuracy: 0.0001)
        XCTAssertEqual(endpoint.position.y, 100, accuracy: 0.0001)
        XCTAssertEqual(viewModel.perimeterEntry.activeAnchor?.vertexId, edge.endVertexId)
    }

    func testCommitReusesExistingVertexWhenEndpointSnapsClosed() throws {
        var data = DeckDrawingData()
        data.config.snappingEnabled = false
        data.config.endpointSnapRadius = 8
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0))
        ]

        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        viewModel.beginPerimeterEntry(fromVertexId: "v2")
        viewModel.selectPerimeterDirection(.left)
        viewModel.updatePerimeterLength(.imperial(feet: 6, inches: 0, sixteenths: 0))

        XCTAssertTrue(viewModel.commitPerimeterLength())

        let edge = try XCTUnwrap(viewModel.drawingData.edges.first)
        XCTAssertEqual(viewModel.drawingData.vertices.count, 2)
        XCTAssertEqual(edge.startVertexId, "v2")
        XCTAssertEqual(edge.endVertexId, "v1")
        XCTAssertEqual(edge.dimension ?? -1, 72, accuracy: 0.0001)
        XCTAssertEqual(edge.dimensionSource, .manual)
    }

    private func deckDesign(drawingData: DeckDrawingData) -> DeckDesign {
        DeckDesign(
            companyId: "company-1",
            title: "Perimeter entry deck",
            drawingDataJSON: drawingData.toJSON()
        )
    }
}
