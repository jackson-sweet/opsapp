# Deck Split-Surface Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the deck fullscreen viewer's 2D select mode, with exactly one surface selected, let the user draw a line across the face (two taps, endpoints anywhere — the infinite line through them just has to cross the surface) and instantly read the area of each side. Look-only inspection tool: nothing persists, no model/sync changes. Scope confirmed by Jackson 2026-07-02 (look-only; free endpoints).

**Architecture:** A pure `PolygonSplitter` engine (Sutherland–Hodgman half-plane clipping, concave-safe) + a pure `DeckSplitReadout` reducer feed a `DeckViewerToolState` sub-state of select mode (`isSplitting` + `splitPoints`). `DeckTab2DView` routes select-mode taps to split-point placement while active and renders chord + tinted halves; `DeckFullscreenViewer` adds the contextual scissors rail button, hint copy, and the split readout card. Mirrors the measure tool shipped in `67ab42ba` — same rail/hint/card grammar, same snapping engines.

**Tech Stack:** SwiftUI Canvas, XCTest. iOS 17.6 deployment target — no iOS-18-only APIs. All colors/spacing via `OPSStyle` tokens.

**Context for a fresh session (read first):**
- Work in an isolated ops-ios worktree off local `main` (which already contains the measure-tool commits `37b5614c`/`67ab42ba` — this plan builds on them). Copy secrets in: `cp <primary>/OPS/Utilities/Secrets.xcconfig <worktree>/OPS/Utilities/Secrets.xcconfig`.
- Test command: `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .ddata -only-testing:OPSTests/<Class>`. Background it; grep the log for `TEST SUCCEEDED` — the shell exit code lies (trailing pipe).
- Device build verification: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .ddata build`.
- New Swift files are auto-included (Xcode 16 synchronized groups — no pbxproj edits). SourceKit "Cannot find type" noise in fresh worktrees is index lag; trust xcodebuild.
- Land via: commit on your branch → merge `main` into it if main advanced → `git -C <primary-ops-ios> merge --ff-only <branch>`. Stage files BY NAME (never `git add -A`), no AI attribution in commits. **Do NOT push to origin.**
- Key existing code to read before starting: `OPS/DeckBuilder/Models/DeckViewerToolState.swift` (measure state machine — the pattern to mirror), `OPS/DeckBuilder/Models/DeckMeasureReadout.swift` (reducer pattern), `OPS/Views/Components/Project/Tabs/DeckTab2DView.swift` (`recordSelectionTap`, `drawMeasurement`, `snapToGeometry`, `snapAngleToEdges`, `canvasPoint`), `OPS/Views/Components/Project/Tabs/DeckFullscreenViewer.swift` (rail contextual buttons, `measureSheet`, `measurementHint`), `OPS/DeckBuilder/Engine/PolygonMath.swift`, `OPSTests/Views/DeckFullscreenSnapshotTests.swift` (proof harness — `UIHostingController`+`UIWindow`+`drawHierarchy`, NOT ImageRenderer).

---

## Design decisions (locked — do not relitigate)

- **Cut = infinite line** through the two tap points, clipped against the selected surface. Taps may land inside, outside, or straddling the face.
- **Sub-state of select mode**, not a new `Mode` case: `clearTransient()` wipes selection on mode change, and split REQUIRES the selection — so split lives inside `.select` as `isSplitting`. Toggling select off, changing the selection, or tapping the scissors again exits split.
- **Scissors button gate:** exactly one surface selected (`selectedSurfaceIds.count == 1`). Selected edges are irrelevant to the gate.
- **Sides:** side A = points where `cross(B−A, p−A) ≥ 0`, side B = the rest. Sides are identified by fill tint matched to card row chips, not by geometry labels: A = `OPSStyle.Colors.primaryAccent` fill 0.18, B = `OPSStyle.Colors.warningStatus` fill 0.15.
- **Concave faces:** a line can cut an L-shape into 3+ pieces. Sutherland–Hodgman per half-plane returns one polygon (with zero-width bridges); its shoelace area is still the correct per-side total, and the bridges render invisibly in a fill. Report per-SIDE totals — that is the question the user is asking.
- **No-split feedback:** if either clipped side has area < 0.5% of the face, treat as "line misses the face" — no fills, hint shows `DRAW ACROSS THE FACE`.
- **Snapping:** cut points get `snapToGeometry` (vertex/edge); the second point gets `SnapEngine.snapMeasurementEnd` relative to the first (perpendicular cuts across rectilinear decks are the common case). Both already exist — reuse via the view's private adapters.
- **Copy** (in-app restrained register, parity with measure): hints `TAP POINT` → `TAP ACROSS` → `TAP TO RE-CUT` (+ `DRAW ACROSS THE FACE` on miss); card header `SPLIT`, rows `SIDE A` / `SIDE B` (emphasized, tinted) + `CUT` (chord length); `CLEAR` button. A11y: "Split surface", "Clear split".
- **Haptics:** light per placed point, success notification when a valid split computes, light on re-cut reset. No haptic on miss.
- **Third tap re-cuts** (`splitPoints = [newTap]`) — same reset grammar as measure.

## File structure

- Create: `OPS/DeckBuilder/Engine/PolygonSplitter.swift` — pure line/polygon clipping.
- Create: `OPSTests/DeckBuilder/PolygonSplitterTests.swift`
- Create: `OPS/DeckBuilder/Models/DeckSplitReadout.swift` — pure card-row reducer.
- Create: `OPSTests/DeckBuilder/DeckSplitReadoutTests.swift`
- Modify: `OPS/DeckBuilder/Models/DeckViewerToolState.swift` — split sub-state.
- Modify: `OPSTests/DeckBuilder/DeckViewerToolStateTests.swift`
- Modify: `OPS/Views/Components/Project/Tabs/DeckTab2DView.swift` — tap routing + `drawSplit`.
- Modify: `OPS/Views/Components/Project/Tabs/DeckFullscreenViewer.swift` — scissors button, hint, split card.
- Modify: `OPSTests/Views/DeckFullscreenSnapshotTests.swift` — scenario `08-select-split`.

---

### Task 1: PolygonSplitter engine

**Files:**
- Create: `OPS/DeckBuilder/Engine/PolygonSplitter.swift`
- Test: `OPSTests/DeckBuilder/PolygonSplitterTests.swift`

- [x] **Step 1: Write the failing tests**

```swift
// OPS/OPSTests/DeckBuilder/PolygonSplitterTests.swift

