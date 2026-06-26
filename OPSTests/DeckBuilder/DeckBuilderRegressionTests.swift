//
//  DeckBuilderRegressionTests.swift
//  OPSTests
//
//  Focused regressions for the Supabase bug backlog closed on
//  feat/vinyl-auto-order.
//

import CoreGraphics
import DeckKit
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

    func testSceneBuilder_elevatedHouseEdgeAddsGradeWallBelowDeck() throws {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.overallElevation = 3.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 144, y: 144)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 144)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2", edgeType: .houseEdge, houseEdgeMaterial: .stucco),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]

        let scene = DeckSceneBuilder.buildScene(from: data)
        let houseWall = try XCTUnwrap(scene.rootNode.childNode(withName: "houseWall", recursively: true))
        let gradeWall = try XCTUnwrap(scene.rootNode.childNode(withName: "houseWallToGrade", recursively: true))
        let houseBox = try XCTUnwrap(houseWall.geometry as? SCNBox)
        let gradeBox = try XCTUnwrap(gradeWall.geometry as? SCNBox)

        XCTAssertEqual(Double(houseBox.height), 8.0 * 0.3048, accuracy: 0.01)
        XCTAssertEqual(Double(gradeBox.height), 3.0 * 0.3048, accuracy: 0.01)
        XCTAssertEqual(gradeWall.position.y, Float(3.0 * 0.3048 / 2.0), accuracy: 0.01)
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

    func testSetHouseEdgeMaterial_batchAppliesToAllSelectedHouseEdgesWithSingleUndo() {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2", edgeType: .houseEdge),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3", edgeType: .houseEdge),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4", edgeType: .deckEdge),
        ]
        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        viewModel.selection.selectedEdgeIds = ["e1", "e2", "e3"]

        viewModel.setHouseEdgeMaterial(["e1", "e2", "e3"], material: .hardie)

        XCTAssertEqual(viewModel.findEdge(byId: "e1")?.houseEdgeMaterial, .hardie)
        XCTAssertEqual(viewModel.findEdge(byId: "e2")?.houseEdgeMaterial, .hardie)
        XCTAssertNil(viewModel.findEdge(byId: "e3")?.houseEdgeMaterial)

        viewModel.undo()
        XCTAssertNil(viewModel.findEdge(byId: "e1")?.houseEdgeMaterial)
        XCTAssertNil(viewModel.findEdge(byId: "e2")?.houseEdgeMaterial)
        XCTAssertNil(viewModel.findEdge(byId: "e3")?.houseEdgeMaterial)
    }

    // MARK: - 3D cut-stringer profile (sawtooth seats; never above the treads)

    func testCutStringerProfile_sawtoothSeatsAndUnderside() {
        let r: Float = 0.2, run: Float = 0.25, d: Float = 0.3
        let pts = DeckSceneBuilder.cutStringerProfilePoints(treadCount: 3, riseM: r, runM: run, depthM: d)

        // origin + 2 points per tread + 2 underside points
        XCTAssertEqual(pts.count, 1 + 2 * 3 + 2)
        XCTAssertEqual(pts.first, CGPoint(x: 0, y: 0))

        // Seat 0: back at (0,-r), nosing at (run,-r); riser down to seat 1.
        XCTAssertEqual(Float(pts[1].x), 0, accuracy: 1e-5)
        XCTAssertEqual(Float(pts[1].y), -r, accuracy: 1e-5)
        XCTAssertEqual(Float(pts[2].x), run, accuracy: 1e-5)
        XCTAssertEqual(Float(pts[2].y), -r, accuracy: 1e-5)

        // Bottom-front then bottom-back (underside parallel to the slope).
        XCTAssertEqual(Float(pts[7].x), 3 * run, accuracy: 1e-5)
        XCTAssertEqual(Float(pts[7].y), -3 * r - d, accuracy: 1e-5)
        XCTAssertEqual(Float(pts[8].x), 0, accuracy: 1e-5)
        XCTAssertEqual(Float(pts[8].y), -d, accuracy: 1e-5)

        // Nothing rises above the deck line (v ≤ 0) — the stringer never pokes
        // above the treads.
        XCTAssertTrue(pts.allSatisfy { $0.y <= 1e-6 })
    }

    // MARK: - 3D spanning-box orientation (bug: stair top rail rendered flat)

    func testSpanningBoxOrientation_horizontalSpanMatchesLegacyEulerY() {
        // A level rail (dy == 0) running diagonally in XZ. The fix must be a
        // no-op for every horizontal caller: length lies along the edge, width
        // is the horizontal perpendicular, height is world-up — exactly what
        // the old `eulerAngles.y = atan2(dx, dz)` produced.
        let dx: Float = 3
        let dz: Float = 4
        let q = DeckSceneBuilder.spanningBoxOrientation(
            direction: SCNVector3(dx, 0, dz)
        )
        let lengthAxis = q.act(SIMD3<Float>(0, 0, 1))  // box length → along the span
        let widthAxis = q.act(SIMD3<Float>(1, 0, 0))   // box width → horizontal perpendicular
        let heightAxis = q.act(SIMD3<Float>(0, 1, 0))  // box height → world up

        // Length axis equals the normalized horizontal direction (no tilt).
        let len = (dx * dx + dz * dz).squareRoot()
        XCTAssertEqual(lengthAxis.x, dx / len, accuracy: 0.0001)
        XCTAssertEqual(lengthAxis.y, 0, accuracy: 0.0001)  // dead flat — no slope
        XCTAssertEqual(lengthAxis.z, dz / len, accuracy: 0.0001)

        // Reference orientation from the legacy euler-Y path.
        let ref = SCNNode()
        ref.eulerAngles.y = atan2(dx, dz)
        let refLength = ref.simdOrientation.act(SIMD3<Float>(0, 0, 1))
        let refWidth = ref.simdOrientation.act(SIMD3<Float>(1, 0, 0))
        XCTAssertEqual(lengthAxis.x, refLength.x, accuracy: 0.0001)
        XCTAssertEqual(lengthAxis.y, refLength.y, accuracy: 0.0001)
        XCTAssertEqual(lengthAxis.z, refLength.z, accuracy: 0.0001)
        XCTAssertEqual(widthAxis.x, refWidth.x, accuracy: 0.0001)
        XCTAssertEqual(widthAxis.y, refWidth.y, accuracy: 0.0001)
        XCTAssertEqual(widthAxis.z, refWidth.z, accuracy: 0.0001)

        // Height stays world-up for a level span.
        XCTAssertEqual(heightAxis.x, 0, accuracy: 0.0001)
        XCTAssertEqual(heightAxis.y, 1, accuracy: 0.0001)
        XCTAssertEqual(heightAxis.z, 0, accuracy: 0.0001)
    }

    func testSpanningBoxOrientation_slopedSpanFollowsPitchAndKeepsWidthHorizontal() {
        // A stair top rail descending as it runs outward: equal rise and run
        // along +X (45° pitch), endpoint p2 below and outward from p1. The old
        // path flattened both endpoints to one Y, so the rail floated flat; the
        // fix must tilt the length axis down the slope.
        let q = DeckSceneBuilder.spanningBoxOrientation(
            direction: SCNVector3(1, -1, 0)  // out +X, down -Y, equal magnitude
        )
        let lengthAxis = q.act(SIMD3<Float>(0, 0, 1))
        let widthAxis = q.act(SIMD3<Float>(1, 0, 0))
        let r2 = Float(2).squareRoot() / 2

        // Length axis is unit and points down the 45° slope toward +X / -Y.
        XCTAssertEqual(simd_length(lengthAxis), 1, accuracy: 0.0001)
        XCTAssertEqual(lengthAxis.x, r2, accuracy: 0.0001)
        XCTAssertEqual(lengthAxis.y, -r2, accuracy: 0.0001)   // descends with the stairs
        XCTAssertEqual(lengthAxis.z, 0, accuracy: 0.0001)

        // Width stays horizontal (Y == 0) — the rail's cross-section does not
        // bank — and is perpendicular to the span's ground track (+X ⇒ ∓Z).
        XCTAssertEqual(widthAxis.y, 0, accuracy: 0.0001)
        XCTAssertEqual(abs(widthAxis.z), 1, accuracy: 0.0001)
        XCTAssertEqual(widthAxis.x, 0, accuracy: 0.0001)
    }

    func testSpanningBoxOrientation_slopedSpanIsLongerThanItsGroundTrack() {
        // The TRUE 3D length the box now uses must exceed the XZ-only length the
        // old code computed for any span with rise — the ~cos(pitch) shortfall.
        let dx: Float = 11   // run
        let dy: Float = -7   // rise (descending)
        let dz: Float = 0
        let trueLength = (dx * dx + dy * dy + dz * dz).squareRoot()
        let groundTrack = (dx * dx + dz * dz).squareRoot()
        XCTAssertGreaterThan(trueLength, groundTrack)
        // A 7"/11" stair: the old rail was ~cos(pitch) ≈ 84% of true length.
        XCTAssertEqual(groundTrack / trueLength, cos(atan2(abs(dy), dx)), accuracy: 0.0001)
    }

    // MARK: - Area sums detected surfaces (not the outer perimeter)

    func testCalculateAreaSqFt_sumsDetectedSurfacesAcrossDisconnectedShapes() {
        // Two disconnected rectangles on one level: 144x144 (144 sq ft) +
        // 72x72 (36 sq ft) = 180. The old isClosed/orderedPositions path
        // shoelaced the two-loop graph as one perimeter (or rejected it);
        // the surface-aware area sums each detected face.
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

        XCTAssertEqual(EstimateGeneratorService.calculateAreaSqFt(drawingData: data), 180.0, accuracy: 0.5)
    }

    func testSelectedSurfaceSummaryUsesSelectedPersistedItemsAndArea() throws {
        var data = disconnectedSurfaceDrawingData()
        var persisted = SurfaceReconciler.reconcile(detected: data.detectedSurfaces, persisted: [])
        let smallSurfaceVertexIds: Set<String> = ["b1", "b2", "b3", "b4"]
        let selectedSurfaceIndex = try XCTUnwrap(
            persisted.firstIndex(where: { $0.vertexIds == smallSurfaceVertexIds })
        )
        persisted[selectedSurfaceIndex].label = "Landing"
        persisted[selectedSurfaceIndex].assignedItems = [
            AssignedItem(
                id: "item-pvc",
                name: "PVC deck board",
                unitType: .squareFoot,
                unitPrice: nil,
                taskTypeId: nil,
                taskTypeColor: "#8195B5"
            )
        ]
        data.surfaces = persisted

        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        viewModel.selection.selectedSurfaceIds = [persisted[selectedSurfaceIndex].id]

        let summary = try XCTUnwrap(viewModel.selectedSurfaceSummary)
        XCTAssertEqual(summary.surfaceCount, 1)
        XCTAssertEqual(summary.title, "Landing")
        XCTAssertEqual(summary.areaSquareInches, 72.0 * 72.0, accuracy: 0.001)
        XCTAssertEqual(summary.perimeterInches, 72.0 * 4.0, accuracy: 0.001)
        XCTAssertEqual(summary.assignedItems.map(\.name), ["PVC deck board"])
    }

    func testCopyPasteSelectionStagesGeometryBeforeCommit() {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.config.snappingEnabled = false
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 100, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 100, y: 100)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 100)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]
        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        viewModel.selection.selectedEdgeIds = ["e1", "e2"]

        XCTAssertTrue(viewModel.copySelection())
        XCTAssertTrue(viewModel.canPasteSelection)

        let originalVertexIds = Set(viewModel.drawingData.vertices.map(\.id))
        let originalEdgeIds = Set(viewModel.drawingData.edges.map(\.id))
        viewModel.beginPaste(at: CGPoint(x: 300, y: 300))

        XCTAssertNotNil(viewModel.pendingPastePreview)
        XCTAssertEqual(viewModel.drawingData.vertices.count, 4)
        XCTAssertEqual(viewModel.drawingData.edges.count, 4)

        viewModel.beginPendingPasteMove(at: CGPoint(x: 300, y: 300))
        viewModel.updatePendingPasteMove(to: CGPoint(x: 360, y: 360))
        viewModel.endPendingPasteMove()
        viewModel.commitPendingPaste()

        XCTAssertNil(viewModel.pendingPastePreview)
        XCTAssertEqual(viewModel.drawingData.vertices.count, 7)
        XCTAssertEqual(viewModel.drawingData.edges.count, 6)
        XCTAssertTrue(viewModel.selection.selectedEdgeIds.isDisjoint(with: originalEdgeIds))
        XCTAssertEqual(viewModel.selection.selectedEdgeIds.count, 2)

        let pastedVertices = viewModel.drawingData.vertices.filter { !originalVertexIds.contains($0.id) }
        XCTAssertEqual(pastedVertices.count, 3)
        XCTAssertTrue(pastedVertices.contains { $0.position == CGPoint(x: 310, y: 310) })
        XCTAssertTrue(pastedVertices.contains { $0.position == CGPoint(x: 410, y: 310) })
        XCTAssertTrue(pastedVertices.contains { $0.position == CGPoint(x: 410, y: 410) })
    }

    // MARK: - Selection is pruned when undo/redo removes the selected element

    func testRedo_prunesSelectionOfRemovedEdge() {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 120)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
        ]
        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))

        viewModel.selection.selectedEdgeIds = ["e1"]
        viewModel.deleteSelectedEdges()                 // removes e1 (+ orphaned v1), pushes undo
        XCTAssertNil(viewModel.findEdge(byId: "e1"))

        viewModel.undo()                                // e1 restored
        XCTAssertNotNil(viewModel.findEdge(byId: "e1"))

        viewModel.selection.selectedEdgeIds = ["e1"]    // re-select, then redo removes it again
        viewModel.redo()
        XCTAssertNil(viewModel.findEdge(byId: "e1"))
        XCTAssertFalse(
            viewModel.selection.selectedEdgeIds.contains("e1"),
            "selection must drop the id of an edge the redo removed"
        )
    }

    // MARK: - Marquee rectangle normalizes across a reversing drag (BUG 1)

    func testUpdateMarquee_normalizesRectForReversingDrag() {
        // Start at (100,100), drag up-left to (50,50), then reverse and drag
        // down-right PAST the anchor to (150,150). The rect must always be the
        // axis-aligned box between the FIXED anchor and the live point — i.e.
        // (100,100)→(150,150). The pre-fix code reused the running rect's
        // origin as the anchor, so once the drag reversed the origin stayed
        // pinned at the minimized corner (50,50) and the box never tracked
        // back, spuriously covering geometry the current box no longer bounds.
        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: DeckDrawingData()))

        viewModel.beginMarquee(at: CGPoint(x: 100, y: 100))
        viewModel.updateMarquee(to: CGPoint(x: 50, y: 50))   // up-left
        viewModel.updateMarquee(to: CGPoint(x: 150, y: 150)) // reverse past anchor

        guard case .selecting(let rect) = viewModel.drawingMode else {
            return XCTFail("expected .selecting mode after marquee updates")
        }
        XCTAssertEqual(rect, CGRect(x: 100, y: 100, width: 50, height: 50),
                       "marquee rect must be the box from the fixed anchor to the live point, for any drag direction")
    }

    func testEndMarquee_selectsOnlyVerticesInsideForReversingDrag() {
        // Reversing drag (100,100 → 50,50 → 150,150) must resolve to the final
        // box [100,150]² — selecting the vertex inside it, not one only swept
        // through. (70,70) is inside the transient (50,50)→(100,100) box but
        // outside the correct final box. Vertices carry edges so fromJSON's
        // orphan-pruning keeps them on the deckDesign round-trip.
        var data = DeckDrawingData()
        data.config.snappingEnabled = false
        data.vertices = [
            DeckVertex(id: "inside", position: CGPoint(x: 120, y: 120)),
            DeckVertex(id: "swept", position: CGPoint(x: 70, y: 70)),
            DeckVertex(id: "far", position: CGPoint(x: 300, y: 300)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "inside", endVertexId: "swept"),
            DeckEdge(id: "e2", startVertexId: "swept", endVertexId: "far"),
        ]
        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        viewModel.activeTool = .select

        viewModel.beginMarquee(at: CGPoint(x: 100, y: 100))
        viewModel.updateMarquee(to: CGPoint(x: 50, y: 50))
        viewModel.updateMarquee(to: CGPoint(x: 150, y: 150))
        viewModel.endMarquee()

        XCTAssertTrue(viewModel.selection.selectedVertexIds.contains("inside"),
                      "vertex inside the final box must be selected; got \(viewModel.selection.selectedVertexIds)")
        XCTAssertFalse(viewModel.selection.selectedVertexIds.contains("swept"),
                       "a vertex the final marquee box does not contain must not be selected")
    }

    // MARK: - Stair tap respects additive/toggle semantics (BUG 2)

    func testHandleTap_stairTapInAdditiveModePreservesExistingSelection() {
        // Unit square (scale 1.0) with a stair on the bottom edge e1 (v1→v2).
        // The stair projects to the outward perpendicular (y < 0), spanning
        // x∈[0,100], y∈[-30,0] (width 100, 3 treads × 10" run = 30 depth).
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.config.snappingEnabled = false
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 100, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 100, y: 100)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 100)),
        ]
        var stairEdge = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        stairEdge.stairConfig = StairConfig(width: 100, treadCount: 3, alignment: .center)
        data.edges = [
            stairEdge,
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]
        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))

        let stairTapPoint = CGPoint(x: 50, y: -15)

        // Sanity: a non-additive tap on the stair selects exactly that edge,
        // confirming the tap point lands inside the stair geometry.
        viewModel.activeTool = .draw
        viewModel.handleTap(at: stairTapPoint)
        XCTAssertEqual(viewModel.selection.selectedEdgeIds, ["e1"],
                       "stair tap point must hit the stair rectangle")

        // Additive mode: pre-seed a multi-selection, then tap the stair. An
        // edge tap toggles/adds; the stair tap must do the same — NOT replace
        // the whole set. Pre-fix it did `selectedEdgeIds = [stairEdgeId]`,
        // wiping e2 and e3.
        viewModel.activeTool = .tapSelect
        viewModel.selection.selectedEdgeIds = ["e2", "e3"]
        viewModel.handleTap(at: stairTapPoint)

        XCTAssertEqual(viewModel.selection.selectedEdgeIds, ["e1", "e2", "e3"],
                       "stair tap in additive mode must add to the selection, not clobber it")

        // And a second additive stair tap toggles it OFF (edge-tap parity).
        viewModel.handleTap(at: stairTapPoint)
        XCTAssertEqual(viewModel.selection.selectedEdgeIds, ["e2", "e3"],
                       "a second additive stair tap must toggle the stair edge off")
    }

    // MARK: - Marquee / lasso honor the element-type filter (BUG 3)

    func testEndMarquee_honorsTapSelectFilter() {
        // Filter set to faces only — a marquee drag must add neither vertices
        // nor edges, mirroring how tap selection respects the filter.
        var data = DeckDrawingData()
        data.config.snappingEnabled = false
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 10, y: 10)),
            DeckVertex(id: "v2", position: CGPoint(x: 90, y: 10)),
        ]
        data.edges = [DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")]
        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        viewModel.activeTool = .select
        viewModel.tapSelectFilter = [.face]

        viewModel.beginMarquee(at: CGPoint(x: 0, y: 0))
        viewModel.updateMarquee(to: CGPoint(x: 100, y: 100))
        viewModel.endMarquee()

        XCTAssertTrue(viewModel.selection.selectedVertexIds.isEmpty,
                      "marquee must not add vertices when .vertex is filtered out")
        XCTAssertTrue(viewModel.selection.selectedEdgeIds.isEmpty,
                      "marquee must not add edges when .edge is filtered out")
    }

    func testEndMarquee_edgeOnlyFilterSkipsVertexSelection() {
        // Filter excludes vertices but includes edges. Both endpoints fall in
        // the box, so the edge must still be selected — via its endpoints —
        // without leaving the vertices selected.
        var data = DeckDrawingData()
        data.config.snappingEnabled = false
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 10, y: 10)),
            DeckVertex(id: "v2", position: CGPoint(x: 90, y: 10)),
        ]
        data.edges = [DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")]
        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        viewModel.activeTool = .select
        viewModel.tapSelectFilter = [.edge]

        viewModel.beginMarquee(at: CGPoint(x: 0, y: 0))
        viewModel.updateMarquee(to: CGPoint(x: 100, y: 100))
        viewModel.endMarquee()

        XCTAssertEqual(viewModel.selection.selectedEdgeIds, ["e1"],
                       "edge fully inside the marquee must be selected when .edge is allowed")
        XCTAssertTrue(viewModel.selection.selectedVertexIds.isEmpty,
                      "marquee must not leave vertices selected when .vertex is filtered out")
    }

    func testEndLasso_honorsTapSelectFilter() {
        var data = DeckDrawingData()
        data.config.snappingEnabled = false
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 10, y: 10)),
            DeckVertex(id: "v2", position: CGPoint(x: 90, y: 10)),
        ]
        data.edges = [DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")]
        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        viewModel.activeTool = .lasso
        viewModel.tapSelectFilter = [.face]

        viewModel.beginLasso(at: CGPoint(x: 0, y: 0))
        viewModel.updateLasso(to: CGPoint(x: 100, y: 0))
        viewModel.updateLasso(to: CGPoint(x: 100, y: 100))
        viewModel.updateLasso(to: CGPoint(x: 0, y: 100))
        viewModel.endLasso()

        XCTAssertTrue(viewModel.selection.selectedVertexIds.isEmpty,
                      "lasso must not add vertices when .vertex is filtered out")
        XCTAssertTrue(viewModel.selection.selectedEdgeIds.isEmpty,
                      "lasso must not add edges when .edge is filtered out")
    }

    // MARK: - Stair total rise uses the edge midpoint, not the higher endpoint

    func testCalculateTotalRise_slopedEdgeUsesMidpointNotMax() throws {
        // A stair sits CENTERED on its edge, so its rise is the edge midpoint
        // height. On a sloped edge (endpoints at different per-vertex
        // elevations — 4.0 ft and 2.0 ft) the representative rise is the
        // average: (4 + 2) / 2 = 3 ft = 36". The pre-fix code returned
        // max(4, 2) * 12 = 48", over-counting tread/riser/stringer quantities.
        //
        // Unit square; the stair rides edge e1 (v1→v2). Per-vertex elevations
        // live on v1/v2. Both vertices carry edges, so fromJSON's two-pass
        // orphan-pruning keeps them across the deckDesign round-trip — proving
        // the elevations survive JSON serialization, not just in-memory state.
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0), elevation: 4.0),
            DeckVertex(id: "v2", position: CGPoint(x: 100, y: 0), elevation: 2.0),
            DeckVertex(id: "v3", position: CGPoint(x: 100, y: 100)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 100)),
        ]
        var stairEdge = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        stairEdge.stairConfig = StairConfig(width: 100, treadCount: 4, alignment: .center)
        data.edges = [
            stairEdge,
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]

        // Round-trip through the persisted JSON path (toJSON → fromJSON).
        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        let restored = viewModel.drawingData

        // Per-vertex elevations must survive the round-trip for the math to mean anything.
        XCTAssertEqual(restored.vertex(byId: "v1")?.elevation, 4.0)
        XCTAssertEqual(restored.vertex(byId: "v2")?.elevation, 2.0)

        guard let edge = restored.edge(byId: "e1") else {
            return XCTFail("stair edge e1 must survive the round-trip")
        }
        let rise = try XCTUnwrap(EstimateGeneratorService.calculateTotalRise(edge: edge, drawingData: restored))
        XCTAssertEqual(rise, 36.0, accuracy: 0.0001,
                       "sloped stair edge rise must be the midpoint average (4+2)/2*12 = 36\", not max*12 = 48\"")
        XCTAssertNotEqual(rise, 48.0,
                          "pre-fix max(s,e)*12 = 48\" must no longer be returned")
    }

    func testCalculateTotalRise_levelEdgeUnchanged() throws {
        // Regression guard for the common case: both endpoints at the same
        // elevation (3.0 ft). Average == max == 3 ft = 36" — the fix must be a
        // no-op here so existing level-edge estimates don't shift.
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0), elevation: 3.0),
            DeckVertex(id: "v2", position: CGPoint(x: 100, y: 0), elevation: 3.0),
            DeckVertex(id: "v3", position: CGPoint(x: 100, y: 100)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 100)),
        ]
        var stairEdge = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        stairEdge.stairConfig = StairConfig(width: 100, treadCount: 4, alignment: .center)
        data.edges = [
            stairEdge,
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]

        let viewModel = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        let restored = viewModel.drawingData

        guard let edge = restored.edge(byId: "e1") else {
            return XCTFail("stair edge e1 must survive the round-trip")
        }
        let rise = try XCTUnwrap(EstimateGeneratorService.calculateTotalRise(edge: edge, drawingData: restored))
        XCTAssertEqual(rise, 36.0, accuracy: 0.0001,
                       "level stair edge rise (both 3.0 ft) must stay 3*12 = 36\" — unchanged by the fix")
    }

    private func deckDesign(drawingData: DeckDrawingData) -> DeckDesign {
        DeckDesign(
            companyId: "company-1",
            title: "Regression deck",
            drawingDataJSON: drawingData.toJSON()
        )
    }

    private func disconnectedSurfaceDrawingData() -> DeckDrawingData {
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
        return data
    }
}
