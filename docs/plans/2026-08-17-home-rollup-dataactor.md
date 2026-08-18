# Home Billable Rollup → DataActor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use custom-skills:executing-plans to implement this plan task-by-task.

**Goal:** Move HomeView's billable-this-week rollup (and the needs-tasks count) off the main thread onto the existing `DataActor`, preserving exact project-scoping semantics, locked by a parity test.

**Architecture:** HomeView is MainActor-inferred, so the `Task {}` in `loadTodaysProjects` never leaves the main thread — the rollup faults `project.tasks` for every live project (261 on the founder's device) on mount, tab return, foreground, and sync completion. The fix: HomeView keeps assembling `everyProject` exactly as today (it needs those `[Project]` models for the map regardless, and that assembly does NOT fault tasks), then passes only the **project ids** to a new `DataActor.computeHomeRollup(projectIds:companyId:today:)`. The actor fetches those exact rows in its own background context, faults `.tasks` there, and returns a Sendable snapshot. Scoping is preserved **by construction** — no scoping logic is duplicated, so the rollup can never disagree with the map about which projects exist. Legacy fallback (`FeatureFlags.useDataActor` off → `dataController.dataActor == nil`) keeps the current main-thread compute unchanged.

**Tech Stack:** Swift / SwiftData `@ModelActor`, XCTest.

**Design System:** N/A (no UI change — values rendered must be identical before/after).

**Required Skills:** `superpowers:test-driven-development`, `superpowers:verification-before-completion`.

**Repo:** `/Users/jacksonsweet/Projects/OPS/ops-ios`, branch `main` (clean tree). Commit directly to main — perf fix, no feature branch. NO AI attribution in commits.

**Parallel-session guard:** A sibling session builds in `.worktrees/notification-rpc-legacy-20260817` with worktree-local DerivedData (`.dd-b1`) — it does NOT touch the primary checkout's default DerivedData. Before each `xcodebuild`, re-check `ps aux | grep xcodebuild | grep -v grep | grep -v .worktrees` to confirm nothing else builds the primary checkout.

---

## Context you must know (read these before starting)

- `OPS/Views/Home/HomeView.swift` — `loadTodaysProjects` (line ~298), `computeBillableRollup` (line ~381), and the `onChange(of: appState.showProjectsNeedingTasksReview)` handler (line ~77).
- `OPS/Services/HomeBillableThisWeekRollupEngine.swift` — pure compute engine, already tested.
- `OPS/Utilities/ProjectsWithoutTasksDetector.swift` — pure filter, faults `project.tasks`.
- `OPS/Utilities/DataActor.swift` — `@ModelActor actor DataActor` (line 34). Do NOT edit this 275KB file; new code goes in a new extension file.
- `OPS/Utilities/DataController.swift` — `private(set) var dataActor: DataActor?` (line 112), created in `setModelContext` when `FeatureFlags.useDataActor` (default true).
- `OPSTests/HomeBillableThisWeekRollupTests.swift` — fixture style to mirror (`makeProject`/`makeTask`/`makeInvoice`/`makeEstimate`).
- Test-container gotchas (ops-ios/CLAUDE.md): a `ModelContext` does NOT retain its container — retain the container for the test case's lifetime (see `retainedContainers` in `OPSTests/Sync/SyncCrossEntityDependencyTests.swift`). Find and mirror an existing in-memory `ModelContainer` setup from OPSTests (grep `isStoredInMemoryOnly: true` in OPSTests) rather than inventing one. The `SyncOperation` predicate trap does not apply here (we never fetch SyncOperation).
- The Xcode project uses file-system-synchronized groups — new files under `OPS/` and `OPSTests/` are picked up automatically.

## Exactness contract (what "preserving semantics" means)

Current main-thread behavior in `computeBillableRollup` (HomeView.swift:381–418) that the actor must replicate byte-for-byte:

1. Invoices/estimates fetched with `#Predicate` gates: `deletedAt == nil`, AND `companyId == companyId` **only when** a company id exists ("no company id means no filter"). Fetch failures degrade to `[]` via `try?`.
2. Rollup = `HomeBillableThisWeekRollupEngine.compute(projects:invoices:estimates:today:)` with default calendar.
3. Projects input = exactly the caller-assembled list (tutorial filter, team-scoping, scheduled-task merge all already applied upstream). The actor receives ids and fetches those rows — nothing more, nothing less. Deleted projects whose ids are passed are dropped by the engine itself (`project.deletedAt == nil` guard), same as today.
4. Needs-tasks count = `ProjectsWithoutTasksDetector.projectsWithoutTasks(from: projects).count`, with `tutorialMode ? 0 : …` applied on the main side (unchanged).

---

### Task 1: Sendable conformances on the rollup value types

**Files:**
- Modify: `OPS/Services/HomeBillableThisWeekRollupEngine.swift:8-25`

**Step 1:** Make the actor-boundary contract explicit (all fields are already value types):

```swift
enum HomeBillableRollupSection: String, Sendable {
```
```swift
struct HomeBillableProjectCandidate: Identifiable, Sendable {
```
```swift
struct HomeBillableThisWeekRollup: Sendable {
```

**Step 2:** No commit yet — rides with Task 3's commit (atomic unit is "rollup crosses the actor boundary").

### Task 2: Failing tests first

**Files:**
- Create: `OPSTests/HomeRollupDataActorTests.swift`

Mirror the fixture helpers from `OPSTests/HomeBillableThisWeekRollupTests.swift`, but insert everything into an in-memory `ModelContainer` (models needed: at least `Project`, `ProjectTask`, `Invoice`, `Estimate` — reuse whatever schema/container helper pattern OPSTests already uses; retain the container in a property for the case's lifetime).

**Test 1 — `testActorRollupMatchesMainThreadComputationExactly` (the parity lock):**

Seed into the container, all `companyId == "company-1"` unless noted, dates **relative to a pinned `today = Calendar.current.startOfDay(for: Date())`** so the test is calendar-robust on any run date:

- `closing` — status `.inProgress`, one `.active` task with `endDate = today` (inside this week by definition), draft invoice total 8_400.
- `ready` — status `.completed`, one `.completed` task with `endDate = today - 1 day` (always ≥ the grace floor of weekStart − 7d), approved estimate total 2_600.
- `stale` — status `.completed`, one `.completed` task with `endDate = today - 60 days` (always below the grace floor) → must appear in neither section.
- `tombstone` — status `.inProgress` with `deletedAt = Date()`, one `.active` task ending `today`. Its id IS passed in `projectIds` → the engine drops it on both paths.
- `foreign-visible` — same company, status `.inProgress`, `.active` task ending `today`, draft invoice 9_999 — but its id is NOT in `projectIds` → must not appear (locks "the actor fetches exactly the ids given, never re-derives visibility").
- `needs-tasks` — status `.accepted`, zero tasks → counts toward `projectsNeedingTasksCount` (and never enters either rollup section).
- One draft invoice on `ready` with `companyId = "company-2"`, total 7_777 → must be excluded by the company-scoped invoice fetch on both paths (locks invoice/estimate company gating; without the gate, draft-invoice priority would override `ready`'s estimate amount and the test fails loudly).

Save the context. Then:

```swift
let projectIds = ["closing", "ready", "stale", "tombstone", "needs-tasks"]

// Expected: the CURRENT main-thread path, computed on the main context.
let expectedProjects = projectIds.compactMap { id in mainFetchedProjectsById[id] }
let expectedInvoices = /* main-context fetch: deletedAt == nil && companyId == "company-1" */
let expectedEstimates = /* same for estimates */
let expected = HomeBillableThisWeekRollupEngine.compute(
    projects: expectedProjects, invoices: expectedInvoices,
    estimates: expectedEstimates, today: today)
let expectedNeedsTasks = ProjectsWithoutTasksDetector.projectsWithoutTasks(from: expectedProjects).count

// Actual: the actor path.
let actor = DataActor(modelContainer: container)
await actor.configure()
let snapshot = await actor.computeHomeRollup(
    projectIds: projectIds, companyId: "company-1", today: today)
```

Assert (candidates aren't Equatable — compare fields):
- `snapshot.rollup.closingThisWeek.map(\.projectId) == expected.closingThisWeek.map(\.projectId)` and same for `readyToBill` (and assert the concrete expected content too: closing == `["closing"]`, ready == `["ready"]` — the parity assert alone would pass if both paths were identically wrong).
- Per-candidate: `amount`, `invoiceId`, `estimateId`, `taskCount`, `section`, `latestTaskEnd` equal across paths; `ready`'s amount is 2_600 via `estimateId == "est-ready"` (proving the company-2 invoice was excluded).
- `snapshot.rollup.weekStart == expected.weekStart`, `weekEnd == expected.weekEnd`.
- `snapshot.rollup.totalKnownAmount == expected.totalKnownAmount` (accuracy 0.001).
- `snapshot.projectsNeedingTasksCount == expectedNeedsTasks` and `== 1`.

**Test 2 — `testNeedsTasksCountMethodMatchesDetector`:** seed 2 task-less `.accepted` projects + 1 `.inProgress` with a live task + 1 task-less `.accepted` project whose id is not passed; assert `await actor.projectsNeedingTasksCount(projectIds: ids) == 2` and equals the main-context detector count over the same ids.

**Test 3 — `testMainThreadCostEvidence` (measurement, not assertion):** seed 261 projects × 5 tasks each (mix of statuses/end dates) + ~100 invoices/estimates. Measure with `ContinuousClock`:
- (a) the old main-thread cost: `HomeBillableThisWeekRollupEngine.compute` + `ProjectsWithoutTasksDetector` over main-context-fetched projects (fresh context so relationship faults actually fire, mirroring a cold Home load);
- (b) the new main-thread cost: wall time of `await actor.computeHomeRollup(...)` from the test (suspension, not blocking — report it as latency, not main-thread time).
Print both durations clearly (`[PERF-EVIDENCE] old main-thread compute: Xms; actor round-trip: Yms; main-thread work after refactor: ~0 (suspension)`). Assert only that both complete and results match on `projectCount`. No timing assertions (flaky).

**Step: run tests to verify they FAIL to compile** (`computeHomeRollup` doesn't exist yet):

```bash
xcodebuild build-for-testing -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' 2>&1 | tail -20
```
Expected: compile error on `computeHomeRollup`.

### Task 3: The actor method

**Files:**
- Create: `OPS/Utilities/DataActor+HomeRollup.swift`

```swift
//
//  DataActor+HomeRollup.swift
//  OPS
//
//  Home's billable-this-week rollup, computed off the main thread
//  (bug 3d9ead2f follow-up: HomeView is MainActor-inferred, so its
//  loadTodaysProjects Task faulted project.tasks for every live project
//  on the main thread on mount, tab return, foreground, and sync).
//
//  Scoping contract: the CALLER decides which projects the card counts.
//  HomeView passes the ids of the same list it feeds the map
//  (getProjectsForCurrentUser + scheduled-task merge + tutorial filter);
//  this actor fetches exactly those rows in its own context and never
//  re-derives visibility, so the rollup cannot disagree with the map.
//  HomeRollupDataActorTests locks the parity.
//

import Foundation
import SwiftData

/// Everything Home needs back from the background rollup pass.
struct HomeRollupSnapshot: Sendable {
    let rollup: HomeBillableThisWeekRollup
    let projectsNeedingTasksCount: Int
}

extension DataActor {

    /// Compute the billable-this-week rollup and the needs-tasks count for
    /// exactly the given projects, faulting `project.tasks` on the actor's
    /// context instead of the main thread.
    ///
    /// Mirrors the retired HomeView.computeBillableRollup gates exactly:
    /// invoices/estimates are company-scoped at the fetch when a company id
    /// exists ("no company id means no filter"), tombstones never materialize.
    func computeHomeRollup(
        projectIds: [String],
        companyId: String?,
        today: Date = Date()
    ) -> HomeRollupSnapshot {
        let projects = fetchProjects(ids: projectIds)

        var invoiceDescriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate<Invoice> { $0.deletedAt == nil }
        )
        var estimateDescriptor = FetchDescriptor<Estimate>(
            predicate: #Predicate<Estimate> { $0.deletedAt == nil }
        )
        if let companyId {
            invoiceDescriptor.predicate = #Predicate<Invoice> {
                $0.deletedAt == nil && $0.companyId == companyId
            }
            estimateDescriptor.predicate = #Predicate<Estimate> {
                $0.deletedAt == nil && $0.companyId == companyId
            }
        }
        let invoices = (try? modelContext.fetch(invoiceDescriptor)) ?? []
        let estimates = (try? modelContext.fetch(estimateDescriptor)) ?? []

        return HomeRollupSnapshot(
            rollup: HomeBillableThisWeekRollupEngine.compute(
                projects: projects,
                invoices: invoices,
                estimates: estimates,
                today: today
            ),
            projectsNeedingTasksCount: ProjectsWithoutTasksDetector
                .projectsWithoutTasks(from: projects)
                .count
        )
    }

    /// Needs-tasks count alone — the review-sheet-dismiss recompute needs the
    /// count without paying for the invoice/estimate fetches.
    func projectsNeedingTasksCount(projectIds: [String]) -> Int {
        ProjectsWithoutTasksDetector
            .projectsWithoutTasks(from: fetchProjects(ids: projectIds))
            .count
    }

    private func fetchProjects(ids: [String]) -> [Project] {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { ids.contains($0.id) }
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("[DataActor] Home rollup project fetch failed: \(error)")
            return []
        }
    }
}
```

**Step: run the new tests — all pass:**

```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/HomeRollupDataActorTests 2>&1 | tail -30
```
Expected: 3 tests pass. **Verify the executed-test COUNT in the output — "SUCCEEDED" can mean 0 tests ran.** Capture the `[PERF-EVIDENCE]` lines from the log.

**Step: commit** (Tasks 1+2+3 together — one atomic unit):

```bash
git add OPS/Services/HomeBillableThisWeekRollupEngine.swift OPS/Utilities/DataActor+HomeRollup.swift OPSTests/HomeRollupDataActorTests.swift
git commit -m "perf(home): compute billable rollup on DataActor

HomeView is MainActor-inferred, so its loadTodaysProjects Task faulted
project.tasks for every live project on the main thread on every Home
load. The rollup and needs-tasks count now compute on the DataActor from
caller-supplied project ids, so scoping stays exactly the list the map
shows. Parity with the main-thread computation is locked by test."
```

### Task 4: Rewire HomeView

**Files:**
- Modify: `OPS/Views/Home/HomeView.swift`

**Step 1 — `loadTodaysProjects`:** replace lines 344–352 (`let billableRollup = computeBillableRollup…` through the `needsTasksCount` computation) with:

```swift
            // Faulting tasks for every live project belongs on the DataActor,
            // not the render thread. The actor gets the ids of the exact list
            // the map shows, so the card can never disagree with the map.
            let billableRollup: HomeBillableThisWeekRollup
            let needsTasksCount: Int
            if let actor = dataController.dataActor {
                let snapshot = await actor.computeHomeRollup(
                    projectIds: everyProject.map(\.id),
                    companyId: dataController.currentUser?.companyId
                )
                billableRollup = snapshot.rollup
                // Data self-scopes (see the comment above), but tutorial demo
                // data is excluded with the same gate as the legacy path.
                needsTasksCount = tutorialMode ? 0 : snapshot.projectsNeedingTasksCount
            } else {
                // Legacy path (feature.useDataActor off): unchanged.
                billableRollup = computeBillableRollup(projects: everyProject)
                needsTasksCount = tutorialMode
                    ? 0
                    : ProjectsWithoutTasksDetector.projectsWithoutTasks(from: everyProject).count
            }
```

Keep the existing comment block about needs-tasks self-scoping (lines 345–349) attached where it reads naturally. `computeBillableRollup` STAYS in the file — it is the legacy fallback.

**Step 2 — the review-sheet-dismiss recompute** (lines 77–84): same defect class (detector faults tasks on main). Replace the body with:

```swift
            guard !showing, isActiveTab else { return }
            let visibleProjects = dataController.getProjectsForCurrentUser(for: nil)
            if let actor = dataController.dataActor {
                let ids = visibleProjects.map(\.id)
                Task {
                    projectsNeedingTasksCount = await actor.projectsNeedingTasksCount(projectIds: ids)
                }
            } else {
                projectsNeedingTasksCount = ProjectsWithoutTasksDetector
                    .projectsWithoutTasks(from: visibleProjects)
                    .count
            }
```

(No tutorial gate here — the current code has none; the review sheet cannot open in tutorial mode.)

**Step 3 — device build (the required build gate):**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -15
```
Expected: `BUILD SUCCEEDED`. (Never the simulator destination for plain build.)

**Step 4 — regression tests** (existing rollup suites + the new one + dispatcher):

```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:OPSTests/HomeRollupDataActorTests \
  -only-testing:OPSTests/HomeBillableThisWeekRollupTests \
  -only-testing:OPSTests/HomeBillableThisWeekNotificationDispatcherTests 2>&1 | tail -30
```
Expected: all pass; verify executed-test counts.

**Step 5 — commit:**

```bash
git add OPS/Views/Home/HomeView.swift
git commit -m "perf(home): rollup and needs-tasks count come from the DataActor

Home's loads now await the actor snapshot instead of faulting tasks on
the main thread; the review-sheet-dismiss recompute rides the same
method. Legacy main-thread compute remains behind the useDataActor flag."
```

### Task 5: Bible + evidence

- Check `ops-software-bible/` for the section describing Home / DataActor phases (grep `DataActor` in ops-software-bible). If the C-pragmatic ModelActor refactor is documented, add one line noting the Home rollup now computes on the actor. Commit to the bible repo with `docs(bible): …` if a relevant section exists; skip silently if none mentions this subsystem.
- Save the `[PERF-EVIDENCE]` numbers and the final test summary lines into the final report (NOT into the repo root — scratchpad only).

## Verification checklist (before claiming done)

- [ ] `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` → BUILD SUCCEEDED
- [ ] New parity suite passes with a non-zero executed-test count visible in output
- [ ] Existing `HomeBillableThisWeekRollupTests` + `HomeBillableThisWeekNotificationDispatcherTests` still pass
- [ ] `[PERF-EVIDENCE]` timing captured
- [ ] Two commits on main, conventional style, no AI attribution
- [ ] `git status` clean afterward; nothing staged that isn't ours
