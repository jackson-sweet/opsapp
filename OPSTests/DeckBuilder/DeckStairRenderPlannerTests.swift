//
//  DeckStairRenderPlannerTests.swift
//  OPSTests
//
//  Regression coverage for ProjectDetails deck stair rendering.
//

import CoreGraphics
import XCTest
@testable import OPS

final class DeckStairRenderPlannerTests: XCTestCase {

    func testPlanMarksRightAlignedStairBoundaryAndLabelsAdjacentEdgeWidth() throws {
        let plan = try XCTUnwrap(DeckStairRenderPlanner.plan(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 222, y: 0),
            polygonVertices: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 222, y: 0),
                CGPoint(x: 222, y: 96),
                CGPoint(x: 0, y: 96)
            ],
            config: StairConfig(
                width: 48,
                runPerTread: 10,
                treadCount: 4,
                alignment: .right
            ),
            treadCount: 4,
            scaleFactor: 1,
            measurementSystem: .imperial
        ))

        XCTAssertEqual(plan.boundaryMarkers.count, 1)
        XCTAssertEqual(plan.boundaryMarkers[0].x, 174, accuracy: 0.01)
        XCTAssertEqual(plan.boundaryMarkers[0].y, 0, accuracy: 0.01)
        XCTAssertEqual(plan.adjacentEdgeLabels.map(\.text), ["14' 6\""])
        XCTAssertEqual(plan.adjacentEdgeLabels[0].position.x, 87, accuracy: 0.01)
        let widthLabel = try XCTUnwrap(plan.dimensionLabels.first { $0.kind == .width })
        XCTAssertEqual(plan.adjacentEdgeLabels.map(\.lane), [1])
        XCTAssertGreaterThan(
            abs(plan.adjacentEdgeLabels[0].position.y),
            abs(widthLabel.position.y)
        )
        XCTAssertTrue(plan.framePoints.contains(plan.boundaryMarkers[0]))
        XCTAssertTrue(plan.framePoints.contains(plan.adjacentEdgeLabels[0].position))
    }

    func testPlanMarksBothCenteredStairBoundariesAndLabelsBothAdjacentSpans() throws {
        let plan = try XCTUnwrap(DeckStairRenderPlanner.plan(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 144, y: 0),
            polygonVertices: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 144, y: 0),
                CGPoint(x: 144, y: 96),
                CGPoint(x: 0, y: 96)
            ],
            config: StairConfig(width: 48, runPerTread: 10, treadCount: 4),
            treadCount: 4,
            scaleFactor: 1,
            measurementSystem: .imperial
        ))

        XCTAssertEqual(plan.boundaryMarkers.map(\.x), [48, 96])
        XCTAssertEqual(plan.adjacentEdgeLabels.map(\.text), ["4'", "4'"])
        XCTAssertEqual(plan.adjacentEdgeLabels.map(\.lane), [1, 2])
    }

    func testPlanUsesSeparateLanesForNearFullCenteredStairSpans() throws {
        let plan = try XCTUnwrap(DeckStairRenderPlanner.plan(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 54, y: 0),
            polygonVertices: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 54, y: 0),
                CGPoint(x: 54, y: 96),
                CGPoint(x: 0, y: 96)
            ],
            config: StairConfig(width: 48, runPerTread: 10, treadCount: 4),
            treadCount: 4,
            scaleFactor: 1,
            measurementSystem: .imperial
        ))

        XCTAssertEqual(plan.boundaryMarkers.map(\.x), [3, 51])
        XCTAssertEqual(plan.adjacentEdgeLabels.map(\.text), ["3\"", "3\""])
        XCTAssertEqual(plan.adjacentEdgeLabels.map(\.lane), [1, 2])
        XCTAssertNotEqual(
            plan.adjacentEdgeLabels[0].position.y,
            plan.adjacentEdgeLabels[1].position.y
        )
    }

    func testPlanLabelsBothGapsWhenRightAlignedStairHasOffset() throws {
        let plan = try XCTUnwrap(DeckStairRenderPlanner.plan(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 222, y: 0),
            polygonVertices: [],
            config: StairConfig(
                width: 48,
                runPerTread: 10,
                treadCount: 4,
                alignment: .right,
                offset: 12
            ),
            treadCount: 4,
            scaleFactor: 1,
            measurementSystem: .imperial
        ))

        XCTAssertEqual(plan.boundaryMarkers.map(\.x), [162, 210])
        XCTAssertEqual(plan.adjacentEdgeLabels.map(\.text), ["13' 6\"", "1'"])
        XCTAssertEqual(plan.adjacentEdgeLabels.map(\.lane), [1, 2])
    }

    func testPlanPreservesLeftAlignmentWhenEdgeDirectionIsReversed() throws {
        let plan = try XCTUnwrap(DeckStairRenderPlanner.plan(
            edgeStart: CGPoint(x: 222, y: 0),
            edgeEnd: CGPoint(x: 0, y: 0),
            polygonVertices: [],
            config: StairConfig(
                width: 48,
                runPerTread: 10,
                treadCount: 4,
                alignment: .left
            ),
            treadCount: 4,
            scaleFactor: 1,
            measurementSystem: .imperial
        ))

        XCTAssertEqual(plan.boundaryMarkers.count, 1)
        XCTAssertEqual(plan.boundaryMarkers[0].x, 174, accuracy: 0.01)
        XCTAssertEqual(plan.adjacentEdgeLabels.map(\.text), ["14' 6\""])
    }

    func testPlanFormatsStairAndAdjacentWidthsForMetricDrawings() throws {
        let plan = try XCTUnwrap(DeckStairRenderPlanner.plan(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 222, y: 0),
            polygonVertices: [],
            config: StairConfig(
                width: 48,
                runPerTread: 10,
                treadCount: 4,
                alignment: .right
            ),
            treadCount: 4,
            scaleFactor: 1,
            measurementSystem: .metric
        ))

        XCTAssertEqual(plan.dimensionLabels.first { $0.kind == .width }?.text, "WIDTH 1.22 m")
        XCTAssertEqual(plan.adjacentEdgeLabels.map(\.text), ["4.42 m"])
    }

    func testPlanUsesAuthoritativeEdgeDimensionForAdjacentSpanText() throws {
        let plan = try XCTUnwrap(DeckStairRenderPlanner.plan(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 200, y: 0),
            polygonVertices: [],
            config: StairConfig(
                width: 48,
                runPerTread: 10,
                treadCount: 4,
                alignment: .right
            ),
            treadCount: 4,
            scaleFactor: 1,
            measurementSystem: .imperial,
            edgeDimensionInches: 222
        ))

        // Geometry still anchors to the actual drawn edge, while the printed
        // field measurement follows the edge's authoritative typed dimension.
        XCTAssertEqual(plan.boundaryMarkers.map(\.x), [152])
        XCTAssertEqual(plan.adjacentEdgeLabels.map(\.text), ["14' 6\""])
    }

    func testEdgeLabelLanesStayScreenStableAcrossZoomRange() throws {
        let plan = try XCTUnwrap(DeckStairRenderPlanner.plan(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 54, y: 0),
            polygonVertices: [],
            config: StairConfig(width: 48, runPerTread: 10, treadCount: 4),
            treadCount: 4,
            scaleFactor: 1,
            measurementSystem: .imperial
        ))
        let width = try XCTUnwrap(plan.dimensionLabels.first { $0.kind == .width })
        let adjacent = plan.adjacentEdgeLabels

        for zoom: CGFloat in [0.3, 1, 4] {
            let widthPosition = plan.edgeLabelPosition(for: width, zoomScale: zoom)
            let firstPosition = plan.edgeLabelPosition(for: adjacent[0], zoomScale: zoom)
            let secondPosition = plan.edgeLabelPosition(for: adjacent[1], zoomScale: zoom)

            XCTAssertEqual(
                abs(widthPosition.y) * zoom,
                CGFloat(OPSStyle.Layout.spacing3),
                accuracy: 0.01
            )
            XCTAssertEqual(
                abs(firstPosition.y) * zoom,
                CGFloat(OPSStyle.Layout.spacing3) + CGFloat(OPSStyle.Layout.spacing4),
                accuracy: 0.01
            )
            XCTAssertEqual(
                abs(secondPosition.y) * zoom,
                CGFloat(OPSStyle.Layout.spacing3)
                    + CGFloat(OPSStyle.Layout.spacing4) * 2,
                accuracy: 0.01
            )
        }
    }

    func testPlanDoesNotAddSyntheticBoundaryForFullWidthStairs() throws {
        let plan = try XCTUnwrap(DeckStairRenderPlanner.plan(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 48, y: 0),
            polygonVertices: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 48, y: 0),
                CGPoint(x: 48, y: 96),
                CGPoint(x: 0, y: 96)
            ],
            config: StairConfig(width: 48, runPerTread: 10, treadCount: 4),
            treadCount: 4,
            scaleFactor: 1,
            measurementSystem: .imperial
        ))

        XCTAssertTrue(plan.boundaryMarkers.isEmpty)
        XCTAssertTrue(plan.adjacentEdgeLabels.isEmpty)
    }

    func testPlanAddsReadableWidthAndRunLabelsForEdgeStairs() {
        let plan = DeckStairRenderPlanner.plan(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 120, y: 0),
            polygonVertices: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 120, y: 0),
                CGPoint(x: 120, y: 96),
                CGPoint(x: 0, y: 96)
            ],
            config: StairConfig(width: 48, runPerTread: 10, treadCount: 4),
            treadCount: 4,
            scaleFactor: 1,
            measurementSystem: .imperial
        )

        XCTAssertEqual(plan?.outline.count, 4)
        XCTAssertEqual(plan?.treadLines.count, 3)
        XCTAssertEqual(
            plan?.dimensionLabels.map(\.text),
            ["WIDTH 4'", "RUN 3' 4\""]
        )
    }

    func testPlanAddsRailLabelWhenRiseIsKnown() {
        // 30" rise over 4 treads × 10" run = 40" → 30-40-50 triangle: the
        // rail run (hypotenuse — what a stair railing follows) is exactly 50".
        let plan = DeckStairRenderPlanner.plan(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 120, y: 0),
            polygonVertices: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 120, y: 0),
                CGPoint(x: 120, y: 96),
                CGPoint(x: 0, y: 96)
            ],
            config: StairConfig(width: 48, runPerTread: 10, treadCount: 4),
            treadCount: 4,
            scaleFactor: 1,
            measurementSystem: .imperial,
            totalRiseInches: 30
        )

        XCTAssertEqual(
            plan?.dimensionLabels.map(\.text),
            ["WIDTH 4'", "RUN 3' 4\"", "RAIL 4' 2\""]
        )
        XCTAssertEqual(plan?.dimensionLabels.last?.kind, .rail)
        // The rail chip's position is part of the frame so zoom-to-fit never
        // crops it.
        if let plan {
            XCTAssertTrue(plan.framePoints.contains(where: { $0 == plan.dimensionLabels.last?.position }))
        }
    }

    // MARK: - Outward direction (stairs face away from the deck surface)

    /// Every side of a closed square must send stairs OUT of the square,
    /// under both winding directions and with the edge given in either
    /// direction. The old probe-based implementation was only incidentally
    /// right here; the winding math makes it exact.
    func testOutwardPerpendicularPointsAwayFromInterior_allSidesBothWindings() {
        let ccw = [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)
        ]
        let cw = Array(ccw.reversed())
        let center = CGPoint(x: 50, y: 50)

        for polygon in [ccw, cw] {
            for index in 0..<polygon.count {
                let a = polygon[index]
                let b = polygon[(index + 1) % polygon.count]
                // Both traversal directions of the same physical side.
                for (start, end) in [(a, b), (b, a)] {
                    let normal = PolygonMath.outwardPerpendicular(
                        edgeStart: start, edgeEnd: end, polygonVertices: polygon
                    )
                    let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                    // A step along the normal must increase distance from the
                    // centre — i.e. leave the deck.
                    let stepped = CGPoint(x: mid.x + CGFloat(normal.x) * 5,
                                          y: mid.y + CGFloat(normal.y) * 5)
                    XCTAssertGreaterThan(
                        hypot(stepped.x - center.x, stepped.y - center.y),
                        hypot(mid.x - center.x, mid.y - center.y),
                        "normal must point out of the square"
                    )
                    XCTAssertFalse(
                        PolygonMath.pointInPolygon(stepped, vertices: polygon),
                        "stepping along the outward normal must leave the polygon"
                    )
                }
            }
        }
    }

    /// Concave (L-shaped) decks are where a centroid shortcut fails: the
    /// notch edges point away from the interior but TOWARD the centroid.
    func testOutwardPerpendicularHandlesConcaveDeck() {
        // L-shape, clockwise in screen coords.
        let lShape = [
            CGPoint(x: 0, y: 0), CGPoint(x: 120, y: 0), CGPoint(x: 120, y: 60),
            CGPoint(x: 60, y: 60), CGPoint(x: 60, y: 120), CGPoint(x: 0, y: 120)
        ]
        for index in 0..<lShape.count {
            let start = lShape[index]
            let end = lShape[(index + 1) % lShape.count]
            let normal = PolygonMath.outwardPerpendicular(
                edgeStart: start, edgeEnd: end, polygonVertices: lShape
            )
            let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let stepped = CGPoint(x: mid.x + CGFloat(normal.x) * 4,
                                  y: mid.y + CGFloat(normal.y) * 4)
            XCTAssertFalse(
                PolygonMath.pointInPolygon(stepped, vertices: lShape),
                "outward normal of the concave notch must still leave the deck"
            )
        }
    }

    func testPlanHonorsAlignmentOffsetAndFlipDirection() {
        let plan = DeckStairRenderPlanner.plan(
            edgeStart: CGPoint(x: 0, y: 0),
            edgeEnd: CGPoint(x: 144, y: 0),
            polygonVertices: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 144, y: 0),
                CGPoint(x: 144, y: 96),
                CGPoint(x: 0, y: 96)
            ],
            config: StairConfig(
                width: 48,
                runPerTread: 11,
                treadCount: 5,
                alignment: .right,
                offset: 12,
                flipDirection: true
            ),
            treadCount: 5,
            scaleFactor: 1,
            measurementSystem: .imperial
        )

        let baseStart = try! XCTUnwrap(plan?.baseStart)
        let farStart = try! XCTUnwrap(plan?.farStart)

        XCTAssertEqual(baseStart.x, 84, accuracy: 0.01)
        XCTAssertGreaterThan(farStart.y, baseStart.y)
    }
}
