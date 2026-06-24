# Deck Designer Drop 1 — 3D Fixes & Render Reliability — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the project-details Deck 3D viewer look right and render reliably — remove shadows, fix level-connection stairs ignoring the flip toggle, fade the info badges during pan/zoom, make "won't render" shapes close reliably with an actionable message, and show the project name instead of a separate deck title.

**Architecture:** All five items are surface-level fixes over the existing 2D-canvas → `DeckDrawingData` (JSON blob) → `DeckSceneBuilder` (SceneKit) pipeline. No schema change, no migration, no estimate-adapter contract change. Work happens in the existing worktree `.worktrees/ios-deck-designer` on branch `feat/ios-deck-designer`.

**Tech Stack:** Swift, SwiftUI, SceneKit, SwiftData, XCTest. iOS tokens via `OPSStyle`. Snap/geometry via `SnapEngine`/`SurfaceDetector`. Tests in `OPSTests/DeckBuilder/`.

---

## Pre-flight (read once before starting)

- **Worktree is already created.** Work in `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/ios-deck-designer` (branch `feat/ios-deck-designer`). `Secrets.xcconfig` is already copied in. Do NOT switch the root tree's branch.
- **Spec:** `docs/superpowers/specs/2026-06-23-deck-designer-overhaul-design.md` (§5 = this drop, §8 = spin-off modularity constraint: do not deepen `DeckBuilder/` coupling to `Project`/`companyId`; pass primitives at the boundary).
- **Device build (verification of record):**
  ```bash
  WT=/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/ios-deck-designer
  ps aux | grep -i "[x]codebuild" || true   # ensure no sibling build is running
  xcodebuild -scheme OPS -destination 'generic/platform=iOS' \
    -derivedDataPath "$WT/.build-dd" build 2>&1 | tail -40
  ```
  A background `xcodebuild`'s shell exit code is the trailing pipe, not the build — confirm by grepping the log for `BUILD SUCCEEDED` / `BUILD FAILED`.
- **Tests (compile + run):**
  ```bash
  xcodebuild test -scheme OPS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
    -derivedDataPath "$WT/.build-dd" \
    -only-testing:OPSTests/StairConfigCodableTests 2>&1 | tail -40
  ```
- **Commits:** atomic, one per task, conventional style (`fix(deck): …`), staged by name. No AI attribution. Commit on `feat/ios-deck-designer`.
- **Skills to invoke mid-plan:** `animation-studio:animation-architect` → `animation-studio:ios-animations` before Task 4 (badge fade). `ops-copywriter` before writing any user-facing string in Task 5. `superpowers:systematic-debugging` at the start of Task 5's investigation.

---

## Task 1: Remove shadows

**Files:**
- Modify: `OPS/DeckBuilder/3D/DeckSceneBuilder.swift:1286-1289` (inside `addLighting(to:)`)

- [ ] **Step 1: Remove shadow casting from the directional light**

Replace lines 1286–1289:
```swift
        directionalLight.castsShadow = true
        directionalLight.shadowMode = .deferred
        directionalLight.shadowRadius = 3
        directionalLight.shadowMapSize = CGSize(width: 1024, height: 1024)
```
with:
```swift
        // Shadows intentionally disabled. This is schematic CAD, not photoreal —
        // cast shadows muddied structural member reads (posts, joists, stringers)
        // and added nothing to comprehension. Deck Drop 1.
        directionalLight.castsShadow = false
```

- [ ] **Step 2: Confirm no other shadow casters/receivers exist**

Run: `grep -n "castsShadow\|shadowMode\|shadowColor\|categoryBitMask" OPS/DeckBuilder/3D/DeckSceneBuilder.swift OPS/DeckBuilder/3D/DeckMeshGenerator.swift`
Expected: the only `castsShadow` line is the one you just set to `false`. If `addGroundPlane` sets any shadow material, leave the geometry but ensure nothing re-enables shadows.

- [ ] **Step 3: Build for device to verify it compiles**

