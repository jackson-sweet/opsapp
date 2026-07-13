# Shared Project Task Composer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Replace the constrained inline task row in Project Form and Projects Needing Tasks with one shared composer that supports one-tap suggestions and persistent editable task rows.

**Architecture:** Keep `LocalTask` as the shared draft representation. Build `ProjectTaskComposer` in the already-compiled `InlineTaskRow.swift` source so no Xcode project-file mutation is needed, and inject async save/delete adapters for local staging versus immediate persistence. Extend `TaskSuggestionEngine` with a project-independent exclusion input so new-project forms can use company-history suggestions.

**Tech Stack:** SwiftUI, SwiftData, existing DataController task APIs, XCTest.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md`, `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`, and `OPS/Styles/OPSStyle.swift`.

**Required Skills:** `custom-skills:ops-design`, `custom-skills:mobile-ux-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `ops-copywriter:ops-copywriter`, `superpowers:test-driven-development`, `custom-skills:audit-design-system`, `superpowers:verification-before-completion`.

---

### Task 1: Lock Composer State Behavior

**Skills:** Test-driven development.

**Files:**
- Create: `OPSTests/Views/JobBoard/ProjectTaskComposerLogicTests.swift`
- Modify: `OPS/Styles/Components/InlineTaskRow.swift`

**Design tokens:** None; pure state behavior.

1. Write failing tests proving a suggested task becomes a committed `LocalTask`, saving an edited task replaces the matching row without reordering, and deleting removes only the selected row.
2. Run the focused test target and confirm failure because composer logic does not exist.
3. Add the smallest pure `ProjectTaskComposerLogic` implementation.
4. Re-run the focused tests and confirm they pass.

### Task 2: Build The Shared Composer

**Skills:** OPS design, mobile UX, interface design, UI/UX Pro Max, OPS copywriter.

**Files:**
- Modify: `OPS/Styles/Components/InlineTaskRow.swift`
- Modify: `OPS/Utilities/TaskSuggestionEngine.swift`
- Test: `OPSTests/Views/JobBoard/ProjectTaskComposerLogicTests.swift`

**Design tokens:** `OPSStyle.Colors` semantic surface/text/status tokens; `OPSStyle.Layout` spacing, touch target, radius, border, and icon tokens; `OPSStyle.Typography` roles.

1. Add project-independent suggestion exclusions while preserving the existing Project Details API.
2. Replace the constrained row presentation with shared suggestion cards, persistent task summaries, and a stacked inline editor.
3. Keep picker and scheduler presentation inside the composer so both consumers behave identically.
4. Add accessibility labels for icon-only controls and maintain 44pt minimum targets.
5. Re-run focused tests.

### Task 3: Adopt Composer In Project Form

**Skills:** Mobile UX, interface design, OPS copywriter.

**Files:**
- Modify: `OPS/Views/JobBoard/ProjectFormSheet.swift`

**Design tokens:** Shared component tokens only; no new screen styling.

1. Replace the per-row UI and add-row button with `ProjectTaskComposer`.
2. Preserve tutorial add-task routing and full-editor behavior.
3. Keep local task mutations staged for the existing project save reconciliation path.
4. Remove obsolete row picker/scheduler state and helpers.

### Task 4: Adopt Composer In Projects Needing Tasks

**Skills:** Mobile UX, interface design, OPS copywriter.

**Files:**
- Modify: `OPS/Views/Review/ProjectsWithoutTasksReviewView.swift`

**Design tokens:** Existing project card L1 surface plus shared composer L2 surfaces.

1. Replace the single disposable draft with a bound persistent task list.
2. Implement create, edit, and delete adapters using existing DataController APIs.
3. Keep added tasks visible and the project card expanded after every mutation.
4. Keep `DONE` as the explicit action that removes a now-complete project from the review list.

### Task 5: Documentation And Verification

**Skills:** Audit design system, verification before completion.

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/07_SPECIALIZED_FEATURES.md`

**Design tokens:** Audit all touched SwiftUI against `OPSStyle`.

1. Update the Quick Add Task Suggestions documentation with the shared composer behavior.
2. Run focused tests, `git diff --check`, and the hardcoded-token scan.
3. Run a generic iOS device build with isolated DerivedData and worktree-local Swift packages.
4. Commit the implementation atomically and integrate it without touching unrelated dirty files.