import XCTest
@testable import OPS

final class PolygonSplitterTests: XCTestCase {

    private let square: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
    ]

    func testVerticalCut_splitsSquareInHalf() {
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: 50, y: -20), lineB: CGPoint(x: 50, y: 120)
        )
        XCTAssertTrue(r.didSplit)
        XCTAssertEqual(PolygonMath.area(vertices: r.sideA), 5000, accuracy: 1)
        XCTAssertEqual(PolygonMath.area(vertices: r.sideB), 5000, accuracy: 1)
    }

    func testEndpointsInsideFace_lineStillExtends() {
        // Both taps INSIDE the square — the infinite line through them must
        // still cut the full face (Jackson's free-endpoint requirement).
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: 50, y: 40), lineB: CGPoint(x: 50, y: 60)
        )
        XCTAssertTrue(r.didSplit)
        XCTAssertEqual(PolygonMath.area(vertices: r.sideA), 5000, accuracy: 1)
        XCTAssertEqual(PolygonMath.area(vertices: r.sideB), 5000, accuracy: 1)
    }

    func testDiagonalCut_areasConserve() {
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: -10, y: -10), lineB: CGPoint(x: 110, y: 110)
        )
        XCTAssertTrue(r.didSplit)
        let total = PolygonMath.area(vertices: r.sideA) + PolygonMath.area(vertices: r.sideB)
        XCTAssertEqual(total, 10000, accuracy: 1)
        XCTAssertEqual(PolygonMath.area(vertices: r.sideA), 5000, accuracy: 1)
    }

    func testUnevenCut_areasMatchGeometry() {
        // Vertical line at x=25 → 2500 / 7500.
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: 25, y: -5), lineB: CGPoint(x: 25, y: 105)
        )
        let areas = [PolygonMath.area(vertices: r.sideA), PolygonMath.area(vertices: r.sideB)].sorted()
        XCTAssertEqual(areas[0], 2500, accuracy: 1)
        XCTAssertEqual(areas[1], 7500, accuracy: 1)
    }

    func testConcaveL_multiPieceSideTotalsCorrect() {
        // L-shape = 100×100 minus the x∈[50,100], y∈[0,50] quadrant (area 7500).
        // Horizontal line y=75 cuts the L into: below (both legs' lower parts)
        // and above. Below y=75: full-width strip y∈[75,100] is ABOVE... use
        // y-down canvas: region y∈[0,75] of the L = left column x∈[0,50],y∈[0,75]
        // (3750) + right block x∈[50,100],y∈[50,75] (1250) = 5000; remainder 2500.
        let lShape: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0),
            CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 50),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
        ]
        let r = PolygonSplitter.split(
            polygon: lShape,
            lineA: CGPoint(x: -10, y: 75), lineB: CGPoint(x: 110, y: 75)
        )
        XCTAssertTrue(r.didSplit)
        let areas = [PolygonMath.area(vertices: r.sideA), PolygonMath.area(vertices: r.sideB)].sorted()
        XCTAssertEqual(areas[0], 2500, accuracy: 1)
        XCTAssertEqual(areas[1], 5000, accuracy: 1)
    }

    func testLineMissesFace_noSplit() {
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: 200, y: 0), lineB: CGPoint(x: 200, y: 100)
        )
        XCTAssertFalse(r.didSplit)
    }

    func testLineAlongEdge_noSplit() {
        // Colinear with the left edge — one side is the whole face.
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: 0, y: -10), lineB: CGPoint(x: 0, y: 110)
        )
        XCTAssertFalse(r.didSplit)
    }

    func testCoincidentPoints_noSplit() {
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: 50, y: 50), lineB: CGPoint(x: 50, y: 50)
        )
        XCTAssertFalse(r.didSplit)
    }

    func testChord_verticalCutChordSpansFace() {
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: 50, y: -20), lineB: CGPoint(x: 50, y: 120)
        )
        XCTAssertEqual(r.chordSegments.count, 1)
        let seg = r.chordSegments[0]
        XCTAssertEqual(min(seg.start.y, seg.end.y), 0, accuracy: 0.5)
        XCTAssertEqual(max(seg.start.y, seg.end.y), 100, accuracy: 0.5)
        XCTAssertEqual(seg.start.x, 50, accuracy: 0.5)
    }

    func testChord_concaveGivesTwoSegments() {
        // Horizontal line y=25 crosses only the LEFT leg of the L (x∈[0,50])
        // — one chord. Line y=75 crosses the full width — one chord. A line
        // crossing a concave notch gives 2 chords: use a U-shape.
        let uShape: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0),
            CGPoint(x: 30, y: 60), CGPoint(x: 70, y: 60),
            CGPoint(x: 70, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
        ]
        let r = PolygonSplitter.split(
            polygon: uShape,
            lineA: CGPoint(x: -10, y: 30), lineB: CGPoint(x: 110, y: 30)
        )
        XCTAssertTrue(r.didSplit)
        XCTAssertEqual(r.chordSegments.count, 2, "the line crosses both arms of the U")
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test ... -only-testing:OPSTests/PolygonSplitterTests` (full flags from the header). Expected: compile FAILURE — `PolygonSplitter` not defined. That is the red state for a new type.

- [x] **Step 3: Implement PolygonSplitter**

```swift
// OPS/OPS/DeckBuilder/Engine/PolygonSplitter.swift

