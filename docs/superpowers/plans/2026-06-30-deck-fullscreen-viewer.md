# Deck Fullscreen Viewer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an overscroll-triggered fullscreen focus mode to the project Deck tab, where the canvas fills the screen and the measuring tools (2D only) get a proper tool rail.

**Architecture:** A shared `DeckViewerToolState` decouples tool state from the canvas so the same 2D/3D canvas views render both inline (chrome-less) and fullscreen (with a tool rail + peek-sheet readouts). `ProjectDetailsView` probes its own scroll overscroll to drive a `matchedGeometryEffect` grow into a new `DeckFullscreenViewer`. The global tab bar hides via the existing `.hidesGlobalTabBar()` token controller.

**Tech Stack:** SwiftUI, SwiftData, SceneKit (3D), `Canvas` (2D), `matchedGeometryEffect`, `UIImpactFeedbackGenerator`, OPSStyle tokens.

**Spec:** `docs/superpowers/specs/2026-06-30-deck-fullscreen-viewer-design.md`

**Worktree build (device check):**
`xcodebuild -scheme OPS -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .ddata build`
**Worktree tests (sim):**
`xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .ddata test -only-testing:OPSTests/<Suite>`

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `OPS/DeckBuilder/Models/DeckViewerToolState.swift` | Observable tool-state bag (modes, selection, dimensions, isolate, fit) + mutual-exclusion logic | **Create** |
| `OPS/DeckBuilder/Models/DeckSelectionReadout.swift` | Pure reducer: (drawingData, edgeIds, surfaceIds) → totals by type | **Create** (extracted from DeckTab2DView) |
| `OPS/Views/Components/Project/Tabs/DeckTab2DView.swift` | 2D canvas: drawing + viewport gestures + tap→toolState. Honors showDimensions/isolate/fit. No chrome. | **Modify** |
| `OPS/Views/Components/Project/Tabs/DeckFullscreenViewer.swift` | Fullscreen chrome: top bar, tool rail (2D), peek-sheet readouts, dismiss gesture | **Create** |
| `OPS/Views/Components/Project/Tabs/DeckTabView.swift` | Inline: chrome-less canvas + pull cue + matchedGeometry source | **Modify** |
| `OPS/Views/Components/Project/ProjectDetailsView.swift` | Overscroll probe, `isDeckFullscreen`, namespace, fullscreen layer, tab-bar hide | **Modify** |
| `OPSTests/DeckBuilder/DeckViewerToolStateTests.swift` | Unit: mode mutual exclusion, dimension/isolate toggles | **Create** |
| `OPSTests/DeckBuilder/DeckOverscrollMathTests.swift` | Unit: pull→progress→commit threshold | **Create** |
| `OPSTests/Views/DeckFullscreenSnapshotTests.swift` | Snapshot proof: inline, fullscreen 2D+tools, fullscreen 3D | **Create** |

---

## Task 1: DeckViewerToolState + overscroll math (pure logic, TDD)

**Files:**
- Create: `OPS/DeckBuilder/Models/DeckViewerToolState.swift`
- Test: `OPSTests/DeckBuilder/DeckViewerToolStateTests.swift`, `OPSTests/DeckBuilder/DeckOverscrollMathTests.swift`

- [ ] **Step 1: Write `DeckViewerToolState`**

