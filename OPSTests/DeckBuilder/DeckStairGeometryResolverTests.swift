//
//  DeckStairGeometryResolverTests.swift
//  OPSTests
//
//  Bug 4a773e11 — stairs drawn backwards in 2D while 3D drew them correctly
//  from the same stored model.
//
//  These tests assert ORIENTATION, never pixels: which way a stair travels,
//  which axis its treads lie on, and that the answer is the same no matter
//  which renderer asks or which coordinate space it asks in.
//
//  The primary fixture is real production geometry — deck_designs row
//  f5c2eb47-ab88-4503-a66c-e3c83baeb12c, "3998 Holland Ave", the deck whose
//  level-1-to-level-2 stair rendered mirrored in plan. Canvas coordinates are
//  reproduced verbatim from `drawing_data`.
//

import CoreGraphics
import XCTest
@testable import OPS

final class DeckStairGeometryResolverTests: XCTestCase {

    // MARK: - Reported case A: connection stair mirrored in 2D

    /// 3998 Holland Ave. Upper level (3' 7") sits at canvas y 2400…2568; the
    /// lower level (1' 11") sits below it at y 2568…3000. The connection rides
    /// the upper level's y = 2568 edge, and the stored `flipDirection` is TRUE
    /// — the operator set it to correct the 3D view, which is the only view
    /// that was right.
    ///
    /// A connecting stair has to land on the deck below. Travel is +y here, and
    /// the flip toggle must not be able to send it back across the deck it
    /// descends from.
    func testHollandAveConnectionStairTravelsTowardTheLowerLevel() throws {
        let orientation = try XCTUnwrap(DeckStairGeometryResolver.connectionOrientation(
            edgeStart: HollandAve.edgeStart,
            edgeEnd: HollandAve.edgeEnd,
            upperFacePolygon: HollandAve.upperFace,
            lowerDestination: HollandAve.lowerDestination,
            flipDirection: true
        ))

        XCTAssertEqual(orientation.facing, .towardLowerLevel)
        XCTAssertEqual(orientation.travel.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(orientation.travel.dy, 1, accuracy: 1e-9,
                       "the lower level lies at greater y — the stair must descend toward it")
        XCTAssertFalse(orientation.userFlipApplied,
                       "a connection stair's destination is a fact, not a preference")
    }

    /// The same drawing with the toggle cleared resolves identically. Before the
    /// fix these two differed by 180°, which is exactly what the operator saw
    /// between the 2D and 3D views.
    func testHollandAveConnectionStairIgnoresTheFlipToggle() throws {
        let flipped = try XCTUnwrap(DeckStairGeometryResolver.connectionOrientation(
            edgeStart: HollandAve.edgeStart,
            edgeEnd: HollandAve.edgeEnd,
            upperFacePolygon: HollandAve.upperFace,
            lowerDestination: HollandAve.lowerDestination,
            flipDirection: true
        ))
        let unflipped = try XCTUnwrap(DeckStairGeometryResolver.connectionOrientation(
            edgeStart: HollandAve.edgeStart,
            edgeEnd: HollandAve.edgeEnd,
            upperFacePolygon: HollandAve.upperFace,
            lowerDestination: HollandAve.lowerDestination,
            flipDirection: false
        ))

        assertParallel(flipped.travel, unflipped.travel, "flip must not move a connection stair")
    }

    /// The bug's signature: 2D and 3D disagreeing. 3D evaluates the same
    /// geometry in metres against a scene-wide centre, which is a positive
    /// uniform scale plus a translation. The resolved direction must survive
    /// that map exactly.
    func testConnectionStairResolvesIdenticallyInCanvasPointsAndInMetres() throws {
        let canvas = try XCTUnwrap(DeckStairGeometryResolver.connectionOrientation(
            edgeStart: HollandAve.edgeStart,
            edgeEnd: HollandAve.edgeEnd,
            upperFacePolygon: HollandAve.upperFace,
            lowerDestination: HollandAve.lowerDestination,
            flipDirection: true
        ))

        // The scene's canvas → metres map: subtract a shared centre, scale by a
        // single positive factor.
        let centre = CGPoint(x: 2600, y: 2500)
        let metresPerPoint: CGFloat = 1.0 / 12.0 / 39.3701
        func toMetres(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: (point.x - centre.x) * metresPerPoint,
                y: (point.y - centre.y) * metresPerPoint
            )
        }

        let metres = try XCTUnwrap(DeckStairGeometryResolver.connectionOrientation(
            edgeStart: toMetres(HollandAve.edgeStart),
            edgeEnd: toMetres(HollandAve.edgeEnd),
            upperFacePolygon: HollandAve.upperFace.map(toMetres),
            lowerDestination: toMetres(HollandAve.lowerDestination),
            flipDirection: true
        ))

        XCTAssertEqual(metres.facing, canvas.facing)
        assertParallel(canvas.travel, metres.travel, "2D and 3D must resolve one direction")
        assertParallel(canvas.treadAxis, metres.treadAxis)
    }

