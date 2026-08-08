import CoreGraphics
import XCTest
@testable import OPS

@MainActor
final class DeckDesignerPerformanceTests: XCTestCase {
    func testGeometrySnapshot_repeated1121ScaleReadsDetectSurfaceOnce() throws {
        var drawing = ringDrawing(vertexCount: 29, radius: 240)

        for _ in 0..<100 {
            XCTAssertEqual(drawing.detectedSurfaces.count, 1)
            _ = drawing.geometrySnapshot.totalCanvasArea
            _ = drawing.geometrySnapshot.totalCanvasPerimeter
        }

        XCTAssertEqual(drawing.geometrySnapshotComputationCount, 1)

        drawing.edges[0].dimension = 144
        drawing.edges[0].label = "Operator label"
        XCTAssertEqual(drawing.detectedSurfaces.count, 1)
        XCTAssertEqual(
            drawing.geometrySnapshotComputationCount,
            1,
            "dimension and label changes must not invalidate geometry topology"
        )

        drawing.vertices[0].position.x += 12
        XCTAssertEqual(drawing.detectedSurfaces.count, 1)
        XCTAssertEqual(drawing.geometrySnapshotComputationCount, 2)
    }

    func testGeometrySnapshot_heavyMultiLevelReadsInvalidateOnlyChangedLevel() {
        var drawing = DeckDrawingData()
        drawing.levels = [
            ringLevel(id: "level-29", vertexCount: 29, radius: 240),
            ringLevel(id: "level-64", vertexCount: 64, radius: 420),
            ringLevel(id: "level-96", vertexCount: 96, radius: 620),
        ]

        for _ in 0..<50 {
            XCTAssertGreaterThan(drawing.geometrySnapshot.totalCanvasArea ?? 0, 0)
            XCTAssertGreaterThan(drawing.geometrySnapshot.totalCanvasPerimeter ?? 0, 0)
        }
        XCTAssertEqual(drawing.levels.map(\.geometrySnapshotComputationCount), [1, 1, 1])

        drawing.levels[1].vertices[0].position.y += 18
        _ = drawing.geometrySnapshot.totalCanvasArea

        XCTAssertEqual(drawing.levels.map(\.geometrySnapshotComputationCount), [1, 2, 1])
    }

    func testGeometryMutation_29VertexMoveVisitsEachVertexAndEdgeOnce() {
        let drawing = ringDrawing(vertexCount: 29, radius: 240)
        let positions = Dictionary(uniqueKeysWithValues: drawing.vertices.map {
            ($0.id, CGPoint(x: $0.position.x + 36, y: $0.position.y - 24))
        })

        let result = DeckGeometryMutationEngine.applying(
            positions: positions,
            to: drawing.vertices,
            edges: drawing.edges,
            scaleFactor: 2,
            fallbackScale: DeckBuilderViewModel.prescaleFallbackScale
        )

        XCTAssertEqual(result.metrics.vertexIndexBuildCount, 1)
        XCTAssertEqual(result.metrics.updatedVertexCount, 29)
        XCTAssertEqual(result.metrics.edgeVisitCount, 29)
        XCTAssertEqual(result.metrics.dimensionRecalculationCount, 29)
        XCTAssertEqual(result.vertices[0].position, positions[result.vertices[0].id])

        for edge in result.edges {
            guard let start = result.vertices.first(where: { $0.id == edge.startVertexId }),
                  let end = result.vertices.first(where: { $0.id == edge.endVertexId }) else {
                return XCTFail("ring endpoint missing")
            }
            XCTAssertEqual(
                edge.dimension ?? 0,
                SnapEngine.distance(start.position, end.position) / 2,
                accuracy: 0.000_001
            )
        }
    }

    func testGeometryMutation_preservesManualDimensionAndMarksItsDrift() {
        var edge = DeckEdge(
            id: "e1",
            startVertexId: "v1",
            endVertexId: "v2",
            dimension: 60,
            dimensionSource: .manual
        )
        edge.dimensionStale = false

        let result = DeckGeometryMutationEngine.applying(
            positions: ["v2": CGPoint(x: 240, y: 0)],
            to: [
                DeckVertex(id: "v1", position: .zero),
                DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            ],
            edges: [edge],
            scaleFactor: 2,
            fallbackScale: DeckBuilderViewModel.prescaleFallbackScale
        )

        XCTAssertEqual(result.edges[0].dimension, 60)
        XCTAssertTrue(result.edges[0].dimensionStale)
        XCTAssertEqual(result.metrics.edgeVisitCount, 1)
        XCTAssertEqual(result.metrics.dimensionRecalculationCount, 1)
    }