Run the device build command from Pre-flight.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add OPS/DeckBuilder/3D/DeckSceneBuilder.swift
git commit -m "fix(deck): remove cast shadows from 3D viewer for clean schematic reads"
```

---

## Task 2: Level-connection stairs honor flip direction

**Root cause:** `buildStairs` (per-edge) correctly inverts the outward perpendicular on `stairConfig.flipDirection` (`DeckSceneBuilder.swift:883-884`), and the 2D planner is already tested for this (`DeckStairRenderPlannerTests.testPlanHonorsAlignmentOffsetAndFlipDirection`). But `buildLevelConnection` hardcodes the perpendicular (`DeckSceneBuilder.swift:1111-1112`) with no flip check, so stairs between deck levels always render on the default side.

**Files:**
- Create: `OPSTests/DeckBuilder/StairConfigCodableTests.swift`
- Modify: `OPS/DeckBuilder/3D/DeckSceneBuilder.swift:1111-1112`
- Reference (read for fixture pattern): `OPSTests/DeckBuilder/MultiLevelTests.swift`

- [ ] **Step 1: Write the Codable round-trip regression test**

Create `OPSTests/DeckBuilder/StairConfigCodableTests.swift`:
```swift
//
//  StairConfigCodableTests.swift
//  OPSTests
//
//  Locks the flipDirection round-trip so a future key rename or decoder
//  change can't silently swallow the stair-swap toggle (it decodes via
//  decodeLegacyBoolIfPresent, which defaults to false on any miss).
//

import XCTest
@testable import OPS

final class StairConfigCodableTests: XCTestCase {

    func testFlipDirectionSurvivesRoundTrip() throws {
        let original = StairConfig(width: 48, flipDirection: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StairConfig.self, from: data)
        XCTAssertTrue(decoded.flipDirection,
                      "flipDirection must survive an encode/decode round-trip")
    }

    func testFlipDirectionDefaultsFalseForLegacyJSON() throws {
        let legacy = Data(#"{"width":48}"#.utf8)
        let decoded = try JSONDecoder().decode(StairConfig.self, from: legacy)
        XCTAssertFalse(decoded.flipDirection,
                       "legacy JSON without flipDirection must default to false")
    }
}
```

- [ ] **Step 2: Run the Codable test — expect PASS (regression lock)**

Run: `xcodebuild test ... -only-testing:OPSTests/StairConfigCodableTests` (full command in Pre-flight).
Expected: both pass. (This characterizes/locks the already-correct data round-trip — it is NOT the bug. The bug is in the renderer, fixed next.)

- [ ] **Step 3: Write the scene-graph flip regression test (drives the fix — expect FAIL first)**

Add `OPSTests/DeckBuilder/LevelConnectionStairFlipTests.swift` (the multi-level fixture is provided in full at the bottom of this code block):
```swift
import CoreGraphics
import SceneKit
import XCTest
@testable import OPS

final class LevelConnectionStairFlipTests: XCTestCase {

    /// Build a two-level design with a connecting stair, once with
    /// flipDirection=false and once true, and assert the stair tread cluster
    /// lands on OPPOSITE sides of the connection edge. Before the fix the two
    /// are identical (the level-connection path ignored the toggle).
    func testLevelConnectionStairsHonorFlipDirection() throws {
        // Build `data` mirroring MultiLevelTests' multi-level fixture, with a
        // single levelConnection between the two levels. Capture the connection id.
        let (dataDefault, connectionId) = makeTwoLevelConnectedDesign(flip: false)
        let (dataFlipped, _) = makeTwoLevelConnectedDesign(flip: true)

        let centroidDefault = try connectionStairCentroid(
            in: DeckSceneBuilder.buildScene(from: dataDefault), connectionId: connectionId)
        let centroidFlipped = try connectionStairCentroid(
            in: DeckSceneBuilder.buildScene(from: dataFlipped), connectionId: connectionId)

        // The two centroids must straddle the connection edge — i.e. their
        // perpendicular offsets have opposite sign. A simple, robust proxy:
        // they must not be (near-)equal.
        let dx = Double(centroidDefault.x - centroidFlipped.x)
        let dz = Double(centroidDefault.z - centroidFlipped.z)
        let separation = (dx * dx + dz * dz).squareRoot()
        XCTAssertGreaterThan(separation, 0.3,
            "flipDirection must move the connecting stairs to the opposite side")
    }

