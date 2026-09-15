# Deck Viewer Fixes (P9-5) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Load `ops-design`, `custom-skills:mobile-ux-design`, `animation-studio:animation-architect` + `animation-studio:ios-animations` (Tasks 1–3) and `custom-skills:interface-design` + `animation-studio:web-animations` (Task 4) before touching code. Use `superpowers:test-driven-development` for every task and `superpowers:systematic-debugging` discipline: the root causes below were traced from source; fix those, not symptoms.

**Goal:** Close the four deck reports the founder reopened or filed on 2026-09-15: viewer surface labels that fill their surface (`f7dd3673`), a truly pannable and zoomable vinyl order review (`1a8e48af`), quick-draw and dictate auto-pan that actually happens (`5f285f64`), and a web deck viewer with parity to iOS (`b130d23f`).

**Architecture:** Three independent iOS fixes on three worktrees (one branch each, merged to local `main` after a serialized simulator test pass), plus one web fix on its own worktree based on `origin/main`. Each iOS fix follows the codebase's established pattern of a pure, unit-tested policy/placement type next to the view that uses it. The web fix renders the design as live SVG from `drawing_data` inside a pan/zoom viewport with a measure mode.

**Tech Stack:** SwiftUI `Canvas` + `GraphicsContext` (iOS 17.6 target: no iOS 18 APIs), XCTest in target `OPSTests`; Next.js 15 / React / TypeScript, vitest, Tailwind tokens, `lucide-react`, Framer Motion with `EASE_SMOOTH`.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` (+ `mobile/MOBILE.md` for iOS). Every value traces to `OPSStyle` (iOS) or Tailwind tokens (web). Numbers and dimension labels: JetBrains Mono, tabular, 11px minimum on screen. One easing curve `cubic-bezier(0.22, 1, 0.36, 1)` (`OPSStyle.Animation` on iOS, `EASE_SMOOTH` on web). No accent on toggles, no spring, no bounce.

**Required Skills:** `superpowers:test-driven-development`, `superpowers:systematic-debugging`, `ops-design`, `custom-skills:mobile-ux-design`, `custom-skills:interface-design`, `animation-studio:animation-architect`, `animation-studio:ios-animations`, `animation-studio:web-animations`, `custom-skills:audit-design-system` (before calling any UI task done).

---

## Working rules for every task

- **Worktrees (already created, based on ops-ios local `main` `86f873e0`):**
  - Task 1: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/deck-labels` (branch `fix/deck-labels-20260915`)
  - Task 2: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/deck-vinyl-zoom` (branch `fix/deck-vinyl-zoom-20260915`)
  - Task 3: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/deck-quickdraw-pan` (branch `fix/deck-quickdraw-pan-20260915`)
  - Task 4: `/Users/jacksonsweet/Projects/OPS/ops-web-deck-viewer` (branch `fix/web-deck-viewer-parity-20260915`, based on `origin/main` `a06f6f5e5`; `node_modules` is a symlink to the primary checkout: never run `npm install`/`ci` there)
- **iOS: do not run `xcodebuild` or the simulator from a task.** The standing rule is that builds are batched and serialized by the coordinating session. Write the code and the tests, commit, and report "code-complete, NOT BUILT". The coordinator runs the test pass. (Line endings: every file named below is LF; the Edit tool is safe.)
- **Web: run vitest and the bounded TypeScript check yourself** (`NODE_OPTIONS=--max-old-space-size=8192 npx tsc --noEmit -p tsconfig.json` filtered to your files; the repo has 6 pre-existing test-file errors elsewhere). Do not run `next build` (the coordinator does).
- **Commits:** conventional commits, atomic, only the files you touched, no AI attribution lines. Never `git add -A`.
- **Copy:** any new user-facing string goes through `ops-copywriter` voice (terse, no exclamation points); web strings live in the i18n dictionaries (`en` + `es`).
- **Reduced motion:** every animation reads `accessibilityReduceMotion` (iOS) / `prefers-reduced-motion` (web) and degrades to a 150ms opacity or instant placement, never removed.

---

## Task 1: Viewer surface labels fill the largest inscribed rectangle (`f7dd3673`)

**Skills:** `ops-design` (JetBrains Mono, `--text`, glass pill tokens), `custom-skills:mobile-ux-design` (outdoor legibility, 11pt floor), TDD.

**Root cause (traced):** `OPS/Views/Components/Project/Tabs/DeckTab2DView.swift:361-389` `drawSurfaceLabel` draws the label at a fixed `OPSStyle.Typography.microLabel` (11pt) **in canvas space** at the naive vertex mean. The whole 4800×4800 canvas is then `.scaleEffect(canvasScale)` with `canvasScale = min(fit)*0.85` ≈ 0.25–0.5 for a real deck (`:229-274`), so the label lands at 3–6pt on screen. The nightly fix `94543f95` only made edge captions appear (`:647-673`), at an inverse-scaled fixed 11pt. No inscribed-rectangle utility exists anywhere in the app.

**Requirement (founder, 2026-09-15):** label size is responsive, stretching to fill the largest rectangular space that fits inside the surface, so a label never overlaps any geometry.

