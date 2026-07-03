//
//  DeckCanvasSceneCalibrationTests.swift
//  OPSTests
//
//  Regression coverage for the deck builder's own 3D canvas (DeckScene3DView)
//  rendering an empty scene for uncalibrated drawings.
//
//  ~93% of saved decks — and EVERY freshly drawn deck in the builder — have no
//  `scaleFactor`. `DeckSceneBuilder.buildScene(from:)` returns a ground+lights
//  only scene for those (the guard at the top of buildScene), so the builder's
//  3D toggle showed a black screen with no deck. The project-details tab already
//  worked around this by injecting `effectiveScaleFactor`; the canvas did not.
//  Both viewers now route through `DeckSceneBuilder.buildCalibratedScene(from:)`,
//  which injects the prescale fallback so uncalibrated decks always render.
//

import SceneKit
import XCTest
@testable import OPS

final class DeckCanvasSceneCalibrationTests: XCTestCase {

    /// A closed 12' x 10' square with real per-edge dimensions but NO
    /// `scaleFactor` — exactly the shape a user just drew in the builder.
    private func uncalibratedClosedDeck() -> DeckDrawingData {
        var data = DeckDrawingData()
        // scaleFactor deliberately left nil — the crux of the bug.
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 144, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]
        return data
    }

    private func deckSurfaceCount(in scene: SCNScene) -> Int {
        var count = 0
        scene.rootNode.enumerateHierarchy { node, _ in
            if node.name == "deckSurface" { count += 1 }
        }
        return count
    }

    /// Documents the trap: the primitive builder renders NOTHING for an
    /// uncalibrated drawing. If this ever starts producing deck geometry the
    /// guard changed and the fix below can be revisited.
    func testRawBuilderRendersEmptyForUncalibratedDeck() {
        let scene = DeckSceneBuilder.buildScene(from: uncalibratedClosedDeck())
        XCTAssertEqual(deckSurfaceCount(in: scene), 0,
                       "Raw buildScene should return an empty (ground+lights) scene when scaleFactor is nil")
        XCTAssertNil(scene.rootNode.childNode(withName: "camera", recursively: true),
                     "Raw buildScene's empty path adds no camera")
    }

    /// The fix: the calibrated entry point injects the prescale fallback so the
    /// same uncalibrated deck renders its surface AND a framing camera — this is
    /// what the builder's 3D canvas now calls.
    func testCalibratedBuilderRendersUncalibratedDeck() {
        let scene = DeckSceneBuilder.buildCalibratedScene(from: uncalibratedClosedDeck())
        XCTAssertGreaterThan(deckSurfaceCount(in: scene), 0,
                             "Calibrated builder must render deck geometry for an uncalibrated drawing")
        XCTAssertNotNil(scene.rootNode.childNode(withName: "camera", recursively: true),
                        "Calibrated builder must add a framing camera so pointOfView is set")
    }

    /// A calibrated drawing must be untouched — the calibrated wrapper is a
    /// no-op passthrough when a real scaleFactor is already present.
    func testCalibratedBuilderPassesThroughCalibratedDeck() {
        var data = uncalibratedClosedDeck()
        data.scaleFactor = 1.0
        let scene = DeckSceneBuilder.buildCalibratedScene(from: data)
        XCTAssertGreaterThan(deckSurfaceCount(in: scene), 0)
        XCTAssertNotNil(scene.rootNode.childNode(withName: "camera", recursively: true))
    }

    // MARK: - AR placement (same uncalibrated trap in buildARNode)

    /// The raw AR node is empty for an uncalibrated deck — "View in AR" placed
    /// nothing.
    func testRawARNodeEmptyForUncalibratedDeck() {
        let node = DeckSceneBuilder.buildARNode(from: uncalibratedClosedDeck())
        XCTAssertTrue(node.childNodes.isEmpty,
                      "Raw buildARNode returns an empty root when scaleFactor is nil")
    }

    /// The calibrated AR node places the deck geometry for an uncalibrated deck.
    func testCalibratedARNodeRendersUncalibratedDeck() {
        let node = DeckSceneBuilder.buildCalibratedARNode(from: uncalibratedClosedDeck())
        var surfaces = 0
        node.enumerateHierarchy { child, _ in
            if child.name == "deckSurface" { surfaces += 1 }
        }
        XCTAssertGreaterThan(surfaces, 0,
                             "Calibrated AR node must place deck geometry for an uncalibrated drawing")
    }
}