    /// Average world position of the descendant geometry nodes under the
    /// `levelConnection_<id>` group.
    private func connectionStairCentroid(in scene: SCNScene, connectionId: String) throws -> SCNVector3 {
        let node = try XCTUnwrap(
            scene.rootNode.childNode(withName: "levelConnection_\(connectionId)", recursively: true),
            "level-connection node not found")
        var sum = SCNVector3Zero
        var count: Float = 0
        node.enumerateChildNodes { child, _ in
            guard child.geometry != nil else { return }
            let w = child.worldPosition
            sum = SCNVector3(sum.x + w.x, sum.y + w.y, sum.z + w.z)
            count += 1
        }
        XCTAssertGreaterThan(count, 0, "no stair geometry under the connection node")
        return SCNVector3(sum.x / count, sum.y / count, sum.z / count)
    }

    // MARK: - Fixture
    // Two closed 100×100 rects, upper at +3 ft, joined by one LevelConnection
    // on the upper rect's y=0 edge. Verify field names against DeckLevel.swift
    // and DeckGeometry.swift if the compiler disagrees (DeckLevel/DeckVertex/
    // DeckEdge construction mirrors MultiLevelTests.swift).
    private func makeTwoLevelConnectedDesign(flip: Bool) -> (DeckDrawingData, String) {
        var upper = DeckLevel(name: "Upper")
        upper.elevation = 3.0
        upper.vertices = [
            DeckVertex(id: "u1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "u2", position: CGPoint(x: 100, y: 0)),
            DeckVertex(id: "u3", position: CGPoint(x: 100, y: 100)),
            DeckVertex(id: "u4", position: CGPoint(x: 0, y: 100)),
        ]
        upper.edges = [
            DeckEdge(id: "ue1", startVertexId: "u1", endVertexId: "u2"),
            DeckEdge(id: "ue2", startVertexId: "u2", endVertexId: "u3"),
            DeckEdge(id: "ue3", startVertexId: "u3", endVertexId: "u4"),
            DeckEdge(id: "ue4", startVertexId: "u4", endVertexId: "u1"),
        ]

        var lower = DeckLevel(name: "Lower")
        lower.elevation = 0.0
        lower.vertices = [
            DeckVertex(id: "l1", position: CGPoint(x: 0, y: 100)),
            DeckVertex(id: "l2", position: CGPoint(x: 100, y: 100)),
            DeckVertex(id: "l3", position: CGPoint(x: 100, y: 200)),
            DeckVertex(id: "l4", position: CGPoint(x: 0, y: 200)),
        ]
        lower.edges = [
            DeckEdge(id: "le1", startVertexId: "l1", endVertexId: "l2"),
            DeckEdge(id: "le2", startVertexId: "l2", endVertexId: "l3"),
            DeckEdge(id: "le3", startVertexId: "l3", endVertexId: "l4"),
            DeckEdge(id: "le4", startVertexId: "l4", endVertexId: "l1"),
        ]

        let connection = LevelConnection(
            id: "conn1",
            upperLevelId: upper.id,
            lowerLevelId: lower.id,
            upperEdgeId: "ue1",                              // upper rect's y=0 edge
            stairConfig: StairConfig(width: 48, flipDirection: flip)
        )

        var data = DeckDrawingData()
        data.levels = [upper, lower]
        data.levelConnections = [connection]
        data.scaleFactor = 1.0                              // calibrated → buildScene uses it directly
        return (data, connection.id)
    }
}
```

- [ ] **Step 4: Run the scene-graph test — expect FAIL**

Run: `xcodebuild test ... -only-testing:OPSTests/LevelConnectionStairFlipTests`.
Expected: FAIL — separation ≈ 0 because the level-connection path ignores `flipDirection`.

- [ ] **Step 5: Fix the level-connection perpendicular**

In `OPS/DeckBuilder/3D/DeckSceneBuilder.swift`, replace lines 1111–1112:
```swift
        let nx = -edgeDz / edgeLen
        let nz = edgeDx / edgeLen
```
with:
```swift
        // Honor the stair flip toggle here too. The per-edge buildStairs path
        // (see ~line 883) inverts BOTH perpendicular components on
        // flipDirection; this connection path previously hardcoded the default
        // side, so multi-level connecting stairs ignored the swap. Mirror it.
        let rawN = (x: -edgeDz / edgeLen, z: edgeDx / edgeLen)
        let nx = connection.stairConfig.flipDirection ? -rawN.x : rawN.x
        let nz = connection.stairConfig.flipDirection ? -rawN.z : rawN.z
```

- [ ] **Step 6: Run the scene-graph test — expect PASS**

Run: `xcodebuild test ... -only-testing:OPSTests/LevelConnectionStairFlipTests`.
Expected: PASS.

- [ ] **Step 7: Device build verify**

Run the device build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add OPS/DeckBuilder/3D/DeckSceneBuilder.swift \
        OPSTests/DeckBuilder/StairConfigCodableTests.swift \
        OPSTests/DeckBuilder/LevelConnectionStairFlipTests.swift
git commit -m "fix(deck): honor stair flipDirection on level-connection stairs in 3D"
```

- [ ] **Step 9: Visual QA (post-merge, needs running app)**

The report was "often backwards" — confirm by eye, not code alone: in the builder, toggle stair flip on (a) a single perimeter edge and (b) a level-connection stair; verify both land on the opposite side and the 2D and 3D agree. If the single-edge case is ALSO wrong (it should be correct), open a follow-up — but do not block this commit, which fixes the confirmed connection-path bug.

---

## Task 3: Deck name → project name

**Decision:** the deck's display name mirrors the parent project name. The standalone editable title is retired from the UI; the stored `DeckDesign.title` column is kept (no migration). `Project.title` is the project's name (`OPS/DataModels/Project.swift:15`). To respect the spin-off modularity constraint, the builder receives the name as a `String?` boundary value — it does NOT import/hold a `Project`.

**Files:**
- Modify: `OPS/Views/Components/Project/Tabs/DeckTabView.swift:117` (project-tab badge)
- Modify: `OPS/DeckBuilder/Views/DeckBuilderView.swift` (add `projectName` param + `inlineTitleEditor` 580-619)
- Modify call sites: `OPS/Views/Components/Project/ProjectDetailsView.swift:849`, `OPS/Views/JobBoard/ProjectFormSheet.swift:878`

- [ ] **Step 1: Project-tab badge shows the project name**

In `DeckTabView.swift`, `DeckTabView` already holds `let project: Project` (line 18). In `floatingDesignInfo(design:)` change line 117:
```swift
            titlePill(design.title)
```
to:
```swift
            titlePill(project.title)
```

- [ ] **Step 2: Add a `projectName` boundary param to the builder**

In `DeckBuilderView.swift`, add a stored property near `let projectId: String?` (line 25):
```swift
    let projectId: String?
    let companyId: String
    /// The parent project's display name, passed at the boundary so the
    /// builder shows it WITHOUT importing/holding a `Project` (keeps the
    /// DeckBuilder core extraction-ready for the standalone spin-off). nil in
    /// the future standalone context, where the editable title returns.
    var projectName: String? = nil
```
Confirm the `init` (line 52) either threads `projectName` through or relies on the memberwise default; if `init` is custom and sets these explicitly, add a `projectName: String? = nil` parameter and assign it.

- [ ] **Step 3: Render the project name read-only in the title bar**

In `DeckBuilderView.swift`, replace the `inlineTitleEditor` body (580-619) so that when `projectName` is non-nil it renders read-only (no edit affordance), and falls back to the existing editable flow only when `projectName == nil`:
```swift
    @ViewBuilder
    private var inlineTitleEditor: some View {
        if let projectName, !projectName.isEmpty {
            // Name mirrors the project — read-only, no edit affordance.
            Text(projectName)
                .font(OPSStyle.Typography.bodyEmphasis)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if viewModel.isEditingTitle {
            // ... existing edit-state HStack unchanged ...
        } else {
            // ... existing read-state Button unchanged ...
        }
    }
```
Keep the existing `isEditingTitle` and read-state branches exactly as-is below the new `if let projectName` branch (they serve the standalone/no-project case).

- [ ] **Step 4: Pass the project name at both call sites**

In `ProjectDetailsView.swift:849` and `ProjectFormSheet.swift:878`, add `projectName:` to the `DeckBuilderView(...)` call using the project in scope, e.g.:
```swift
                DeckBuilderView(
                    // ... existing args ...
                    projectName: project.title
                )
```
Use whatever the in-scope project variable is named at each site (read 20 lines above each call to confirm).

- [ ] **Step 5: Device build verify**

Run the device build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add OPS/Views/Components/Project/Tabs/DeckTabView.swift \
        OPS/DeckBuilder/Views/DeckBuilderView.swift \
        OPS/Views/Components/Project/ProjectDetailsView.swift \
        OPS/Views/JobBoard/ProjectFormSheet.swift
git commit -m "fix(deck): show project name as the deck title, retire editable title in-project"
```

---

## Task 4: Fade info badges during pan/zoom

**Current:** the badges are a SwiftUI overlay in `DeckTabView.floatingDesignInfo` (line 96-101, 114-190), `.allowsHitTesting(false)`. The project-tab 3D view is the private `DeckTab3DSceneView` inside `DeckTab3DView.swift` (`allowsCameraControl = true`, no exposed interaction state). We add gesture recognizers (coexisting with SceneKit's camera control) and surface an interaction flag up to `DeckTabView` to drive opacity.

- [ ] **Step 1: Invoke animation skills**

Invoke `animation-studio:animation-architect`, then `animation-studio:ios-animations`. Constraints from OPSStyle: single easing curve (`OPSStyle.Animation.standard`/`.fast`, which encode `cubic-bezier(0.22,1,0.36,1)`), no spring/bounce, honor reduce-motion.

**Files:**
- Modify: `OPS/Views/Components/Project/Tabs/DeckTab3DView.swift`
- Modify: `OPS/Views/Components/Project/Tabs/DeckTabView.swift`

- [ ] **Step 2: Surface interaction state from the 3D scene view**

In `DeckTab3DView.swift`, add an interaction callback to both the public view and the private representable, plus a coordinator with pan + pinch recognizers:
```swift
struct DeckTab3DView: View {
    let drawingData: DeckDrawingData
    var onInteractingChange: (Bool) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            if geo.size.height > 0 {
                DeckTab3DSceneView(drawingData: drawingData,
                                   onInteractingChange: onInteractingChange)
                    .transition(.opacity)
            }
        }
    }
}

