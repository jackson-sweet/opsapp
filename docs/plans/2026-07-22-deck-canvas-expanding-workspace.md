# Deck Canvas Expanding Workspace Implementation Plan

> **For implementation:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` task by task.

**Goal:** Make Deck Designer's workspace boundary unmistakable and automatically expand it around real or previewed geometry without changing saved coordinates.

**Architecture:** Add one pure `DeckCanvasWorkspace` value that owns initial bounds, non-shrinking quantized expansion, coordinate conversion, visible-world calculation, and recoverable pan limits. `DeckCanvasView` keeps that value as session state and uses it for input, grid culling, rendering, centering, pinch pan, and edge auto-pan.

**Tech Stack:** Swift 6, SwiftUI `Canvas`, UIKit pinch gestures, XCTest.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` and `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`; implementation tokens live in `OPS/Styles/OPSStyle.swift`.

**Required Skills:** `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `custom-skills:mobile-ux-design`, `custom-skills:interface-design`, `custom-skills:ops-design`, `custom-skills:ui-ux-pro-max`, `custom-skills:audit-design-system`, `superpowers:verification-before-completion`, `superpowers:finishing-a-development-branch`.

---

### Task 1: Prove the workspace policy in isolation

**Skills:** `superpowers:test-driven-development`

**Files:**

- Create: `OPSTests/DeckBuilder/DeckCanvasWorkspaceTests.swift`
- Create after the red run: `OPS/DeckBuilder/Models/DeckCanvasWorkspace.swift`

**Steps:**

1. Add failing tests for the exact initial `4800 × 4800` bounds.
2. Add failing tests for left/top and right/bottom expansion with a safety margin and growth quantum.
3. Add a failing test proving repeated updates never shrink established bounds.
4. Add failing tests for negative coordinates and non-finite point rejection.
5. Add failing tests for reversible screen/world conversion and visible-world bounds.
6. Add failing tests proving pan limits retain 44 screen points at zoom `0.15` and `8.0`, and center a workspace that fits inside the viewport.
7. Run only `DeckCanvasWorkspaceTests` and confirm failure because `DeckCanvasWorkspace` does not exist.
8. Implement the smallest pure model that satisfies the tests.
9. Re-run `DeckCanvasWorkspaceTests` and require a clean pass.

### Task 2: Route every canvas concern through the workspace

**Skills:** `custom-skills:mobile-ux-design`, `custom-skills:interface-design`, `custom-skills:ops-design`

**Files:**

- Modify: `OPS/DeckBuilder/Views/DeckCanvasView.swift`
- Test: `OPSTests/DeckBuilder/DeckCanvasWorkspaceTests.swift`

**Design tokens:** `OPSStyle.Colors.background`, `OPSStyle.Colors.surfaceInput`, `OPSStyle.Colors.inputFieldBorderFocus`, `OPSStyle.Layout.Border.thick`, `OPSStyle.Layout.touchTargetMin`.

**Steps:**

1. Replace the private fixed canvas-size constant with `@State` workspace state.
2. Build one content-point envelope from committed vertices, the active line, typed perimeter preview, and pending paste preview.
3. Initialize and expand the state from that envelope without ever shrinking it.
4. Draw the workspace fill before the grid and the compensated hairline after canvas content.
5. Make grid culling use dynamic bounds, the actual viewport size, and negative grid indices.
6. Replace clamped finger conversion with the workspace's unbounded screen-to-world conversion.
7. Apply the workspace pan constraint to edge auto-pan, UIKit pinch pan, programmatic centering, and viewport-size changes.
8. Correct dimension-label viewport culling so negative world coordinates remain visible.
9. Re-run the focused workspace and existing perimeter/selection regression tests.

### Task 3: Update the system record

**Skills:** `custom-skills:ops-design`

**Files:**

- Modify: `../ops-software-bible/07_SPECIALIZED_FEATURES.md`

**Steps:**

1. Document the expanding workspace, visible boundary, non-persisted bounds, and recoverable pan invariant in the Deck Builder section.
2. Confirm the documentation does not imply a schema or payload change.

### Task 4: Audit and verify the complete fix

**Skills:** `custom-skills:audit-design-system`, `superpowers:verification-before-completion`

**Files:**

- Audit: `OPS/DeckBuilder/Models/DeckCanvasWorkspace.swift`
- Audit: `OPS/DeckBuilder/Views/DeckCanvasView.swift`

**Steps:**

1. Scan new code for hardcoded visual values; require every new colour, width, and touch-size reference to resolve through `OPSStyle` tokens.
2. Run the focused workspace tests.
3. Run the adjacent perimeter-entry and DeckBuilder regression tests.
4. Run the full DeckBuilder test group.
5. Build the generic iOS destination with worktree-local package and DerivedData paths.
6. Request an independent code review and resolve every material finding.
7. Commit the implementation atomically.

### Task 5: Close the live bug and integrate locally

**Skills:** `supabase:supabase`, `superpowers:finishing-a-development-branch`

**Files:**

- No additional source files.

**Steps:**

1. Read the exact implementation commit with `git rev-parse HEAD`.
2. Update bug `f5f81410-f287-4be5-b7fa-a1b5f9d0981e` to `resolved` with exact verification notes and commit hash.
3. Read the live row back and verify status, timestamps, notes, and hash.
4. Merge the branch into local `main` without touching unrelated primary-checkout work.
5. Verify the merge ancestry and local-main status.
6. Stop and give Jackson one concise manual verification path. Do not push.
