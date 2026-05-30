//
//  VinylPreviewAnnotationPlannerTests.swift
//  OPSTests
//
//  Geometry-only coverage for the vinyl-order preview callouts.
//

import CoreGraphics
import XCTest
@testable import OPS

final class VinylPreviewAnnotationPlannerTests: XCTestCase {

    func testOverlapLeaderStopsBeforeTextBounds() {
        let placement = VinylPreviewAnnotationPlanner.overlapLeaderPlacement(
            anchor: CGPoint(x: 80, y: 20),
            labelCenter: CGPoint(x: 80, y: 48),
            labelSize: CGSize(width: 84, height: 12),
            padding: 4
        )

        XCTAssertEqual(placement.leaderStart.x, 80, accuracy: 0.001)
        XCTAssertEqual(placement.leaderStart.y, 20, accuracy: 0.001)
        XCTAssertEqual(placement.leaderEnd.x, 80, accuracy: 0.001)
        XCTAssertEqual(placement.leaderEnd.y, 38, accuracy: 0.001)
    }

    func testHouseEdgeLabelPointUsesSmallInsideInsetFromEdge() {
        let labelPoint = VinylPreviewAnnotationPlanner.houseEdgeLabelSourcePoint(
            edgeMidpoint: CGPoint(x: 100, y: 100),
            outwardNormal: CGVector(dx: 0, dy: -1),
            previewScale: 2
        )

        XCTAssertEqual(labelPoint.x, 100, accuracy: 0.001)
        XCTAssertEqual(labelPoint.y, 106, accuracy: 0.001)
    }

    func testHouseEdgeAnnotationStyleIsNeutralAndCompact() {
        XCTAssertEqual(VinylPreviewAnnotationPlanner.houseEdgeTone, .neutral)
        XCTAssertLessThanOrEqual(VinylPreviewAnnotationPlanner.houseEdgeLabelFontSize, 8)
    }
}