import Foundation
import SwiftUI

/// Pure geometry: split a simple polygon by the INFINITE line through two
/// points. Used by the fullscreen viewer's look-only split tool — the user
/// draws a rough slash across a selected surface (endpoints anywhere) and
/// reads the area on each side. Sutherland–Hodgman half-plane clipping:
/// concave polygons may split into multiple pieces per side; each side is
/// returned as ONE polygon whose zero-width bridges are invisible in fills
/// and contribute nothing to the shoelace area, so per-side totals stay
/// correct — which is the number the user asked for.
enum PolygonSplitter {

    struct ChordSegment: Equatable {
        let start: CGPoint
        let end: CGPoint
    }

    struct SplitResult: Equatable {
        /// Vertices on the cross(B−A, p−A) ≥ 0 side. Empty when the line misses.
        let sideA: [CGPoint]
        /// Vertices on the other side.
        let sideB: [CGPoint]
        /// Visible cut segments — the line clipped to the polygon interior.
        let chordSegments: [ChordSegment]
        /// True when the line genuinely crosses the face: both sides carry
        /// meaningful area (≥ 0.5% of the whole — degenerate slivers from a
        /// cut along an edge do not count as a split).
        let didSplit: Bool
    }

    /// Signed side of point `p` relative to the directed line a→b.
    private static func side(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        (Double(b.x) - Double(a.x)) * (Double(p.y) - Double(a.y))
      - (Double(b.y) - Double(a.y)) * (Double(p.x) - Double(a.x))
    }

    /// Intersection of segment p→q with the infinite line a→b (call only when
    /// p and q are on strictly opposite sides).
    private static func intersect(_ p: CGPoint, _ q: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let sp = side(p, a, b)
        let sq = side(q, a, b)
        let t = sp / (sp - sq)
        return CGPoint(
            x: p.x + CGFloat(t) * (q.x - p.x),
            y: p.y + CGFloat(t) * (q.y - p.y)
        )
    }

    /// Sutherland–Hodgman: clip `polygon` to one half-plane of line a→b.
    /// `keepPositive` selects the cross ≥ 0 side. On-line vertices (|side| ≤ ε)
    /// are kept by BOTH half-planes so the two outputs share the cut boundary.
    static func clip(polygon: [CGPoint], lineA a: CGPoint, lineB b: CGPoint, keepPositive: Bool) -> [CGPoint] {
        guard polygon.count >= 3 else { return [] }
        let epsilon = 1e-9
        var output: [CGPoint] = []
        let n = polygon.count
        for i in 0..<n {
            let current = polygon[i]
            let next = polygon[(i + 1) % n]
            let sc = side(current, a, b) * (keepPositive ? 1 : -1)
            let sn = side(next, a, b) * (keepPositive ? 1 : -1)
            let currentIn = sc >= -epsilon
            let nextIn = sn >= -epsilon
            if currentIn {
                output.append(current)
                if !nextIn {
                    output.append(intersect(current, next, a, b))
                }
            } else if nextIn {
                output.append(intersect(current, next, a, b))
            }
        }
        return output.count >= 3 ? output : []
    }