    // MARK: - Reported case B: tread axis

    /// Rose Vlaar's report — the stair reading as though it ran sideways along
    /// the deck edge. A tread is a step you stand across, so in plan every
    /// tread line lies PARALLEL to the host edge and PERPENDICULAR to travel.
    /// The connection renderers used to draw their lines along the direction of
    /// travel, which renders the stringers, not the treads.
    func testConnectionStairTreadLinesRunParallelToTheHostEdgeAndAcrossTravel() throws {
        let plan = try XCTUnwrap(DeckStairRenderPlanner.connectionPlan(
            edgeStart: HollandAve.edgeStart,
            edgeEnd: HollandAve.edgeEnd,
            upperFacePolygon: HollandAve.upperFace,
            lowerDestination: HollandAve.lowerDestination,
            config: StairConfig(width: 168, runPerTread: 10, treadCount: 3, flipDirection: true),
            treadCount: 3,
            scaleFactor: 1,
            measurementSystem: .imperial
        ))

        XCTAssertFalse(plan.treadLines.isEmpty)
        let edgeAxis = CGVector(dx: -1, dy: 0)  // the host edge runs -x
        for tread in plan.treadLines {
            let line = CGVector(dx: tread.end.x - tread.start.x, dy: tread.end.y - tread.start.y)
            assertParallel(normalized(line), edgeAxis, "treads lie along the host edge")
            let dotWithTravel = line.dx * plan.orientation.travel.dx + line.dy * plan.orientation.travel.dy
            XCTAssertEqual(dotWithTravel, 0, accuracy: 1e-6, "treads never run along the descent")
        }
    }

    /// A stair projects its real run — tread count × run per tread × scale —
    /// not a fixed decorative band. The connection renderers hardcoded 20, 24
    /// and 30 point depths regardless of the stair.
    func testConnectionStairProjectsItsRealRunDepth() throws {
        let plan = try XCTUnwrap(DeckStairRenderPlanner.connectionPlan(
            edgeStart: HollandAve.edgeStart,
            edgeEnd: HollandAve.edgeEnd,
            upperFacePolygon: HollandAve.upperFace,
            lowerDestination: HollandAve.lowerDestination,
            config: StairConfig(width: 168, runPerTread: 10, treadCount: 3),
            treadCount: 3,
            scaleFactor: 2,
            measurementSystem: .imperial
        ))

        // 3 treads × 10" × 2 points-per-inch = 60 points of run.
        let depth = hypot(plan.farStart.x - plan.baseStart.x, plan.farStart.y - plan.baseStart.y)
        XCTAssertEqual(depth, 60, accuracy: 1e-6)
        // 168" wide × 2 = 336 points, which is exactly the host edge here.
        let width = hypot(plan.baseEnd.x - plan.baseStart.x, plan.baseEnd.y - plan.baseStart.y)
        XCTAssertEqual(width, 336, accuracy: 1e-6)
    }

    // MARK: - Mirror and rotation cases around the reports

    /// The host edge's stored direction is an accident of how the operator drew
    /// it. Reversing it must not move the stair — the raw-winding perpendicular
    /// that 3D used to trust does exactly that.
    func testReversingTheStoredEdgeDirectionDoesNotMoveTheStair() throws {
        let forward = try XCTUnwrap(DeckStairGeometryResolver.connectionOrientation(
            edgeStart: HollandAve.edgeStart,
            edgeEnd: HollandAve.edgeEnd,
            upperFacePolygon: HollandAve.upperFace,
            lowerDestination: HollandAve.lowerDestination,
            flipDirection: false
        ))
        let reversed = try XCTUnwrap(DeckStairGeometryResolver.connectionOrientation(
            edgeStart: HollandAve.edgeEnd,
            edgeEnd: HollandAve.edgeStart,
            upperFacePolygon: HollandAve.upperFace,
            lowerDestination: HollandAve.lowerDestination,
            flipDirection: false
        ))

        assertParallel(forward.travel, reversed.travel,
                       "edge winding is a drawing accident, not a direction")
    }

