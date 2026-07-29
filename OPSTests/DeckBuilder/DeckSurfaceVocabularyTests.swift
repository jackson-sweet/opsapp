//
//  DeckSurfaceVocabularyTests.swift
//  OPSTests
//
//  Bug ee41a0a0 — the Properties sheet showed every surface as "composite" /
//  "Brown" whether or not anyone had picked those. They were MODEL defaults:
//  the decoder materialised them on any drawing saved before the fields
//  existed, and the sheet rendered them as though the operator had chosen.
//  Unset is now genuinely unset — the sheet reads "—" — while the estimate
//  projection and the 3D renderer keep the concrete fallback so nothing
//  downstream changes shape.
//

import CoreGraphics
import XCTest
@testable import OPS

final class DeckSurfaceVocabularyTests: XCTestCase {

    private func decodeSurface(_ json: String) throws -> DeckSurface {
        try JSONDecoder().decode(DeckSurface.self, from: Data(json.utf8))
    }

    // MARK: - Codable back-compat

    /// A drawing saved before these fields existed has no keys for them.
    /// It must come back unset, NOT silently wearing a material nobody chose.
    func testLegacyJSONWithoutVocabularyDecodesAsUnset() throws {
        let surface = try decodeSurface(#"{"id":"s1","vertexIds":["v1","v2","v3"]}"#)

        XCTAssertNil(surface.color)
        XCTAssertNil(surface.boardMaterial)
    }

    /// A drawing that DID record a choice keeps it exactly.
    func testLegacyJSONWithVocabularyKeepsIt() throws {
        let surface = try decodeSurface(
            #"{"id":"s1","vertexIds":["v1"],"color":"Brown","boardMaterial":"composite"}"#
        )

        XCTAssertEqual(surface.color, "Brown")
        XCTAssertEqual(surface.boardMaterial, "composite")
    }

    func testUnsetVocabularyRoundTrips() throws {
        let original = DeckSurface(id: "s1", vertexIds: ["v1", "v2", "v3"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DeckSurface.self, from: data)

        XCTAssertNil(decoded.color)
        XCTAssertNil(decoded.boardMaterial)
    }

    func testChosenVocabularyRoundTrips() throws {
        let original = DeckSurface(
            id: "s1",
            vertexIds: ["v1", "v2", "v3"],
            color: "Slate",
            boardMaterial: "pvc"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DeckSurface.self, from: data)

        XCTAssertEqual(decoded.color, "Slate")
        XCTAssertEqual(decoded.boardMaterial, "pvc")
    }

    /// A brand-new surface starts unset — the operator hasn't answered yet.
    func testANewSurfaceStartsUnset() {
        let surface = DeckSurface(id: "s1", vertexIds: ["v1"])

        XCTAssertNil(surface.color)
        XCTAssertNil(surface.boardMaterial)
    }

    // MARK: - Projection boundary keeps a concrete value

    private func squareDrawing(surfaceVocabulary: (color: String?, material: String?)) -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 144, y: 144)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 144)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]
        data.surfaces = [
            DeckSurface(
                id: "s1",
                vertexIds: ["v1", "v2", "v3", "v4"],
                color: surfaceVocabulary.color,
                boardMaterial: surfaceVocabulary.material
            )
        ]
        return data
    }

    /// Estimates must not change shape because the operator left a field
    /// blank — the adapter still receives a concrete vocabulary.
    func testEmitterSubstitutesTheDefaultVocabularyForAnUnsetSurface() {
        let rows = ComponentEmitter.emit(squareDrawing(surfaceVocabulary: (nil, nil)))
        guard let board = rows.first(where: { $0.componentType == "deck_board" }) else {
            return XCTFail("expected a deck_board row")
        }

        XCTAssertEqual(board.metadata["color"], AnyCodable(DeckSurfaceDefaults.color))
        XCTAssertEqual(board.metadata["material"], AnyCodable(DeckSurfaceDefaults.boardMaterial))
    }

    func testEmitterUsesTheOperatorsChoiceWhenTheyMadeOne() {
        let rows = ComponentEmitter.emit(squareDrawing(surfaceVocabulary: ("Slate", "pvc")))
        guard let board = rows.first(where: { $0.componentType == "deck_board" }) else {
            return XCTFail("expected a deck_board row")
        }

        XCTAssertEqual(board.metadata["color"], AnyCodable("Slate"))
        XCTAssertEqual(board.metadata["material"], AnyCodable("pvc"))
    }

    // MARK: - Resolver reports unset honestly

    func testResolverReportsUnsetRatherThanInventingAMaterial() {
        let detected = DetectedSurface(
            id: "d1",
            vertexIds: ["v1", "v2", "v3", "v4"],
            positions: [
                CGPoint(x: 0, y: 0), CGPoint(x: 144, y: 0),
                CGPoint(x: 144, y: 144), CGPoint(x: 0, y: 144),
            ]
        )
        let payload = DeckSurfaceInspector.resolvedPayload(
            detected: detected,
            persisted: [],
            legacyFootprint: DeckFootprint(),
            isLegacyPrimary: false
        )

        XCTAssertNil(payload.color)
        XCTAssertNil(payload.boardMaterial)
    }

    /// The by-type readout says DECKING for an unnamed surface — never a
    /// material the operator did not choose.
    func testReadoutLabelsAnUnsetSurfaceAsPlainDecking() {
        let payload = DeckResolvedSurfacePayload(
            persistedId: "s1",
            assignedItems: [],
            label: nil,
            color: nil,
            boardMaterial: nil
        )

        XCTAssertEqual(DeckSelectionReadout.surfaceMaterialLabel(payload), "DECKING")
    }
}