    /// Split `polygon` by the infinite line through `lineA`→`lineB`.
    static func split(polygon: [CGPoint], lineA: CGPoint, lineB: CGPoint) -> SplitResult {
        let none = SplitResult(sideA: [], sideB: [], chordSegments: [], didSplit: false)
        guard polygon.count >= 3 else { return none }
        // Coincident definition points define no line.
        guard SnapEngine.distance(lineA, lineB) > 0.5 else { return none }

        let a = clip(polygon: polygon, lineA: lineA, lineB: lineB, keepPositive: true)
        let b = clip(polygon: polygon, lineA: lineA, lineB: lineB, keepPositive: false)

        let total = PolygonMath.area(vertices: polygon)
        let areaA = PolygonMath.area(vertices: a)
        let areaB = PolygonMath.area(vertices: b)
        // Both sides must carry real area — a cut along an edge or a miss
        // leaves one side ~empty and is not a split.
        let minimum = total * 0.005
        guard total > 0, areaA >= minimum, areaB >= minimum else { return none }

        return SplitResult(
            sideA: a,
            sideB: b,
            chordSegments: chords(polygon: polygon, lineA: lineA, lineB: lineB),
            didSplit: true
        )
    }

    /// The visible cut: intersections of the line with the polygon boundary,
    /// sorted along the line direction, paired even–odd into interior segments.
    static func chords(polygon: [CGPoint], lineA a: CGPoint, lineB b: CGPoint) -> [ChordSegment] {
        guard polygon.count >= 3 else { return [] }
        let epsilon = 1e-9
        var hits: [CGPoint] = []
        let n = polygon.count
        for i in 0..<n {
            let p = polygon[i]
            let q = polygon[(i + 1) % n]
            let sp = side(p, a, b)
            let sq = side(q, a, b)
            if (sp > epsilon && sq < -epsilon) || (sp < -epsilon && sq > epsilon) {
                hits.append(intersect(p, q, a, b))
            } else if abs(sp) <= epsilon {
                hits.append(p) // vertex exactly on the line
            }
        }
        guard hits.count >= 2 else { return [] }
        // Sort along the line direction, dedupe near-identical hits (vertex +
        // both touching edges can each report the same point).
        let dx = Double(b.x - a.x)
        let dy = Double(b.y - a.y)
        var sorted = hits.sorted {
            (Double($0.x) * dx + Double($0.y) * dy) < (Double($1.x) * dx + Double($1.y) * dy)
        }
        var deduped: [CGPoint] = []
        for h in sorted {
            if let last = deduped.last, SnapEngine.distance(last, h) < 0.5 { continue }
            deduped.append(h)
        }
        sorted = deduped
        var segments: [ChordSegment] = []
        var i = 0
        while i + 1 < sorted.count {
            let mid = CGPoint(x: (sorted[i].x + sorted[i + 1].x) / 2, y: (sorted[i].y + sorted[i + 1].y) / 2)
            if PolygonMath.pointInPolygon(mid, vertices: polygon) {
                segments.append(ChordSegment(start: sorted[i], end: sorted[i + 1]))
                i += 1
            } else {
                i += 1
            }
        }
        return segments
    }
}
```

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test ... -only-testing:OPSTests/PolygonSplitterTests`. Expected: `** TEST SUCCEEDED **`, 10/10. If `testChord_concaveGivesTwoSegments` fails on count, debug `chords` midpoint-inside filtering before touching anything else.

- [x] **Step 5: Commit**

```bash
git add OPS/DeckBuilder/Engine/PolygonSplitter.swift OPSTests/DeckBuilder/PolygonSplitterTests.swift
git commit -m "feat(deck): concave-safe polygon splitter for the split inspection tool"
```

---

### Task 2: DeckSplitReadout reducer

**Files:**
- Create: `OPS/DeckBuilder/Models/DeckSplitReadout.swift`
- Test: `OPSTests/DeckBuilder/DeckSplitReadoutTests.swift`

- [x] **Step 1: Write the failing tests**

```swift
// OPS/OPSTests/DeckBuilder/DeckSplitReadoutTests.swift

import XCTest
@testable import OPS

final class DeckSplitReadoutTests: XCTestCase {

    private let square: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
    ]

    func testEvenSplit_formatsBothSides() {
        // Scale 2.0 pts/inch → 50"×50" face = 2500 in²; halves = 1250 in² =
        // 8.68 ft² → "8.7 sq ft" each; chord 100 pts = 50" = "4' 2\"".
        let r = DeckSplitReadout.build(
            surface: square,
            cutA: CGPoint(x: 50, y: -10), cutB: CGPoint(x: 50, y: 110),
            scaleFactor: 2.0, system: .imperial
        )
        XCTAssertTrue(r.didSplit)
        XCTAssertEqual(r.sideAText, "8.7 sq ft")
        XCTAssertEqual(r.sideBText, "8.7 sq ft")
        XCTAssertEqual(r.cutLengthText, "4' 2\"")
    }

    func testMiss_reportsNoSplit() {
        let r = DeckSplitReadout.build(
            surface: square,
            cutA: CGPoint(x: 300, y: 0), cutB: CGPoint(x: 300, y: 100),
            scaleFactor: 2.0, system: .imperial
        )
        XCTAssertFalse(r.didSplit)
        XCTAssertNil(r.sideAText)
        XCTAssertNil(r.sideBText)
    }

    func testZeroScale_noSplit() {
        let r = DeckSplitReadout.build(
            surface: square,
            cutA: CGPoint(x: 50, y: -10), cutB: CGPoint(x: 50, y: 110),
            scaleFactor: 0, system: .imperial
        )
        XCTAssertFalse(r.didSplit)
    }

    func testResultCarriesPolygonsForRendering() {
        let r = DeckSplitReadout.build(
            surface: square,
            cutA: CGPoint(x: 50, y: -10), cutB: CGPoint(x: 50, y: 110),
            scaleFactor: 2.0, system: .imperial
        )
        XCTAssertGreaterThanOrEqual(r.sideAPolygon.count, 3)
        XCTAssertGreaterThanOrEqual(r.sideBPolygon.count, 3)
        XCTAssertEqual(r.chordSegments.count, 1)
    }
}
```