**Files:**
- Create: `OPS/DeckBuilder/Rendering/DeckSurfaceLabelPlacement.swift`
- Create: `OPSTests/DeckBuilder/DeckSurfaceLabelPlacementTests.swift`
- Modify: `OPS/Views/Components/Project/Tabs/DeckTab2DView.swift` (`drawSurfaceLabel` :361-389; both call sites :342-349 and :713-720 already pass `positions: [CGPoint]`; edge caption sizing :647-673)
- Modify: `OPS/DeckBuilder/Views/DeckCanvasView.swift` (`drawSurfaceLabel` :819-832 adopts the same placement for its anchor and clamps its pill inside the rectangle)
- Modify: `OPSTests/Views/DeckViewerEdgeLabelRenderingTests.swift` (add a geometric assertion, see Step 7)

**Design tokens:** font `OPSStyle.Typography` mono family (JetBrains Mono, same family as `microLabel`; size computed), color `OPSStyle.Colors.text`, pill `OPSStyle.Colors.glassDenseApprox` + `OPSStyle.Colors.line` hairline (as today), padding `OPSStyle.Layout.spacing1`, floor 11pt **on screen**, cap 28pt on screen (DESIGN.md display ceiling).

**Design decisions (do not re-litigate):**
- The label is sized in **canvas space** so it scales with the geometry, then clamped by screen-space floor/cap: `fontCanvas = clamp(fitFont, 11/canvasScale, 28/canvasScale)`. At fit zoom a big simple deck gets a large label; zooming in never makes it absurd.
- If even the 11pt-on-screen floor does not fit the inscribed rectangle's width, truncate the text with `…` to the rectangle width (never draw outside the rectangle). Never hide the label.
- Placement anchor is the inscribed rectangle's center, not the vertex mean (which falls outside concave shapes).
- Edge custom captions (`DeckEdge.label`, :652-673) keep their inverse-scaled treatment but become proportional: caption font on screen = `clamp(fit to 60% of the edge's on-screen length, 11, 20)` so they read at fit zoom without covering the neighbouring geometry. The dimension pill itself stays 11pt.

**Step 1: Write the failing placement tests**

```swift
// OPSTests/DeckBuilder/DeckSurfaceLabelPlacementTests.swift
import XCTest
@testable import OPS

final class DeckSurfaceLabelPlacementTests: XCTestCase {
    private let square: [CGPoint] = [.init(x: 0, y: 0), .init(x: 400, y: 0), .init(x: 400, y: 300), .init(x: 0, y: 300)]
    // L-shape: 400 wide, 300 tall, with the top-right 200×150 notch removed
    private let lShape: [CGPoint] = [.init(x: 0, y: 0), .init(x: 200, y: 0), .init(x: 200, y: 150), .init(x: 400, y: 150), .init(x: 400, y: 300), .init(x: 0, y: 300)]

    func testRectangleSurfaceYieldsNearlyTheWholeSurface() {
        let rect = DeckSurfaceLabelPlacement.largestInscribedRect(in: square)!
        XCTAssertGreaterThan(rect.width * rect.height, 0.9 * 400 * 300)
        XCTAssertTrue(DeckSurfaceLabelPlacement.isInside(rect, polygon: square))
    }

    func testLShapeRectangleLiesInsideOneLegAndNeverInTheNotch() {
        let rect = DeckSurfaceLabelPlacement.largestInscribedRect(in: lShape)!
        XCTAssertTrue(DeckSurfaceLabelPlacement.isInside(rect, polygon: lShape))
        // the notch is x>200 && y<150; no corner may be there
        for corner in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
            XCTAssertFalse(corner.x > 200 && corner.y < 150, "corner \(corner) is in the notch")
        }
        XCTAssertGreaterThan(rect.width * rect.height, 0.5 * 200 * 300) // at least half of the tall leg
    }

    func testDegeneratePolygonReturnsNil() {
        XCTAssertNil(DeckSurfaceLabelPlacement.largestInscribedRect(in: [.zero, .init(x: 10, y: 10)]))
    }

    func testFitFillsTheRectangleAndRespectsScreenFloorAndCap() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
        // a fake measurer: width = 0.6 * fontSize per character, height = 1.2 * fontSize
        let measure: (String, CGFloat) -> CGSize = { text, size in CGSize(width: CGFloat(text.count) * 0.6 * size, height: 1.2 * size) }
        let fit = DeckSurfaceLabelPlacement.fit(text: "Upper deck", in: rect, canvasScale: 0.5, padding: 8, measure: measure)
        XCTAssertLessThanOrEqual(fit.size.width, rect.width - 16)
        XCTAssertLessThanOrEqual(fit.size.height, rect.height - 16)
        XCTAssertLessThanOrEqual(fit.fontSize * 0.5, 28) // cap on screen
        XCTAssertGreaterThanOrEqual(fit.fontSize * 0.5, 11) // floor on screen
        XCTAssertEqual(fit.text, "Upper deck")
    }

    func testTooNarrowRectangleTruncatesAtTheScreenFloorInsteadOfOverflowing() {
        let rect = CGRect(x: 0, y: 0, width: 60, height: 40)
        let measure: (String, CGFloat) -> CGSize = { text, size in CGSize(width: CGFloat(text.count) * 0.6 * size, height: 1.2 * size) }
        let fit = DeckSurfaceLabelPlacement.fit(text: "Upper deck level two", in: rect, canvasScale: 1, padding: 4, measure: measure)
        XCTAssertEqual(fit.fontSize, 11)
        XCTAssertTrue(fit.text.hasSuffix("…"))
        XCTAssertLessThanOrEqual(fit.size.width, rect.width - 8)
    }

    func testCenterIsInsideConcavePolygon() {
        let placement = DeckSurfaceLabelPlacement.largestInscribedRect(in: lShape)!
        XCTAssertTrue(PolygonMath.pointInPolygon(CGPoint(x: placement.midX, y: placement.midY), vertices: lShape))
    }
}
```