    /// Rotating the whole design rotates the stair with it, and nothing else
    /// changes. Runs all four quarter turns so a sign error on any axis pair
    /// cannot hide.
    func testRotatingTheDesignRotatesTheStairWithIt() throws {
        for degrees in [90.0, 180.0, 270.0] {
            let radians = degrees * .pi / 180
            func rotate(_ point: CGPoint) -> CGPoint {
                CGPoint(
                    x: point.x * cos(radians) - point.y * sin(radians),
                    y: point.x * sin(radians) + point.y * cos(radians)
                )
            }

            let base = try XCTUnwrap(DeckStairGeometryResolver.connectionOrientation(
                edgeStart: HollandAve.edgeStart,
                edgeEnd: HollandAve.edgeEnd,
                upperFacePolygon: HollandAve.upperFace,
                lowerDestination: HollandAve.lowerDestination,
                flipDirection: false
            ))
            let turned = try XCTUnwrap(DeckStairGeometryResolver.connectionOrientation(
                edgeStart: rotate(HollandAve.edgeStart),
                edgeEnd: rotate(HollandAve.edgeEnd),
                upperFacePolygon: HollandAve.upperFace.map(rotate),
                lowerDestination: rotate(HollandAve.lowerDestination),
                flipDirection: false
            ))

            let expected = CGVector(
                dx: base.travel.dx * cos(radians) - base.travel.dy * sin(radians),
                dy: base.travel.dx * sin(radians) + base.travel.dy * cos(radians)
            )
            assertParallel(turned.travel, expected, "rotation \(Int(degrees))° did not carry the stair")
            XCTAssertEqual(turned.facing, .towardLowerLevel)
        }
    }

    /// Mirroring the design mirrors the stair. A resolver that leaned on a
    /// fixed handedness rather than on the deck itself would keep pointing the
    /// old way here.
    func testMirroringTheDesignMirrorsTheStair() throws {
        func mirror(_ point: CGPoint) -> CGPoint { CGPoint(x: -point.x, y: point.y) }

        let base = try XCTUnwrap(DeckStairGeometryResolver.connectionOrientation(
            edgeStart: HollandAve.edgeStart,
            edgeEnd: HollandAve.edgeEnd,
            upperFacePolygon: HollandAve.upperFace,
            lowerDestination: HollandAve.lowerDestination,
            flipDirection: false
        ))
        let mirrored = try XCTUnwrap(DeckStairGeometryResolver.connectionOrientation(
            edgeStart: mirror(HollandAve.edgeStart),
            edgeEnd: mirror(HollandAve.edgeEnd),
            upperFacePolygon: HollandAve.upperFace.map(mirror),
            lowerDestination: mirror(HollandAve.lowerDestination),
            flipDirection: false
        ))

        assertParallel(mirrored.travel, CGVector(dx: -base.travel.dx, dy: base.travel.dy))
    }

    /// Move the lower level to the far side of the host edge and the stair
    /// follows it. This is the case the old "always outward from the upper
    /// face" rule could not express.
    func testStairFollowsTheLowerLevelWhenItSitsOnTheOtherSide() throws {
        let near = try XCTUnwrap(DeckStairGeometryResolver.connectionOrientation(
            edgeStart: HollandAve.edgeStart,
            edgeEnd: HollandAve.edgeEnd,
            upperFacePolygon: HollandAve.upperFace,
            lowerDestination: CGPoint(x: 2556, y: 2733),   // below the edge
            flipDirection: false
        ))
        let far = try XCTUnwrap(DeckStairGeometryResolver.connectionOrientation(
            edgeStart: HollandAve.edgeStart,
            edgeEnd: HollandAve.edgeEnd,
            upperFacePolygon: HollandAve.upperFace,
            lowerDestination: CGPoint(x: 2556, y: 2450),   // above the edge
            flipDirection: false
        ))

        XCTAssertEqual(near.travel.dy, 1, accuracy: 1e-9)
        XCTAssertEqual(far.travel.dy, -1, accuracy: 1e-9)
    }

