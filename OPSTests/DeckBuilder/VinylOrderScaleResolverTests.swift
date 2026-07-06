// OPSTests/DeckBuilder/VinylOrderScaleResolverTests.swift
//
// Parity coverage for the scale-resolution logic extracted out of
// DeckBuilderViewModel into the pure `VinylOrderScaleResolver`. Locks the four
// resolution branches (stale-block → scaleFactor → prescale-fallback → inferred)
// so the read-only deck-tab materials list resolves identically to the editor.

import CoreGraphics
import XCTest
@testable import OPS

final class VinylOrderScaleResolverTests: XCTestCase {

    private func edge(
        _ a: DeckVertex,
        _ b: DeckVertex,
        dim: Double?,
        source: DimensionSource,
        stale: Bool = false
    ) -> DeckEdge {
        DeckEdge(
            startVertexId: a.id,
            endVertexId: b.id,
            dimension: dim,
            dimensionSource: source,
            dimensionStale: stale
        )
    }

    private func square(_ side: CGFloat) -> [DeckVertex] {
        [
            CGPoint(x: 0, y: 0),
            CGPoint(x: side, y: 0),
            CGPoint(x: side, y: side),
            CGPoint(x: 0, y: side)
        ].map { DeckVertex(position: $0) }
    }

    /// Four sides of a `side`-pt square, each carrying `dim`/`source`/`stale`.
    private func squareEdges(
        _ verts: [DeckVertex],
        dim: Double?,
        source: DimensionSource,
        staleFirst: Bool = false
    ) -> [DeckEdge] {
        [
            edge(verts[0], verts[1], dim: dim, source: source, stale: staleFirst),
            edge(verts[1], verts[2], dim: dim, source: source),
            edge(verts[2], verts[3], dim: dim, source: source),
            edge(verts[3], verts[0], dim: dim, source: source)
        ]
    }

    // 1. Any stale edge blocks the order outright.
    func testStaleEdgeReturnsNil() {
        let verts = square(100)
        var data = DeckDrawingData()
        data.scaleFactor = 2.0
        data.vertices = verts
        data.edges = squareEdges(verts, dim: 50, source: .manual, staleFirst: true)
        XCTAssertNil(VinylOrderScaleResolver.resolve(data))
    }

    // 2. A persisted scaleFactor wins over everything (even dims implying 4.0).
    func testScaleFactorWinsOverInferredDimensions() {
        let verts = square(100)
        var data = DeckDrawingData()
        data.scaleFactor = 2.0
        data.vertices = verts
        data.edges = squareEdges(verts, dim: 25, source: .manual) // would infer 4.0
        XCTAssertEqual(VinylOrderScaleResolver.resolve(data), 2.0)
    }

    // 3. No scaleFactor, every edge is scale-sourced → prescale fallback.
    func testAllScaleSourceUsesPrescaleFallback() {
        let verts = square(100)
        var data = DeckDrawingData()
        data.vertices = verts
        data.edges = squareEdges(verts, dim: 50, source: .scale)
        XCTAssertEqual(
            VinylOrderScaleResolver.resolve(data),
            DeckBuilderViewModel.prescaleFallbackScale
        )
    }

    // 4. No scaleFactor, agreeing manual-confirmed dims → inferred scale (2.0).
    func testInferredScaleFromAgreeingManualDimensions() {
        let verts = square(100)
        var data = DeckDrawingData()
        data.vertices = verts
        data.edges = squareEdges(verts, dim: 50, source: .manual) // 100pt / 50" = 2.0
        XCTAssertEqual(VinylOrderScaleResolver.resolve(data), 2.0)
    }

    // 5. One dim disagreeing beyond tolerance → nil (drawing untrustworthy).
    func testDisagreeingDimensionReturnsNil() {
        let verts = square(100)
        var data = DeckDrawingData()
        data.vertices = verts
        data.edges = [
            edge(verts[0], verts[1], dim: 50, source: .manual),
            edge(verts[1], verts[2], dim: 50, source: .manual),
            edge(verts[2], verts[3], dim: 50, source: .manual),
            edge(verts[3], verts[0], dim: 40, source: .manual) // 100pt / 40" = 2.5, off by 10"
        ]
        XCTAssertNil(VinylOrderScaleResolver.resolve(data))
    }
}