private struct DeckTab3DSceneView: UIViewRepresentable {
    let drawingData: DeckDrawingData
    var onInteractingChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onInteractingChange: onInteractingChange) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onInteractingChange: (Bool) -> Void
        private var endWork: DispatchWorkItem?
        init(onInteractingChange: @escaping (Bool) -> Void) {
            self.onInteractingChange = onInteractingChange
        }
        @objc func handle(_ gr: UIGestureRecognizer) {
            switch gr.state {
            case .began, .changed:
                endWork?.cancel()
                onInteractingChange(true)
            case .ended, .cancelled, .failed:
                let work = DispatchWorkItem { [weak self] in self?.onInteractingChange(false) }
                endWork = work
                // Trailing debounce so badges don't flicker between the pan and
                // pinch phases of a two-finger move.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            default: break
            }
        }
        // Coexist with SceneKit's built-in camera-control recognizers.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = UIColor(red: 10/255, green: 10/255, blue: 10/255, alpha: 1)
        scnView.preferredFramesPerSecond = 60

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handle(_:)))
        pan.delegate = context.coordinator
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handle(_:)))
        pinch.delegate = context.coordinator
        scnView.addGestureRecognizer(pan)
        scnView.addGestureRecognizer(pinch)

        let scene = buildScene()
        scnView.scene = scene
        if let cam = scene.rootNode.childNode(withName: "camera", recursively: true) {
            scnView.pointOfView = cam
        }
        return scnView
    }
    // updateUIView and buildScene() unchanged.
}
```

- [ ] **Step 3: Drive badge opacity from `DeckTabView`**

In `DeckTabView.swift`: add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` and `@State private var is3DInteracting = false` near the other `@State` (line 26-27). In the `.threeD` case (line 83) pass the callback:
```swift
                    if design.drawingData.hasAnyClosedSurface {
                        DeckTab3DView(drawingData: design.drawingData,
                                      onInteractingChange: { is3DInteracting = $0 })
                    } else {
                        incompleteDesignMessage
                    }
```
On the `floatingDesignInfo` overlay (line 96-101), add opacity + animation:
```swift
            .overlay(alignment: .topLeading) {
                floatingDesignInfo(design: design)
                    .padding(.leading, OPSStyle.Layout.spacing2_5)
                    .padding(.top, OPSStyle.Layout.spacing2_5)
                    .allowsHitTesting(false)
                    .opacity(is3DInteracting && viewMode == .threeD ? 0 : 1)
                    .animation(reduceMotion ? nil : OPSStyle.Animation.standard,
                               value: is3DInteracting)
            }
```
Reset on mode switch so the badges can't get stuck hidden: in the existing `.onChange(of: viewMode)` (control bar, line 221) add `is3DInteracting = false`.

