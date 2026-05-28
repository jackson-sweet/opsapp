// OPS/OPSTests/DeckBuilder/VinylOrderSelectionTests.swift

import CoreGraphics
import XCTest
@testable import OPS

@MainActor
final class VinylOrderSelectionTests: XCTestCase {

    func testSelectedCanvasDrawnSurfaceUsesFallbackScaleBeforeManualCalibration() {
        let viewModel = viewModelWithSelectedSurface(drawingData: rectangleDrawingData())

        let inputs = viewModel.selectedVinylOrderSurfaceInputs()

        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(viewModel.vinylOrderEffectiveScale, DeckBuilderViewModel.prescaleFallbackScale)
        XCTAssertEqual(inputs.first?.scaleFactor, DeckBuilderViewModel.prescaleFallbackScale)
    }

    func testSelectedSurfaceRequiresConfirmedLengthWhenPrescaleDrawingHasManualDimension() {
        var data = rectangleDrawingData()
        data.edges[0].dimensionSource = .manual
        let viewModel = viewModelWithSelectedSurface(drawingData: data)

        let inputs = viewModel.selectedVinylOrderSurfaceInputs()

        XCTAssertNil(viewModel.vinylOrderEffectiveScale)
        XCTAssertTrue(inputs.isEmpty)
    }

    func testSelectedSurfaceUsesPersistedScaleWhenDrawingIsCalibrated() {
        var data = rectangleDrawingData()
        data.scaleFactor = 2.5
        data.edges[0].dimensionSource = .manual
        let viewModel = viewModelWithSelectedSurface(drawingData: data)

        let inputs = viewModel.selectedVinylOrderSurfaceInputs()

        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(viewModel.vinylOrderEffectiveScale, 2.5)
        XCTAssertEqual(inputs.first?.scaleFactor, 2.5)
    }

    func testSelectedSurfaceBlocksWhenConfirmedDimensionIsStale() {
        var data = rectangleDrawingData()
        data.scaleFactor = 2
        data.edges[0].dimensionSource = .manual
        data.edges[0].dimensionStale = true
        let viewModel = viewModelWithSelectedSurface(drawingData: data)

        let inputs = viewModel.selectedVinylOrderSurfaceInputs()

        XCTAssertNil(viewModel.vinylOrderEffectiveScale)
        XCTAssertTrue(inputs.isEmpty)
    }

    private func rectangleDrawingData() -> DeckDrawingData {
        let v1 = DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(id: "v2", position: CGPoint(x: 288, y: 0))
        let v3 = DeckVertex(id: "v3", position: CGPoint(x: 288, y: 192))
        let v4 = DeckVertex(id: "v4", position: CGPoint(x: 0, y: 192))

        var data = DeckDrawingData()
        data.vertices = [v1, v2, v3, v4]
        data.edges = [
            scaledEdge(id: "e1", start: "v1", end: "v2", dimension: 144),
            scaledEdge(id: "e2", start: "v2", end: "v3", dimension: 96),
            scaledEdge(id: "e3", start: "v3", end: "v4", dimension: 144),
            scaledEdge(id: "e4", start: "v4", end: "v1", dimension: 96)
        ]
        data.footprint.isClosed = true
        data.scaleFactor = nil
        return data
    }

    private func scaledEdge(id: String, start: String, end: String, dimension: Double) -> DeckEdge {
        var edge = DeckEdge(id: id, startVertexId: start, endVertexId: end)
        edge.dimension = dimension
        edge.dimensionSource = .scale
        edge.dimensionStale = false
        return edge
    }

    private func deckDesign(drawingData: DeckDrawingData) -> DeckDesign {
        DeckDesign(
            companyId: "company-1",
            title: "Test deck",
            drawingDataJSON: drawingData.toJSON()
        )
    }

    private func viewModelWithSelectedSurface(drawingData: DeckDrawingData) -> DeckBuilderViewModel {
        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: drawingData))
        viewModel.reconcileSurfaces()
        let surface = try! XCTUnwrap(viewModel.drawingData.surfaces.first)
        viewModel.selection.selectedSurfaceIds = [surface.id]
        return viewModel
    }
}
