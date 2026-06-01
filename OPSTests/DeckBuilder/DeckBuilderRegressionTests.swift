//
//  DeckBuilderRegressionTests.swift
//  OPSTests
//
//  Focused regressions for the Supabase bug backlog closed on
//  feat/vinyl-auto-order.
//

import CoreGraphics
import SceneKit
import simd
import XCTest
@testable import OPS

@MainActor
final class DeckBuilderRegressionTests: XCTestCase {

    func testTotalRealWorldArea_sumsMultipleDetectedSurfaces() {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.vertices = [
            DeckVertex(id: "a1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "a2", position: CGPoint(x: 144, y: 0)),
            DeckVertex(id: "a3", position: CGPoint(x: 144, y: 144)),
            DeckVertex(id: "a4", position: CGPoint(x: 0, y: 144)),
            DeckVertex(id: "b1", position: CGPoint(x: 240, y: 0)),
            DeckVertex(id: "b2", position: CGPoint(x: 312, y: 0)),
            DeckVertex(id: "b3", position: CGPoint(x: 312, y: 72)),
            DeckVertex(id: "b4", position: CGPoint(x: 240, y: 72)),
        ]
        data.edges = [
            DeckEdge(id: "ae1", startVertexId: "a1", endVertexId: "a2"),
            DeckEdge(id: "ae2", startVertexId: "a2", endVertexId: "a3"),
            DeckEdge(id: "ae3", startVertexId: "a3", endVertexId: "a4"),
            DeckEdge(id: "ae4", startVertexId: "a4", endVertexId: "a1"),
            DeckEdge(id: "be1", startVertexId: "b1", endVertexId: "b2"),
            DeckEdge(id: "be2", startVertexId: "b2", endVertexId: "b3"),
            DeckEdge(id: "be3", startVertexId: "b3", endVertexId: "b4"),
            DeckEdge(id: "be4", startVertexId: "b4", endVertexId: "b1"),
        ]

        XCTAssertEqual(data.detectedSurfaces.count, 2)
        XCTAssertEqual(data.totalRealWorldArea(scaleFactor: 1.0) / 144.0, 180.0, accuracy: 0.01)
    }

    func testEdgeTypeRules_keepHouseEdgesAndDeckRailingMutuallyExclusive() {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        ]

        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        viewModel.setRailing(
            "e1",
            config: RailingConfig(
                railingType: .parapetWall,
                maxPostSpacing: RailingType.parapetWall.defaultMaxPostSpacing
            )
        )
        XCTAssertEqual(viewModel.findEdge(byId: "e1")?.railingConfig?.railingType, .parapetWall)

        viewModel.setEdgeType("e1", type: .houseEdge)
        XCTAssertNil(viewModel.findEdge(byId: "e1")?.railingConfig)

        viewModel.setRailing(
            "e1",
            config: RailingConfig(
                railingType: .parapetWall,
                maxPostSpacing: RailingType.parapetWall.defaultMaxPostSpacing
            )
        )
        XCTAssertNil(viewModel.findEdge(byId: "e1")?.railingConfig)

        viewModel.setHouseEdgeMaterial("e1", material: .hardie)
        XCTAssertEqual(viewModel.findEdge(byId: "e1")?.houseEdgeMaterial, .hardie)

        viewModel.setEdgeType("e1", type: .deckEdge)
        XCTAssertNil(viewModel.findEdge(byId: "e1")?.houseEdgeMaterial)
    }

