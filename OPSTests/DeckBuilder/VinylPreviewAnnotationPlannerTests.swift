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

    func testMixedPreviewUsesThePlansExactTransitionAndCutRegion() {
        let surface = mixedVinylSurfacePlan()
        let preview = VinylPreviewAnnotationPlanner.plan(
            surface: surface,
            settings: VinylOrderSettings(
                color: "",
                rollWidthInches: 72,
                seamOverlapInches: 0,
                edgeWrapInches: 0,
                direction: .automatic,
                allowsDirectionalChanges: true
            ),
            viewportScale: 1
        )

        let plannedTransition = try! XCTUnwrap(surface.directionTransitions.first)
        XCTAssertEqual(preview.transitions.count, 1)
        XCTAssertEqual(preview.transitions.first?.sourceTransitionId, plannedTransition.id)
        XCTAssertEqual(preview.transitions.first?.start, plannedTransition.segments.first?.start)
        XCTAssertEqual(preview.transitions.first?.end, plannedTransition.segments.first?.end)

        let cut = try! XCTUnwrap(surface.cuts.first)
        let region = try! XCTUnwrap(surface.directionRegions.first { $0.id == cut.directionRegionId })
        XCTAssertEqual(
            VinylPreviewAnnotationPlanner.regionPolygon(for: cut, in: surface),
            region.polygon
        )
    }

    func testSingleDirectionPreviewHasNoTransition() {
        let surface = vinylSurfacePlan()
        let preview = VinylPreviewAnnotationPlanner.plan(
            surface: surface,
            settings: .default,
            viewportScale: 1
        )

        XCTAssertTrue(preview.transitions.isEmpty)
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

    private func mixedVinylSurfacePlan() -> VinylSurfaceCutPlan {
        let positions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 300, y: 0),
            CGPoint(x: 300, y: 70),
            CGPoint(x: 60, y: 70),
            CGPoint(x: 60, y: 300),
            CGPoint(x: 0, y: 300)
        ]
        let surface = VinylOrderSurfaceInput(
            id: "surface",
            label: "Deck",
            levelName: nil,
            positions: positions,
            scaleFactor: 1,
            edges: positions.indices.map { index in
                VinylOrderSurfaceEdge(
                    id: index == 3 ? "house" : "edge-\(index)",
                    start: positions[index],
                    end: positions[(index + 1) % positions.count],
                    edgeType: index == 3 ? .houseEdge : .deckEdge,
                    label: nil
                )
            }
        )
        let plan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: VinylOrderSettings(
                color: "",
                rollWidthInches: 72,
                seamOverlapInches: 0,
                edgeWrapInches: 0,
                direction: .automatic,
                allowsDirectionalChanges: true
            )
        )
        return plan.surfaces[0]
    }
}

final class VinylOrderViewportStateTests: XCTestCase {

    // Workspace band geometry moved to VinylOrderWorkspaceGeometryTests when the
    // zoom rail was retired (bug 317da29f) — this class owns the viewport model.

    func testZoomClampsAtBothBoundsAndRecentersAtFitScale() {
        var state = VinylOrderViewportState()
        let viewport = CGSize(width: 320, height: 640)

        state.applyZoom(multiplier: 20, viewportSize: viewport)
        XCTAssertEqual(state.scale, VinylOrderViewportState.maximumScale)

        state.applyPan(translation: CGSize(width: 100, height: 200), viewportSize: viewport)
        state.applyZoom(multiplier: 0.001, viewportSize: viewport)

        XCTAssertEqual(state.scale, VinylOrderViewportState.minimumScale)
        XCTAssertEqual(state.offset, .zero)
    }

    func testPanClampsToTheVisibleZoomedCanvasBounds() {
        var state = VinylOrderViewportState()
        let viewport = CGSize(width: 320, height: 640)

        state.applyZoom(multiplier: 2, viewportSize: viewport)
        state.applyPan(
            translation: CGSize(width: 1_000, height: -1_000),
            viewportSize: viewport
        )

        XCTAssertEqual(state.offset.width, 160, accuracy: 0.001)
        XCTAssertEqual(state.offset.height, -320, accuracy: 0.001)
    }

    func testFitResetsZoomAndPan() {
        var state = VinylOrderViewportState(
            scale: 3,
            offset: CGSize(width: 80, height: -120)
        )

        state.fit()

        XCTAssertEqual(state, VinylOrderViewportState())
    }

    // MARK: - Double tap (the gesture that replaced the +/- rail)

    /// The point under the finger stays under the finger. That is the whole
    /// contract of an anchored zoom — anything else feels like the drawing
    /// jumped away from the thing the operator was pointing at.
    func testDoubleTapZoomsAboutTheTappedPoint() {
        var state = VinylOrderViewportState()
        let viewport = CGSize(width: 320, height: 640)
        let tap = CGPoint(x: 240, y: 480)

        state.toggleFit(at: tap, viewportSize: viewport)

        XCTAssertEqual(state.scale, VinylOrderViewportState.doubleTapScale)
        XCTAssertEqual(
            projected(tap, in: state, viewportSize: viewport).x,
            tap.x,
            accuracy: 0.001
        )
        XCTAssertEqual(
            projected(tap, in: state, viewportSize: viewport).y,
            tap.y,
            accuracy: 0.001
        )
    }

    func testDoubleTapFromAnyZoomedStateReturnsToFit() {
        var state = VinylOrderViewportState()
        let viewport = CGSize(width: 320, height: 640)

        state.toggleFit(at: CGPoint(x: 60, y: 120), viewportSize: viewport)
        XCTAssertFalse(state.isFitted)

        state.toggleFit(at: CGPoint(x: 300, y: 600), viewportSize: viewport)
        XCTAssertEqual(state, VinylOrderViewportState())
        XCTAssertTrue(state.isFitted)
    }

    /// A tap in the corner must not push the drawing off its own clamp — the
    /// resulting offset is still inside the pan bounds for the new scale.
    func testDoubleTapInACornerStaysWithinThePanClamp() {
        var state = VinylOrderViewportState()
        let viewport = CGSize(width: 320, height: 640)

        state.toggleFit(at: CGPoint(x: 0, y: 0), viewportSize: viewport)

        let limit = CGSize(
            width: viewport.width * (state.scale - 1) / 2,
            height: viewport.height * (state.scale - 1) / 2
        )
        XCTAssertLessThanOrEqual(abs(state.offset.width), limit.width + 0.001)
        XCTAssertLessThanOrEqual(abs(state.offset.height), limit.height + 0.001)
    }

    // MARK: - FIT chip visibility follows the viewport

    func testIsFittedIsTrueOnlyAtTheRestState() {
        XCTAssertTrue(VinylOrderViewportState().isFitted)
        XCTAssertFalse(VinylOrderViewportState(scale: 2).isFitted)
        XCTAssertFalse(
            VinylOrderViewportState(offset: CGSize(width: 10, height: 0)).isFitted
        )
    }

    /// Where a viewport point lands on screen: the drawing is scaled about the
    /// viewport centre, then offset.
    private func projected(
        _ point: CGPoint,
        in state: VinylOrderViewportState,
        viewportSize: CGSize
    ) -> CGPoint {
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        return CGPoint(
            x: center.x + ((point.x - center.x) * state.scale) + state.offset.width,
            y: center.y + ((point.y - center.y) * state.scale) + state.offset.height
        )
    }
}
