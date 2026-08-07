# Deck Fullscreen Decode Watchdog Repair Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Stop the 2D deck pull-to-fullscreen gesture from watchdog-killing OPS while preserving the current gesture, drawing, sync, and display-candidate behavior.

**Architecture:** Cache the decoded `DeckDrawingData` beside each `DeckDesign` as transient, in-memory state. Key the cache by the exact persisted JSON string so normal model writes and direct server-sync replacements both invalidate automatically. The SwiftData model remains the source of truth; no database, wire-contract, gesture, or visual change is involved.

**Tech Stack:** Swift 6, SwiftData, XCTest, Xcode 26.5.

---

### Task 1: Lock the regression into a test

**Files:**
- Create: `OPSTests/DataModels/DeckDesignDrawingDataCacheTests.swift`

1. Add a test proving two reads of identical JSON invoke the decoder once.
2. Add a test proving replacement JSON invokes the decoder again.
3. Add a model-level test proving a direct `drawingDataJSON` replacement returns the new geometry rather than stale cached geometry.
4. Run only this test class and confirm it fails because the cache behavior does not exist yet.

### Task 2: Add exact-source decode caching

**Files:**
- Modify: `OPS/DataModels/DeckDesign.swift`

1. Add a small reference cache that retains the last JSON string and decoded value.
2. Store that cache in a SwiftData `@Transient` property so it is never persisted or synced.
3. Route `drawingData` reads through the cache and seed the cache from `drawingData` writes.
4. Read `drawingData` once per `hasRenderableGeometry` evaluation.
5. Rerun the regression test and confirm it passes.

### Task 3: Verify the complete deck path

**Files:**
- Verify only; no expected source changes.

1. Run the focused deck design, opportunity, fullscreen snapshot, and cache tests.
2. Run the full `OPSTests` suite on the iPhone 17 simulator.
3. Run a generic iOS device build using isolated DerivedData and the worktree-local Swift package checkout.
4. Confirm the exact current 1121 Oscar drawing still decodes as 29 vertices and 29 edges using the production decoder.
5. Commit the plan, implementation, and tests atomically; do not push or install over the customer/device build without explicit authorization.