```swift
import SwiftUI

/// Shared tool state for the deck viewer. Owned by the fullscreen viewer, passed
/// into the canvas so tool chrome lives in the viewer while drawing stays in the
/// canvas. Inline usage constructs a default instance and never mutates it.
@MainActor
final class DeckViewerToolState: ObservableObject {
    enum Mode: Equatable { case none, measure, select }

    @Published var mode: Mode = .none
    @Published var showDimensions: Bool = true
    @Published var isolatedLevelId: String?
    /// Bumped to request the canvas re-run centerViewport(). Views observe onChange.
    @Published var fitTrigger: Int = 0

    // Measurement (canvas-space points)
    @Published var measurementStart: CGPoint?
    @Published var measurementEnd: CGPoint?

    // Selection
    @Published var selectedEdgeIds: Set<String> = []
    @Published var selectedSurfaceIds: Set<String> = []

    var isMeasuring: Bool { mode == .measure }
    var isSelecting: Bool { mode == .select }
    var hasSelection: Bool { !selectedEdgeIds.isEmpty || !selectedSurfaceIds.isEmpty }

    func toggleMeasure() {
        mode = (mode == .measure) ? .none : .measure
        clearTransient()
    }
    func toggleSelect() {
        mode = (mode == .select) ? .none : .select
        clearTransient()
    }
    func requestFit() { fitTrigger &+= 1 }
    func clearSelection() { selectedEdgeIds = []; selectedSurfaceIds = [] }

    /// Reset per-mode transient state on any mode change so a stale half-drawn
    /// measurement / selection never bleeds into the next mode.
    private func clearTransient() {
        measurementStart = nil; measurementEnd = nil
        selectedEdgeIds = []; selectedSurfaceIds = []
    }
}

/// Pure overscroll→expand math, factored out of the view for unit testing.
enum DeckOverscrollMath {
    static let commitThreshold: CGFloat = 120

    /// Progress in [0,1] for a given overscroll pull distance.
    static func progress(pull: CGFloat, threshold: CGFloat = commitThreshold) -> CGFloat {
        guard threshold > 0 else { return 0 }
        return min(1, max(0, pull) / threshold)
    }
    static func isCommitted(pull: CGFloat, threshold: CGFloat = commitThreshold) -> Bool {
        pull >= threshold
    }
}
```

- [ ] **Step 2: Write tests**

```swift
import XCTest
@testable import OPS

@MainActor final class DeckViewerToolStateTests: XCTestCase {
    func testMeasureAndSelectAreMutuallyExclusive() {
        let s = DeckViewerToolState()
        s.toggleMeasure(); XCTAssertEqual(s.mode, .measure)
        s.toggleSelect();  XCTAssertEqual(s.mode, .select)   // switching modes
        XCTAssertFalse(s.isMeasuring)
    }
    func testTogglingModeClearsTransient() {
        let s = DeckViewerToolState()
        s.toggleMeasure(); s.measurementStart = .init(x: 1, y: 1)
        s.toggleSelect()   // leaving measure clears the half-drawn point
        XCTAssertNil(s.measurementStart)
    }
    func testFitTriggerIncrements() {
        let s = DeckViewerToolState(); let before = s.fitTrigger
        s.requestFit(); XCTAssertEqual(s.fitTrigger, before &+ 1)
    }
    func testDimensionsDefaultOn() { XCTAssertTrue(DeckViewerToolState().showDimensions) }
}

final class DeckOverscrollMathTests: XCTestCase {
    func testProgressClampsToUnit() {
        XCTAssertEqual(DeckOverscrollMath.progress(pull: 0), 0)
        XCTAssertEqual(DeckOverscrollMath.progress(pull: 60, threshold: 120), 0.5, accuracy: 0.001)
        XCTAssertEqual(DeckOverscrollMath.progress(pull: 999, threshold: 120), 1)
        XCTAssertEqual(DeckOverscrollMath.progress(pull: -30), 0)   // negative = no pull
    }
    func testCommitAtThreshold() {
        XCTAssertFalse(DeckOverscrollMath.isCommitted(pull: 119))
        XCTAssertTrue(DeckOverscrollMath.isCommitted(pull: 120))
    }
}
```

- [ ] **Step 3: Build-for-testing + run**

Run: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .ddata test -only-testing:OPSTests/DeckViewerToolStateTests -only-testing:OPSTests/DeckOverscrollMathTests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add OPS/DeckBuilder/Models/DeckViewerToolState.swift OPSTests/DeckBuilder/DeckViewerToolStateTests.swift OPSTests/DeckBuilder/DeckOverscrollMathTests.swift
git commit -m "feat(deck): shared viewer tool state + overscroll math"
```

---

## Task 2: Extract `DeckSelectionReadout` reducer

**Files:**
- Create: `OPS/DeckBuilder/Models/DeckSelectionReadout.swift`
- Modify: `OPS/Views/Components/Project/Tabs/DeckTab2DView.swift` (remove the private readout types + `buildSelectionReadout`, call the extracted reducer)

- [ ] **Step 1:** Move `SelectionGroup`, `SelectionReadout`, `buildSelectionReadout`, `edgeCategoryLabel`, `surfaceMaterialLabel`, `surfaceContexts`, `selectableEdges/Vertices`, `edgeLengthInches` out of `DeckTab2DView` into a pure struct:

```swift
import SwiftUI

