# Deck Label Commit Boundary Implementation Plan

> **For Codex:** Execute this plan in the isolated `fix/project-label-notifications-p1-1` worktree. Keep verification to one focused red test run and one focused green test run.

**Goal:** Stop surface and edge label fields from treating every keystroke as a completed edit.

**Architecture:** Give each label field a local edit session and an immutable geometry target (edge/surface IDs plus originating level). Text changes update draft state only. Return, focus loss, target change, or sheet dismissal asks the session for an idempotent normalized commit to that exact target; only a changed final value reaches `DeckBuilderViewModel`. Add view-model no-op guards as a second boundary so duplicate lifecycle callbacks cannot create undo, save, sync, or toast work.

**Tech Stack:** SwiftUI, XCTest, existing `DeckBuilderViewModel`, existing OPS iOS design tokens.

---

### Task 1: Pin the interaction contract with regression tests

**Files:**
- Modify: `OPSTests/DeckBuilder/DeckBuilderRegressionTests.swift`

Add tests proving:

- successive draft changes emit no commit;
- one explicit commit emits the final normalized label once;
- a repeated commit is a no-op;
- whitespace commits clear an existing label;
- unchanged edge, surface, and footprint mutations do not create undo state.
- a draft captured on level A still commits to level A after selection and active level move to B.

Run the focused test target once and confirm it fails because the new edit-session contract does not exist yet.

### Task 2: Move label typing behind one commit boundary

**Files:**
- Modify: `OPS/DeckBuilder/Views/PropertySheetView.swift`
- Modify: `OPS/DeckBuilder/DeckBuilderViewModel.swift`

Add an internal, testable label edit session and a reusable SwiftUI field that:

- owns the draft while typing;
- commits on keyboard Done, focus loss, and disappearance;
- treats duplicate commit callbacks as no-ops;
- preserves all existing visual modifiers and OPS tokens.

Use the field for both edge and surface labels. Add equality guards to all three label mutators before undo, save, sync, haptic, or toast work begins.

### Task 3: Verify, document, and integrate

**Files:**
- Modify: `ops-software-bible/07_SPECIALIZED_FEATURES.md`

Run the focused tests once after implementation. Audit the changed UI diff for hardcoded styling or visual drift. Document the draft/commit contract in the Deck Builder selection-editing section, commit atomically, fast-forward local `main` only if its head is unchanged, and update only bug report `f8b539f6-5c96-4ed2-83c2-ab3a42ac73ba` with the exact commit and manual-review instructions.
