# Deleted Task Type Selection Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Keep soft-deleted task types available for historical task display and sync while excluding them from every user-facing task-type filter, picker, reassignment list, and suggestion surface.

**Architecture:** Preserve `DataController.getAllTaskTypes(for:)` as the complete local cache because existing tasks retain their task-type references after deletion. Add one pure `TaskTypeSelectionPolicy` that defines which rows may be offered as a new choice, then route each affected selection surface through that policy. Do not alter historical lookups, repository fetches, layout, copy, motion, or design tokens.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` and `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`

**Required Skills:** `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `custom-skills:ops-design`, `custom-skills:mobile-ux-design`, `custom-skills:interface-design`, `custom-skills:audit-design-system`, `superpowers:verification-before-completion`

---

### Task 1: Prove the selection boundary

**Skills:** `superpowers:test-driven-development`, `superpowers:systematic-debugging`

**Files:**
- Modify: `OPSTests/Views/JobBoard/JobBoardListBehaviorTests.swift`
- Create: `OPS/Utilities/TaskTypeSelectionPolicy.swift`

**Design tokens:** None. This is behavior-only.

1. Add a focused failing test showing that selectable task types preserve active same-company rows while excluding soft-deleted and other-company rows.
2. Run only the focused Job Board behavior test selector and confirm it fails for the missing policy.
3. Implement the smallest pure policy that makes the test pass without changing the complete-cache fetch path.

### Task 2: Route every affected choice surface through the policy

**Skills:** `custom-skills:ops-design`, `custom-skills:mobile-ux-design`, `custom-skills:interface-design`

**Files:**
- Modify only confirmed affected task-type option producers under `OPS/Views/`, `OPS/Styles/Components/`, and `OPS/Utilities/`

**Design tokens:** Existing `OPSStyle` tokens remain unchanged; no new values.

1. Update Job Board task filters first.
2. Update calendar/project/photo filters, task creation/editing menus, shared project task composer suggestions, and task-type deletion reassignment choices where the audit proves they consume tombstones.
3. Keep raw task-type collections for historical names, colors, and retained references.
4. Do not modify debug-only lists or non-selection display lookups.

### Task 3: Verify behavior and design-system integrity

**Skills:** `custom-skills:audit-design-system`, `superpowers:verification-before-completion`

**Files:**
- Modify: `docs/plans/2026-07-24-deleted-task-type-selection.md` only if the audited file list changes materially
- Modify: relevant OPS Software Bible section describing task-type lifecycle/selection behavior

**Design tokens:** Confirm changed UI files introduce zero hardcoded color, spacing, radius, or font values.

1. Audit all task-type option producers with `rg` and confirm each uses the shared policy or an equivalent SwiftData predicate that excludes `deletedAt`.
2. Run `git diff --check`.
3. Run one final focused Job Board behavior test selector; do not run a broad build or full suite.
4. Commit atomically, fast-forward local `main` only if its known state is unchanged, then update the exact Supabase bug row with the verified commit and manual-review request.