- [x] **Step 2: Run to verify compile failure (red)**

Run: `xcodebuild test ... -only-testing:OPSTests/DeckSplitReadoutTests`. Expected: FAIL — `DeckSplitReadout` not defined.

- [x] **Step 3: Implement DeckSplitReadout**

```swift
// OPS/OPS/DeckBuilder/Models/DeckSplitReadout.swift

import SwiftUI

/// Pure reducer: selected surface + two cut points → the split card's rows
/// and the render geometry. Mirrors DeckMeasureReadout / DeckSelectionReadout
/// so the fullscreen viewer renders without owning canvas math.
enum DeckSplitReadout {

    struct Result: Equatable {
        let didSplit: Bool
        /// Formatted per-side areas — nil until a valid split exists.
        let sideAText: String?
        let sideBText: String?
        /// Formatted total chord length (the board line).
        let cutLengthText: String?
        /// Render geometry (canvas space). Empty when no split.
        let sideAPolygon: [CGPoint]
        let sideBPolygon: [CGPoint]
        let chordSegments: [PolygonSplitter.ChordSegment]
    }

    static let empty = Result(
        didSplit: false, sideAText: nil, sideBText: nil, cutLengthText: nil,
        sideAPolygon: [], sideBPolygon: [], chordSegments: []
    )

    static func build(
        surface: [CGPoint],
        cutA: CGPoint,
        cutB: CGPoint,
        scaleFactor: Double,
        system: MeasurementSystem
    ) -> Result {
        guard scaleFactor > 0 else { return empty }
        let split = PolygonSplitter.split(polygon: surface, lineA: cutA, lineB: cutB)
        guard split.didSplit else { return empty }

        let areaA = PolygonMath.realWorldArea(vertices: split.sideA, scaleFactor: scaleFactor)
        let areaB = PolygonMath.realWorldArea(vertices: split.sideB, scaleFactor: scaleFactor)
        let chordInches = split.chordSegments.reduce(0.0) {
            $0 + SnapEngine.distance($1.start, $1.end)
        } / scaleFactor

        return Result(
            didSplit: true,
            sideAText: DimensionEngine.formatArea(areaA, system: system),
            sideBText: DimensionEngine.formatArea(areaB, system: system),
            cutLengthText: DimensionEngine.format(chordInches, system: system),
            sideAPolygon: split.sideA,
            sideBPolygon: split.sideB,
            chordSegments: split.chordSegments
        )
    }
}
```

- [x] **Step 4: Run tests to verify pass**

Run: `xcodebuild test ... -only-testing:OPSTests/DeckSplitReadoutTests`. Expected: `** TEST SUCCEEDED **`, 4/4.

- [x] **Step 5: Commit**

```bash
git add OPS/DeckBuilder/Models/DeckSplitReadout.swift OPSTests/DeckBuilder/DeckSplitReadoutTests.swift
git commit -m "feat(deck): split readout reducer — per-side areas + cut length"
```

---

### Task 3: DeckViewerToolState split sub-state

**Files:**
- Modify: `OPS/DeckBuilder/Models/DeckViewerToolState.swift`
- Test: `OPSTests/DeckBuilder/DeckViewerToolStateTests.swift`

- [x] **Step 1: Write the failing tests** (append inside the existing `DeckViewerToolStateTests` class)

```swift
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
```

- [x] **Step 2: Run to verify red**

Run: `xcodebuild test ... -only-testing:OPSTests/DeckViewerToolStateTests`. Expected: compile FAIL — `toggleSplitting` undefined.

- [x] **Step 3: Implement the sub-state** (inside `DeckViewerToolState`)

Add published state after the selection properties:

```swift
    // MARK: Split (select-mode sub-state, look-only inspection)
    /// True while the scissors tool is armed on the selected surface.
    @Published var isSplitting: Bool = false
    /// The cut line's definition points (0–2, canvas space). The cut is the
    /// INFINITE line through them — endpoints need not touch the surface.
    @Published var splitPoints: [CGPoint] = []
```

Add the affordance + methods after `clearSelection()`:

