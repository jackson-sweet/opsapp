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

    func testAbsoluteDirectionWheelUsesCompassLabels() {
        XCTAssertEqual(PerimeterDirection.up.wheelLabel, "NORTH")
        XCTAssertEqual(PerimeterDirection.upRight45.wheelLabel, "NORTHEAST")
        XCTAssertEqual(PerimeterDirection.right.wheelLabel, "EAST")
        XCTAssertEqual(PerimeterDirection.downRight45.wheelLabel, "SOUTHEAST")
        XCTAssertEqual(PerimeterDirection.down.wheelLabel, "SOUTH")
        XCTAssertEqual(PerimeterDirection.downLeft45.wheelLabel, "SOUTHWEST")
        XCTAssertEqual(PerimeterDirection.left.wheelLabel, "WEST")
        XCTAssertEqual(PerimeterDirection.upLeft45.wheelLabel, "NORTHWEST")
    }

    func testRelativeDirectionWheelUsesSignedAngleLabels() {
        XCTAssertEqual(PerimeterDirection.relativeDirections, [
            .straight, .right45, .right90, .right135, .back, .left135, .left90, .left45
        ])
        XCTAssertEqual(PerimeterDirection.straight.wheelLabel, "0°")
        XCTAssertEqual(PerimeterDirection.right45.wheelLabel, "+45°")
        XCTAssertEqual(PerimeterDirection.right90.wheelLabel, "+90°")
        XCTAssertEqual(PerimeterDirection.right135.wheelLabel, "+135°")
        XCTAssertEqual(PerimeterDirection.back.wheelLabel, "180°")
        XCTAssertEqual(PerimeterDirection.left135.wheelLabel, "-135°")
        XCTAssertEqual(PerimeterDirection.left90.wheelLabel, "-90°")
        XCTAssertEqual(PerimeterDirection.left45.wheelLabel, "-45°")
    }

    func testDirectionWheelSelectionTracksCompassPosition() throws {
        let anchor = PerimeterEntryAnchor(
            vertexId: "v1",
            position: CGPoint(x: 100, y: 100),
            incomingAngleDegrees: nil,
            rootVertexId: "v1"
        )
        let center = CGPoint(x: PerimeterDirectionWheelGeometry.diameter / 2,
                             y: PerimeterDirectionWheelGeometry.diameter / 2)

        XCTAssertEqual(
            PerimeterDirectionWheelGeometry.nearestDirection(
                to: CGPoint(x: center.x, y: center.y - 92),
                anchor: anchor
            ),
            .up
        )
        XCTAssertEqual(
            PerimeterDirectionWheelGeometry.nearestDirection(
                to: CGPoint(x: center.x + 92, y: center.y),
                anchor: anchor
            ),
            .right
        )
        XCTAssertEqual(
            PerimeterDirectionWheelGeometry.nearestDirection(
                to: CGPoint(x: center.x - 92, y: center.y - 92),
                anchor: anchor
            ),
            .upLeft45
        )
    }

    func testDirectionWheelSelectionTracksRelativeIncomingAngle() throws {
        let anchor = PerimeterEntryAnchor(
            vertexId: "v2",
            position: CGPoint(x: 100, y: 100),
            incomingAngleDegrees: 0,
            rootVertexId: "v1"
        )
        let center = CGPoint(x: PerimeterDirectionWheelGeometry.diameter / 2,
                             y: PerimeterDirectionWheelGeometry.diameter / 2)

        XCTAssertEqual(
            PerimeterDirectionWheelGeometry.nearestDirection(
                to: CGPoint(x: center.x + 92, y: center.y),
                anchor: anchor
            ),
            .straight
        )
        XCTAssertEqual(
            PerimeterDirectionWheelGeometry.nearestDirection(
                to: CGPoint(x: center.x + 92, y: center.y - 92),
                anchor: anchor
            ),
            .left45
        )
        XCTAssertEqual(
            PerimeterDirectionWheelGeometry.nearestDirection(
                to: CGPoint(x: center.x + 92, y: center.y + 92),
                anchor: anchor
            ),
            .right45
        )
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

        let viewModel = viewModel(drawingData: data)
        viewModel.beginPerimeterEntry(fromVertexId: "v1")
        XCTAssertEqual(viewModel.perimeterEntry.activeAnchor?.availableDirections, PerimeterDirection.absoluteDirections)
        viewModel.selectPerimeterDirection(.right)
        XCTAssertEqual(viewModel.perimeterEntry.selectedDirection, .right)
        viewModel.updatePerimeterLength(.imperial(feet: 6, inches: 0, sixteenths: 0))
        XCTAssertEqual(try XCTUnwrap(viewModel.perimeterEntry.lengthDraft).totalInches, 72, accuracy: 0.0001)

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

        let viewModel = viewModel(drawingData: data)
        viewModel.beginPerimeterEntry(fromVertexId: "v2")
        XCTAssertEqual(viewModel.perimeterEntry.activeAnchor?.availableDirections, PerimeterDirection.absoluteDirections)
        viewModel.selectPerimeterDirection(.left)
        XCTAssertEqual(viewModel.perimeterEntry.selectedDirection, .left)
        viewModel.updatePerimeterLength(.imperial(feet: 6, inches: 0, sixteenths: 0))
        XCTAssertEqual(try XCTUnwrap(viewModel.perimeterEntry.lengthDraft).totalInches, 72, accuracy: 0.0001)

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

    private func viewModel(drawingData: DeckDrawingData) -> DeckBuilderViewModel {
        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: DeckDrawingData()))
        viewModel.drawingData = drawingData
        return viewModel
    }
}