**Step 2: Run to verify they fail** (coordinator runs; you may confirm the file compiles by reading `DeckDimensionLabelViewportTests.swift` for the import/`@testable` pattern).

**Step 3: Implement the placement type** (pure CoreGraphics, no SwiftUI views)

```swift
// OPS/DeckBuilder/Rendering/DeckSurfaceLabelPlacement.swift
import CoreGraphics
import Foundation

/// Largest axis-aligned rectangle inside a surface polygon, and text fitting
/// inside it. Pure and viewport-free so the viewer, the builder and export
/// renderers place surface labels identically. Grid-rasterized maximal
/// rectangle: O(n²) over a 64×64 grid of the polygon's bounding box, which is
/// well under a millisecond for deck surfaces and deterministic.
enum DeckSurfaceLabelPlacement {
    static let gridResolution = 64
    static let screenFloorPoints: CGFloat = 11   // DESIGN.md: 11px minimum, no exceptions
    static let screenCapPoints: CGFloat = 28     // DESIGN.md display ceiling

    struct Fit: Equatable {
        let text: String        // possibly truncated with "…"
        let fontSize: CGFloat   // canvas units
        let size: CGSize        // measured text size at fontSize (canvas units)
    }

    static func largestInscribedRect(in polygon: [CGPoint]) -> CGRect? {
        guard polygon.count >= 3 else { return nil }
        let xs = polygon.map(\.x), ys = polygon.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
              maxX > minX, maxY > minY else { return nil }
        let n = gridResolution
        let cellW = (maxX - minX) / CGFloat(n), cellH = (maxY - minY) / CGFloat(n)
        // inside[r][c] == true when the cell's center is inside the polygon
        var inside = [[Bool]](repeating: [Bool](repeating: false, count: n), count: n)
        for r in 0..<n { for c in 0..<n {
            let p = CGPoint(x: minX + (CGFloat(c) + 0.5) * cellW, y: minY + (CGFloat(r) + 0.5) * cellH)
            inside[r][c] = PolygonMath.pointInPolygon(p, vertices: polygon)
        } }
        // maximal rectangle in a binary matrix via per-row histograms + stack
        var heights = [Int](repeating: 0, count: n)
        var best = (area: 0, r0: 0, c0: 0, r1: 0, c1: 0)
        for r in 0..<n {
            for c in 0..<n { heights[c] = inside[r][c] ? heights[c] + 1 : 0 }
            var stack: [Int] = []
            for c in 0...n {
                let h = c == n ? 0 : heights[c]
                while let top = stack.last, heights[top] >= h {
                    stack.removeLast()
                    let height = heights[top]
                    let left = stack.last.map { $0 + 1 } ?? 0
                    let width = c - left
                    let area = height * width
                    if area > best.area { best = (area, r - height + 1, left, r, c - 1) }
                }
                stack.append(c)
            }
        }
        guard best.area > 0 else { return nil }
        // shrink by half a cell on every side so the rectangle is strictly inside
        let x0 = minX + CGFloat(best.c0) * cellW + cellW / 2
        let y0 = minY + CGFloat(best.r0) * cellH + cellH / 2
        let x1 = minX + CGFloat(best.c1 + 1) * cellW - cellW / 2
        let y1 = minY + CGFloat(best.r1 + 1) * cellH - cellH / 2
        guard x1 > x0, y1 > y0 else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    static func isInside(_ rect: CGRect, polygon: [CGPoint]) -> Bool {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
         CGPoint(x: rect.midX, y: rect.midY)].allSatisfy { PolygonMath.pointInPolygon($0, vertices: polygon) }
    }

    /// Chooses the largest font (canvas units) whose measured single line fits
    /// `rect` inset by `padding`, clamped to the on-screen floor/cap given the
    /// current `canvasScale`. Text metrics scale linearly with font size, so one
    /// reference measurement plus one confirmation measurement is enough.
    static func fit(text: String, in rect: CGRect, canvasScale: CGFloat, padding: CGFloat,
                    measure: (String, CGFloat) -> CGSize) -> Fit {
        let scale = max(canvasScale, CGFloat.ulpOfOne.squareRoot())
        let floor = screenFloorPoints / scale, cap = screenCapPoints / scale
        let availW = max(rect.width - 2 * padding, 0), availH = max(rect.height - 2 * padding, 0)
        let reference: CGFloat = 100
        let ref = measure(text, reference)
        var size = reference
        if ref.width > 0 && ref.height > 0 {
            size = min(availW / ref.width, availH / ref.height) * reference
        }
        size = min(cap, max(floor, size))
        var candidate = text
        var measured = measure(candidate, size)
        if measured.width > availW && size <= floor + 0.01 {
            // floor cannot fit: truncate rather than overflow the rectangle
            var chars = Array(text)
            while chars.count > 1 {
                chars.removeLast()
                candidate = String(chars).trimmingCharacters(in: .whitespaces) + "…"
                measured = measure(candidate, size)
                if measured.width <= availW { break }
            }
        }
        return Fit(text: candidate, fontSize: size, size: measured)
    }
}
```

