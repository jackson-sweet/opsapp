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

    /// The drawing band, and a fitted drawing that fills it. `VinylPreviewFit`
    /// has already sized the drawing to its canvas, so at rest the viewport
    /// transform is the identity and the drawn content rect IS the band.
    private let drawingSize = CGSize(width: 320, height: 640)
    private let content = CGRect(x: 0, y: 0, width: 320, height: 640)

    // MARK: - Zoom

    /// The whole contract of an anchored zoom: whatever is under the fingers
    /// stays under the fingers. Bug 1a8e48af — the pinch used to zoom about the
    /// centre of the viewport, so the seam being inspected slid away mid-pinch.
    func testPinchZoomKeepsThePointUnderTheFingersFixed() {
        var viewport = VinylOrderViewportState(scale: 1, offset: .zero)
        let size = CGSize(width: 320, height: 640)
        let anchor = CGPoint(x: 80, y: 500)
        let before = viewport.contentPoint(forViewportPoint: anchor, viewportSize: size)

        viewport.applyZoom(
            multiplier: 2,
            anchor: anchor,
            viewportSize: size,
            contentBounds: CGRect(x: 0, y: 0, width: 320, height: 640)
        )

        let after = viewport.contentPoint(forViewportPoint: anchor, viewportSize: size)
        XCTAssertEqual(before.x, after.x, accuracy: 0.5)
        XCTAssertEqual(before.y, after.y, accuracy: 0.5)
    }

    /// Fit is 1× by construction, and the ceiling is the deck builder's own 8×,
    /// so a seam reads the same close on both surfaces. The old ceiling was 4×.
    func testZoomRangeIsFitToEightTimesFit() {
        var state = VinylOrderViewportState()
        let anchor = CGPoint(x: drawingSize.width / 2, y: drawingSize.height / 2)

        state.applyZoom(
            multiplier: 100,
            anchor: anchor,
            viewportSize: drawingSize,
            contentBounds: content
        )
        XCTAssertEqual(state.scale, 8)
        XCTAssertEqual(state.scale, VinylOrderViewportState.maximumScale)

        state.applyZoom(
            multiplier: 0.01,
            anchor: anchor,
            viewportSize: drawingSize,
            contentBounds: content
        )
        XCTAssertEqual(state.scale, 1)
        XCTAssertEqual(state.scale, VinylOrderViewportState.minimumScale)
    }

    /// Zooming back out no longer snaps the drawing home. The fit-scale reset
    /// was half of bug 1a8e48af; the FIT chip is the way back, and it is on
    /// screen the moment the drawing leaves its rest state.
    func testZoomingBackOutToFitKeepsThePanTheOperatorChose() {
        var state = VinylOrderViewportState()
        let anchor = CGPoint(x: 160, y: 320)

        state.applyZoom(multiplier: 2, anchor: anchor, viewportSize: drawingSize, contentBounds: content)
        state.applyPan(
            translation: CGSize(width: 60, height: 40),
            viewportSize: drawingSize,
            contentBounds: content
        )
        state.applyZoom(multiplier: 0.001, anchor: anchor, viewportSize: drawingSize, contentBounds: content)

        XCTAssertEqual(state.scale, VinylOrderViewportState.minimumScale)
        XCTAssertNotEqual(state.offset, .zero)
        XCTAssertFalse(state.isFitted)
    }

    // MARK: - Pan

    /// "Fully pannable" (bug 1a8e48af) means the drawing moves at EVERY zoom —
    /// including the one it opens at, so a callout sitting under the header can
    /// be pulled into the clear without zooming in first. The old model refused
    /// the gesture outright while scale was 1.
    func testPanIsAllowedAtFitScaleWithinContentMargins() {
        var viewport = VinylOrderViewportState(scale: 1, offset: .zero)
        let size = CGSize(width: 320, height: 640)

        viewport.applyPan(
            translation: CGSize(width: 40, height: -30),
            viewportSize: size,
            contentBounds: CGRect(x: 0, y: 0, width: 320, height: 640)
        )

        XCTAssertEqual(viewport.offset.width, 40, accuracy: 0.5)
        XCTAssertEqual(viewport.offset.height, -30, accuracy: 0.5)
    }

    /// The clamp fences the DRAWN CONTENT plus a quarter-viewport margin, not
    /// the viewport box the old math assumed the drawing filled. Renamed from
    /// `testPanClampsToTheVisibleZoomedCanvasBounds`, which pinned that old math.
    func testPanClampsToContentBoundsPlusMargin() {
        var state = VinylOrderViewportState()
        state.applyZoom(
            multiplier: 2,
            anchor: CGPoint(x: 160, y: 320),
            viewportSize: drawingSize,
            contentBounds: content
        )

        state.applyPan(
            translation: CGSize(width: 10_000, height: -10_000),
            viewportSize: drawingSize,
            contentBounds: content
        )

        let marginX = drawingSize.width * VinylOrderViewportState.contentMarginFraction
        let marginY = drawingSize.height * VinylOrderViewportState.contentMarginFraction
        XCTAssertEqual(
            state.offset.width,
            drawingSize.width - marginX - (content.minX * state.scale),
            accuracy: 0.001
        )
        XCTAssertEqual(
            state.offset.height,
            marginY - (content.maxY * state.scale),
            accuracy: 0.001
        )
        XCTAssertEqual(state.offset.width, 240, accuracy: 0.001)
        XCTAssertEqual(state.offset.height, -1_120, accuracy: 0.001)
    }

    /// However hard it is flung, a quarter-band of drawing is still on screen.
    func testAFlungDrawingIsNeverLostOffScreen() {
        var state = VinylOrderViewportState()

        for translation in [
            CGSize(width: 9_000, height: 9_000),
            CGSize(width: -9_000, height: -9_000),
            CGSize(width: 9_000, height: -9_000)
        ] {
            state.applyPan(translation: translation, viewportSize: drawingSize, contentBounds: content)
            assertContentStaysReachable(state)
        }
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
        let tap = CGPoint(x: 240, y: 480)

        state.toggleFit(at: tap, viewportSize: drawingSize, contentBounds: content)

        XCTAssertEqual(state.scale, VinylOrderViewportState.doubleTapScale)
        XCTAssertEqual(projected(tap, in: state).x, tap.x, accuracy: 0.001)
        XCTAssertEqual(projected(tap, in: state).y, tap.y, accuracy: 0.001)
    }

    func testDoubleTapFromAnyZoomedStateReturnsToFit() {
        var state = VinylOrderViewportState()

        state.toggleFit(at: CGPoint(x: 60, y: 120), viewportSize: drawingSize, contentBounds: content)
        XCTAssertFalse(state.isFitted)

        state.toggleFit(at: CGPoint(x: 300, y: 600), viewportSize: drawingSize, contentBounds: content)
        XCTAssertEqual(state, VinylOrderViewportState())
        XCTAssertTrue(state.isFitted)
    }

    /// A drawing merely dragged at fit scale is still off its rest state, so the
    /// double tap re-fits it rather than zooming in from a shifted position.
    func testDoubleTapAfterAPanAtFitScaleReturnsToFit() {
        var state = VinylOrderViewportState()
        state.applyPan(
            translation: CGSize(width: 50, height: 50),
            viewportSize: drawingSize,
            contentBounds: content
        )

        state.toggleFit(at: CGPoint(x: 160, y: 320), viewportSize: drawingSize, contentBounds: content)

        XCTAssertEqual(state, VinylOrderViewportState())
    }

    /// A tap in the corner must not push the drawing past its clamp — a
    /// quarter-band of drawing is still on screen afterwards.
    func testDoubleTapInACornerStaysWithinThePanClamp() {
        var state = VinylOrderViewportState()

        state.toggleFit(at: .zero, viewportSize: drawingSize, contentBounds: content)

        assertContentStaysReachable(state)
    }

    // MARK: - FIT chip visibility follows the viewport

    func testIsFittedIsTrueOnlyAtTheRestState() {
        XCTAssertTrue(VinylOrderViewportState().isFitted)
        XCTAssertFalse(VinylOrderViewportState(scale: 2).isFitted)
        XCTAssertFalse(
            VinylOrderViewportState(offset: CGSize(width: 10, height: 0)).isFitted
        )
    }

    // MARK: - The rect the clamp fences

    /// The clamp and the drawing have to agree on where the drawing IS. The fit
    /// result carries that answer so neither side re-derives it.
    func testDrawnRectIsWhereTheFittedDrawingLands() {
        let result = VinylPreviewFitResult(
            bounds: CGRect(x: -10, y: -10, width: 200, height: 100),
            origin: CGPoint(x: 20, y: 60),
            scale: 0.5
        )

        XCTAssertEqual(result.drawnRect, CGRect(x: 20, y: 60, width: 100, height: 50))
    }

    /// End to end on a real plan: the fitted drawing lands inside its canvas,
    /// which is what makes the 25% margin a margin and not a licence to lose it.
    func testContentRectIsTheDrawnDrawingInsideItsCanvas() throws {
        let preview = VinylCutPreview(plan: squarePlan(), measurementSystem: .imperial)
        let canvas = CGSize(width: 320, height: 640)

        let rect = try XCTUnwrap(preview.contentRect(in: canvas))

        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertGreaterThan(rect.height, 0)
        XCTAssertGreaterThanOrEqual(rect.minX, -0.001)
        XCTAssertGreaterThanOrEqual(rect.minY, -0.001)
        XCTAssertLessThanOrEqual(rect.maxX, canvas.width + 0.001)
        XCTAssertLessThanOrEqual(rect.maxY, canvas.height + 0.001)
    }

    /// Nothing drawn, nothing to fence — the clamp falls back to the canvas.
    func testAnEmptyPlanHasNoContentRect() {
        let preview = VinylCutPreview(
            plan: VinylCutListEngine.makePlan(surfaces: [], settings: .default)
        )

        XCTAssertNil(preview.contentRect(in: CGSize(width: 320, height: 640)))
    }

    // MARK: - Helpers

    /// Where a point of the fitted drawing lands on screen: the canvas carries
    /// the viewport transform, so content scales about the canvas origin and is
    /// then translated — the same order `GraphicsContext` applies it in.
    private func projected(_ point: CGPoint, in state: VinylOrderViewportState) -> CGPoint {
        CGPoint(
            x: (point.x * state.scale) + state.offset.width,
            y: (point.y * state.scale) + state.offset.height
        )
    }

    private func assertContentStaysReachable(
        _ state: VinylOrderViewportState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let drawn = CGRect(
            x: (content.minX * state.scale) + state.offset.width,
            y: (content.minY * state.scale) + state.offset.height,
            width: content.width * state.scale,
            height: content.height * state.scale
        )
        let marginX = drawingSize.width * VinylOrderViewportState.contentMarginFraction
        let marginY = drawingSize.height * VinylOrderViewportState.contentMarginFraction

        XCTAssertGreaterThanOrEqual(drawn.maxX, marginX - 0.001, "drawing pushed off the left", file: file, line: line)
        XCTAssertLessThanOrEqual(drawn.minX, drawingSize.width - marginX + 0.001, "drawing pushed off the right", file: file, line: line)
        XCTAssertGreaterThanOrEqual(drawn.maxY, marginY - 0.001, "drawing pushed off the top", file: file, line: line)
        XCTAssertLessThanOrEqual(drawn.minY, drawingSize.height - marginY + 0.001, "drawing pushed off the bottom", file: file, line: line)
    }

    private func squarePlan() -> VinylCutPlan {
        let positions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 240, y: 0),
            CGPoint(x: 240, y: 144),
            CGPoint(x: 0, y: 144)
        ]
        let surface = VinylOrderSurfaceInput(
            id: "surface",
            label: "Deck",
            levelName: nil,
            positions: positions,
            scaleFactor: 1,
            edges: positions.indices.map { index in
                VinylOrderSurfaceEdge(
                    id: "edge-\(index)",
                    start: positions[index],
                    end: positions[(index + 1) % positions.count],
                    edgeType: .deckEdge,
                    label: nil
                )
            }
        )
        return VinylCutListEngine.makePlan(surfaces: [surface], settings: .default)
    }
}