```swift
    /// Scissors gate: exactly one surface picked — two is ambiguous.
    var canSplit: Bool { isSelecting && selectedSurfaceIds.count == 1 }

    /// Arm/disarm the scissors on the current selection.
    func toggleSplitting() {
        guard canSplit else {
            isSplitting = false
            splitPoints = []
            return
        }
        isSplitting.toggle()
        splitPoints = []
    }

    /// Place a cut point: first tap anchors, second defines the line, a
    /// third starts a fresh cut at the tap. Coincident seconds are ignored —
    /// two identical points define no line.
    func recordSplitTap(_ point: CGPoint) {
        if splitPoints.count >= 2 {
            splitPoints = [point]
            return
        }
        if let last = splitPoints.last, SnapEngine.distance(last, point) < 0.5 {
            return
        }
        splitPoints.append(point)
    }

    /// Card CLEAR — wipe the cut, keep the scissors armed.
    func clearSplit() {
        splitPoints = []
    }

    /// The canvas calls this whenever a selection tap changes the picked
    /// set — a different surface invalidates the cut entirely.
    func selectionDidChange() {
        isSplitting = false
        splitPoints = []
    }
```

Extend `clearTransient()` (add the two lines before the selection resets):

```swift
        isSplitting = false
        splitPoints = []
```

- [x] **Step 4: Run to verify pass**

Run: `xcodebuild test ... -only-testing:OPSTests/DeckViewerToolStateTests`. Expected: `** TEST SUCCEEDED **` (26 existing + 7 new = 33).

- [x] **Step 5: Commit**

```bash
git add OPS/DeckBuilder/Models/DeckViewerToolState.swift OPSTests/DeckBuilder/DeckViewerToolStateTests.swift
git commit -m "feat(deck): split sub-state on the viewer tool state"
```

---

### Task 4: Canvas — tap routing + split rendering

**Files:**
- Modify: `OPS/Views/Components/Project/Tabs/DeckTab2DView.swift`

- [x] **Step 1: Route select-mode taps to the cut while splitting**

In `recordSelectionTap(at:in:)`, add at the very top (before the edge hit-test):

```swift
        // Scissors armed: taps place the cut line instead of changing the
        // selection. Points get the same geometry + angle snapping as the
        // measure tool (perpendicular cuts across rectilinear decks are the
        // common case); the SECOND point snaps relative to the first.
        if toolState.isSplitting {
            let raw = canvasPoint(from: location, viewportSize: viewportSize)
            let snapped = snapToGeometry(raw)
            let point = toolState.splitPoints.count == 1
                ? snapAngleToEdges(from: toolState.splitPoints[0], candidate: snapped)
                : snapped
            toolState.recordSplitTap(point)
            if toolState.splitPoints.count == 2 {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            return
        }
```

NOTE: `recordSelectionTap` currently computes `let p = canvasPoint(...)` below this block — leave that untouched; the split branch returns early. Also: in the surface/edge toggle paths at the bottom of `recordSelectionTap`, add `toolState.selectionDidChange()` immediately after each `selectedEdgeIds`/`selectedSurfaceIds` mutation so changing the pick disarms the scissors.

- [x] **Step 2: Render the split**

In `canvasContent`, after `drawMeasurement(context: context)` add:

```swift
            drawSplit(context: context)
```

Add the renderer after `drawMeasurePill`:

```swift
    /// Render the split inspection: tinted side fills, the cut chord(s), and
    /// the two definition dots. Side tints match the card rows — A accent,
    /// B amber. Drawn last, over the plan and the selection highlight.
    private func drawSplit(context: GraphicsContext) {
        guard showsTools, toolState.isSplitting else { return }
        let points = toolState.splitPoints
        guard !points.isEmpty else { return }
        let accentA = OPSStyle.Colors.primaryAccent
        let accentB = OPSStyle.Colors.warningStatus

        // Definition dots (always visible so the first tap reads immediately).
        let dotR: CGFloat = 6
        for p in points {
            let circle = Path(ellipseIn: CGRect(x: p.x - dotR, y: p.y - dotR, width: dotR * 2, height: dotR * 2))
            context.fill(circle, with: .color(Color.white.opacity(0.25)))
            context.stroke(circle, with: .color(Color.white), lineWidth: 2)
        }
        guard points.count == 2, let surface = selectedSplitSurface() else { return }

        let readout = DeckSplitReadout.build(
            surface: surface,
            cutA: points[0], cutB: points[1],
            scaleFactor: drawingData.effectiveScaleFactor,
            system: drawingData.config.measurementSystem
        )
        guard readout.didSplit else { return }

        var fillA = Path()
        if let first = readout.sideAPolygon.first {
            fillA.move(to: first)
            for p in readout.sideAPolygon.dropFirst() { fillA.addLine(to: p) }
            fillA.closeSubpath()
            context.fill(fillA, with: .color(accentA.opacity(0.18)))
        }
        var fillB = Path()
        if let first = readout.sideBPolygon.first {
            fillB.move(to: first)
            for p in readout.sideBPolygon.dropFirst() { fillB.addLine(to: p) }
            fillB.closeSubpath()
            context.fill(fillB, with: .color(accentB.opacity(0.15)))
        }
        for segment in readout.chordSegments {
            var chord = Path()
            chord.move(to: segment.start)
            chord.addLine(to: segment.end)
            context.stroke(chord, with: .color(Color.white), lineWidth: 2.5)
        }
    }

    /// Positions of the single selected surface (the scissors gate guarantees
    /// exactly one) — nil when the selection changed out from under the tool.
    private func selectedSplitSurface() -> [CGPoint]? {
        guard let id = toolState.selectedSurfaceIds.first,
              toolState.selectedSurfaceIds.count == 1 else { return nil }
        return DeckSelectionReadout.surfaceContexts(in: drawingData)
            .first(where: { $0.face.id == id })?
            .face.positions
    }
```

