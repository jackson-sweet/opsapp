// OPS/OPSTests/DeckBuilder/DeckViewerToolStateTests.swift

import XCTest
@testable import OPS

@MainActor
final class DeckViewerToolStateTests: XCTestCase {

    func testMeasureAndSelectAreMutuallyExclusive() {
        let s = DeckViewerToolState()
        s.toggleMeasure()
        XCTAssertEqual(s.mode, .measure)
        XCTAssertTrue(s.isMeasuring)

        s.toggleSelect()
        XCTAssertEqual(s.mode, .select)
        XCTAssertTrue(s.isSelecting)
        XCTAssertFalse(s.isMeasuring)
    }

    func testTogglingSameModeTwiceReturnsToNone() {
        let s = DeckViewerToolState()
        s.toggleMeasure()
        s.toggleMeasure()
        XCTAssertEqual(s.mode, .none)
    }

    func testLeavingModeClearsTransientMeasurement() {
        let s = DeckViewerToolState()
        s.toggleMeasure()
        s.recordMeasureTap(raw: CGPoint(x: 10, y: 10), closeThreshold: 12)
        s.recordMeasureTap(raw: CGPoint(x: 200, y: 20), closeThreshold: 12)

        s.toggleSelect() // leaving measure clears the half-drawn polyline
        XCTAssertTrue(s.measurementPoints.isEmpty)
        XCTAssertEqual(s.measurementPhase, .drawing)
    }

    func testLeavingModeClearsSelection() {
        let s = DeckViewerToolState()
        s.toggleSelect()
        s.selectedEdgeIds = ["edge-1"]
        s.selectedSurfaceIds = ["surf-1"]
        XCTAssertTrue(s.hasSelection)

        s.toggleMeasure() // leaving select clears picks
        XCTAssertFalse(s.hasSelection)
    }

    func testClearSelectionEmptiesBothSets() {
        let s = DeckViewerToolState()
        s.selectedEdgeIds = ["a", "b"]
        s.selectedSurfaceIds = ["c"]
        s.clearSelection()
        XCTAssertFalse(s.hasSelection)
    }

    func testFitTriggerIncrements() {
        let s = DeckViewerToolState()
        let before = s.fitTrigger
        s.requestFit()
        XCTAssertEqual(s.fitTrigger, before &+ 1)
    }

    func testDimensionsDefaultOn() {
        XCTAssertTrue(DeckViewerToolState().showDimensions)
    }

    func testDefaultsAreCleanReadState() {
        let s = DeckViewerToolState()
        XCTAssertEqual(s.mode, .none)
        XCTAssertNil(s.isolatedLevelId)
        XCTAssertFalse(s.hasSelection)
        XCTAssertTrue(s.measurementPoints.isEmpty)
        XCTAssertEqual(s.measurementPhase, .drawing)
    }

    // MARK: - Measure polyline state machine

    /// Convenience: a drawing-state polyline through the given points.
    private func polyline(_ points: [CGPoint]) -> DeckViewerToolState {
        let s = DeckViewerToolState()
        s.toggleMeasure()
        for p in points { s.recordMeasureTap(raw: p, closeThreshold: 12) }
        return s
    }

    func testMeasureTap_appendsVertices() {
        let s = DeckViewerToolState()
        s.toggleMeasure()
        XCTAssertEqual(s.recordMeasureTap(raw: CGPoint(x: 0, y: 0), closeThreshold: 12), .appended)
        XCTAssertEqual(s.recordMeasureTap(raw: CGPoint(x: 100, y: 0), closeThreshold: 12), .appended)
        XCTAssertEqual(s.recordMeasureTap(raw: CGPoint(x: 100, y: 100), closeThreshold: 12), .appended)
        XCTAssertEqual(s.measurementPoints.count, 3)
        XCTAssertEqual(s.measurementPhase, .drawing)
    }

