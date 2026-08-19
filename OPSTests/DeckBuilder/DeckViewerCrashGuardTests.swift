//
//  DeckViewerCrashGuardTests.swift
//  OPSTests
//
//  A deck drawing is USER DATA that arrives over sync from other devices, and
//  the read-only viewers (the lead deck screen, the project deck tab, the share
//  and overlay renderers) open it unconditionally. Every trap below aborts the
//  process — no `catch` can intercept a trapping `Int(_:)` conversion, a
//  `Dictionary` uniqueness precondition, or a stack overflow — so a single
//  malformed field would take the app down on open with no diagnostic beyond a
//  SIGTRAP. These tests pin the guards that keep a corrupt drawing renderable
//  (or blank) instead of fatal.
//
//  Why these paths, now: `2d0d83bc` (2026-08-18) replaced
//  `if let treadCount = edge.stairConfig?.treadCount, treadCount > 0` with
//  `if edge.stairConfig != nil` in `DeckTab2DView`, deliberately so that a stair
//  whose tread count is DERIVED rather than stored finally draws. That was the
//  right call — but it also made `StairConfig.calculateTreadCount` reachable
//  from a plain deck view for the first time, and every in-app level-connection
//  stair takes the derived branch (`StairConfigView.applyStairs` leaves
//  `treadCount` nil on purpose so the count tracks live level heights).
//
//  NOTE ON LITERALS: every floating-point argument below names its type
//  explicitly (`Double.nan`, `Float.infinity`, `240.0`). `SCNVector3` and
//  `CGPoint` each expose Float/CGFloat/Double/Int initializer overloads, so a
//  bare `.nan` or `.infinity` is genuinely ambiguous to the type checker and
//  fails the build — a file about degenerate float inputs is exactly where that
//  bites.
//

#if DEBUG
import CoreGraphics
import SceneKit
import simd
import XCTest
@testable import OPS

final class DeckViewerCrashGuardTests: XCTestCase {

    // MARK: - Derived tread count

    /// The real values off a shipped lead deck (deck_designs "636 Langford St":
    /// 97.5" total rise, 7.5" risers). Pins that hardening the guard did not
    /// move the answer for well-formed data.
    func testDerivedTreadCountUnchangedForRealDeck() {
        XCTAssertEqual(
            StairConfig.calculateTreadCount(totalRise: 97.5, risePerStep: 7.5),
            13
        )
        // Partial step rounds up — a stair always reaches the deck.
        XCTAssertEqual(
            StairConfig.calculateTreadCount(totalRise: 30.0, risePerStep: 7.5),
            4
        )
    }

    /// `Int(ceil(totalRise / 0))` is `Int(+inf)`, which TRAPS. `risePerStep`
    /// reaches this straight from stored JSON, so this is the crash guard.
    func testDerivedTreadCountSurvivesZeroRisePerStep() {
        XCTAssertEqual(
            StairConfig.calculateTreadCount(totalRise: 97.5, risePerStep: 0.0),
            0
        )
    }

    func testDerivedTreadCountSurvivesNonFiniteInputs() {
        XCTAssertEqual(
            StairConfig.calculateTreadCount(totalRise: 97.5, risePerStep: Double.nan),
            0
        )
        XCTAssertEqual(
            StairConfig.calculateTreadCount(totalRise: 97.5, risePerStep: -0.0),
            0
        )
        XCTAssertEqual(
            StairConfig.calculateTreadCount(totalRise: Double.nan, risePerStep: 7.5),
            0
        )
        XCTAssertEqual(
            StairConfig.calculateTreadCount(totalRise: Double.infinity, risePerStep: 7.5),
            0
        )
    }

    /// A rise big enough to overflow the conversion clamps instead of trapping.
    func testDerivedTreadCountClampsAbsurdRise() {
        let count = StairConfig.calculateTreadCount(totalRise: 1e300, risePerStep: 0.0001)
        XCTAssertEqual(count, StairConfig.maximumTreadCount)
    }

    // MARK: - The decode hole that feeds it