/// Pure reducer: turn a selection over a DeckDrawingData into totals by type.
/// Extracted from DeckTab2DView so the fullscreen viewer's peek sheet can render
/// the same readout without owning the canvas.
enum DeckSelectionReadout {
    struct Group: Identifiable { let id: String; let label: String; let value: String }
    struct Result {
        let surfaceGroups: [Group]; let edgeGroups: [Group]; let stairGroup: Group?
        let totalAreaText: String?; let totalLengthText: String?; let selectionCount: Int
    }

    static func build(drawingData: DeckDrawingData,
                      selectedEdgeIds: Set<String>,
                      selectedSurfaceIds: Set<String>) -> Result {
        // ... (verbatim move of the existing buildSelectionReadout body, using the
        // helper funcs also moved here) ...
    }
    // moved: surfaceContexts, edgeCategoryLabel, surfaceMaterialLabel, edgeLengthInches,
    // selectableEdges/Vertices — as static helpers taking drawingData.
}
```

- [ ] **Step 2:** In `DeckTab2DView`, the tap handlers (`recordSelectionTap`) still read `selectableEdges`/`selectableVertices` — keep thin computed wrappers that delegate to `DeckSelectionReadout` statics, or inline. No behavior change.

- [ ] **Step 3: Build**

Run: device build command (above).
Expected: BUILD SUCCEEDED, no behavior change (readout identical).

- [ ] **Step 4: Commit**

```bash
git add OPS/DeckBuilder/Models/DeckSelectionReadout.swift OPS/Views/Components/Project/Tabs/DeckTab2DView.swift
git commit -m "refactor(deck): extract selection readout reducer from 2D view"
```

---

## Task 3: Drive `DeckTab2DView` from shared tool state (no chrome)

**Files:** Modify `OPS/Views/Components/Project/Tabs/DeckTab2DView.swift`

- [ ] **Step 1: Change the signature + state ownership**

```swift
struct DeckTab2DView: View {
    let drawingData: DeckDrawingData
    @ObservedObject var toolState: DeckViewerToolState
    /// When false (inline), the tap gesture + measurement rendering are inert and
    /// no tool chrome shows — the canvas is a pure read-only preview.
    var showsTools: Bool = false
    var onInteractingChange: (Bool) -> Void = { _ in }

