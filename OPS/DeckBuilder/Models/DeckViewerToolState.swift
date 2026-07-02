//
//  DeckViewerToolState.swift
//  OPS
//
//  Shared tool state for the deck viewer. Owned by the fullscreen viewer and
//  passed into the canvas so tool CHROME lives in the viewer while DRAWING stays
//  in the canvas. Inline usage constructs a default instance and never mutates it
//  (showsTools = false), so the inline deck tab stays a pure read-only preview.
//
//  Viewport pan/zoom is deliberately NOT here — that is local view state, not a
//  tool. Only the measuring/inspection tools + their transient picks live here.
//

import SwiftUI

@MainActor
final class DeckViewerToolState: ObservableObject {
    /// The active tool. Measure and Select are mutually exclusive; `.none` is the
    /// default read/navigate state.
    enum Mode: Equatable { case none, measure, select }

    /// Lifecycle of the measure polyline. `.drawing` accepts taps; `.finished`
    /// freezes an open run; `.closed` freezes a loop (area readout). Any tap in a
    /// frozen phase starts a fresh measurement at that point.
    enum MeasurePhase: Equatable { case drawing, finished, closed }

    /// What a measure-mode tap did — the canvas maps this to haptics.
    enum MeasureTapResult: Equatable { case started, appended, finished, closed, ignored }

    @Published var mode: Mode = .none
    /// Per-edge dimension labels. Default on — turning them off de-clutters a busy
    /// multi-level plan without losing the geometry.
    @Published var showDimensions: Bool = true
    /// When set (multi-level designs only), only this level renders fully; the rest
    /// dim back. `nil` = show all levels.
    @Published var isolatedLevelId: String?
    /// Bumped to request the canvas re-run `centerViewport()`. The canvas observes
    /// this via `onChange` — a trigger, not a value.
    @Published var fitTrigger: Int = 0

    // MARK: Measurement (canvas-space polyline)
    /// Ordered polyline vertices in canvas space. A single segment is the
    /// degenerate two-point case; closing connects the last point back to the first.
    @Published var measurementPoints: [CGPoint] = []
    @Published var measurementPhase: MeasurePhase = .drawing

    // MARK: Selection
    @Published var selectedEdgeIds: Set<String> = []
    @Published var selectedSurfaceIds: Set<String> = []

    var isMeasuring: Bool { mode == .measure }
    var isSelecting: Bool { mode == .select }
    var hasSelection: Bool { !selectedEdgeIds.isEmpty || !selectedSurfaceIds.isEmpty }

    // MARK: Measure affordances (drive the rail's contextual buttons)

    /// The rail ✓ appears once an open run has at least one segment.
    var canFinishMeasurement: Bool { measurementPhase == .drawing && measurementPoints.count >= 2 }
    /// Tapping the first dot closes the loop once three vertices exist.
    var canCloseMeasurement: Bool { measurementPhase == .drawing && measurementPoints.count >= 3 }
    /// The rail ⟲ appears whenever there is something to take back — a drawn
    /// vertex, or a frozen finish/close that can be re-opened.
    var canUndoMeasurement: Bool { measurementPhase != .drawing || !measurementPoints.isEmpty }

    /// Toggle measure mode; leaving any mode clears its half-drawn transient state.
    func toggleMeasure() {
        mode = (mode == .measure) ? .none : .measure
        clearTransient()
    }

    /// Toggle select mode; leaving any mode clears its transient state.
    func toggleSelect() {
        mode = (mode == .select) ? .none : .select
        clearTransient()
    }

    func requestFit() { fitTrigger &+= 1 }

    func clearSelection() {
        selectedEdgeIds = []
        selectedSurfaceIds = []
    }

    // MARK: Measure polyline state machine

    /// Advance the polyline with one measure-mode tap.
    ///
    /// Close and finish are detected on the RAW canvas point — before any
    /// snapping — so a nearby deck-vertex snap can't yank a deliberate
    /// close-tap out of the finger-sized target. Appended vertices are
    /// refined by the injected snappers: `snapPoint` (vertex/edge geometry
    /// snap) always runs; `snapSegmentEnd` (angle snap relative to the
    /// previous vertex) runs only when a previous vertex exists.
    ///
    /// Routing, in priority order:
    /// 1. Frozen phase → reset and start a new run at the tap.
    /// 2. ≥3 points and tap within `closeThreshold` of the FIRST point → close.
    /// 3. Tap within `closeThreshold` of the LAST point → finish (≥2 points)
    ///    or ignore (a sole-point self-tap records nothing).
    /// 4. Otherwise → snap and append; a tap whose snap collapses onto the
    ///    previous vertex is ignored rather than recording a zero-length segment.
    @discardableResult
    func recordMeasureTap(
        raw: CGPoint,
        closeThreshold: Double,
        snapPoint: (CGPoint) -> CGPoint = { $0 },
        snapSegmentEnd: (CGPoint, CGPoint) -> CGPoint = { _, candidate in candidate }
    ) -> MeasureTapResult {
        guard measurementPhase == .drawing else {
            measurementPoints = [snapPoint(raw)]
            measurementPhase = .drawing
            return .started
        }
        if let first = measurementPoints.first, measurementPoints.count >= 3,
           SnapEngine.distance(raw, first) <= closeThreshold {
            measurementPhase = .closed
            return .closed
        }
        if let last = measurementPoints.last, SnapEngine.distance(raw, last) <= closeThreshold {
            guard measurementPoints.count >= 2 else { return .ignored }
            measurementPhase = .finished
            return .finished
        }
        let snapped = snapPoint(raw)
        let point = measurementPoints.last.map { snapSegmentEnd($0, snapped) } ?? snapped
        if let last = measurementPoints.last, SnapEngine.distance(point, last) < 0.5 {
            return .ignored
        }
        measurementPoints.append(point)
        return .appended
    }

    /// Rail ✓ — freeze the open polyline without re-tapping the last dot.
    func finishMeasurement() {
        guard canFinishMeasurement else { return }
        measurementPhase = .finished
    }

    /// Rail ⟲ — while drawing, drop the last vertex; from a frozen phase,
    /// re-open the run instead (recovers an accidental finish/close without
    /// losing the drawn points).
    func undoMeasurePoint() {
        guard measurementPhase == .drawing else {
            measurementPhase = .drawing
            return
        }
        if !measurementPoints.isEmpty { measurementPoints.removeLast() }
    }

    /// Card CLEAR — wipe the polyline, stay in measure mode.
    func clearMeasurement() {
        measurementPoints = []
        measurementPhase = .drawing
    }

    /// Reset per-mode transient state on any mode change so a stale half-drawn
    /// measurement or a leftover selection never bleeds into the next mode.
    private func clearTransient() {
        measurementPoints = []
        measurementPhase = .drawing
        selectedEdgeIds = []
        selectedSurfaceIds = []
    }
}

/// Pure overscroll → expand math, factored out of `ProjectDetailsView` so the
/// threshold behaviour is unit-testable without a running scroll view.
enum DeckOverscrollMath {
    /// Points of top-overscroll pull required to commit to fullscreen.
    static let commitThreshold: CGFloat = 120

    /// Progress in `[0, 1]` for a given overscroll pull distance. Negative pulls
    /// (content at or below rest) read as 0.
    static func progress(pull: CGFloat, threshold: CGFloat = commitThreshold) -> CGFloat {
        guard threshold > 0 else { return 0 }
        return min(1, max(0, pull) / threshold)
    }

    /// Whether the pull has reached the commit threshold.
    static func isCommitted(pull: CGFloat, threshold: CGFloat = commitThreshold) -> Bool {
        pull >= threshold
    }
}