    /// `decodeIfPresent(...) ?? 7.5` only defaults a MISSING key — an explicit
    /// zero survives decoding. This documents the vector rather than asserting
    /// it away, because the fix belongs in the consumer (a stored drawing is
    /// never rewritten just because it was opened).
    func testExplicitZeroRisePerStepSurvivesDecode() throws {
        let json = Data(#"{"width":48,"risePerStep":0,"runPerTread":10}"#.utf8)
        let config = try JSONDecoder().decode(StairConfig.self, from: json)
        XCTAssertEqual(config.risePerStep, 0.0)
        XCTAssertNil(config.treadCount)
    }

    /// End to end: the exact shape `2d0d83bc` newly admits — a stair with NO
    /// stored tread count and a zero riser. Before the guard this trapped inside
    /// `DeckStairGeometryResolver.treadCount`; now it resolves to "no plan".
    func testStairPlanDoesNotTrapOnDerivedCountWithZeroRiser() {
        var drawing = DeckDrawingData()
        drawing.scaleFactor = 1.0
        drawing.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 48, y: 0))
        ]
        var edge = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2", dimension: 48.0)
        edge.stairConfig = StairConfig(
            width: 48.0,
            risePerStep: 0.0,
            runPerTread: 10.0,
            treadCount: nil
        )
        drawing.edges = [edge]

        // The assertion is that this RETURNS. A trap would abort the process.
        let plan = drawing.edgeStairPlan(
            for: edge,
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 48, y: 0)
        )
        XCTAssertNil(plan, "A stair with no derivable tread count renders nothing, it does not crash")
    }

    // MARK: - Dimension formatting

    /// `NaN >= 0` is false and `abs(NaN)` is NaN, so the negative-value branch
    /// recursed on the identical argument forever and overflowed the stack.
    func testFormatImperialSurvivesNonFiniteInput() {
        XCTAssertEqual(DimensionEngine.formatImperial(Double.nan), "—")
        XCTAssertEqual(DimensionEngine.formatImperial(Double.infinity), "—")
        XCTAssertEqual(DimensionEngine.formatImperial(-Double.infinity), "—")
    }

    func testFormatImperialUnchangedForRealDimensions() {
        XCTAssertEqual(DimensionEngine.formatImperial(240.0), "20'")
        XCTAssertEqual(DimensionEngine.formatImperial(294.0), "24' 6\"")
    }

    /// `+inf >= 10` is true, so the infinite case reached `Int(_:)` and trapped.
    func testFormatAreaSurvivesNonFiniteInput() {
        XCTAssertEqual(DimensionEngine.formatAreaImperial(Double.infinity), "—")
        XCTAssertEqual(DimensionEngine.formatAreaImperial(Double.nan), "—")
    }

    func testFormatAreaUnchangedForRealAreas() {
        // 240" × 144" = 34,560 sq in = 240 sq ft.
        XCTAssertEqual(DimensionEngine.formatAreaImperial(34_560.0), "240 sq ft")
    }

    // MARK: - Scene geometry

    /// `simd_normalize` of a zero vector is NaN, and a NaN quaternion silently
    /// corrupts the whole node transform. A self-loop edge produces exactly this.
    ///
    /// `SCNVector3`'s components are `Float`; every argument is built as a
    /// concrete `Float` so only the `(Float, Float, Float)` overload can match.
    func testSpanningOrientationIsFiniteForDegenerateDirection() {
        let degenerateDirections: [SCNVector3] = [
            SCNVector3(Float.zero, Float.zero, Float.zero),
            SCNVector3(Float.nan, Float.zero, Float.zero),
            SCNVector3(Float.zero, Float.infinity, Float.zero)
        ]

        for direction in degenerateDirections {
            let orientation = DeckSceneBuilder.spanningBoxOrientation(direction: direction)
            let vector = orientation.vector
            XCTAssertTrue(
                vector.x.isFinite && vector.y.isFinite
                    && vector.z.isFinite && vector.w.isFinite,
                "Degenerate span (\(direction.x), \(direction.y), \(direction.z)) produced a non-finite orientation"
            )
        }
    }

    /// `Dictionary(uniqueKeysWithValues:)` traps on a duplicate key, and nothing
    /// validates vertex-id uniqueness on decode or on import. This runs during
    /// camera framing — the first thing `buildScene` does.
    func testBuildSceneSurvivesDuplicateVertexIds() {
        var drawing = DeckDrawingData()
        drawing.scaleFactor = 1.0
        drawing.vertices = [
            DeckVertex(id: "dup", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "dup", position: CGPoint(x: 48, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 48, y: 48))
        ]
        var edge = DeckEdge(id: "e1", startVertexId: "dup", endVertexId: "v3", dimension: 48.0)
        edge.stairConfig = StairConfig(
            width: 48.0,
            risePerStep: 7.5,
            runPerTread: 10.0,
            treadCount: 4
        )
        drawing.edges = [edge]

        // Returning at all is the assertion; a scene always carries its ground,
        // lights and camera, so an empty root would mean we bailed early.
        let scene = DeckSceneBuilder.buildScene(from: drawing)
        XCTAssertFalse(scene.rootNode.childNodes.isEmpty)
    }

    /// A self-loop edge (both endpoints resolving to one vertex) is what the
    /// sketch-scan and AR importers produce for a very short segment — they map
    /// each end to the closest vertex with no "must differ" rule.
    func testBuildSceneSurvivesZeroLengthEdge() {
        var drawing = DeckDrawingData()
        drawing.scaleFactor = 1.0
        drawing.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 48, y: 0))
        ]
        drawing.edges = [
            DeckEdge(id: "loop", startVertexId: "v1", endVertexId: "v1", dimension: 0.0),
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2", dimension: 48.0)
        ]

        let scene = DeckSceneBuilder.buildScene(from: drawing)
        XCTAssertFalse(scene.rootNode.childNodes.isEmpty)
    }
}
#endif
