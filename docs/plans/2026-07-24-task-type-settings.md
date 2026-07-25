# Task Type Settings Implementation Plan

> Execute with `custom-skills:executing-plans`. Apply `superpowers:test-driven-development` and `superpowers:verification-before-completion`.

**Goal:** Replace the inefficient Task Types administration UI and add invariant-safe selective reassignment.

**Required skills:** `supabase:supabase`, `custom-skills:ops-design`, `custom-skills:mobile-ux-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `custom-skills:wireframe`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`

## 1. Lock the reassignment contract with failing tests

Files:

- Create `OPSTests/Settings/TaskTypeManagementTests.swift`
- Modify `OPSTests/Settings/TaskTypeSettingsLogicTests.swift`

Cover:

- selected tasks update relationship, scalar id, color, `needsSync`, and queued payload;
- unrelated, deleted, wrong-company, and stale-source tasks do not mutate;
- invalid source/target combinations fail before mutation;
- a batch records exactly one durable mutation command;
- merge records one command and updates relationship, scalar id, and color;
- merge deletion is blocked while any non-deleted task retains the source scalar id;
- index presentation exposes default rows and places the add row last.

Run the focused tests and confirm they fail for missing behavior before production edits.

## 2. Add one canonical bulk reassignment path

Files:

- Create `OPS/Network/Sync/TaskTypeMutationSync.swift`
- Create `OPS/Utilities/TaskTypeManagement.swift`
- Modify `OPS/Network/Sync/OutboundProcessor.swift`
- Modify `OPS/Network/Sync/SyncEngine.swift`
- Modify `OPS/Utilities/DataActor.swift`
- Modify `OPS/Utilities/DataController.swift`
- Modify `OPS/Views/Settings/TaskTypeMergeSheet.swift`

Implement a main-actor batch API that:

- validates source, target, company, and exact current membership;
- mutates all three local assignment fields;
- saves the local projection and one durable command in the same transaction;
- routes selective reassignment and whole-type merge to idempotent RPCs;
- permits one explicit background drain after the caller completes;
- refuses task-type deletion while a live scalar reference remains.

The RPC transaction revalidates permissions and membership, updates task id/color together, and reconciles reminders. Whole merge moves every server-side mutable reference before deleting the source; it never depends on the phone having a complete cache.

Run the focused data tests green.

## 3. Install database guarantees

Files in the isolated OPS Web worktree:

- Create one timestamped Supabase migration
- Create `tests/unit/supabase/task-type-reassignment-merge-migration.test.ts`

Add the selective reassignment RPC, whole-type merge RPC, idempotency receipts, assignment/deletion guards, reminder reconciliation, and supporting partial indexes. Mirror live RLS permissions and leave the discovered legacy broken rows untouched. Apply through Supabase only after static review, then run transactional live probes and security/performance advisors.

## 4. Build the compact Task Types index

Files:

- Modify `OPS/Views/Settings/Components/SettingsComponents.swift`
- Modify `OPS/Views/Settings/TaskSettingsView.swift`
- Modify `OPS/Views/Settings/TaskTypeSettingsLogic.swift`

Add a tokenized header trailing-action API. Replace per-row cards and the footer with one grouped L1 surface, 56pt rows, inset separators, compact color markers, counts, and a terminal add row. Make default rows navigable while retaining destructive-action protection. Preserve an explicit fetch-error state.

Add or update presentation-logic tests.

## 5. Make create/edit progressive and expose usage

Files:

- Modify `OPS/Views/JobBoard/TaskTypeSheet.swift`
- Create `OPS/Views/Settings/TaskTypeUsageSheet.swift`

Remove the oversized preview. Add a compact color selector sheet with 44pt swatches. Start advanced sections collapsed. Add the edit-only usage summary and the dedicated selection/reassignment manager. Keep default identity read-only while allowing usage management.

Use only OPS tokens and current SF Symbols through `OPSStyle.Icons` where available. Add no motion.

## 6. Keep the Software Bible current

Files:

- Update the relevant TaskType/ProjectTask contract in `../ops-software-bible/03_DATA_ARCHITECTURE.md`
- Update RPC behavior in `../ops-software-bible/04_API_AND_INTEGRATION.md`
- Update task-type management behavior in `../ops-software-bible/02_USER_EXPERIENCE_AND_DESIGN.md` where routed

Document the three-field invariant, offline batch queue behavior, protected default types, and usage-management surface. Preserve unrelated Bible work.

## 7. Verify and land

Run:

```bash
ps aux | rg '[x]codebuild'
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/ops-task-types-p1-tests -only-testing:OPSTests/TaskTypeManagementTests -only-testing:OPSTests/TaskTypeSettingsLogicTests
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/ops-task-types-p1-tests -only-testing:OPSTests/TaskTypeSettingsSnapshotTests
xcodebuild build -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/ops-task-types-p1-build CODE_SIGNING_ALLOWED=NO
```

Then:

- inspect 390×844 visual artifacts;
- run the OPS design-system audit over every changed UI file;
- inspect git diff and status;
- commit app and Bible changes atomically in their respective repositories;
- update only bug `9a00f447-c555-41f0-ae35-b9b5469d704b` with exact commit and verification evidence;
- do not push;
- stop for Jackson’s manual verification.