**Step 4: Wire the viewer** — replace the body of `DeckTab2DView.drawSurfaceLabel` (`:361-389`): compute `largestInscribedRect(in: positions)`; if nil fall back to `PolygonMath.polygonCentroid` with the floor font; call `fit` with a measurer built from `context.resolve(Text(candidate).font(.custom("JetBrainsMono-Regular", size: size)))` (`OPSStyle` exposes the mono family name; keep the existing weight/family), draw the glass pill sized to `fit.size + spacing1` centered at `rect.mid`, then the text. Keep it in canvas space (no `drawLayer` inverse scale). Both call sites need no change. Then make the edge caption (`:652-673`) proportional per the design decision: measure the edge's on-screen length (`hypot` of the endpoints × `canvasScale`), fit the caption to 60% of it, clamp `[11, 20]` on screen.

**Step 5: Wire the builder** — in `DeckCanvasView.drawSurfaceLabel` (`:819-832`) use `DeckSurfaceLabelPlacement.largestInscribedRect` for the anchor (fallback centroid) and clamp `pillW`/`pillH` to the rectangle so the pill can never cover geometry; keep the builder's `scaledSize` font clamps (the builder is an editing surface; it does not need fill-to-rectangle sizing).

**Step 6: Commit** (`fix(deck): size viewer surface labels to the largest inscribed rectangle (f7dd3673)`), then a second commit for the builder anchor adoption.

**Step 7: Geometric render test** — in `DeckViewerEdgeLabelRenderingTests.swift` add `testSurfaceLabelFitsInsideItsSurface`: build a drawing with one 400×300 surface labeled "Upper deck", render via `FixedSizeSnapshot` at 393×393, and assert that the label placement computed by `DeckSurfaceLabelPlacement` (same inputs the view uses) has `isInside == true` and `fontSize * canvasScale >= 11`. (The byte-diff test stays.) Commit.

**Acceptance:** at fit zoom on a typical deck the surface label is legible without zooming (≥11pt on screen, typically far larger); zooming in grows it up to 28pt on screen; an L-shaped deck's label sits inside one leg; no label pill ever crosses an edge.

---

## Task 2: Vinyl order review is fully pannable and zoomable (`1a8e48af`)

**Skills:** `animation-studio:animation-architect` (Discovery beat: immediate response; Transition beat for double-tap fit, 200ms `OPSStyle.Animation.panel`, no bounce), `animation-studio:ios-animations`, `custom-skills:mobile-ux-design` (44pt targets unchanged; FIT chip stays), TDD.

**Root cause (traced):** `OPS/DeckBuilder/Views/VinylCutPreview.swift:1098-1116` applies `.scaleEffect(viewport.scale).offset(viewport.offset)` **outside** the live `Canvas`, so zoom is a bitmap scale of a fixed-size render (blurry, "snapshot" feel). `VinylOrderViewportState.applyZoom` (`:28-38`) has no anchor, so pinch zooms about the viewport centre while double-tap (`toggleFit`, `:67-91`) is anchored. `applyPan` (`:40-53`) refuses to pan at fit scale. The clamp (`:99-107`) assumes the drawing fills the viewport. `MagnificationGesture` + `simultaneousGesture(DragGesture)` fight during a pinch. Max zoom is 4×.

**Requirement (founder):** fully pannable and zoomable on the live drawing, not centre-zoom on a snapshot.

**Files:**
- Modify: `OPS/DeckBuilder/Views/VinylCutPreview.swift` (`VinylOrderViewportState` :12-113; `VinylCutPreview.body` :286-341 draw + `fit(in:)`; `drawingViewport(size:)` :1098-1123; gestures :1260-1325)
- Reuse: `OPS/DeckBuilder/Views/DeckCanvasView.swift:2323-2434` `CanvasGestureView` (single `UIPinchGestureRecognizer` doing pan + anchored zoom) and the in-canvas transform pattern at `:370-379`
- Modify: `OPSTests/DeckBuilder/VinylPreviewAnnotationPlannerTests.swift` (`VinylOrderViewportStateTests` :203-300)
- Modify if needed: `OPSTests/Views/VinylOrderWorkspaceSnapshotTests.swift` (helper `makeWorkspace(viewport:)` :199-210)

**Design tokens:** no new colors; labels stay screen-sized via inverse scale like the builder (`DeckCanvasView.swift:1164, 1189-1195`); FIT chip unchanged; double-tap animation `OPSStyle.Animation.panel`, reduced motion → instant.

