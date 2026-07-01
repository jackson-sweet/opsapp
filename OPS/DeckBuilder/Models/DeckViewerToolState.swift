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

    // MARK: Measurement (canvas-space points)
    @Published var measurementStart: CGPoint?
    @Published var measurementEnd: CGPoint?

    // MARK: Selection
    @Published var selectedEdgeIds: Set<String> = []
    @Published var selectedSurfaceIds: Set<String> = []

    var isMeasuring: Bool { mode == .measure }
    var isSelecting: Bool { mode == .select }
    var hasSelection: Bool { !selectedEdgeIds.isEmpty || !selectedSurfaceIds.isEmpty }

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

    /// Reset per-mode transient state on any mode change so a stale half-drawn
    /// measurement or a leftover selection never bleeds into the next mode.
    private func clearTransient() {
        measurementStart = nil
        measurementEnd = nil
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