- [x] **Step 3: Build for testing to verify compilation**

Run: `xcodebuild build-for-testing -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .ddata`. Expected: `** TEST BUILD SUCCEEDED **` (grep the log).

- [x] **Step 4: Commit**

```bash
git add OPS/Views/Components/Project/Tabs/DeckTab2DView.swift
git commit -m "feat(deck): split tap routing + side-fill/chord rendering in the 2D canvas"
```

---

### Task 5: Fullscreen chrome — scissors button, hint, split card

**Files:**
- Modify: `OPS/Views/Components/Project/Tabs/DeckFullscreenViewer.swift`

- [x] **Step 1: Scissors contextual button**

In the chrome's trailing `VStack` (where measure's undo/finish buttons live), add a select-mode block after the measure block:

```swift
                        if toolState.isSelecting, toolState.canSplit {
                            toolButton(
                                icon: "scissors",
                                isActive: toolState.isSplitting,
                                activeColor: OPSStyle.Colors.primaryAccent,
                                label: toolState.isSplitting ? "Stop splitting" : "Split surface"
                            ) {
                                toolState.toggleSplitting()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            .transition(.opacity)
                        }
```

Extend the container's animation values so the button animates in (add below the two existing `.animation` modifiers):

```swift
                .animation(reduceMotion ? nil : OPSStyle.Animation.fast, value: toolState.canSplit)
                .animation(reduceMotion ? nil : OPSStyle.Animation.fast, value: toolState.isSplitting)
                .animation(reduceMotion ? nil : OPSStyle.Animation.fast, value: toolState.splitPoints.count)
```

- [x] **Step 2: Hint copy**

Replace `measurementHint` with a combined hint (keep the property name — it feeds the same pill):

```swift
    /// Live instruction for the active tool. Split hints take over while the
    /// scissors are armed; measure hints otherwise. Each state teaches only
    /// the newly unlocked, non-obvious action.
    private var measurementHint: String? {
        if toolState.isSplitting {
            switch toolState.splitPoints.count {
            case 0: return "TAP POINT"
            case 1: return "TAP ACROSS"
            default: return splitReadout.didSplit ? "TAP TO RE-CUT" : "DRAW ACROSS THE FACE"
            }
        }
        guard toolState.isMeasuring else { return nil }
        switch toolState.measurementPhase {
        case .finished, .closed:
            return "TAP TO RESET"
        case .drawing:
            switch toolState.measurementPoints.count {
            case 0: return "TAP POINT"
            case 1: return "TAP NEXT"
            case 2: return "TAP LAST TO FINISH"
            default: return "TAP FIRST TO CLOSE"
            }
        }
    }
```

- [x] **Step 3: Split readout + card**

Add next to `measureSheet`:

```swift
    /// Split readout — recomputed on every cut change. Empty until two points.
    private var splitReadout: DeckSplitReadout.Result {
        guard toolState.isSplitting, toolState.splitPoints.count == 2,
              let id = toolState.selectedSurfaceIds.first,
              toolState.selectedSurfaceIds.count == 1,
              let surface = DeckSelectionReadout.surfaceContexts(in: drawingData)
                  .first(where: { $0.face.id == id })?.face.positions
        else { return DeckSplitReadout.empty }
        return DeckSplitReadout.build(
            surface: surface,
            cutA: toolState.splitPoints[0], cutB: toolState.splitPoints[1],
            scaleFactor: drawingData.effectiveScaleFactor,
            system: drawingData.config.measurementSystem
        )
    }

    /// Split card — the peek-sheet pattern with side rows tinted to match
    /// the canvas fills (A accent, B amber).
    private var splitSheet: some View {
        let readout = splitReadout
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("SPLIT")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer(minLength: 12)
                Button {
                    toolState.clearSplit()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text("CLEAR")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .accessibilityLabel("Clear split")
            }
            if let a = readout.sideAText {
                selectionRow("SIDE A", a.uppercased(), emphasized: true, accent: OPSStyle.Colors.primaryAccent)
            }
            if let b = readout.sideBText {
                selectionRow("SIDE B", b.uppercased(), emphasized: true, accent: OPSStyle.Colors.warningStatus)
            }
            if let cut = readout.cutLengthText {
                selectionRow("CUT", cut)
            }
        }
        .padding(10)
        .frame(maxWidth: 260, alignment: .leading)
        .background(Color.black.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(6)
    }
```

