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
