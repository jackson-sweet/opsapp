//
//  DeckStairRenderPlannerTests.swift
//  OPSTests
//
//  Regression coverage for ProjectDetails deck stair rendering.
//

import CoreGraphics
import DeckKit
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
