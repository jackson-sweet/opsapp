//
//  DeckBuilderRegressionTests.swift
//  OPSTests
//
//  Focused regressions for the Supabase bug backlog closed on
//  feat/vinyl-auto-order.
//

import CoreGraphics
import SceneKit
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
        XCTAssertEqual(Double(wallBox?.height ?? 0), 9.0 * 0.3048, accuracy: 0.01)
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

    private func deckDesign(drawingData: DeckDrawingData) -> DeckDesign {
        DeckDesign(
            companyId: "company-1",
            title: "Regression deck",
            drawingDataJSON: drawingData.toJSON()
        )
    }
}