    // Viewport pan/zoom stays LOCAL — it is not tool state.
    @State private var canvasScale: CGFloat = 1.0
    @State private var canvasOffset: CGSize = .zero
    @State private var lastCenteredSize: CGSize = .zero
    // REMOVED: measurementMode/Start/End, selectionMode, selectedEdge/SurfaceIds
    //          — now on toolState.
```

- [ ] **Step 2: Route reads through `toolState`** — replace every former `measurementMode` with `showsTools && toolState.isMeasuring`, `selectionMode` with `showsTools && toolState.isSelecting`, `measurementStart/End` with `toolState.measurementStart/End`, `selectedEdgeIds/selectedSurfaceIds` with `toolState.selectedEdgeIds/…`. Tap gesture guard:

```swift
.simultaneousGesture(
    (showsTools && (toolState.isMeasuring || toolState.isSelecting))
        ? SpatialTapGesture().onEnded { value in
            if toolState.isMeasuring { recordMeasurementTap(at: value.location, in: geometry.size) }
            else { recordSelectionTap(at: value.location, in: geometry.size) }
        } : nil
)
```

- [ ] **Step 3: Honor dimensions / isolate / fit in `canvasContent`**

```swift
// dimensions: guard the two drawDimensionLabel loops
if toolState.showDimensions {
    for edge in level.edges { drawDimensionLabel(context: context, edge: edge, vertexLookup: level.vertex(byId:)) }
}
// isolate (multi-level): when set, dim non-isolated levels
for level in drawingData.levels {
    let isolated = toolState.isolatedLevelId
    if let iso = isolated, iso != level.id {
        drawInactiveLevel(context: context, level: level)   // existing dim renderer
        continue
    }
    // ... full render (existing) ...
}
```
And re-center on fit:
```swift
.onChange(of: toolState.fitTrigger) { _, _ in centerViewport(viewportSize: lastCenteredSize) }
```

- [ ] **Step 4: Delete the chrome** — remove `measurementToolOverlay`, `selectionReadoutCard`, `selectionRow`, `measurementHintText`, `selectionHintText` from this file (they move to the viewer in Task 4). Keep `drawMeasurement` (Canvas pass) — it reads `toolState.measurementStart/End`, gated by `showsTools`.

- [ ] **Step 5: Build**

Run: device build command. Expected: BUILD SUCCEEDED. (Call sites break until Task 5 — temporarily pass a throwaway `DeckViewerToolState()` if compiling this task alone; the DeckTabView/viewer wiring lands in Tasks 4–5.)

- [ ] **Step 6: Commit**

```bash
git add OPS/Views/Components/Project/Tabs/DeckTab2DView.swift
git commit -m "refactor(deck): drive 2D canvas from shared tool state, drop inline chrome"
```

---

## Task 4: `DeckFullscreenViewer`

**Files:** Create `OPS/Views/Components/Project/Tabs/DeckFullscreenViewer.swift`

- [ ] **Step 1: Build the viewer** — top bar (title + mono readout + `SegmentedControl` 3D/2D + close), full-bleed canvas via `matchedGeometryEffect`, right tool rail (2D only), bottom peek-sheet readout, chrome auto-dim on `isViewportInteracting`, swipe-down + close dismiss. Key structure:

```swift
struct DeckFullscreenViewer: View {
    let project: Project
    let design: DeckDesign
    @Binding var viewMode: DeckTabViewMode        // shared with inline so mode persists
    @ObservedObject var toolState: DeckViewerToolState
    let namespace: Namespace.ID
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isViewportInteracting = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            canvas
                .matchedGeometryEffect(id: "deckCanvas", in: namespace)
                .ignoresSafeArea()
            chrome.opacity(chromeOpacity)
        }
        .hidesGlobalTabBar()
        .offset(y: dragOffset)
        .gesture(dismissDrag)
    }
    // canvas: switch viewMode → DeckTab2DView(drawingData:toolState:showsTools:true,…)
    //         or DeckTab3DView(drawingData:…). 3D shows NO rail.
    // chrome: topBar + (viewMode == .twoD ? toolRail + peekSheet : EmptyView())
}
```

- [ ] **Step 2: Tool rail (2D)** — five 44×44 circular buttons, tokens per spec. Active tint: measure→`warningStatus`, select→`primaryAccent`; others neutral. Isolate hidden unless `design.drawingData.isMultiLevel`. Each with the copy-approved `.accessibilityLabel`. `Fit` → `toolState.requestFit()`. `Dimensions` → `toolState.showDimensions.toggle()`. `Isolate` → cycle levels then nil.

- [ ] **Step 3: Peek sheet** — when `toolState.isSelecting && toolState.hasSelection`, render `DeckSelectionReadout.build(...)` in the §6.1 peek-sheet surface with `SELECTED n / CLEAR / TOTAL …` rows (moved from the 2D view).

- [ ] **Step 4: Dismiss** — `dismissDrag` tracks downward drag; `>threshold` → `onClose()` (light haptic), else spring-free snap `dragOffset = 0`. Close button → `onClose()`. Reduce Motion respected by the parent's transition.

- [ ] **Step 5: Build**

Run: device build command. Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add OPS/Views/Components/Project/Tabs/DeckFullscreenViewer.swift
git commit -m "feat(deck): fullscreen deck viewer chrome + tool rail"
```

---

## Task 5: Inline `DeckTabView` — chrome-less canvas + pull cue + namespace

**Files:** Modify `OPS/Views/Components/Project/Tabs/DeckTabView.swift`

- [ ] **Step 1:** Accept `namespace: Namespace.ID`, `sharedToolState: DeckViewerToolState`, `expandProgress: CGFloat`, `onRequestFullscreen: () -> Void` from the parent. Pass `showsTools: false` + `sharedToolState` into `DeckTab2DView`. Add `.matchedGeometryEffect(id: "deckCanvas", in: namespace)` on the rendering `Group` (source when not fullscreen).
- [ ] **Step 2:** Add the pull cue overlay above the canvas — up-chevron + `PULL TO EXPAND` (→ `RELEASE TO EXPAND` when `expandProgress >= 1`), opacity/knob driven by `expandProgress`, `.accessibilityAction(named: "Expand deck to fullscreen") { onRequestFullscreen() }`. Subtle canvas preview scale `1 + 0.03 * expandProgress` (skip under Reduce Motion).
- [ ] **Step 3:** Build. Expected: BUILD SUCCEEDED.
- [ ] **Step 4: Commit** `git add … && git commit -m "feat(deck): inline deck tab drives shared canvas + pull-to-expand cue"`

---

## Task 6: `ProjectDetailsView` — overscroll probe + fullscreen layer

