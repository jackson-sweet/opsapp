# Review snapshot runtime repair

Baseline: main `6f485f7289695ced487cead1aebb7e0aab290d7f`. Runtime checkout: `.worktrees/ios-performance-p1-2-runtime`. Implement with `custom-skills:executing-plans`. Parent owns builds, tests, integration, and device proof; this task has no build baton.

## Intended behavior

All passive review counts come from one cached, immutable, Sendable snapshot computed on the configured background DataActor. Review entry still loads model rows explicitly. Existing eligibility, completed-work unlock thresholds, reminder thresholds, and three rail reports including zero remain intact. No review table fetch occurs in a view body or passive main-thread refresh.

## Ownership and seams

- Add `OPS/Utilities/ReviewSnapshot.swift`: immutable scope/request/count values and shared pure eligibility predicates. Identity includes container, user, company, effective permissions, local calendar day/time zone, company thresholds, and unlock thresholds.
- Add `OPS/Utilities/DataActor+ReviewSnapshot.swift`: fetch scoped live tasks/projects once on the actor-owned context and return scalar values only. Await P1-4's `@MainActor DataController.readyDataActor() async -> DataActor?`; never construct another actor/context. Capture and recheck scope before/after both awaits.
- Add `OPS/Utilities/ReviewSnapshotStore.swift`: main-actor cache, injectable async reader, a coalesced refresh coordinator, stale-result rejection, and explicit unavailable/loading state. Account/container/scope replacement immediately retires old values. Relevant task/project changes invalidate; unrelated visit/queue changes do not.
- Update `ReviewThresholdService.swift`, `MainTabView.swift`, and `AppState.swift`: consume shared counts; serialize/coalesce rail reports and preserve zero clears. Startup and foreground consumers await the same refresh. Reminder checks consume counts; invoice-specific logic remains independent.
- Update `FloatingActionMenu.swift` and `JobBoardView.swift`: render cached scalar values; unknown counts remain unavailable until loaded. Keep current typography/layout/tokens. Fetch review row arrays only on explicit entry.
- Update pure row query helpers where necessary so snapshot and sheet membership use identical predicates. Preserve assignment case rules and project access through task teams.
- Add focused tests for row/count parity, scoped company/deletion handling, date/threshold boundaries, lock gates, one reader for concurrent demand, coalescing, invalidation during read, account/container/permission replacement, failure vs valid zero, and notification zero/error isolation.

## Sequence and validation

1. Extract immutable scope and shared predicates; implement actor scalar reader.
2. Implement injected cache/refresh coordinator and deterministic async tests.
3. Wire ready actor provider and MainTab lifecycle invalidations; remove passive fetches from FAB, JobBoard, and reminder/rail call sites.
4. Preserve explicit review-entry row queries and current tokenized presentation; statically inspect all changed consumers.
5. Parent runs the focused OPSTests review snapshot/query/threshold/refresh suites together with actor-readiness suites, then Release phone launch/capture proof. This worker may parse Swift syntax and inspect diffs only, with no build/test execution.
6. Commit owned files only; supply Bible additions and exact verification limitations to the parent.

No edits to DataActor.swift, DataController.swift, SyncEngine.swift, or CalendarViewModel.swift; those belong to P1-4. No phone/server mutations, pushes, deployment, or independently created database context.

## Implementation decisions confirmed during work

- PM explicitly approved existing-context two-read rollback when `FeatureFlags.useDataActor` is false; enabled-but-unavailable readiness still fails closed.
- PM explicitly approved correcting review-only cross-company eligibility, including sheet rows and completed-task unlock count. The old test intentionally admitted both companies; it now requires foreign rows to be excluded. General task getters are untouched.
- Freshness uses derived next eligibility change, including same-day elapsed thresholds, plus foreground refresh. Local Company saves invalidate threshold identity.
- Authored a persisted read/edit/read test against the same already-registered actor. P1-4 has not yet proven this reverse-context propagation boundary; parent must run this test before runtime approval.
