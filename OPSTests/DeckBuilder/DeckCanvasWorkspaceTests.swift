// OPSTests/DeckBuilder/DeckCanvasWorkspaceTests.swift

import CoreGraphics
import XCTest
@testable import OPS

final class DeckCanvasWorkspaceTests: XCTestCase {
    func testInitialBoundsPreserveLegacyFourHundredFootWorkspace() {
        let workspace = DeckCanvasWorkspace()

        XCTAssertEqual(workspace.bounds, CGRect(x: 0, y: 0, width: 4_800, height: 4_800))
    }

    func testExpandGrowsLeftAndTopInWholeQuantaWithSafetyMargin() {
        var workspace = DeckCanvasWorkspace()

        let changed = workspace.expand(toInclude: [CGPoint(x: -50, y: -10)])

        XCTAssertTrue(changed)
        XCTAssertEqual(workspace.bounds.minX, -480)
        XCTAssertEqual(workspace.bounds.minY, -480)
        XCTAssertEqual(workspace.bounds.maxX, 4_800)
        XCTAssertEqual(workspace.bounds.maxY, 4_800)
    }

    func testExpandGrowsRightAndBottomInWholeQuantaWithSafetyMargin() {
        var workspace = DeckCanvasWorkspace()

        let changed = workspace.expand(toInclude: [CGPoint(x: 5_000, y: 5_001)])

        XCTAssertTrue(changed)
        XCTAssertEqual(workspace.bounds.minX, 0)
        XCTAssertEqual(workspace.bounds.minY, 0)
        XCTAssertEqual(workspace.bounds.maxX, 5_280)
        XCTAssertEqual(workspace.bounds.maxY, 5_280)
    }

    func testExpandGrowsOnlyAxesThatEnterSafetyGutter() {
        var workspace = DeckCanvasWorkspace()

        let changed = workspace.expand(toInclude: [CGPoint(x: 4_561, y: 2_400)])

        XCTAssertTrue(changed)
        XCTAssertEqual(workspace.bounds, CGRect(x: 0, y: 0, width: 5_280, height: 4_800))
    }

    func testPointOnSafetyGutterBoundaryDoesNotExpand() {
        var workspace = DeckCanvasWorkspace()

        let changed = workspace.expand(toInclude: [
            CGPoint(x: 240, y: 240),
            CGPoint(x: 4_560, y: 4_560)
        ])

        XCTAssertFalse(changed)
        XCTAssertEqual(workspace.bounds, DeckCanvasWorkspace.initialBounds)
    }

    func testExpandedWorkspaceNeverShrinksDuringSession() {
        var workspace = DeckCanvasWorkspace()
        workspace.expand(toInclude: [CGPoint(x: -50, y: 5_000)])
        let expandedBounds = workspace.bounds

        let changed = workspace.expand(toInclude: [CGPoint(x: 2_400, y: 2_400)])

        XCTAssertFalse(changed)
        XCTAssertEqual(workspace.bounds, expandedBounds)
    }

    func testExpandIgnoresNonFinitePoints() {
        var workspace = DeckCanvasWorkspace()

        let changed = workspace.expand(toInclude: [
            CGPoint(x: CGFloat.infinity, y: 12),
            CGPoint(x: 12, y: CGFloat.nan)
        ])

        XCTAssertFalse(changed)
        XCTAssertEqual(workspace.bounds, DeckCanvasWorkspace.initialBounds)
    }

    func testScreenAndWorldConversionAreReversible() {
        let workspace = DeckCanvasWorkspace()
        let world = CGPoint(x: -144, y: 5_040)
        let scale: CGFloat = 2.5
        let offset = CGSize(width: 37, height: -91)

        let screen = workspace.screenPoint(fromWorld: world, scale: scale, offset: offset)
        let roundTrip = workspace.worldPoint(fromScreen: screen, scale: scale, offset: offset)

        XCTAssertEqual(roundTrip.x, world.x, accuracy: 0.000_001)
        XCTAssertEqual(roundTrip.y, world.y, accuracy: 0.000_001)
    }

    func testVisibleWorldRectUsesRealViewportDimensions() {
        let workspace = DeckCanvasWorkspace()

        let visible = workspace.visibleWorldRect(
            viewportSize: CGSize(width: 390, height: 844),
            scale: 2,
            offset: CGSize(width: -100, height: -200)
        )

        XCTAssertEqual(visible.origin.x, 50, accuracy: 0.000_001)
        XCTAssertEqual(visible.origin.y, 100, accuracy: 0.000_001)
        XCTAssertEqual(visible.width, 195, accuracy: 0.000_001)
        XCTAssertEqual(visible.height, 422, accuracy: 0.000_001)
    }

