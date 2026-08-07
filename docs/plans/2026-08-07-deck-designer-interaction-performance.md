# Deck Designer Interaction Performance Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Make the embedded OPS iOS Deck Designer responsive during drawing and selection manipulation without changing drawing, snapping, persistence, undo, 2D, or 3D behavior.

**Architecture:** Cache exact derived geometry by ordered vertex/edge inputs, keep in-flight vertex positions in a frame-coalesced overlay, commit geometry and dimensions in one indexed pass, defer persistence until after the gesture transaction while retaining exit/background flushes, and replace 3D JSON comparison with an explicit drawing revision.

**Tech Stack:** Swift, SwiftUI Canvas, SwiftData, SceneKit, XCTest.

**Design System:** N/A — no visual, layout, token, copy, or motion change.

**Required Skills:** `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `custom-skills:executing-plans`, `superpowers:verification-before-completion`, `superpowers:finishing-a-development-branch`.

---

### Task 1: Lock the deterministic performance contracts

**Skills:** `superpowers:test-driven-development`

**Files:**
- Create: `OPSTests/DeckBuilder/DeckDesignerPerformanceTests.swift`
- Create: `OPS/DeckBuilder/Models/DeckPerformanceCore.swift`
- Create: `OPS/DeckBuilder/Models/DeckGeometrySnapshot.swift`

1. Write tests for a 29-vertex/29-edge ring proving repeated snapshot reads produce one surface-detection miss.
2. Write a heavier multi-level test proving unchanged reads produce one miss per level and a changed level invalidates only its own exact context cache.
3. Write a generic one-pass geometry-mutation test proving 29 moved vertices visit 29 edges once, with scale dimensions recalculated and operator-entered dimensions preserved/staled exactly.
4. Write a frame batcher test proving a burst schedules once and publishes only its latest payload.
5. Write a 3D revision-gate test proving equal revisions are ignored.
6. Establish RED without an extra Xcode build by compiling the pure core test harness against the production core file; the missing APIs must fail. The final combined Xcode run will compile and execute the app-integrated tests.

### Task 2: Cache exact derived geometry

**Skills:** `superpowers:test-driven-development`

**Files:**
- Modify: `OPS/DeckBuilder/Models/DeckGeometry.swift`
- Modify: `OPS/DeckBuilder/Models/DeckLevel.swift`
- Modify: `OPS/DeckBuilder/Models/DeckSelectionReadout.swift`
- Modify: `OPS/DeckBuilder/DeckBuilderViewModel.swift`

1. Add the exact geometry key and reference cache in `DeckPerformanceCore.swift`.
2. Add immutable context/drawing snapshots with id indexes, surfaces, ordered positions, closed state, and canvas-space totals.
3. Store runtime-only caches on `DeckDrawingData` and `DeckLevel`; keep Codable payloads and equality semantics unchanged.
4. Route surface, topology, lookup, whole-area, whole-perimeter, and selection-readout hot paths through snapshots.
5. Run the standalone pure core checks and `swiftc -parse` for every changed Swift file.

### Task 3: Move direct manipulation onto the live overlay

**Skills:** `superpowers:test-driven-development`

**Files:**
- Modify: `OPS/DeckBuilder/DeckBuilderViewModel.swift`
- Modify: `OPS/DeckBuilder/Views/DeckCanvasView.swift`
- Modify: `OPSTests/DeckBuilder/DeckBuilderRegressionTests.swift`
- Modify: `OPSTests/DeckBuilder/DeckDesignerPerformanceTests.swift`

1. Add a small published live-geometry overlay and pure frame batcher.
2. Snapshot indexed active geometry once when a vertex or selection move begins.
3. Resolve snap candidates against that stable snapshot and submit only overlay positions/guides during updates.
4. Render active fills, edges, vertices, labels, selection chrome, and workspace extents through overlay-resolved positions.
5. On lift, synchronously consume the latest staged value, apply positions and dimension rules in one pass, publish the committed drawing once, and clear the overlay.
6. Preserve vertex merge, selection stickiness, haptics, undo, snapping, and existing regression contracts.

### Task 4: Remove serialization and persistence from the gesture transaction

**Skills:** `superpowers:test-driven-development`

**Files:**
- Modify: `OPS/DataModels/DeckDesign.swift`
- Modify: `OPS/DeckBuilder/DeckBuilderViewModel.swift`
- Modify: `OPSTests/DeckBuilder/DeckDesignerPerformanceTests.swift`
- Modify: `OPSTests/DataModels/DeckDesignDrawingDataCacheTests.swift`

1. Mark drawing revisions dirty at the committed drawing boundary.
2. Schedule the geometry save for the next main-actor turn instead of calling `save()` inside finger lift.
3. Keep `flushPendingSave()` and `flushBeforeExit()` synchronous so close/background remains crash-safe.
4. Reconcile once, encode once, seed the DeckDesign decode cache with the pre-encoded value, and pass the same JSON into sync-queue construction.
5. Prove the JSON is unchanged immediately after the move, pending durability is visible, and explicit flush persists the exact final drawing.

### Task 5: Make 3D rebuilds revision-aware

**Skills:** `superpowers:test-driven-development`

**Files:**
- Modify: `OPS/DeckBuilder/3D/DeckScene3DView.swift`
- Modify: `OPS/DeckBuilder/Views/DeckBuilderView.swift`
- Modify: `OPSTests/DeckBuilder/DeckDesignerPerformanceTests.swift`

1. Replace controller JSON state with the pure revision gate.
2. Pass the builder's committed drawing revision into `DeckScene3DView`.
3. Rebuild only on a new revision and keep the current camera-control, lighting, anti-aliasing, and frame-rate behavior.
4. Confirm there is no `toJSON()` call in the 3D update path.

### Task 6: Verify, document, and commit

**Skills:** `superpowers:verification-before-completion`, `superpowers:finishing-a-development-branch`

**Files:**
- Modify: `../ops-software-bible/07_SPECIALIZED_FEATURES.md`
- Modify: `../ops-software-bible/03_DATA_ARCHITECTURE.md`

1. Update the Bible with the snapshot/overlay/revision boundary and the deferred-but-flushable persistence contract.
2. Run pure core checks, `swiftc -parse`, `git diff --check`, and focused source/static checks.
3. Copy `Secrets.xcconfig`, verify no competing Xcode process owns the chosen DerivedData, then run at most one combined focused Xcode test/build verification using `.spm-local` and worktree-local DerivedData.
4. Inspect the complete diff and commit coherent implementation/tests separately from the Bible update. Do not push, merge, install, deploy, release, or mutate production data.