    func testSceneBuilder_usesVertexIdsForAngledHouseWallGeometry() {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.overallElevation = 3.0

        let v1 = DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(id: "v2", position: CGPoint(x: 144, y: 24))
        let v3 = DeckVertex(id: "v3", position: CGPoint(x: 156, y: 144))
        let v4 = DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120))
        data.vertices = [v1, v3, v2, v4]

        var e1 = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        e1.edgeType = .houseEdge
        e1.houseEdgeMaterial = .stucco
        data.edges = [
            e1,
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]

        let scene = DeckSceneBuilder.buildScene(from: data)
        let wallNode = scene.rootNode.childNode(withName: "houseWall", recursively: true)
        let wallBox = wallNode?.geometry as? SCNBox

        XCTAssertNotNil(wallBox)
        let expectedLengthMeters = hypot(144.0, 24.0) / 39.3701
        XCTAssertEqual(Double(wallBox?.length ?? 0), expectedLengthMeters, accuracy: 0.02)
        XCTAssertEqual(Double(wallBox?.height ?? 0), 8.0 * 0.3048, accuracy: 0.01)
    }

    func testBuiltInLinearStandards_onlyExposeParapetAsDefaultRailing() {
        let ids = BuiltInMaterial.linearStandards.map(\.id)

        XCTAssertTrue(ids.contains("std.wall.parapet"))
        XCTAssertFalse(ids.contains("std.railing.glass"))
        XCTAssertFalse(ids.contains("std.railing.picket"))
        XCTAssertFalse(ids.contains("std.railing.cable"))
        XCTAssertEqual(RailingType.assignableDefaultTypes, [.parapetWall])
    }

    func testComponentProjection_parapetWallDoesNotEmitPostSet() {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        let v1 = DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0))
        var edge = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        edge.dimension = 144
        edge.railingConfig = RailingConfig(
            railingType: .parapetWall,
            maxPostSpacing: RailingType.parapetWall.defaultMaxPostSpacing,
            wallMaterial: .stone
        )
        data.vertices = [v1, v2]
        data.edges = [edge]

        let rows = ComponentEmitter.emit(data)

        XCTAssertEqual(rows.filter { $0.componentType == "railing" }.count, 1)
        XCTAssertTrue(rows.filter { $0.componentType == "post_set" }.isEmpty)
        XCTAssertEqual(rows.first { $0.componentType == "railing" }?.metadata["wall_material"], AnyCodable("stone"))
    }

    func testARConverter_dropsRailingFromHouseEdge() {
        let vertices = [
            ARCoordinateConverter.ARVertex(id: "v1", x: 0, z: 0, y: 0),
            ARCoordinateConverter.ARVertex(id: "v2", x: 5, z: 0, y: 0),
        ]
        let edges = [
            ARCoordinateConverter.AREdge(
                id: "e1",
                startVertexId: "v1",
                endVertexId: "v2",
                distanceMeters: 5,
                accuracyPercent: 2,
                edgeType: .houseEdge,
                railingConfig: RailingConfig(railingType: .glass, maxPostSpacing: 60)
            ),
        ]

        let data = ARCoordinateConverter.convert(arVertices: vertices, arEdges: edges, isClosed: false)

        XCTAssertEqual(data.edges.first?.edgeType, .houseEdge)
        XCTAssertNil(data.edges.first?.railingConfig)
    }

    func testSelectionMove_translatesEverySelectedVertexByDelta() {
        var data = DeckDrawingData()
        data.config.snappingEnabled = false
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 80)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 80)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]

        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        viewModel.selection.selectedVertexIds = ["v1", "v2", "v3", "v4"]

        viewModel.armSelectionMove()
        viewModel.beginSelectionMove(at: CGPoint(x: 200, y: 200))
        viewModel.updateSelectionMove(to: CGPoint(x: 250, y: 230))
        viewModel.endSelectionMove()

        // Snapping disabled — every selected vertex shifts by the raw delta.
        XCTAssertEqual(viewModel.findVertex(byId: "v1")?.position, CGPoint(x: 50, y: 30))
        XCTAssertEqual(viewModel.findVertex(byId: "v2")?.position, CGPoint(x: 170, y: 30))
        XCTAssertEqual(viewModel.findVertex(byId: "v3")?.position, CGPoint(x: 170, y: 110))
        XCTAssertEqual(viewModel.findVertex(byId: "v4")?.position, CGPoint(x: 50, y: 110))
        XCTAssertEqual(viewModel.drawingMode, .idle)
        // Sticky toggle — endSelectionMove no longer auto-disarms, so the
        // user can perform back-to-back moves without re-tapping Move-XY.
        XCTAssertTrue(viewModel.isSelectionMoveArmed)
    }

    func testSelectionMove_toggleStaysArmedAcrossMultipleMovesAndDisarmsOnRequest() {
        var data = DeckDrawingData()
        data.config.snappingEnabled = false
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
        ]
        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        viewModel.selection.selectedVertexIds = ["v1", "v2"]

        viewModel.toggleSelectionMove()
        XCTAssertTrue(viewModel.isSelectionMoveArmed)

        // Move #1
        viewModel.beginSelectionMove(at: CGPoint(x: 200, y: 200))
        viewModel.updateSelectionMove(to: CGPoint(x: 250, y: 230))
        viewModel.endSelectionMove()
        XCTAssertEqual(viewModel.findVertex(byId: "v1")?.position, CGPoint(x: 50, y: 30))
        XCTAssertTrue(viewModel.isSelectionMoveArmed)

        // Move #2 without re-arming — sticky.
        viewModel.beginSelectionMove(at: CGPoint(x: 300, y: 300))
        viewModel.updateSelectionMove(to: CGPoint(x: 280, y: 290))
        viewModel.endSelectionMove()
        XCTAssertEqual(viewModel.findVertex(byId: "v1")?.position, CGPoint(x: 30, y: 20))
        XCTAssertEqual(viewModel.findVertex(byId: "v2")?.position, CGPoint(x: 150, y: 20))
        XCTAssertTrue(viewModel.isSelectionMoveArmed)

        viewModel.toggleSelectionMove()
        XCTAssertFalse(viewModel.isSelectionMoveArmed)
    }

    func testSelectionMove_autoDisarmsWhenSelectionEmpties() {
        var data = DeckDrawingData()
        data.config.snappingEnabled = false
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
        ]
        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        viewModel.selection.selectedVertexIds = ["v1", "v2"]
        viewModel.toggleSelectionMove()
        XCTAssertTrue(viewModel.isSelectionMoveArmed)

        // Clearing the selection drops the armed flag — the Move-XY button
        // would otherwise reappear pre-activated the next time something
        // gets selected.
        viewModel.selection.clear()
        XCTAssertFalse(viewModel.isSelectionMoveArmed)
    }

    func testSelectionMove_compoundsTwoEdgeColinearitiesSimultaneously() {
        // Two crossing static edges that do NOT share a vertex — se1
        // vertical on x=300, se2 horizontal on y=300. Square B sits offset
        // from the crossing; a single Move-XY drag should snap B so its
        // left edge becomes colinear with se1 AND its top edge becomes
        // colinear with se2 — corner snap. The single-best-snap behavior
        // (else-if between vertex and edge in the old resolver) locks at
        // most one axis; the new accumulator locks both.
        var data = DeckDrawingData()
        data.config.snappingEnabled = true
        data.vertices = [
            // Static — not selected.
            DeckVertex(id: "s_v1", position: CGPoint(x: 300, y: 144)),
            DeckVertex(id: "s_v2", position: CGPoint(x: 300, y: 468)),
            DeckVertex(id: "s_h1", position: CGPoint(x: 144, y: 300)),
            DeckVertex(id: "s_h2", position: CGPoint(x: 468, y: 300)),
            // Moving square B (84×84 offset from the crossing).
            DeckVertex(id: "b1", position: CGPoint(x: 414, y: 407)),
            DeckVertex(id: "b2", position: CGPoint(x: 498, y: 407)),
            DeckVertex(id: "b3", position: CGPoint(x: 498, y: 491)),
            DeckVertex(id: "b4", position: CGPoint(x: 414, y: 491)),
        ]
        data.edges = [
            DeckEdge(id: "se1", startVertexId: "s_v1", endVertexId: "s_v2"),
            DeckEdge(id: "se2", startVertexId: "s_h1", endVertexId: "s_h2"),
            DeckEdge(id: "bt", startVertexId: "b1", endVertexId: "b2"),
            DeckEdge(id: "br", startVertexId: "b2", endVertexId: "b3"),
            DeckEdge(id: "bb", startVertexId: "b3", endVertexId: "b4"),
            DeckEdge(id: "bl", startVertexId: "b4", endVertexId: "b1"),
        ]

        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        viewModel.selection.selectedVertexIds = ["b1", "b2", "b3", "b4"]

        viewModel.toggleSelectionMove()
        viewModel.beginSelectionMove(at: CGPoint(x: 1000, y: 1000))
        // Raw delta = (-109, -101): B's top-left lands ~5pt past the
        // x=300 / y=300 crossing on both axes — well inside the 20pt
        // endpoint snap radius for BOTH static edges. Compounding pins
        // both axes; single-snap would lock only one and leave the other
        // at the grid baseline (≠ 300).
        viewModel.updateSelectionMove(to: CGPoint(x: 891, y: 899))
        viewModel.endSelectionMove()

        XCTAssertEqual(viewModel.findVertex(byId: "b1")?.position, CGPoint(x: 300, y: 300))
        XCTAssertEqual(viewModel.findVertex(byId: "b2")?.position, CGPoint(x: 384, y: 300))
        XCTAssertEqual(viewModel.findVertex(byId: "b3")?.position, CGPoint(x: 384, y: 384))
        XCTAssertEqual(viewModel.findVertex(byId: "b4")?.position, CGPoint(x: 300, y: 384))
    }

    // MARK: - Multi-edge edge-type application (bug: only one edge changed)

    func testSetEdgeType_batchAppliesToAllSelectedEdgesWithSingleUndo() {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
        ]
        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        viewModel.selection.selectedEdgeIds = ["e1", "e2", "e3"]

        viewModel.setEdgeType(["e1", "e2", "e3"], type: .houseEdge)

        XCTAssertEqual(viewModel.findEdge(byId: "e1")?.edgeType, .houseEdge)
        XCTAssertEqual(viewModel.findEdge(byId: "e2")?.edgeType, .houseEdge)
        XCTAssertEqual(viewModel.findEdge(byId: "e3")?.edgeType, .houseEdge)

        // The whole batch is one undo snapshot — a single undo restores all
        // three, not just the last edge touched.
        viewModel.undo()
        XCTAssertEqual(viewModel.findEdge(byId: "e1")?.edgeType, .deckEdge)
        XCTAssertEqual(viewModel.findEdge(byId: "e2")?.edgeType, .deckEdge)
        XCTAssertEqual(viewModel.findEdge(byId: "e3")?.edgeType, .deckEdge)
    }

    // MARK: - 3D stringer orientation (bug: skewed for non-world-X edges)

    func testStringerOrientation_followsSlopeForEdgeNotAlignedToWorldX() {
        // Edge runs along world +Z — the orientation the old dual-`eulerAngles`
        // path skewed because it pitched about the world X axis.
        let q = DeckSceneBuilder.stringerOrientation(
            tangent: SIMD2<Float>(0, 1),         // box width → along the +Z edge
            outwardNormal: SIMD2<Float>(-1, 0),  // stair runs out toward -X
            slopeAngle: Float.pi / 4             // 45°: equal rise and run
        )
        let lengthAxis = q.act(SIMD3<Float>(0, 0, 1))  // box length → down the slope
        let widthAxis = q.act(SIMD3<Float>(1, 0, 0))   // box width → along the edge
        let r2 = Float(2).squareRoot() / 2

        XCTAssertEqual(lengthAxis.x, -r2, accuracy: 0.0001)
        XCTAssertEqual(lengthAxis.y, -r2, accuracy: 0.0001)
        XCTAssertEqual(lengthAxis.z, 0, accuracy: 0.0001)

        XCTAssertEqual(widthAxis.x, 0, accuracy: 0.0001)
        XCTAssertEqual(widthAxis.y, 0, accuracy: 0.0001)
        XCTAssertEqual(widthAxis.z, 1, accuracy: 0.0001)
    }

    func testStringerOrientation_lengthDescendsAndStaysUnitLength() {
        let q = DeckSceneBuilder.stringerOrientation(
            tangent: SIMD2<Float>(1, 0),        // +X edge
            outwardNormal: SIMD2<Float>(0, 1),  // outward +Z
            slopeAngle: Float.pi / 6            // 30°
        )
        let lengthAxis = q.act(SIMD3<Float>(0, 0, 1))

        XCTAssertEqual(simd_length(lengthAxis), 1, accuracy: 0.0001)
        XCTAssertEqual(lengthAxis.y, -sin(Float.pi / 6), accuracy: 0.0001)  // descends
        XCTAssertEqual(lengthAxis.z, cos(Float.pi / 6), accuracy: 0.0001)   // runs outward
    }

    private func deckDesign(drawingData: DeckDrawingData) -> DeckDesign {
        DeckDesign(
            companyId: "company-1",
            title: "Regression deck",
            drawingDataJSON: drawingData.toJSON()
        )
    }
}