**Files:** Modify `OPS/Views/Components/Project/ProjectDetailsView.swift`

- [ ] **Step 1:** Add `@Namespace private var deckNamespace`, `@StateObject private var deckToolState = DeckViewerToolState()`, `@State private var isDeckFullscreen = false`, `@State private var deckPull: CGFloat = 0`.
- [ ] **Step 2: Overscroll probe** — add `.coordinateSpace(name: "projectDetailsScroll")` to the `ScrollView` (line ~372) and a `GeometryReader→PreferenceKey` background on the first content child reporting `minY`. In the preference `onChange`, when `viewModel.selectedTab == .deck` and a renderable design exists, set `deckPull = max(0, minY - restMinY)`; fire a one-shot medium haptic as it crosses `DeckOverscrollMath.commitThreshold`.

```swift
private struct DeckPullKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
```

- [ ] **Step 3: Release→commit** — attach a simultaneous zero-distance `DragGesture(minimumDistance: 0, coordinateSpace: .named("projectDetailsScroll"))` whose `.onEnded` commits when `DeckOverscrollMath.isCommitted(pull: deckPull)`:

```swift
withAnimation(reduceMotion ? OPSStyle.Animation.faster : OPSStyle.Animation.standard) {
    isDeckFullscreen = true
}
deckPull = 0
```

- [ ] **Step 4: Fullscreen layer** — add above the nav bar layer (zIndex 30):

```swift
if isDeckFullscreen, let design = viewModel.displayedDeckDesign {
    DeckFullscreenViewer(
        project: project, design: design,
        viewMode: $deckViewMode, toolState: deckToolState,
        namespace: deckNamespace,
        onClose: { withAnimation(reduceMotion ? OPSStyle.Animation.faster : OPSStyle.Animation.standard) { isDeckFullscreen = false } }
    )
    .zIndex(30)
    .transition(reduceMotion ? .opacity : .identity)  // grow handled by matchedGeometry
}
```

- [ ] **Step 5:** In the `.deck` case of `tabContent`, pass `namespace: deckNamespace`, `sharedToolState: deckToolState`, `expandProgress: DeckOverscrollMath.progress(pull: deckPull)`, `onRequestFullscreen:` (the same commit closure). Move `viewMode` up to `@State private var deckViewMode` so inline + fullscreen share it.
- [ ] **Step 6:** Build (device) + run app-level smoke. Expected: BUILD SUCCEEDED.
- [ ] **Step 7: Commit** `git commit -m "feat(deck): overscroll-to-fullscreen wiring in project details"`

---

## Task 7: Snapshot proofs + design-system audit

**Files:** Create `OPSTests/Views/DeckFullscreenSnapshotTests.swift`

- [ ] **Step 1:** Extend the ImageRenderer harness (see `OPSTests/Views/BooksSnapshotTests.swift` / `DeckSceneSnapshotTests.swift`) to render, with a multi-level fixture `DeckDrawingData`:
  1. inline deck tab (proves unchanged), 2. `DeckFullscreenViewer` in 2D with measure active + a selection, 3. same in 3D (no rail).
- [ ] **Step 2:** Run + export attachments:

`xcodebuild ... test -only-testing:OPSTests/DeckFullscreenSnapshotTests` then `xcrun xcresulttool export attachments`.

- [ ] **Step 3:** Run `audit-design-system` over the three touched/new view files; fix any hardcoded value → token.
- [ ] **Step 4: Commit** `git commit -m "test(deck): fullscreen viewer snapshot harness"`

---

## Self-Review

- **Spec coverage:** overscroll+haptic+snap-back (T6), fullscreen layout V4 (T4), 5 tools 2D-only (T3/T4), 3D no tools (T4), inline chrome removed + pull cue (T3/T5), matchedGeometry grow + Reduce Motion (T5/T6), tab-bar hide (T4), tokens/copy (all), snapshots (T7). ✔
- **Type consistency:** `DeckViewerToolState.mode`/`.showDimensions`/`.isolatedLevelId`/`.fitTrigger`/`.requestFit()` used identically across T1/T3/T4. `DeckSelectionReadout.build(drawingData:selectedEdgeIds:selectedSurfaceIds:)` T2↔T4. `matchedGeometryEffect(id: "deckCanvas")` T4↔T5. ✔
- **Parallel-session guard:** does NOT touch `CustomTabBar.swift` (sibling WIP) — tab-bar hide via existing `.hidesGlobalTabBar()`. ✔