- [ ] **Step 4: Device build verify**

Run the device build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Visual QA (post-merge, needs running app)**

In the project Deck tab (3D), pan and pinch: badges fade out during the gesture and return ~0.25s after release. Camera still pans/zooms normally (recognizers coexist). With Reduce Motion ON, badges stay visible (no fade).

- [ ] **Step 6: Commit**

```bash
git add OPS/Views/Components/Project/Tabs/DeckTab3DView.swift \
        OPS/Views/Components/Project/Tabs/DeckTabView.swift
git commit -m "feat(deck): fade 3D info badges while panning/zooming the viewer"
```

---

## Task 5: Render reliability — make "won't render" shapes close

**Current reality (corrected):** the 3D tab is NOT silently empty — `DeckTabView` gates on `hasAnyClosedSurface` and otherwise shows `incompleteDesignMessage` (line 82-86, 298-314). The real problem: shapes the user *believes* are closed read as open (so the message shows), and the message is generic. `isClosed` (`DeckGeometry.swift:790-826`) needs every vertex to have exactly 2 neighbors. Magnetic snap-to-vertex already exists (`SnapEngine.findSnapTarget`, used at `DeckBuilderViewModel.swift:855, 950, 1397` with `config.endpointSnapRadius`) — so the failure is in the *closing* path, not a missing snap.

