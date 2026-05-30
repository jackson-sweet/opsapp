//
//  VinylPreviewAnnotationPlannerTests.swift
//  OPSTests
//
//  Regression coverage for deck visualizer vinyl preview annotations,
//  plus geometry-only coverage for the vinyl-order preview callouts.
//

import CoreGraphics
import XCTest
@testable import OPS

final class VinylPreviewAnnotationPlannerTests: XCTestCase {

    func testHouseWrapUsesNeutralMarkupAndCompactInsideLabel() {
        let surface = vinylSurfacePlan()
        let plan = VinylPreviewAnnotationPlanner.plan(
            surface: surface,
            settings: .default,
            viewportScale: 1
        )

        let houseBand = try! XCTUnwrap(plan.bands.first { $0.edgeType == .houseEdge })
        let houseLabel = try! XCTUnwrap(plan.houseLabels.first)

        XCTAssertEqual(houseBand.tone, .neutral)
        XCTAssertEqual(houseLabel.tone, .neutral)
        XCTAssertLessThan(houseLabel.distanceFromEdge, CGFloat(OPSStyle.Layout.spacing3))
        XCTAssertFalse(houseBand.hatchLines.isEmpty)
    }

    func testOverlapLeaderStopsBeforeTheLabelRect() {
        let surface = vinylSurfacePlan()
        let plan = VinylPreviewAnnotationPlanner.plan(
            surface: surface,
            settings: .default,
            viewportScale: 1
        )

        let houseLeader = try! XCTUnwrap(plan.leaders.first { $0.edgeType == .houseEdge })

        XCTAssertFalse(houseLeader.labelRect.insetBy(dx: -0.5, dy: -0.5).contains(houseLeader.lineEnd))
        XCTAssertLessThan(houseLeader.lineLength, houseLeader.centerLineLength)
    }

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

    private func vinylSurfacePlan() -> VinylSurfaceCutPlan {
        let surface = VinylOrderSurfaceInput(
            id: "surface",
            label: "Deck",
            levelName: nil,
            positions: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 120, y: 0),
                CGPoint(x: 120, y: 96),
                CGPoint(x: 0, y: 96)
            ],
            scaleFactor: 1,
            edges: [
                VinylOrderSurfaceEdge(
                    id: "house",
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 120, y: 0),
                    edgeType: .houseEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "right",
                    start: CGPoint(x: 120, y: 0),
                    end: CGPoint(x: 120, y: 96),
                    edgeType: .deckEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "front",
                    start: CGPoint(x: 120, y: 96),
                    end: CGPoint(x: 0, y: 96),
                    edgeType: .deckEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "left",
                    start: CGPoint(x: 0, y: 96),
                    end: CGPoint(x: 0, y: 0),
                    edgeType: .deckEdge,
                    label: nil
                )
            ]
        )

        return VinylCutListEngine.makePlan(surfaces: [surface], settings: .default).surfaces[0]
    }
}