    func testGestureFrameBatcher_collapsesBurstAndPublishesLatestPayload() {
        var batcher = DeckGestureFrameBatcher<Int>()

        XCTAssertTrue(batcher.submit(1))
        for value in 2...120 {
            XCTAssertFalse(batcher.submit(value))
        }

        XCTAssertEqual(batcher.submissionCount, 120)
        XCTAssertEqual(batcher.consume(), 120)
        XCTAssertEqual(batcher.publicationCount, 1)
        XCTAssertNil(batcher.consume())
    }

    func testSelectionMove_keepsCommittedDrawingStableUntilOnePassCommitAndDeferredFlush() {
        var drawing = ringDrawing(vertexCount: 29, radius: 240)
        drawing.config.snappingEnabled = false
        let design = DeckDesign(companyId: UUID().uuidString, drawingDataJSON: drawing.toJSON())
        let originalJSON = design.drawingDataJSON
        var encodeCount = 0
        let viewModel = DeckBuilderViewModel(
            deckDesign: design,
            drawingEncoder: { drawing in
                encodeCount += 1
                return drawing.toJSON()
            }
        )
        viewModel.selection.selectedVertexIds = Set(drawing.vertices.map(\.id))
        viewModel.armSelectionMove()

        let originalRevision = viewModel.drawingRevision
        let originalPosition = try! XCTUnwrap(viewModel.findVertex(byId: "v0")?.position)
        viewModel.beginSelectionMove(at: CGPoint(x: 500, y: 500))
        for value in 1...120 {
            viewModel.updateSelectionMove(to: CGPoint(x: 500 + value, y: 500 + value / 2))
        }
        viewModel.flushPendingLiveGeometryFrame()

        XCTAssertEqual(viewModel.liveGeometrySubmissionCount, 120)
        XCTAssertEqual(viewModel.liveGeometryPublicationCount, 1)
        XCTAssertEqual(viewModel.drawingRevision, originalRevision)
        XCTAssertEqual(viewModel.findVertex(byId: "v0")?.position, originalPosition)
        XCTAssertNotEqual(viewModel.renderVertex(byId: "v0")?.position, originalPosition)
        XCTAssertEqual(design.drawingDataJSON, originalJSON)

        viewModel.endSelectionMove()

        XCTAssertEqual(viewModel.drawingRevision, originalRevision + 1)
        XCTAssertEqual(viewModel.findVertex(byId: "v0")?.position, viewModel.renderVertex(byId: "v0")?.position)
        XCTAssertTrue(viewModel.hasPendingSave)
        XCTAssertEqual(design.drawingDataJSON, originalJSON)

        viewModel.flushPendingSave()

        XCTAssertFalse(viewModel.hasPendingSave)
        XCTAssertEqual(encodeCount, 1, "one save must produce drawing JSON once")
        XCTAssertNotEqual(design.drawingDataJSON, originalJSON)
        XCTAssertEqual(design.drawingData.vertex(byId: "v0")?.position, viewModel.findVertex(byId: "v0")?.position)
    }

    func testSceneRevisionGate_rebuildsOnlyForNewCommittedRevision() {
        var gate = DeckSceneRevisionGate()

        XCTAssertTrue(gate.shouldRebuild(for: 41))
        for _ in 0..<100 {
            XCTAssertFalse(gate.shouldRebuild(for: 41))
        }
        XCTAssertTrue(gate.shouldRebuild(for: 42))

        XCTAssertEqual(gate.rebuildCount, 2)
    }

    private func ringDrawing(vertexCount: Int, radius: CGFloat) -> DeckDrawingData {
        var drawing = DeckDrawingData()
        drawing.scaleFactor = 2
        drawing.vertices = (0..<vertexCount).map { index in
            let angle = (Double(index) / Double(vertexCount)) * 2 * Double.pi
            return DeckVertex(
                id: "v\(index)",
                position: CGPoint(
                    x: radius + cos(angle) * radius,
                    y: radius + sin(angle) * radius
                )
            )
        }
        drawing.edges = (0..<vertexCount).map { index in
            DeckEdge(
                id: "e\(index)",
                startVertexId: "v\(index)",
                endVertexId: "v\((index + 1) % vertexCount)",
                dimension: nil,
                dimensionSource: .scale
            )
        }
        return drawing
    }

    private func ringLevel(id: String, vertexCount: Int, radius: CGFloat) -> DeckLevel {
        let drawing = ringDrawing(vertexCount: vertexCount, radius: radius)
        var level = DeckLevel(id: id, name: id)
        level.vertices = drawing.vertices
        level.edges = drawing.edges
        return level
    }
}