This task has an **investigation** half (why the loop doesn't close) and a **deterministic** half (actionable message). Do the investigation with `superpowers:systematic-debugging`.

**Files:**
- Investigate/Modify: `OPS/DeckBuilder/DeckBuilderViewModel.swift` (draw-commit/snap: ~840-960 and merge ~1390-1410)
- Modify: `OPS/DeckBuilder/Models/DeckGeometry.swift` (add an open-endpoint helper)
- Modify: `OPS/Views/Components/Project/Tabs/DeckTabView.swift:298-314` (message copy)

- [ ] **Step 1: Invoke systematic-debugging and reproduce**

Invoke `superpowers:systematic-debugging`. Write a failing test or a scripted repro that constructs a perimeter where the final edge ends NEAR (within a few points of, but not exactly on) the start vertex — the realistic "looks closed but isn't" case — and assert `drawingData.isClosed == false` today. Read `DeckBuilderViewModel.swift:840-960` (drawing commit + `findSnapTarget`) and `1390-1410` (drag merge) to see exactly how the closing endpoint is resolved.

- [ ] **Step 2: Identify the gap (record the finding)**

Determine which is true (the fix in Step 3 follows from this):
  - (a) the closing endpoint's `findSnapTarget` excludes the start vertex (e.g. via `excludeVertexIds`) so it never reuses it → loop left open with a near-duplicate vertex; or
  - (b) `endpointSnapRadius` is too small for the closing gesture; or
  - (c) the snapped id is found but the committed edge still uses a freshly-created vertex id.
Write the conclusion as a comment in the test from Step 1.

- [ ] **Step 3: Fix the closing path so the loop actually closes**

Implement the fix indicated by Step 2 (most likely: when the drawing's final endpoint snaps to the start vertex, reuse that vertex id for the edge's end so the perimeter closes; do not create a coincident vertex). Keep `isClosed`/`SurfaceDetector` untouched — only ensure the closing edge reuses the existing vertex. Re-run the Step 1 repro: `isClosed` is now `true`.

- [ ] **Step 4: Add an open-endpoint count helper**

In `DeckGeometry.swift` add to `DeckDrawingData`:
```swift
    /// Count of vertices whose edge-degree ≠ 2 — i.e. loose/open ends that
    /// keep the perimeter from forming a closed face. 0 ⇒ topologically closed.
    var openEndpointCount: Int {
        guard !vertices.isEmpty else { return 0 }
        var degree: [String: Int] = [:]
        for edge in edges {
            degree[edge.startVertexId, default: 0] += 1
            degree[edge.endVertexId, default: 0] += 1
        }
        return vertices.reduce(0) { $0 + ((degree[$1.id] ?? 0) == 2 ? 0 : 1) }
    }
```

- [ ] **Step 5: Make the incomplete message actionable (ops-copywriter)**

Invoke `ops-copywriter`. Rewrite `incompleteDesignMessage` (`DeckTabView.swift:298-314`) to name the problem and point to the fix, using `design.drawingData.openEndpointCount` when > 0. OPS voice: terse, tactical, no emoji, no exclamation. Use OPSStyle tokens only. The headline must read like a plan-check, not a vague error (e.g. it states how many ends are open and that connecting them in 2D unlocks the 3D model). Confirm the copy with the skill; do not hand-write final strings.

- [ ] **Step 6: Build + run the repro test**

Run the device build; run the Step 1 test (now expecting `isClosed == true` / closed). Both green.

- [ ] **Step 7: Visual QA (post-merge, needs running app)**

Draw a perimeter and close it near the start vertex — it now snaps closed and the 3D model renders. Draw a deliberately open shape — the message names the open-end count and directs to 2D.

- [ ] **Step 8: Commit**

```bash
git add OPS/DeckBuilder/DeckBuilderViewModel.swift \
        OPS/DeckBuilder/Models/DeckGeometry.swift \
        OPS/Views/Components/Project/Tabs/DeckTabView.swift \
        OPSTests/DeckBuilder/<repro test file you added>
git commit -m "fix(deck): close perimeters reliably and explain unclosed shapes in 3D tab"
```

---

## Done criteria for Drop 1

- [ ] All five tasks committed atomically on `feat/ios-deck-designer`.
- [ ] `xcodebuild ... build` (device) succeeds; the new tests pass.
- [ ] Visual QA items (2.9, 4.5, 5.7) confirmed on a running app (Jackson or computer-use) before any PR/merge — these are the parts code can't self-verify.
- [ ] No change to `DeckDesign` schema, the JSON blob shape, or the estimate-adapter contract.
- [ ] Root tree untouched; sibling WIP intact.
```