**Design decisions:**
- Zoom range `[fitScale, 8 × fitScale]` (builder uses 8× max). Pan is always allowed; the clamp uses the **drawn content bounds** (`VinylPreviewFitResult`'s content rect) plus a margin of 25% of the viewport, not the viewport size.
- Pinch zoom is anchored at the pinch midpoint (same math as `CanvasGestureView`, and as `toggleFit`).
- The `Canvas` applies `context.translateBy/scaleBy` from the viewport state so strokes stay crisp at every zoom; annotation text is inverse-scaled so it stays 11pt on screen.
- Keep double-tap toggle (fit ↔ 2.5× about the tap) and the FIT chip.

**Step 1: Failing tests** (add to `VinylOrderViewportStateTests`):

```swift
func testPinchZoomKeepsThePointUnderTheFingersFixed() {
    var viewport = VinylOrderViewportState(scale: 1, offset: .zero)
    let size = CGSize(width: 320, height: 640)
    let anchor = CGPoint(x: 80, y: 500)
    let before = viewport.contentPoint(forViewportPoint: anchor, viewportSize: size)
    viewport.applyZoom(multiplier: 2, anchor: anchor, viewportSize: size, contentBounds: CGRect(x: 0, y: 0, width: 320, height: 640))
    let after = viewport.contentPoint(forViewportPoint: anchor, viewportSize: size)
    XCTAssertEqual(before.x, after.x, accuracy: 0.5); XCTAssertEqual(before.y, after.y, accuracy: 0.5)
}

func testPanIsAllowedAtFitScaleWithinContentMargins() {
    var viewport = VinylOrderViewportState(scale: 1, offset: .zero)
    let size = CGSize(width: 320, height: 640)
    viewport.applyPan(translation: CGSize(width: 40, height: -30), viewportSize: size, contentBounds: CGRect(x: 0, y: 0, width: 320, height: 640))
    XCTAssertEqual(viewport.offset.width, 40, accuracy: 0.5)
    XCTAssertEqual(viewport.offset.height, -30, accuracy: 0.5)
}

func testPanClampsToContentBoundsPlusMargin() { /* pan far beyond; assert offset stops at contentBounds ± 25% viewport */ }

func testZoomRangeIsFitToEightTimesFit() { /* applyZoom by 100 → scale == 8; by 0.01 → scale == 1 */ }
```

Update the existing `testPanClampsToTheVisibleZoomedCanvasBounds` (`:222`) to the new content-bounds clamp semantics (it currently pins the old viewport-size math) and keep `testDoubleTapZoomsAboutTheTappedPoint` green.

**Step 2–3:** Implement in `VinylOrderViewportState`: add `anchor` + `contentBounds` parameters (`applyZoom(multiplier:anchor:viewportSize:contentBounds:)`, `applyPan(translation:viewportSize:contentBounds:)`, `contentPoint(forViewportPoint:viewportSize:)`), anchored-zoom math `offset = anchor - ratio * (anchor - offset)`, content-bounds clamp with 25% margin, `maximumScale = 8`. Remove the fit-scale pan guard.

**Step 4:** In `drawingViewport(size:)` replace `.scaleEffect/.offset` + `MagnificationGesture`/`DragGesture` with: the `Canvas` receiving `viewport` and applying `context.translateBy(x: offset.width, y: offset.height); context.scaleBy(x: scale, y: scale)` inside `VinylCutPreview` (thread `viewport` in as a parameter; annotation text uses `layer.scaleBy(1/scale)` like `DeckCanvasView.swift:1189-1195`), and `CanvasGestureView(scale: $scaleBinding, offset: $offsetBinding, constrainOffset:)` in the overlay. Keep `onTapGesture(count: 2)` → `toggleFit(at:)`. Provide the content bounds from `VinylPreviewFit`.

**Step 5:** Reduced motion: the double-tap `withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel)`.

**Step 6:** Commit: `fix(vinyl): pan and zoom the live cut layout about the fingers (1a8e48af)`.

**Acceptance:** pinch anywhere zooms about the fingers with crisp lines; one-finger and two-finger drag pans at any zoom; content cannot be lost off screen; double-tap fits; labels stay 11pt.

---

## Task 3: Quick-draw and dictate pan to the next point (`5f285f64`)

**Skills:** `animation-studio:animation-architect` (Transition beat: camera move 200ms `OPSStyle.Animation.panel`, light haptic already handled by the commit action, none added), `animation-studio:ios-animations`, TDD.

**Root causes (traced, three independent):**
1. `OPS/DeckBuilder/Views/DeckCanvasView.swift:231-249` `.onChange(of: viewportLayout)` calls `viewportSnap.stop()` (`:236`). The speed-draw overlay is the bottom chrome (`DeckBuilderView.swift:144-156`, `:304-306`), and its height animates ~150–190pt on every commit and direction pick (`PerimeterLengthControlView.swift:54`). That re-fires the layout handler every frame for the same 200ms the camera pan needs (`OPSStyle.Animation.durationPanel`), so the pan is cancelled at ~0% progress. Only the half-chrome nudge from `offsetPreservingUnobstructedCenter` survives, which reads as jitter.
2. On commit, `followPerimeterDraft` is never called: `.onChange(of: viewModel.perimeterDraftPreview)` (`:258-261`) guards on a non-nil preview, but commit moves the state to `.choosingDirection` (`DeckBuilderViewModel.swift:1756-1762`), where `perimeterDraftPreview` (`:1520-1543`) is nil.
3. Direction change is gated off: `followPerimeterDraft` returns when `hasActiveWorkspaceManipulation` (`:1786-1787`, set by the reorient drag at `:2010`), and the end-of-drag action centres on the **anchor** (`DeckCanvasWorkspace.swift:284-286`), not the new endpoint. Wheel selection (`selectPerimeterDirection`, VM `:1627`) produces only `perimeterDirectionGhost` (VM `:1547`), which nothing follows. Also `followPerimeterDraft`'s `constrainedOffset` (`:1821-1827`) leaves `centerWhenWorkspaceFits` at its default `true`, which discards the pan whenever the workspace fits an axis.

**Files:**
- Modify: `OPS/DeckBuilder/Views/DeckCanvasView.swift` (`:231-249`, `:258-280`, `:1777-1837`, `:2010`, `ViewportSnapAnimator` `:2141-2205`)
- Modify: `OPS/DeckBuilder/Models/DeckCanvasWorkspace.swift` (`DeckCanvasFollowPolicy` `:353-424`; `perimeterReorientationCameraAction` `:276-289`)
- Create: `OPS/DeckBuilder/Models/DeckCanvasCameraPlan.swift` (pure decision: which point to follow for a perimeter-entry transition)
- Create: `OPSTests/DeckBuilder/DeckCanvasCameraPlanTests.swift`
- Modify: `OPSTests/DeckBuilder/DeckCanvasFollowPolicyTests.swift`, `OPSTests/DeckBuilder/PerimeterEntryTests.swift` (`:320` interpolation test area)

**Design decisions:**
- **Retarget, never cancel.** `ViewportSnapAnimator` gains `translateTarget(by delta: CGSize)`; the layout handler, when a snap is in flight, shifts both the current offset and the target by the `offsetPreservingUnobstructedCenter` delta instead of calling `stop()`. The animation continues to the corrected destination, so the pan and the chrome animate together.
- **One camera plan for every perimeter transition.** `DeckCanvasCameraPlan.focus(after transition: PerimeterEntryMode, previous: PerimeterEntryMode, ghostLength: CGFloat) -> CGPoint?` returns the point to follow: on `.choosingDirection(anchor)` after `.enteringLength` (a commit) → the new anchor; on `.enteringLength(anchor, direction, draft)` when direction changed → the draft end, or the ghost end when the draft is zero-length; on the same state with only a length change → the draft end (existing follow). The view calls `followPoint(_:)` (renamed generalization of `followPerimeterDraft`) with that focus.
- **Direction change follows on release.** During the reorient drag the finger owns the canvas (no pan); on `.ended`, `perimeterReorientationCameraAction` returns `.follow(draftEnd)` instead of `.centerOn(anchor)`. Wheel selection follows immediately.
- Follow uses `DeckCanvasFollowPolicy` (minimal pan that brings the focus inside the unobstructed safe area) with `centerWhenWorkspaceFits: false`. If the point is already comfortably in view nothing moves.
- Reduced motion: follow applies instantly (no animator).

**Step 1: Failing camera-plan tests**

```swift
// OPSTests/DeckBuilder/DeckCanvasCameraPlanTests.swift
final class DeckCanvasCameraPlanTests: XCTestCase {
    func testCommitFollowsTheNewAnchor() {
        let previous = PerimeterEntryMode.enteringLength(anchor: .init(x: 0, y: 0), direction: .absolute(.east), draft: .inches(120))
        let next = PerimeterEntryMode.choosingDirection(anchor: .init(x: 120, y: 0))
        XCTAssertEqual(DeckCanvasCameraPlan.focus(after: next, previous: previous, ghostLength: 96), CGPoint(x: 120, y: 0))
    }
    func testDirectionChangeWithZeroLengthFollowsTheGhostEnd() { /* .enteringLength same anchor, new direction, draft .zero → anchor + direction*ghostLength */ }
    func testDirectionChangeWithLengthFollowsTheDraftEnd() { /* → PerimeterEntryGeometry.endpoint */ }
    func testIdleTransitionHasNoFocus() { XCTAssertNil(DeckCanvasCameraPlan.focus(after: .idle, previous: .idle, ghostLength: 96)) }
}
```
(Use the real `PerimeterEntryMode`/`PerimeterDirection`/`PerimeterEntryGeometry.endpoint` from `PerimeterEntryState.swift`; mirror how `PerimeterEntryTests.swift:353,431` construct them.)

**Step 2: Failing animator test** (in `PerimeterEntryTests.swift` next to `:320`, or a new `ViewportSnapAnimatorTests.swift`): drive the animator with an injectable clock/step (add `step(now:)` if the timer is not injectable), start a snap from `.zero` to `(100, 0)`, call `translateTarget(by: CGSize(width: 0, height: -80))` at 30% progress, keep stepping, assert the final offset is `(100, -80)` and that no step ever moved backwards.

**Step 3: Failing follow-policy test** in `DeckCanvasFollowPolicyTests.swift`: with a workspace that fits the viewport on the x-axis and `centerWhenWorkspaceFits: false`, a focus under the bottom chrome still produces a non-zero pan.

**Step 4: Implement** `DeckCanvasCameraPlan`, `ViewportSnapAnimator.translateTarget(by:)`, the layout-handler retarget (`:231-249`), `followPoint(_:)` with `centerWhenWorkspaceFits: false`, the `.onChange(of: viewModel.perimeterEntry)` hook using the plan (replace the unconditional `centerViewport` at `:273` for `.choosingDirection`), and the reorient `.ended` action change (`DeckCanvasWorkspace.swift:284-286`). Do not remove the initial-anchor centering for the transition from `.idle`.

**Step 5: Commit** in two atomic commits: `fix(deck): keep the camera pan alive across bottom-chrome remeasure` and `fix(deck): follow the next point after commit and direction change (5f285f64)`.

**Acceptance:** commit a length → the view glides so the new point sits inside the safe area above the picker; change direction by drag or wheel → on release the view glides to the new endpoint; dictating a length then committing behaves identically; no jitter from the overlay resize.

---

## Task 4: Web deck viewer with parity to iOS (`b130d23f`, also closes `acc0d021`)

**Skills:** `custom-skills:interface-design` (state intent before each component), `ops-design` (Tailwind tokens only), `animation-studio:animation-architect` + `animation-studio:web-animations` (pan/zoom = Discovery beat, immediate; fit = Transition beat, 250ms `EASE_SMOOTH`, reduced motion → instant), `ops-copywriter` (all strings via `useDictionary`, en + es), TDD, `custom-skills:audit-design-system` before done.

**Root causes (traced):**
1. `src/lib/api/services/deck-design-service.ts:86-92` selects only `drawing_data->vertices` and `drawing_data->edges`. Multi-level designs store geometry under `levels[]` with empty root arrays (see `src/lib/agent-control-plane/services/p2/deck-design/__fixtures__/ops-ios/multi-level-connection.json`), so `buildWireframeModel` returns null and the UI falls back to the raster thumbnail. Surfaces, dimensions, stairs, labels, `scaleFactor` and levels are never fetched.
2. `src/app/(dashboard)/pipeline/_components/deck-design-viewer.tsx:79,105-122` boxes the "viewer" at `max-w-[720px]` and shows `<img object-contain>` first; the 40px glyph uses `object-cover` (`pipeline-detail-deck-section.tsx:130-134`); `src/lib/utils/deck-wireframe.ts:103-118` forces a square 100-unit viewBox. No transform, wheel or pointer handling exists.
3. No project surface renders a deck at all, although `deck_designs.project_id` is stored and already mapped (`deck-design-service.ts:30,66`). That is report `acc0d021`.

**Intent (interface-design):** the human is a trades owner at a desk or on a tablet in the truck checking a deck drawing before a quote or a crew brief. The verb is *read the drawing and check a run*. It should feel like a drafting table: the drawing owns the whole screen on pure black, hairline geometry, mono dimensions, a thin tool rail that dims while the drawing is being moved. Rejected defaults: modal card with a picture → fullscreen drafting surface; +/− buttons only → rail with fit, measure, labels, levels, 2D/3D; coloured decoration → monochrome fills, with the per-level `displayColor` from the data at low alpha only when a design has more than one level (that colour is meaning: which level).

**Files:**
- Modify: `src/lib/api/services/deck-design-service.ts` (add `fetchDesignWithDrawing(id)` selecting the full `drawing_data`, and `fetchForProject(projectId)`; keep the narrow projection for the glyph and marker scan)
- Create: `src/lib/deck/drawing-data.ts` (client-safe port of plane normalization `levels[]`-else-root, vertex weld, face detection and surface/hole walk from `src/lib/agent-control-plane/services/p2/deck-design/deck-geometry-calculator.ts:624-1160`; `scaleFactor ?? 2` per `:751-754`) and `src/lib/deck/label-placement.ts` (TypeScript port of Task 1's `largestInscribedRect` + `fit`, same algorithm, so labels match iOS)
- Create: `src/lib/deck/viewport.ts` (pure reducer: `zoomBy(delta, anchorX, anchorY)`, `panBy`, `fit(bounds, size, padding 0.85)`, clamp `0.15…8`; copy the anchor math from `src/app/(dashboard)/projects/_components/project-canvas-store.ts:144-151, 247-256`)
- Create: `src/lib/deck/measure.ts` (pure port of iOS `DeckViewerToolState.recordMeasureTap` `OPS/DeckBuilder/Models/DeckViewerToolState.swift:151-203` and `DeckMeasureReadout.build` `DeckMeasureReadout.swift:36-82`: tap-to-place polyline, snap to vertex within 12 screen px, close loop on first point, undo, clear; readout = running length, segment count, and on close area + perimeter, `—` when self-intersecting; inches from `scaleFactor`)
- Create: `src/components/ops/deck/deck-plan-svg.tsx` (one `<svg>` with `viewBox` = true geometry bounds; inside a `<g transform="translate() scale()">` from the viewport; layers in order: level surface fills → house edges (dashed hairline) → deck edges (hairline) → stairs (treads) → vertices → dimension labels (mono 11px, `non-scaling` via inverse scale, hidden when labels off) → surface labels (inscribed-rectangle placement, floor 11px screen, cap 28px) → measure overlay; each level its own `<g>` dimmed to 0.25 opacity when another level is isolated)
- Create: `src/components/ops/deck/deck-viewer.tsx` (fullscreen portal `fixed inset-0 z-[3000]` glass-dense top bar: title, `V3 · Jul 13` stamp in mono, 2D/3D segment per DESIGN.md toggles (no accent), close; right tool rail: fit, measure, labels toggle, levels cycle (multi-level only), each a 36px control with `aria-label`; pointer drag pans, wheel zooms about the cursor, two-pointer pinch zooms about the midpoint, double-click fits; rail dims to `text-mute` while a pointer is down; Escape closes; `useReducedMotion` → no fit animation)
- Create: `src/components/ops/deck/deck-scene-3d.tsx` (React Three Fiber, loaded with `dynamic(() => import(...), { ssr: false })` exactly like `src/app/(dashboard)/calibration/_components/section-corpus.tsx:11-14`; per level: surface extruded to board thickness at the level elevation, rim beams under deck edges, house edges as 8ft walls, posts from surface corners to ground, stairs as treads from `stairConfig`, drei `OrbitControls` with damping off, fit-to-bounds camera; monochrome materials, level fills tinted by `displayColor` at low alpha; gated on a closed outline with an honest empty state as iOS does at `DeckFullscreenViewer.swift:81-118`)
- Modify: `src/app/(dashboard)/pipeline/_components/pipeline-detail-deck-section.tsx` (row opens the new `DeckViewer`; glyph keeps the narrow wireframe but with `object-contain`, never `object-cover`)
- Delete: `src/app/(dashboard)/pipeline/_components/deck-design-viewer.tsx` (superseded)
- Modify: the project workspace viewing mode (`src/components/ops/projects/workspace/`, the dossier tabs) to add a `// DECK DESIGN` section using `useProjectDeckDesigns(projectId)` → `fetchForProject`, state-aware (hidden when the project has no design), opening the same viewer
- i18n: `src/i18n/dictionaries/{en,es}/pipeline.json` and `project-workspace.json` (keys for tool labels: `FIT`, `MEASURE`, `LABELS`, `LEVELS`, `2D`, `3D`, readout labels `LENGTH`, `AREA`, `PERIMETER`, empty state `[ no closed outline ]`)
- Tests (vitest): `tests/unit/deck/drawing-data.test.ts` (parse every fixture in `__fixtures__/ops-ios/` and `__fixtures__/ops-decks-ios/`: face count and surface areas match the server calculator's results for the same fixture), `tests/unit/deck/label-placement.test.ts` (square, L-shape, degenerate, fit floor/cap/truncate — mirror Task 1), `tests/unit/deck/viewport.test.ts` (anchored zoom keeps the point under the cursor, clamp, fit), `tests/unit/deck/measure.test.ts` (snap, running length in inches at `scaleFactor` 2, close loop area/perimeter, self-intersecting → null), `tests/unit/deck/deck-viewer.test.tsx` (opens fullscreen, renders surfaces/edges/dimension text, labels toggle hides dimensions, levels cycle isolates, measure mode readout appears, Escape closes), update `tests/unit/pipeline/pipeline-detail-deck-section.test.tsx` for the new viewer, add `tests/unit/api/deck-design-service.test.ts` asserting the select strings.

**Design tokens:** canvas `bg-black`; geometry strokes `stroke-text-2` hairline (`vectorEffect="non-scaling-stroke"`, 1px), house edges dashed `stroke-text-3`; surface fill `fill-neutral-dim` (single level) or level `displayColor` at 12% (multi-level); vertices `fill-text-3` 2px; dimension and readout text `font-mono text-[11px] tabular-nums [font-feature-settings:'tnum' 1,'zero' 1]` `text-text-2`; surface labels `font-mono text-text` on a `glass-dense` pill; rail controls `border-border-subtle text-text-3 hover:text-text-2` active `text-text bg-surface-hover`; measure polyline `stroke-tan` (attention semantic), readout pill `glass-dense`; no accent anywhere except focus rings; motion `EASE_SMOOTH` 250ms for fit, none for pan/zoom.

**Steps (TDD, commit after each green):**
1. Service: failing test for the two new fetches → implement → commit `fix(deck): fetch full drawing data for the viewer and by project (b130d23f)`.
2. `drawing-data.ts` port with fixture-driven tests → commit.
3. `label-placement.ts`, `viewport.ts`, `measure.ts` with tests → three commits.
4. `deck-plan-svg.tsx` + `deck-viewer.tsx` (2D, measure, labels, levels, fit) with component tests; replace the pipeline viewer; i18n → commit `feat(deck): fullscreen web deck viewer with pan, zoom, measure and levels`.
5. Project workspace `// DECK DESIGN` section + hook → commit `feat(projects): show the project deck design in the workspace (acc0d021)`.
6. `deck-scene-3d.tsx` lazy 3D mode + toggle + tests (scene builder is pure: test the mesh plan, not WebGL) → commit `feat(deck): 3D mode for the web deck viewer`.
7. Run `custom-skills:audit-design-system` on the new files; fix any hardcoded value; run the bounded tsc and every touched test file; report exact pass lines.

**Acceptance:** a multi-level deck opens fullscreen on web with all levels drawn from live geometry; wheel and drag move it crisply; measuring two vertices reads the same inches as iOS; labels toggle and level isolation work; 2D/3D switch shows the massing; the project window shows the project's deck; no thumbnail is ever cropped.