- [x] **Step 4: Card slot routing**

In the bottom-left readout slot, show the split card INSTEAD of the selection peek sheet while a valid cut exists (the selection readout is stale context once the user is cutting). Replace the slot's condition chain with:

```swift
                    if toolState.isSplitting, splitReadout.didSplit {
                        splitSheet
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if toolState.isSelecting, toolState.hasSelection {
                        peekSheet
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if toolState.isMeasuring, showsMeasureCard {
                        measureSheet
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
```

- [x] **Step 5: Build for testing to verify compilation**

Run: `xcodebuild build-for-testing ...` (flags as Task 4). Expected: succeeds.

- [x] **Step 6: Commit**

```bash
git add OPS/Views/Components/Project/Tabs/DeckFullscreenViewer.swift
git commit -m "feat(deck): scissors rail button, split hints, and split readout card"
```

---

### Task 6: Snapshot proof + full verification

**Files:**
- Modify: `OPSTests/Views/DeckFullscreenSnapshotTests.swift`

- [x] **Step 1: Add the split scenario** (after scenario 7 in `testRenderFullscreenChrome`)

```swift
        // 8. Split armed on the footprint surface with a valid diagonal-ish
        //    cut — tinted halves, white chord, SIDE A/B card, scissors active.
        let splitData = Self.centeredSingleLevel()
        let splitting = DeckViewerToolState()
        splitting.toggleSelect()
        if let face = splitData.detectedSurfaces.first {
            splitting.selectedSurfaceIds = [face.id]
        }
        splitting.toggleSplitting()
        splitting.recordSplitTap(CGPoint(x: 196, y: 250))
        splitting.recordSplitTap(CGPoint(x: 196, y: 470))
        snapshot("08-select-split", toolState: splitting,
                 drawingData: splitData, title: "MERIDIAN DECK")
```

NOTE: if `detectedSurfaces` is empty on the fixture (no closed-face detection for the hand-built data), fall back to selecting via `DeckSelectionReadout.surfaceContexts(in: splitData).first?.face.id`; if still empty, the fixture's footprint isn't detected — check how `DeckTab2DView` resolves `drawingData.detectedSurfaces` for the single-level path and mirror it. Do not fake the id.

- [x] **Step 2: Run the full affected suite**

Run: `xcodebuild test ... -only-testing:OPSTests/PolygonSplitterTests -only-testing:OPSTests/DeckSplitReadoutTests -only-testing:OPSTests/DeckViewerToolStateTests -only-testing:OPSTests/DeckMeasureReadoutTests -only-testing:OPSTests/SnapEngineTests -only-testing:OPSTests/PolygonMathTests -only-testing:OPSTests/DeckFullscreenSnapshotTests`. Expected: `** TEST SUCCEEDED **`, zero failures.

- [x] **Step 3: Extract + eyeball the snapshot**

```bash
XCR=$(grep -oE "/[^ ]*\.xcresult" <test-log> | head -1)
xcrun xcresulttool export attachments --path "$XCR" --output-path <scratch-dir>
```
Rename via `manifest.json` `suggestedHumanReadableName`, view `08-select-split`. Verify: two tint fills split at the chord, white cut line spanning the face, SIDE A / SIDE B card with plausible sq-ft values summing to the top-bar area, scissors button in active state, hint absent (cut complete → `TAP TO RE-CUT`). Fix anything off before proceeding.

- [x] **Step 4: Device-target build verification**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .ddata build`. Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 5: Commit + land**

```bash
git add OPSTests/Views/DeckFullscreenSnapshotTests.swift
git commit -m "test(deck): split-tool snapshot scenario"
# Land per protocol: merge main into the branch if it advanced, then
git -C <primary-ops-ios> merge --ff-only <branch>
# Do NOT push. Report with the exported PNG.
```

- [x] **Step 6: Update memory**

Update `~/.claude/projects/-Users-jacksonsweet-Projects-OPS-ops-ios/memory/deck-fullscreen-measure-tools.md`: Task 4 shipped (hashes), device QA pending. Update the MEMORY.md index line to match.

---

## Self-review notes

- Spec coverage: infinite-line semantics (Task 1 `testEndpointsInsideFace...`), free endpoints (same), concave totals (L + U tests), miss/colinear/coincident degenerates, gate = exactly one surface, look-only (no model/sync files touched anywhere), OPSStyle-only styling, reduce-motion via existing pattern, haptics per doctrine, 44pt rail button via `toolButton`.
- Type consistency: `PolygonSplitter.ChordSegment`/`SplitResult`, `DeckSplitReadout.Result.{didSplit,sideAText,sideBText,cutLengthText,sideAPolygon,sideBPolygon,chordSegments}`, tool-state API `{isSplitting,splitPoints,canSplit,toggleSplitting(),recordSplitTap(_:),clearSplit(),selectionDidChange()}` — used identically across Tasks 3–6.
- Known judgment call left to the executor: if `selectionDidChange()` firing on every toggle feels wrong on device (e.g. deselect+reselect the same face), keep the simple behavior — correctness first, the reselect cost is one scissors tap.