    func testMeasureTap_tapNearLastFinishes() {
        let s = polyline([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)])
        let result = s.recordMeasureTap(raw: CGPoint(x: 104, y: 97), closeThreshold: 12)
        XCTAssertEqual(result, .finished)
        XCTAssertEqual(s.measurementPhase, .finished)
        XCTAssertEqual(s.measurementPoints.count, 3, "finishing records no new vertex")
    }

    func testMeasureTap_tapNearFirstCloses() {
        let s = polyline([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)])
        let result = s.recordMeasureTap(raw: CGPoint(x: 4, y: -3), closeThreshold: 12)
        XCTAssertEqual(result, .closed)
        XCTAssertEqual(s.measurementPhase, .closed)
        XCTAssertEqual(s.measurementPoints.count, 3, "closing records no new vertex")
    }

    func testMeasureTap_closeRequiresThreePoints() {
        // With only 2 points, a tap near the first vertex APPENDS (doubling
        // back is a legitimate run), never closes.
        let s = polyline([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])
        let result = s.recordMeasureTap(raw: CGPoint(x: 4, y: 3), closeThreshold: 12)
        XCTAssertEqual(result, .appended)
        XCTAssertEqual(s.measurementPhase, .drawing)
        XCTAssertEqual(s.measurementPoints.count, 3)
    }

    func testMeasureTap_closeWinsWhenFirstAndLastBothInRange() {
        // Tiny triangle at low zoom: a tap can be inside both the first and
        // last dots' radii — closing is the more meaningful read, so it wins.
        let s = polyline([CGPoint(x: 0, y: 0), CGPoint(x: 14, y: 0), CGPoint(x: 7, y: 12)])
        let result = s.recordMeasureTap(raw: CGPoint(x: 3, y: 4), closeThreshold: 20)
        XCTAssertEqual(result, .closed)
    }

    func testMeasureTap_solePointSelfTapIgnored() {
        let s = polyline([CGPoint(x: 50, y: 50)])
        let result = s.recordMeasureTap(raw: CGPoint(x: 53, y: 47), closeThreshold: 12)
        XCTAssertEqual(result, .ignored)
        XCTAssertEqual(s.measurementPoints.count, 1)
        XCTAssertEqual(s.measurementPhase, .drawing)
    }

    func testMeasureTap_afterFinishedStartsNewRun() {
        let s = polyline([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])
        s.finishMeasurement()
        let result = s.recordMeasureTap(raw: CGPoint(x: 300, y: 300), closeThreshold: 12)
        XCTAssertEqual(result, .started)
        XCTAssertEqual(s.measurementPoints, [CGPoint(x: 300, y: 300)])
        XCTAssertEqual(s.measurementPhase, .drawing)
    }

    func testMeasureTap_afterClosedStartsNewRun() {
        let s = polyline([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)])
        s.recordMeasureTap(raw: CGPoint(x: 0, y: 0), closeThreshold: 12) // close
        let result = s.recordMeasureTap(raw: CGPoint(x: 300, y: 300), closeThreshold: 12)
        XCTAssertEqual(result, .started)
        XCTAssertEqual(s.measurementPoints.count, 1)
        XCTAssertEqual(s.measurementPhase, .drawing)
    }

    func testMeasureTap_snapPointAppliedToEveryVertex() {
        let s = DeckViewerToolState()
        s.toggleMeasure()
        // Snap everything onto a 10pt grid.
        let grid: (CGPoint) -> CGPoint = { CGPoint(x: ($0.x / 10).rounded() * 10, y: ($0.y / 10).rounded() * 10) }
        s.recordMeasureTap(raw: CGPoint(x: 12, y: 18), closeThreshold: 5, snapPoint: grid)
        s.recordMeasureTap(raw: CGPoint(x: 101, y: 22), closeThreshold: 5, snapPoint: grid)
        XCTAssertEqual(s.measurementPoints, [CGPoint(x: 10, y: 20), CGPoint(x: 100, y: 20)])
    }

    func testMeasureTap_segmentEndSnapOnlyWithPreviousVertex() {
        let s = DeckViewerToolState()
        s.toggleMeasure()
        var segmentSnapCalls = 0
        let segmentSnap: (CGPoint, CGPoint) -> CGPoint = { _, candidate in
            segmentSnapCalls += 1
            return CGPoint(x: candidate.x, y: 0) // flatten onto the axis
        }
        s.recordMeasureTap(raw: CGPoint(x: 0, y: 5), closeThreshold: 2, snapSegmentEnd: segmentSnap)
        XCTAssertEqual(segmentSnapCalls, 0, "first vertex has no previous point to snap against")
        s.recordMeasureTap(raw: CGPoint(x: 100, y: 5), closeThreshold: 2, snapSegmentEnd: segmentSnap)
        XCTAssertEqual(segmentSnapCalls, 1)
        XCTAssertEqual(s.measurementPoints[1], CGPoint(x: 100, y: 0))
    }

    func testMeasureTap_zeroLengthAppendIgnored() {
        let s = DeckViewerToolState()
        s.toggleMeasure()
        s.recordMeasureTap(raw: CGPoint(x: 50, y: 50), closeThreshold: 2)
        // Far-away tap whose snap collapses onto the previous vertex.
        let collapse: (CGPoint) -> CGPoint = { _ in CGPoint(x: 50, y: 50) }
        let result = s.recordMeasureTap(raw: CGPoint(x: 400, y: 400), closeThreshold: 2, snapPoint: collapse)
        XCTAssertEqual(result, .ignored)
        XCTAssertEqual(s.measurementPoints.count, 1)
    }

    func testFinishMeasurement_requiresTwoPoints() {
        let s = polyline([CGPoint(x: 0, y: 0)])
        s.finishMeasurement()
        XCTAssertEqual(s.measurementPhase, .drawing, "a single point is not a finishable run")

        s.recordMeasureTap(raw: CGPoint(x: 100, y: 0), closeThreshold: 12)
        s.finishMeasurement()
        XCTAssertEqual(s.measurementPhase, .finished)
    }

    func testUndo_dropsLastVertexWhileDrawing() {
        let s = polyline([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)])
        s.undoMeasurePoint()
        XCTAssertEqual(s.measurementPoints.count, 2)
        XCTAssertEqual(s.measurementPhase, .drawing)
    }

    func testUndo_fromFinishedReopensKeepingPoints() {
        let s = polyline([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])
        s.finishMeasurement()
        s.undoMeasurePoint()
        XCTAssertEqual(s.measurementPhase, .drawing)
        XCTAssertEqual(s.measurementPoints.count, 2, "re-opening does not drop a vertex")
    }

    func testUndo_fromClosedReopensKeepingPoints() {
        let s = polyline([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)])
        s.recordMeasureTap(raw: CGPoint(x: 0, y: 0), closeThreshold: 12) // close
        s.undoMeasurePoint()
        XCTAssertEqual(s.measurementPhase, .drawing)
        XCTAssertEqual(s.measurementPoints.count, 3)
    }

    func testUndo_onEmptyIsNoop() {
        let s = DeckViewerToolState()
        s.toggleMeasure()
        s.undoMeasurePoint()
        XCTAssertTrue(s.measurementPoints.isEmpty)
        XCTAssertEqual(s.measurementPhase, .drawing)
    }

    func testClearMeasurement_wipesRunKeepsMode() {
        let s = polyline([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)])
        s.recordMeasureTap(raw: CGPoint(x: 0, y: 0), closeThreshold: 12) // close
        s.clearMeasurement()
        XCTAssertTrue(s.measurementPoints.isEmpty)
        XCTAssertEqual(s.measurementPhase, .drawing)
        XCTAssertTrue(s.isMeasuring, "CLEAR starts over without leaving the tool")
    }

    func testMeasureAffordanceFlags() {
        let s = DeckViewerToolState()
        s.toggleMeasure()
        XCTAssertFalse(s.canUndoMeasurement)
        XCTAssertFalse(s.canFinishMeasurement)
        XCTAssertFalse(s.canCloseMeasurement)

        s.recordMeasureTap(raw: CGPoint(x: 0, y: 0), closeThreshold: 12)
        XCTAssertTrue(s.canUndoMeasurement)
        XCTAssertFalse(s.canFinishMeasurement)

        s.recordMeasureTap(raw: CGPoint(x: 100, y: 0), closeThreshold: 12)
        XCTAssertTrue(s.canFinishMeasurement)
        XCTAssertFalse(s.canCloseMeasurement)

        s.recordMeasureTap(raw: CGPoint(x: 100, y: 100), closeThreshold: 12)
        XCTAssertTrue(s.canCloseMeasurement)

        s.finishMeasurement()
        XCTAssertFalse(s.canFinishMeasurement, "frozen runs cannot finish again")
        XCTAssertFalse(s.canCloseMeasurement)
        XCTAssertTrue(s.canUndoMeasurement, "frozen runs can be re-opened")
    }

    // MARK: - Split sub-state (select mode)

    func testToggleSplitting_requiresSelectModeAndOneSurface() {
        let s = DeckViewerToolState()
        s.toggleSplitting()
        XCTAssertFalse(s.isSplitting, "no mode, no split")

        s.toggleSelect()
        s.toggleSplitting()
        XCTAssertFalse(s.isSplitting, "no surface selected")

        s.selectedSurfaceIds = ["surf-1"]
        s.toggleSplitting()
        XCTAssertTrue(s.isSplitting)
        s.toggleSplitting()
        XCTAssertFalse(s.isSplitting, "toggles off")
        XCTAssertTrue(s.splitPoints.isEmpty, "exit clears the cut")
    }

    func testCanSplit_gateIsExactlyOneSurface() {
        let s = DeckViewerToolState()
        s.toggleSelect()
        XCTAssertFalse(s.canSplit)
        s.selectedSurfaceIds = ["surf-1"]
        XCTAssertTrue(s.canSplit)
        s.selectedSurfaceIds = ["surf-1", "surf-2"]
        XCTAssertFalse(s.canSplit, "two surfaces is ambiguous — no scissors")
    }

    func testRecordSplitTap_placesTwoPointsThenRecuts() {
        let s = DeckViewerToolState()
        s.toggleSelect()
        s.selectedSurfaceIds = ["surf-1"]
        s.toggleSplitting()

        s.recordSplitTap(CGPoint(x: 10, y: 10))
        XCTAssertEqual(s.splitPoints.count, 1)
        s.recordSplitTap(CGPoint(x: 90, y: 90))
        XCTAssertEqual(s.splitPoints.count, 2)
        // Third tap re-cuts: starts a fresh line at the tap.
        s.recordSplitTap(CGPoint(x: 40, y: 60))
        XCTAssertEqual(s.splitPoints, [CGPoint(x: 40, y: 60)])
    }

    func testRecordSplitTap_ignoresCoincidentSecondPoint() {
        let s = DeckViewerToolState()
        s.toggleSelect()
        s.selectedSurfaceIds = ["surf-1"]
        s.toggleSplitting()
        s.recordSplitTap(CGPoint(x: 10, y: 10))
        s.recordSplitTap(CGPoint(x: 10.2, y: 10.1))
        XCTAssertEqual(s.splitPoints.count, 1, "coincident points define no line")
    }

    func testClearSplit_keepsSplittingActive() {
        let s = DeckViewerToolState()
        s.toggleSelect()
        s.selectedSurfaceIds = ["surf-1"]
        s.toggleSplitting()
        s.recordSplitTap(CGPoint(x: 10, y: 10))
        s.recordSplitTap(CGPoint(x: 90, y: 90))
        s.clearSplit()
        XCTAssertTrue(s.splitPoints.isEmpty)
        XCTAssertTrue(s.isSplitting, "CLEAR restarts the cut, not the tool")
    }

    func testSelectionChangeExitsSplit() {
        let s = DeckViewerToolState()
        s.toggleSelect()
        s.selectedSurfaceIds = ["surf-1"]
        s.toggleSplitting()
        s.recordSplitTap(CGPoint(x: 10, y: 10))
        s.selectionDidChange()
        XCTAssertFalse(s.isSplitting)
        XCTAssertTrue(s.splitPoints.isEmpty)
    }

    func testLeavingSelectModeClearsSplit() {
        let s = DeckViewerToolState()
        s.toggleSelect()
        s.selectedSurfaceIds = ["surf-1"]
        s.toggleSplitting()
        s.recordSplitTap(CGPoint(x: 10, y: 10))
        s.toggleMeasure()
        XCTAssertFalse(s.isSplitting)
        XCTAssertTrue(s.splitPoints.isEmpty)
    }
}
