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
        s.measurementStart = CGPoint(x: 10, y: 10)
        s.measurementEnd = CGPoint(x: 20, y: 20)

        s.toggleSelect() // leaving measure clears the half-drawn line
        XCTAssertNil(s.measurementStart)
        XCTAssertNil(s.measurementEnd)
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
    }
}