    /// With no destination and no closed face, nothing in the drawing names a
    /// side — and only then does the operator's toggle get a vote.
    func testFlipStillDecidesWhenTheDrawingNamesNoSide() throws {
        let unflipped = try XCTUnwrap(DeckStairGeometryResolver.connectionOrientation(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 100, y: 0),
            upperFacePolygon: [],
            lowerDestination: nil,
            flipDirection: false
        ))
        let flipped = try XCTUnwrap(DeckStairGeometryResolver.connectionOrientation(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 100, y: 0),
            upperFacePolygon: [],
            lowerDestination: nil,
            flipDirection: true
        ))

        XCTAssertEqual(unflipped.facing, .edgeWindingFallback)
        XCTAssertTrue(flipped.userFlipApplied)
        assertParallel(flipped.travel, CGVector(dx: -unflipped.travel.dx, dy: -unflipped.travel.dy))
    }

    // MARK: - Edge-attached stairs

    /// An edge stair lands on grade, so the operator's flip is legitimate and
    /// must keep working. Guards the resolver refactor against over-reach.
    func testEdgeStairRunsOffTheDeckSurfaceAndHonoursFlip() throws {
        let square = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 0, y: 100)
        ]
        let outward = try XCTUnwrap(DeckStairGeometryResolver.orientation(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 100, y: 0),
            deckFacePolygon: square,
            flipDirection: false
        ))
        let flipped = try XCTUnwrap(DeckStairGeometryResolver.orientation(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 100, y: 0),
            deckFacePolygon: square,
            flipDirection: true
        ))

        XCTAssertEqual(outward.facing, .awayFromDeckSurface)
        XCTAssertEqual(outward.travel.dy, -1, accuracy: 1e-9, "away from the fill at y > 0")
        XCTAssertTrue(flipped.userFlipApplied)
        XCTAssertEqual(flipped.travel.dy, 1, accuracy: 1e-9)
    }

    /// Reversing an edge stair's stored winding must not move it either.
    func testEdgeStairIgnoresStoredEdgeWinding() throws {
        let square = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 0, y: 100)
        ]
        let forward = try XCTUnwrap(DeckStairGeometryResolver.orientation(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 100, y: 0),
            deckFacePolygon: square,
            flipDirection: false
        ))
        let reversed = try XCTUnwrap(DeckStairGeometryResolver.orientation(
            edgeStart: CGPoint(x: 100, y: 0),
            edgeEnd: CGPoint(x: 0, y: 0),
            deckFacePolygon: square,
            flipDirection: false
        ))

        assertParallel(forward.travel, reversed.travel)
    }

    // MARK: - Tread count

    /// 2D used to require a stored override and drew nothing without one, while
    /// 3D always derived a count — so a stair on an auto-counted rise existed in
    /// one view and not the other.
    func testTreadCountDerivesFromRiseWhenNoOverrideIsStored() {
        let config = StairConfig(width: 36, risePerStep: 7.5, runPerTread: 10)
        XCTAssertEqual(
            DeckStairGeometryResolver.treadCount(config: config, totalRiseInches: 60),
            8
        )
        XCTAssertNil(DeckStairGeometryResolver.treadCount(config: config, totalRiseInches: nil))
        XCTAssertNil(DeckStairGeometryResolver.treadCount(config: config, totalRiseInches: 0))
    }

    func testStoredTreadCountOverridesTheDerivedOne() {
        let config = StairConfig(width: 36, risePerStep: 7.5, runPerTread: 10, treadCount: 3)
        XCTAssertEqual(
            DeckStairGeometryResolver.treadCount(config: config, totalRiseInches: 60),
            3
        )
    }

    // MARK: - Fixture

    /// Verbatim canvas geometry from deck_designs f5c2eb47 "3998 Holland Ave".
    private enum HollandAve {
        /// Connection edge AFE7A69A on Level 1, running from (2724, 2568) to
        /// (2388, 2568) — i.e. along -x at the upper level's lower boundary.
        static let edgeStart = CGPoint(x: 2724, y: 2568)
        static let edgeEnd = CGPoint(x: 2388, y: 2568)

        /// The closed face on Level 1 that owns that edge.
        static let upperFace = [
            CGPoint(x: 2316, y: 2400),
            CGPoint(x: 2724, y: 2400),
            CGPoint(x: 2724, y: 2568),
            CGPoint(x: 2388, y: 2568),
            CGPoint(x: 2316, y: 2568)
        ]

        /// Mean of Level 2's nine stored vertices — the footprint the stair has
        /// to reach.
        static let lowerDestination = CGPoint(x: 2553.33, y: 2733.33)
    }

    // MARK: - Helpers

    private func normalized(_ vector: CGVector) -> CGVector {
        let length = hypot(vector.dx, vector.dy)
        guard length > 0 else { return vector }
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }

    private func assertParallel(
        _ lhs: CGVector,
        _ rhs: CGVector,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let a = normalized(lhs)
        let b = normalized(rhs)
        XCTAssertEqual(a.dx, b.dx, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(a.dy, b.dy, accuracy: 1e-6, message, file: file, line: line)
    }
}