    func testPanConstraintRetainsRecoverableEdgesAtMinimumZoom() {
        let workspace = DeckCanvasWorkspace()
        let viewport = CGSize(width: 390, height: 600)
        let reveal: CGFloat = 44

        let farPositive = workspace.constrainedOffset(
            CGSize(width: 10_000, height: 10_000),
            scale: 0.15,
            viewportSize: viewport,
            minimumVisibleLength: reveal
        )
        let farNegative = workspace.constrainedOffset(
            CGSize(width: -10_000, height: -10_000),
            scale: 0.15,
            viewportSize: viewport,
            minimumVisibleLength: reveal
        )

        XCTAssertEqual(farPositive.width, 346, accuracy: 0.000_001)
        XCTAssertEqual(farPositive.height, 556, accuracy: 0.000_001)
        XCTAssertEqual(farNegative.width, -676, accuracy: 0.000_001)
        XCTAssertEqual(farNegative.height, -676, accuracy: 0.000_001)
    }

    func testPanConstraintRetainsRecoverableEdgesAtMaximumZoom() {
        let workspace = DeckCanvasWorkspace()
        let viewport = CGSize(width: 390, height: 844)
        let reveal: CGFloat = 44

        let farNegative = workspace.constrainedOffset(
            CGSize(width: -100_000, height: -100_000),
            scale: 8,
            viewportSize: viewport,
            minimumVisibleLength: reveal
        )

        XCTAssertEqual(farNegative.width, -38_356, accuracy: 0.000_001)
        XCTAssertEqual(farNegative.height, -38_356, accuracy: 0.000_001)
    }

    func testPanConstraintCentersWorkspaceWhenItFitsInsideViewport() {
        let workspace = DeckCanvasWorkspace(bounds: CGRect(x: -50, y: 20, width: 380, height: 800))

        let constrained = workspace.constrainedOffset(
            CGSize(width: 9_999, height: -9_999),
            scale: 1,
            viewportSize: CGSize(width: 390, height: 844),
            minimumVisibleLength: 44
        )

        XCTAssertEqual(constrained.width, 55, accuracy: 0.000_001)
        XCTAssertEqual(constrained.height, 2, accuracy: 0.000_001)
    }

    func testExpandedWorkspaceDefersRecenteringUntilDirectManipulationEnds() {
        var workspace = DeckCanvasWorkspace()
        workspace.expand(toInclude: [CGPoint(x: 2_400, y: 5_000)])
        let viewport = CGSize(width: 390, height: 844)
        let initialCenteredOffset = CGSize(width: -165, height: 62)

        let duringManipulation = workspace.constrainedOffset(
            initialCenteredOffset,
            scale: 0.15,
            viewportSize: viewport,
            minimumVisibleLength: 44,
            centerWhenWorkspaceFits: false
        )
        let afterManipulation = workspace.constrainedOffset(
            initialCenteredOffset,
            scale: 0.15,
            viewportSize: viewport,
            minimumVisibleLength: 44
        )

        XCTAssertEqual(duringManipulation.height, 62, accuracy: 0.000_001)
        XCTAssertEqual(afterManipulation.height, 26, accuracy: 0.000_001)
    }

