# Project Task Duplicate Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to
> implement this plan. Keep verification to the focused test target; do not run
> a broad app build.

**Goal:** Add a safe, immediate `Duplicate Task` action to the Project Details
task-row long-press menu.

**Architecture:** A pure duplication factory converts a `ProjectTask` into the
complete create DTO, making copied and reset fields explicit and testable.
`ProjectDetailsViewModel` owns the mutation, while `DetailsTabView` only exposes
the permission-gated menu action. The existing queued `DataController` create
path remains the persistence boundary and is completed so dependency overrides
and creation metadata survive outbound sync.

**Tech stack:** SwiftUI, SwiftData, XCTest, OPS offline-first SyncEngine.

---

### Task 1: Lock the duplication contract with focused tests

**Files:**

- Create: `OPSTests/ProjectTaskDuplicationTests.swift`
- Create: `OPS/Utilities/ProjectTaskDuplication.swift`

1. Add failing tests for copied task-definition fields and reset operational
   fields.
2. Add failing tests for explicit empty dependency overrides and corrupt
   override data.
3. Add a failing test for the full `tasks.create` permission gate.
4. Run only `ProjectTaskDuplicationTests` and confirm the expected missing
   production symbol failure.

### Task 2: Implement the safe duplication payload

**Files:**

- Create: `OPS/Utilities/ProjectTaskDuplication.swift`
- Modify: `OPS/Network/Supabase/DTOs/CoreEntityConverters.swift`
- Modify: `OPS/Utilities/DataController.swift`

1. Build a fresh lowercase UUID and creation timestamp.
2. Copy the approved definition fields and reset schedule, status, source, and
   lineage fields.
3. Preserve explicit dependency overrides, including `[]`; reject malformed
   stored JSON.
4. Ensure the DTO-to-model and queued create payload keep dependency overrides
   and creation metadata.

### Task 3: Wire the existing long-press menu

**Files:**

- Modify: `OPS/Views/Components/Project/Tabs/DetailsTabView.swift`
- Modify: `OPS/Views/Components/Project/ProjectDetailsView.swift`
- Modify: `OPS/Views/Components/Project/ProjectDetailsViewModel.swift`
- Modify: `OPS/Styles/Components/Feedback.swift`

1. Add a `canDuplicateTask` gate based on full `tasks.create` permission and
   mention-only access.
2. Add `Duplicate Task` with `doc.on.doc` to the existing context menu.
3. Create and queue the duplicate, hydrate its local relationships, select it,
   fire success haptic, and present `// TASK DUPLICATED`.
4. Route failures through the existing OPS error-toast surface.

### Task 4: Verify and document

**Files:**

- Modify: `../ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md`

1. Run the single focused test target and confirm green.
2. Audit changed UI for hardcoded visual values and design-system drift.
3. Document the Project Details duplicate contract in the Software Bible.
4. Commit atomically, land onto local iOS `main`, update the exact live bug row,
   and stop for Jackson's manual review.