    func testRenderedStairExtentsExpandWorkspaceBeyondVertexBounds() {
        var drawing = DeckDrawingData()
        drawing.scaleFactor = 2
        drawing.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 1_000, y: 240)),
            DeckVertex(id: "v2", position: CGPoint(x: 1_240, y: 240)),
            DeckVertex(id: "v3", position: CGPoint(x: 1_240, y: 480)),
            DeckVertex(id: "v4", position: CGPoint(x: 1_000, y: 480))
        ]
        var stairEdge = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        stairEdge.stairConfig = StairConfig(width: 48, runPerTread: 12, treadCount: 30)
        drawing.edges = [
            stairEdge,
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1")
        ]

        let stairPoints = DeckCanvasWorkspaceExtentResolver.stairPoints(in: drawing)
        var workspace = DeckCanvasWorkspace()
        let changed = workspace.expand(toInclude: stairPoints)

        XCTAssertEqual(stairPoints.map(\.y).min(), CGFloat(-480))
        XCTAssertTrue(changed)
        XCTAssertEqual(workspace.bounds.minY, -960)
    }

    func testStairExtentPlanClampsLargeAlignmentOffsetToRenderedEdge() {
        var drawing = DeckDrawingData()
        drawing.scaleFactor = 1
        drawing.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 240, y: 1_000)),
            DeckVertex(id: "v2", position: CGPoint(x: 360, y: 1_000)),
            DeckVertex(id: "v3", position: CGPoint(x: 360, y: 1_240)),
            DeckVertex(id: "v4", position: CGPoint(x: 240, y: 1_240))
        ]
        var stairEdge = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        stairEdge.stairConfig = StairConfig(
            width: 48,
            runPerTread: 12,
            treadCount: 3,
            alignment: .right,
            offset: 500
        )
        drawing.edges = [
            stairEdge,
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1")
        ]

        let stairPoints = DeckCanvasWorkspaceExtentResolver.stairPoints(in: drawing)

        XCTAssertEqual(stairPoints.map(\.x).min(), CGFloat(240))
        XCTAssertEqual(stairPoints.map(\.x).max(), CGFloat(288))
    }

    func testPerimeterReorientationDefersCenteringUntilTheDragEnds() {
        XCTAssertTrue(
            DeckCanvasWorkspaceInteractionPolicy.isDirectManipulationActive(
                drawingMode: .idle,
                isReorientingPerimeterDraft: true
            )
        )
        XCTAssertFalse(
            DeckCanvasWorkspaceInteractionPolicy.shouldCenterPerimeterAnchor(
                isReorientingPerimeterDraft: true
            )
        )
        XCTAssertFalse(
            DeckCanvasWorkspaceInteractionPolicy.isDirectManipulationActive(
                drawingMode: .idle,
                isReorientingPerimeterDraft: false
            )
        )
        XCTAssertTrue(
            DeckCanvasWorkspaceInteractionPolicy.shouldCenterPerimeterAnchor(
                isReorientingPerimeterDraft: false
            )
        )
    }

    func testPerimeterReorientationCameraLifecycleStopsMotionThenCentersAfterLift() {
        let anchor = PerimeterEntryAnchor(
            vertexId: "v1",
            position: CGPoint(x: 5_100, y: -120),
            incomingAngleDegrees: 90,
            rootVertexId: "v0"
        )

        XCTAssertEqual(
            DeckCanvasWorkspaceInteractionPolicy.perimeterReorientationCameraAction(
                phase: .changed,
                activeAnchor: anchor
            ),
            .stopCurrentMotion
        )
        XCTAssertEqual(
            DeckCanvasWorkspaceInteractionPolicy.perimeterReorientationCameraAction(
                phase: .ended,
                activeAnchor: anchor
            ),
            .centerOn(anchor.position)
        )
        XCTAssertEqual(
            DeckCanvasWorkspaceInteractionPolicy.perimeterReorientationCameraAction(
                phase: .ended,
                activeAnchor: nil
            ),
            .reconcileWorkspace
        )
    }

    func testEdgePanPolicyPointsTowardThePressedEdgeAndRampsQuadratically() {
        let viewport = CGSize(width: 390, height: 844)
        let interval = 1.0 / 60.0

        let interior = DeckCanvasPanPolicy.delta(
            for: CGPoint(x: 195, y: 422),
            viewportSize: viewport,
            edgeZone: 70,
            maxSpeed: 700,
            interval: interval
        )
        let left = DeckCanvasPanPolicy.delta(
            for: CGPoint(x: 0, y: 422),
            viewportSize: viewport,
            edgeZone: 70,
            maxSpeed: 700,
            interval: interval
        )
        let rightHalf = DeckCanvasPanPolicy.delta(
            for: CGPoint(x: 355, y: 422),
            viewportSize: viewport,
            edgeZone: 70,
            maxSpeed: 700,
            interval: interval
        )
        let rightEdge = DeckCanvasPanPolicy.delta(
            for: CGPoint(x: 390, y: 422),
            viewportSize: viewport,
            edgeZone: 70,
            maxSpeed: 700,
            interval: interval
        )

        XCTAssertEqual(interior, .zero)
        XCTAssertGreaterThan(left.width, 0)
        XCTAssertLessThan(rightHalf.width, 0)
        XCTAssertEqual(abs(rightHalf.width), abs(rightEdge.width) * 0.25, accuracy: 0.000_001)
    }

    func testEdgePanAndConstraintCannotLoseExpandedWorkspace() {
        var workspace = DeckCanvasWorkspace()
        workspace.expand(toInclude: [CGPoint(x: 5_000, y: 2_400)])
        let viewport = CGSize(width: 390, height: 844)
        let unconstrained = CGSize(width: -100_000, height: 0)

        let constrained = workspace.constrainedOffset(
            unconstrained,
            scale: 1,
            viewportSize: viewport,
            minimumVisibleLength: 44
        )

        let workspaceRightEdge = workspace.bounds.maxX + constrained.width
        XCTAssertEqual(workspaceRightEdge, 44, accuracy: 0.000_001)
    }
}
