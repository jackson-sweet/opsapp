# Task Priority Queue + Auto-Schedule — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an office/admin operator rank active tasks by priority (drag-to-reorder, persisted) and auto-schedule them in that order — all at once (preview → commit) or one at a time (tap-to-place) — by feeding the manual order into the existing scheduling engine.

**Architecture:** A persistent `priorityRank: Double?` on `ProjectTask` (fractional indexing). The existing `AutoScheduleManager` placement logic is **extracted into a reusable `placeNext` helper and called**, not rewritten; a new `taskPriorityQueue` mode sequences candidates by priority via a dependency-respecting traversal. One shared `PriorityQueueView` + view-model is mounted from two entry points (FAB item + JobBoard TASKS toggle).

**Tech Stack:** Swift, SwiftUI, SwiftData, Supabase (sync via `TaskRepository` / `OutboundProcessor`), XCTest. Design tokens via `OPSStyle`. Copy via `ops-copywriter`; motion via `animation-studio:animation-architect`.

**Spec:** `docs/superpowers/specs/2026-06-02-task-priority-scheduling-design.md`

**Core constraint:** DO NOT rebuild scheduling. Call `AutoScheduleManager`; adjust only candidate ordering.

**Build commands (from `ops-ios/`):**
- Device-target compile check: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
- Test compile: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build-for-testing`
- Run a test: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:OPSTests/<Class>/<method>`

---

## File Structure

**Create:**
- `OPS/Utilities/FractionalRank.swift` — pure rank math (between/normalize).
- `OPS/Views/Components/Scheduling/PriorityQueueView.swift` — shared core list + waterline + run controls.
- `OPS/Views/Components/Scheduling/PriorityQueueRow.swift` — one task row.
- `OPS/Views/Components/Scheduling/PrioritySchedulePreviewSheet.swift` — batch preview (replaces dead `AutoSchedulePreviewSheet`).
- `OPS/ViewModels/PriorityQueueViewModel.swift` — list/waterline/reorder/run state.
- `OPSTests/FractionalRankTests.swift`
- `OPSTests/PriorityQueueSchedulingTests.swift`

**Modify:**
- `OPS/DataModels/ProjectTask.swift:126` — add `priorityRank`.
- `OPS/Utilities/ScheduleTypes.swift` — add `Mode.taskPriorityQueue`; extend `ScheduleDataProvider`.
- `OPS/Utilities/AutoScheduleManager.swift` — extract `placeNext`; add `schedulePriorityQueue`.
- `OPS/Utilities/DataController.swift:6367` — provider method impls; `:6419` add `autoSchedulePriorityQueue`; add `reorderPriority`/`bulkSetPriority`.
- `OPS/Network/Sync/OutboundProcessor.swift:415` — add `priority_rank` to `validProjectTaskColumns`.
- `OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift` — add `priorityRank`/`priority_rank` to `SupabaseProjectTaskDTO`.
- `OPS/Network/Supabase/DTOs/CoreEntityConverters.swift:263` — map `priorityRank` onto `ProjectTask`.
- `OPS/Views/Components/FloatingActionMenu.swift:557` — add "Prioritize" item to SCHEDULING group.
- `OPS/Views/JobBoard/JobBoardView.swift:182` — add PRIORITIZE toggle; `:283` swap to `PriorityQueueView` when on.
- `OPSTests/AutoScheduleManagerTests.swift` — extend `MockScheduleDataProvider` with new protocol methods.
- `OPS/Views/Components/Scheduling/AutoSchedulePreviewSheet.swift` — delete (dead code).
- Supabase: `project_tasks.priority_rank` column + index (via Supabase MCP).
- `ops-software-bible/03_DATA_ARCHITECTURE.md` + `07_SPECIALIZED_FEATURES.md` — document field + feature.

---

## Phase 1 — Data + sync foundation

### Task 1: Add `priorityRank` to ProjectTask

**Files:**
- Modify: `OPS/DataModels/ProjectTask.swift:126`

> No SwiftData migration needed — optional property on the live model rides lightweight auto-migration (verified: commits `5d5800b0`/`8fe1e39d`/`ef1ce63b` added ProjectTask properties with zero migration changes). Do NOT add a schema version.

- [ ] **Step 1: Add the property**

In `OPS/DataModels/ProjectTask.swift`, immediately after line 126 (`var displayOrder: Int = 0`):

```swift
var displayOrder: Int = 0
/// Global company-wide manual priority. Lower = higher priority.
/// nil = unranked (below the waterline). Fractional indexing: a moved task
/// receives a value strictly between its neighbors, so one reorder dirties one
/// row. Re-spaced by FractionalRank.normalize when neighbor gaps get tight.
/// Synced to Supabase `project_tasks.priority_rank`. Added 2026-06-02.
var priorityRank: Double?
```

No `init` change required (optional defaults to `nil`). `ProjectTask: SchedulableTask` is unaffected (the protocol does not reference priority).

- [ ] **Step 2: Compile**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OPS/DataModels/ProjectTask.swift
git commit -m "feat(tasks): add priorityRank to ProjectTask for manual scheduling priority"
```

---

### Task 2: `FractionalRank` helper (pure, TDD)

**Files:**
- Create: `OPS/Utilities/FractionalRank.swift`
- Test: `OPSTests/FractionalRankTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `OPSTests/FractionalRankTests.swift`:

```swift
import XCTest
@testable import OPS

final class FractionalRankTests: XCTestCase {

    func testBetween_emptyList_returnsZero() {
        XCTAssertEqual(FractionalRank.between(nil, nil), 0)
    }

    func testBetween_openTop_isAboveLower() {
        // Inserting at the very top (no upper bound): result < lower.
        XCTAssertEqual(FractionalRank.between(nil, 100), 99)
    }

    func testBetween_openBottom_isBelowUpper() {
        // Inserting at the very bottom (no lower bound): result > upper.
        XCTAssertEqual(FractionalRank.between(100, nil), 101)
    }

    func testBetween_twoNeighbors_isMidpoint() {
        XCTAssertEqual(FractionalRank.between(10, 20), 15)
    }

    func testBetween_strictlyOrderedAfterRepeatedTopInserts() {
        var upper = 0.0
        var last = Double.greatestFiniteMagnitude
        for _ in 0..<40 {
            let r = FractionalRank.between(nil, upper)
            XCTAssertLessThan(r, upper)
            XCTAssertLessThan(r, last)
            last = r
            upper = r
        }
    }

    func testNeedsNormalization_trueWhenGapTooSmall() {
        XCTAssertTrue(FractionalRank.needsNormalization(between: 1.0, and: 1.0 + 1e-10))
        XCTAssertFalse(FractionalRank.needsNormalization(between: 1.0, and: 2.0))
    }

    func testNormalize_evenlySpacesPreservingOrder() {
        let ids = ["a", "b", "c", "d"]
        let ranks = FractionalRank.normalize(orderedIds: ids)
        XCTAssertEqual(ids.sorted { ranks[$0]! < ranks[$1]! }, ids) // order preserved
        XCTAssertEqual(ranks["a"], 1024)
        XCTAssertEqual(ranks["d"], 4096)
    }
}
```

- [ ] **Step 2: Run, verify failure**

Run: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:OPSTests/FractionalRankTests`
Expected: FAIL — `FractionalRank` not found.

- [ ] **Step 3: Implement**

Create `OPS/Utilities/FractionalRank.swift`:

```swift
//
//  FractionalRank.swift
//  OPS
//
//  Pure fractional-index math for drag-to-reorder priority ranks. A moved item
//  gets a value strictly between its neighbors so one move dirties one row.
//  Re-spaced by `normalize` when neighbor gaps approach Double precision limits.
//

import Foundation

enum FractionalRank {
    /// Default spacing used when (re)assigning a fresh ordered sequence.
    static let step: Double = 1024

    /// Below this neighbor gap, fractional inserts risk precision loss — normalize.
    static let minGap: Double = 1e-6

    /// A rank strictly between `lower` and `upper`.
    /// - nil/nil → 0 (first item in an empty list)
    /// - nil/upper → upper - 1 (insert at top)
    /// - lower/nil → lower + 1 (insert at bottom)
    /// - lower/upper → midpoint
    static func between(_ lower: Double?, _ upper: Double?) -> Double {
        switch (lower, upper) {
        case (nil, nil):                 return 0
        case (nil, let u?):              return u - 1
        case (let l?, nil):              return l + 1
        case (let l?, let u?):           return (l + u) / 2
        }
    }

    /// True when the gap between two adjacent ranks is too small to safely bisect.
    static func needsNormalization(between lower: Double, and upper: Double) -> Bool {
        abs(upper - lower) < minGap
    }

    /// Evenly spaced ranks (step, 2*step, …) for an ordered id list, order preserved.
    static func normalize(orderedIds: [String]) -> [String: Double] {
        var result: [String: Double] = [:]
        for (i, id) in orderedIds.enumerated() {
            result[id] = Double(i + 1) * step
        }
        return result
    }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:OPSTests/FractionalRankTests`
Expected: PASS (all 7).

- [ ] **Step 5: Commit**

```bash
git add OPS/Utilities/FractionalRank.swift OPSTests/FractionalRankTests.swift
git commit -m "feat(scheduling): add FractionalRank helper for drag-reorder priority"
```

---

### Task 3: Supabase column + sync mapping

**Files:**
- Supabase migration (via MCP)
- Modify: `OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift` (`SupabaseProjectTaskDTO`)
- Modify: `OPS/Network/Supabase/DTOs/CoreEntityConverters.swift:263`
- Modify: `OPS/Network/Sync/OutboundProcessor.swift:415`

> Cost: additive nullable column DDL on `project_tasks` — no Supabase cost. Confirm live column type with `list_tables` before applying (OPS precision rule).

- [ ] **Step 1: Inspect the live table**

Use Supabase MCP `list_tables` (schema `public`, table `project_tasks`) to confirm existing columns and that `priority_rank` does not already exist.

- [ ] **Step 2: Apply the migration**

Use Supabase MCP `apply_migration` (name `add_project_tasks_priority_rank`):

```sql
ALTER TABLE public.project_tasks
  ADD COLUMN IF NOT EXISTS priority_rank double precision;

CREATE INDEX IF NOT EXISTS idx_project_tasks_priority
  ON public.project_tasks (company_id, priority_rank)
  WHERE deleted_at IS NULL;
```

- [ ] **Step 3: Add the field to the DTO**

In `OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift`, find `struct SupabaseProjectTaskDTO`. Beside its `displayOrder`/`display_order` member, add (match the existing optional-Double + CodingKeys style in that struct):

```swift
let priorityRank: Double?     // maps to project_tasks.priority_rank
```
and in its `CodingKeys`:
```swift
case priorityRank = "priority_rank"
```
If the struct decodes via an explicit `init(from:)`, decode with `decodeIfPresent(Double.self, forKey: .priorityRank)`.

- [ ] **Step 4: Map DTO → model on inbound**

In `OPS/Network/Supabase/DTOs/CoreEntityConverters.swift`, at the ProjectTask conversion (line 263, beside `task.displayOrder = displayOrder ?? 0`):

```swift
task.displayOrder = displayOrder ?? 0
task.priorityRank = priorityRank   // nil stays nil (unranked)
```

- [ ] **Step 5: Allow the column outbound**

In `OPS/Network/Sync/OutboundProcessor.swift`, add `"priority_rank"` to the `validProjectTaskColumns` set (the literal at line 415 that already contains `"display_order"`):

```swift
"custom_title", "task_notes", "status", "task_color", "display_order", "priority_rank",
```

- [ ] **Step 6: Compile**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift OPS/Network/Supabase/DTOs/CoreEntityConverters.swift OPS/Network/Sync/OutboundProcessor.swift
git commit -m "feat(sync): map project_tasks.priority_rank inbound + allow outbound"
```

---

## Phase 2 — Engine adjustment (call, don't rebuild)

### Task 4: Extract `placeNext` from `scheduleBatch` (behavior-preserving)

**Files:**
- Modify: `OPS/Utilities/AutoScheduleManager.swift`
- Test (regression): `OPSTests/AutoScheduleManagerTests.swift` (unchanged — must stay green)

**Context:** `scheduleBatch` (lines 172–326) places each task with: build `allKnownTasks` (project tasks + already-placed virtuals), `calculateDependencyFloor`, empty-crew branch, `findAvailableSlot`, `findGeographicAlternative`, append `TaskPlacement`, append to `placedTasks`. We move that per-task body verbatim into a shared helper so a second sequencer can reuse it. **No logic change.**

- [ ] **Step 1: Add the shared state + helper**

In `AutoScheduleManager.swift`, add a named record type (replacing the inline tuple) and a `placeNext` helper. Define near the top of the struct:

```swift
/// One already-placed task in a batch run; seen by later tasks as a commitment.
struct PlacedRecord {
    let id: String
    let taskTypeId: String
    let startDate: Date
    let endDate: Date
    let teamMemberIds: Set<String>
    let projectId: String
}

/// Mutable accumulator threaded through a batch/priority run.
private struct RunState {
    var placements: [TaskPlacement] = []
    var conflicts: [ScheduleConflict] = []
    var warnings: [String] = []
    var placed: [PlacedRecord] = []
    var proximityGroups = 0
}
```

Add `placeNext`, copying the existing per-task body (current lines 204–308) and parameterizing the "tasks visible for dependency floor":

```swift
/// Places one task using the existing 4-pass logic and records it as a
/// commitment. This is the SAME body previously inlined in scheduleBatch —
/// extracted so both project-batch and priority-queue sequencing reuse it.
private static func placeNext(
    _ task: any SchedulableTask,
    dependencyVisibleTasks: [any SchedulableTask],
    anchor: Date,
    constraints: ScheduleConstraints,
    provider: ScheduleDataProvider,
    state: inout RunState
) {
    let calendar = Calendar.current
    let teamMemberIds = task.schedulingTeamMemberIds
    let effectiveDuration = max(task.duration, 1)

    // Pass 1: dependency floor (DB tasks + already-placed virtuals for same project)
    var allKnownTasks = dependencyVisibleTasks
    for placed in state.placed where placed.projectId == task.schedulingProjectId {
        allKnownTasks.append(VirtualTask(
            id: placed.id, taskTypeId: placed.taskTypeId,
            startDate: placed.startDate, endDate: placed.endDate,
            duration: (calendar.dateComponents([.day], from: placed.startDate, to: placed.endDate).day ?? 0) + 1,
            effectiveDependencies: [], displayOrder: 0,
            schedulingTeamMemberIds: placed.teamMemberIds, schedulingProjectId: placed.projectId
        ))
    }
    let dependencyFloor = calculateDependencyFloor(
        for: task, allProjectTasks: allKnownTasks, anchor: anchor, skipWeekends: constraints.skipWeekends
    )

    // Pass 2: no crew → place on floor, warn
    if teamMemberIds.isEmpty {
        state.conflicts.append(ScheduleConflict(
            id: task.id, type: .noCrewAssigned,
            message: "No crew assigned — availability not checked"))
        let startDate = constraints.skipWeekends ? skipToWeekday(date: dependencyFloor, calendar: calendar) : dependencyFloor
        let endDate = calendar.date(byAdding: .day, value: max(effectiveDuration - 1, 0), to: startDate) ?? startDate
        state.placements.append(TaskPlacement(id: task.id, taskTypeId: task.taskTypeId, startDate: startDate, endDate: endDate, startTime: nil, endTime: nil, alternative: nil))
        state.placed.append(PlacedRecord(id: task.id, taskTypeId: task.taskTypeId, startDate: startDate, endDate: endDate, teamMemberIds: teamMemberIds, projectId: task.schedulingProjectId))
        return
    }

    // Pass 2: crew availability (DB commitments + already-placed virtuals overlapping crew)
    var existingCommitments = provider.allScheduledTasksForMembers(teamMemberIds, from: dependencyFloor)
    for placed in state.placed where !placed.teamMemberIds.isDisjoint(with: teamMemberIds) {
        existingCommitments.append(VirtualTask(
            id: placed.id, taskTypeId: placed.taskTypeId,
            startDate: placed.startDate, endDate: placed.endDate,
            duration: (calendar.dateComponents([.day], from: placed.startDate, to: placed.endDate).day ?? 0) + 1,
            effectiveDependencies: [], displayOrder: 0,
            schedulingTeamMemberIds: placed.teamMemberIds, schedulingProjectId: placed.projectId))
    }
    let slot = findAvailableSlot(memberIds: teamMemberIds, duration: effectiveDuration, from: dependencyFloor, existingCommitments: existingCommitments, constraints: constraints, calendar: calendar)
    let endDate = calendar.date(byAdding: .day, value: max(effectiveDuration - 1, 0), to: slot) ?? slot

    // Pass 3: geographic alternative
    let alternative = findGeographicAlternative(task: task, teamMemberIds: teamMemberIds, primaryStart: slot, duration: effectiveDuration, existingCommitments: existingCommitments, constraints: constraints, provider: provider, calendar: calendar)
    if alternative != nil { state.proximityGroups += 1 }

    state.placements.append(TaskPlacement(id: task.id, taskTypeId: task.taskTypeId, startDate: slot, endDate: endDate, startTime: nil, endTime: nil, alternative: alternative))
    state.placed.append(PlacedRecord(id: task.id, taskTypeId: task.taskTypeId, startDate: slot, endDate: endDate, teamMemberIds: teamMemberIds, projectId: task.schedulingProjectId))
}
```

- [ ] **Step 2: Rewrite `scheduleBatch` to call `placeNext`**

Replace the body of the inner `for task in sorted` loop (lines 204–308) with:

```swift
for task in sorted {
    placeNext(task, dependencyVisibleTasks: projectTasks, anchor: anchor, constraints: constraints, provider: provider, state: &state)
}
```

…and refactor `scheduleBatch` to use a single `var state = RunState()` instead of the separate `allPlacements`/`allConflicts`/`allWarnings`/`placedTasks`/`proximityGroups` locals. At the end build the result from `state`:

```swift
let totalGapDays = calculateTotalGapDays(placements: state.placements, calendar: calendar)
return SchedulePlan(
    placements: state.placements, conflicts: state.conflicts,
    metadata: ScheduleMetadata(totalGapDays: totalGapDays, proximityGroupsFound: state.proximityGroups, weatherDependentTaskCount: 0, weatherDeferrals: 0, downstreamUnscheduledCount: 0, warnings: state.warnings))
```

- [ ] **Step 3: Run existing engine tests (must stay green)**

Run: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:OPSTests/AutoScheduleManagerTests`
Expected: PASS — all pre-existing tests unchanged. (This proves the extraction is behavior-preserving.)

- [ ] **Step 4: Commit**

```bash
git add OPS/Utilities/AutoScheduleManager.swift
git commit -m "refactor(scheduling): extract placeNext from scheduleBatch (no behavior change)"
```

---

### Task 5: Add `taskPriorityQueue` mode + provider methods + traversal

**Files:**
- Modify: `OPS/Utilities/ScheduleTypes.swift`
- Modify: `OPS/Utilities/AutoScheduleManager.swift`
- Modify: `OPSTests/AutoScheduleManagerTests.swift` (extend mock provider)
- Test: `OPSTests/PriorityQueueSchedulingTests.swift`

- [ ] **Step 1: Extend the Mode + provider protocol**

In `OPS/Utilities/ScheduleTypes.swift`, add to `ScheduleRequest.Mode`:

```swift
/// Auto-schedule a flat, cross-project list of tasks in explicit priority order.
case taskPriorityQueue(orderedTaskIds: [String], includeUnranked: Bool)
```

and to `protocol ScheduleDataProvider`:

```swift
/// Resolve task ids to SchedulableTask, preserving the input order. Missing ids dropped.
func schedulableTasks(forIds ids: [String]) -> [any SchedulableTask]
/// All active, unranked (priorityRank == nil) tasks, default (latest-edited) order.
func unrankedActiveSchedulableTasks() -> [any SchedulableTask]
```

- [ ] **Step 2: Make existing mocks conform (compile fix)**

In `OPSTests/AutoScheduleManagerTests.swift`, add to `MockScheduleDataProvider`:

```swift
let orderedById: [String: any SchedulableTask]   // add to the struct's stored props
let unranked: [any SchedulableTask]              // add to the struct's stored props

func schedulableTasks(forIds ids: [String]) -> [any SchedulableTask] {
    ids.compactMap { orderedById[$0] }
}
func unrankedActiveSchedulableTasks() -> [any SchedulableTask] { unranked }
```
Update existing `MockScheduleDataProvider(...)` initializations in that file to pass `orderedById: [:], unranked: []` (or build from `allTasks`). Keep existing tests compiling and green.

- [ ] **Step 3: Dispatch the new mode**

In `AutoScheduleManager.schedule(request:provider:)`, add the case:

```swift
case .taskPriorityQueue(let orderedTaskIds, let includeUnranked):
    return schedulePriorityQueue(orderedTaskIds: orderedTaskIds, includeUnranked: includeUnranked, anchor: anchor, constraints: request.constraints, provider: provider)
```

- [ ] **Step 4: Write the failing priority tests**

Create `OPSTests/PriorityQueueSchedulingTests.swift`:

```swift
import XCTest
@testable import OPS

final class PriorityQueueSchedulingTests: XCTestCase {
    private let cal = Calendar.current
    private func d(_ y: Int, _ m: Int, _ dd: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: dd))! }

    private struct Mock: SchedulableTask {
        let id: String; let taskTypeId: String
        var startDate: Date? = nil; var endDate: Date? = nil
        var duration: Int = 1
        var effectiveDependencies: [TaskTypeDependency] = []
        var displayOrder: Int = 0
        var schedulingTeamMemberIds: Set<String> = ["crew"]
        var schedulingProjectId: String = "p1"
    }

    private struct Provider: ScheduleDataProvider {
        var tasks: [String: any SchedulableTask]
        var unranked: [any SchedulableTask] = []
        func tasksForProject(_ id: String) -> [any SchedulableTask] { tasks.values.filter { $0.schedulingProjectId == id } }
        func allScheduledTasksForMembers(_ m: Set<String>, from date: Date) -> [any SchedulableTask] { [] }
        func coordinatesForProject(_ id: String) -> (lat: Double, lng: Double)? { nil }
        func priorityDateForProject(_ id: String) -> Date? { nil }
        func schedulableTasks(forIds ids: [String]) -> [any SchedulableTask] { ids.compactMap { tasks[$0] } }
        func unrankedActiveSchedulableTasks() -> [any SchedulableTask] { unranked }
    }

    private func constraints() -> ScheduleConstraints {
        ScheduleConstraints(skipWeekends: false, preciseScheduling: false,
            schedulingWindow: .companyHours(open: "08:00", close: "17:00"),
            proximityRadiusKm: 15, weatherConstraints: nil)
    }

    func testPlacesIndependentTasksInPriorityOrderBackToBack() {
        let a = Mock(id: "a", taskTypeId: "ta", duration: 2, schedulingProjectId: "p1")
        let b = Mock(id: "b", taskTypeId: "tb", duration: 1, schedulingProjectId: "p2")
        let p = Provider(tasks: ["a": a, "b": b])
        let req = ScheduleRequest(mode: .taskPriorityQueue(orderedTaskIds: ["a", "b"], includeUnranked: false), anchorDate: d(2026, 4, 6), constraints: constraints())
        let plan = AutoScheduleManager.schedule(request: req, provider: p)
        XCTAssertEqual(plan.placements.count, 2)
        let pa = plan.placements.first { $0.id == "a" }!
        let pb = plan.placements.first { $0.id == "b" }!
        XCTAssertEqual(cal.startOfDay(for: pa.startDate), d(2026, 4, 6))   // Mon–Tue
        XCTAssertEqual(cal.startOfDay(for: pb.startDate), d(2026, 4, 8))   // Wed, after a's crew block
    }

    func testDependencyForcesPredecessorFirstEvenWhenRankedLower() {
        // Same project, same crew. "framing" depends on "footings".
        // User ranks framing ABOVE footings — dependency must still win.
        let footings = Mock(id: "foot", taskTypeId: "footings", duration: 1, schedulingProjectId: "p1")
        let dep = TaskTypeDependency(dependsOnTaskTypeId: "footings", overlapMode: "after_end", overlapPercentage: 0, constantDays: 0, weekdayConstraint: nil)
        let framing = Mock(id: "frame", taskTypeId: "framing", duration: 1, effectiveDependencies: [dep], schedulingProjectId: "p1")
        let p = Provider(tasks: ["foot": footings, "frame": framing])
        let req = ScheduleRequest(mode: .taskPriorityQueue(orderedTaskIds: ["frame", "foot"], includeUnranked: false), anchorDate: d(2026, 4, 6), constraints: constraints())
        let plan = AutoScheduleManager.schedule(request: req, provider: p)
        let pf = plan.placements.first { $0.id == "foot" }!
        let pframe = plan.placements.first { $0.id == "frame" }!
        XCTAssertLessThan(pf.startDate, pframe.startDate)   // footings scheduled before framing
    }

    func testIncludeUnrankedAppendsTailAfterRanked() {
        let a = Mock(id: "a", taskTypeId: "ta", duration: 1, schedulingProjectId: "p1")
        let u = Mock(id: "u", taskTypeId: "tu", duration: 1, schedulingProjectId: "p2", )
        let p = Provider(tasks: ["a": a, "u": u], unranked: [u])
        let req = ScheduleRequest(mode: .taskPriorityQueue(orderedTaskIds: ["a"], includeUnranked: true), anchorDate: d(2026, 4, 6), constraints: constraints())
        let plan = AutoScheduleManager.schedule(request: req, provider: p)
        XCTAssertEqual(Set(plan.placements.map(\.id)), ["a", "u"])
    }

    func testExcludeUnrankedSchedulesOnlyRanked() {
        let a = Mock(id: "a", taskTypeId: "ta", schedulingProjectId: "p1")
        let u = Mock(id: "u", taskTypeId: "tu", schedulingProjectId: "p2")
        let p = Provider(tasks: ["a": a, "u": u], unranked: [u])
        let req = ScheduleRequest(mode: .taskPriorityQueue(orderedTaskIds: ["a"], includeUnranked: false), anchorDate: d(2026, 4, 6), constraints: constraints())
        let plan = AutoScheduleManager.schedule(request: req, provider: p)
        XCTAssertEqual(plan.placements.map(\.id), ["a"])
    }
}
```

> Verify `TaskTypeDependency`'s real initializer in `OPS/DataModels/...` and adjust the `dep` construction in the test to match it exactly before running.

- [ ] **Step 5: Run, verify failure**

Run: `xcodebuild ... test -only-testing:OPSTests/PriorityQueueSchedulingTests`
Expected: FAIL — `schedulePriorityQueue` not implemented.

- [ ] **Step 6: Implement the traversal**

In `AutoScheduleManager.swift`:

```swift
// MARK: - Priority-Queue Scheduling

/// Schedules a flat, cross-project task list in explicit priority order,
/// deferring any task whose predecessors aren't placed yet so dependencies
/// always win. Reuses placeNext — the SAME placement logic as the batch path.
private static func schedulePriorityQueue(
    orderedTaskIds: [String],
    includeUnranked: Bool,
    anchor: Date,
    constraints: ScheduleConstraints,
    provider: ScheduleDataProvider
) -> SchedulePlan {
    let calendar = Calendar.current
    var state = RunState()

    // Candidate set in priority order; unranked tail appended when requested.
    var candidates = provider.schedulableTasks(forIds: orderedTaskIds)
    if includeUnranked { candidates.append(contentsOf: provider.unrankedActiveSchedulableTasks()) }

    // Only schedule tasks that still need it (no dates). Already-dated tasks act
    // as fixed commitments via provider.allScheduledTasksForMembers (in placeNext).
    var remaining = candidates.filter { $0.startDate == nil || $0.endDate == nil }
    guard !remaining.isEmpty else { return .empty }

    // Priority-respecting topological traversal: among tasks whose predecessors
    // (matched by taskTypeId in the candidate set) are already placed, take the
    // highest-priority (earliest in `remaining`) and place it. Repeat.
    let placedTypeIds = { state.placed.map(\.taskTypeId) }
    func predecessorsSatisfied(_ task: any SchedulableTask) -> Bool {
        for dep in task.effectiveDependencies {
            let inSet = remaining.contains { $0.taskTypeId == dep.dependsOnTaskTypeId }
            // If a predecessor is still in the to-place set, it must be placed first.
            if inSet && !placedTypeIds().contains(dep.dependsOnTaskTypeId) { return false }
        }
        return true
    }

    var safety = remaining.count * remaining.count + 1
    while !remaining.isEmpty && safety > 0 {
        safety -= 1
        if let idx = remaining.firstIndex(where: predecessorsSatisfied) {
            let task = remaining.remove(at: idx)
            let visible = provider.tasksForProject(task.schedulingProjectId)
            placeNext(task, dependencyVisibleTasks: visible, anchor: anchor, constraints: constraints, provider: provider, state: &state)
        } else {
            // Cycle / unresolvable: place the rest in priority order; floor degrades gracefully.
            for task in remaining {
                let visible = provider.tasksForProject(task.schedulingProjectId)
                placeNext(task, dependencyVisibleTasks: visible, anchor: anchor, constraints: constraints, provider: provider, state: &state)
            }
            remaining.removeAll()
        }
    }

    let totalGapDays = calculateTotalGapDays(placements: state.placements, calendar: calendar)
    return SchedulePlan(
        placements: state.placements, conflicts: state.conflicts,
        metadata: ScheduleMetadata(totalGapDays: totalGapDays, proximityGroupsFound: state.proximityGroups, weatherDependentTaskCount: 0, weatherDeferrals: 0, downstreamUnscheduledCount: 0, warnings: state.warnings))
}
```

- [ ] **Step 7: Run, verify pass**

Run: `xcodebuild ... test -only-testing:OPSTests/PriorityQueueSchedulingTests` and `-only-testing:OPSTests/AutoScheduleManagerTests`
Expected: PASS (new + regression).

- [ ] **Step 8: Commit**

```bash
git add OPS/Utilities/ScheduleTypes.swift OPS/Utilities/AutoScheduleManager.swift OPSTests/AutoScheduleManagerTests.swift OPSTests/PriorityQueueSchedulingTests.swift
git commit -m "feat(scheduling): add taskPriorityQueue mode (priority-respecting traversal, reuses placeNext)"
```

---

### Task 6: DataController provider methods + entry point

**Files:**
- Modify: `OPS/Utilities/DataController.swift:6367` (provider) and `:6419` (convenience)

- [ ] **Step 1: Implement the two new provider methods**

In the `extension DataController: ScheduleDataProvider` block (starts line 6367), add:

```swift
func schedulableTasks(forIds ids: [String]) -> [any SchedulableTask] {
    let byId = Dictionary(uniqueKeysWithValues: getAllTasks().map { ($0.id, $0) })
    return ids.compactMap { byId[$0] as (any SchedulableTask)? }
}

func unrankedActiveSchedulableTasks() -> [any SchedulableTask] {
    getAllTasks()
        .filter { $0.status == .active && $0.deletedAt == nil && $0.priorityRank == nil }
        .sorted { ($0.lastSyncedAt ?? .distantPast) > ($1.lastSyncedAt ?? .distantPast) }
        .map { $0 as any SchedulableTask }
}
```

- [ ] **Step 2: Add the convenience entry point**

In the `// MARK: - AutoScheduleManager Convenience` extension (after `autoScheduleProjects`, line 6460):

```swift
/// Auto-schedule a priority-ordered, cross-project task list.
func autoSchedulePriorityQueue(orderedTaskIds: [String], includeUnranked: Bool, anchorDate: Date = Date()) -> SchedulePlan {
    let request = ScheduleRequest(
        mode: .taskPriorityQueue(orderedTaskIds: orderedTaskIds, includeUnranked: includeUnranked),
        anchorDate: anchorDate,
        constraints: buildScheduleConstraints()
    )
    return AutoScheduleManager.schedule(request: request, provider: self)
}
```

- [ ] **Step 3: Compile**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add OPS/Utilities/DataController.swift
git commit -m "feat(scheduling): DataController priority-queue provider methods + entry point"
```

---

## Phase 3 — Reorder persistence API

### Task 7: `reorderPriority` / `bulkSetPriority` + sync enqueue

**Files:**
- Modify: `OPS/Utilities/DataController.swift` (new extension)

> Follow the existing task-field write pattern: mutate the `ProjectTask`, set `needsSync = true`, persist, and enqueue a `SyncOperation` whose payload carries `priority_rank` (allow-listed in Task 3). Locate an existing simple task-field updater (e.g. `updateTaskNotes` / the `enqueueSyncOperation` used by `updateTaskSchedule` at line 3837) and mirror its enqueue call exactly.

- [ ] **Step 1: Add the reorder API**

Add a new extension in `DataController.swift`:

```swift
// MARK: - Task Priority (drag-to-reorder)

extension DataController {
    /// Persist a single task's priority rank (nil = unranked). Marks dirty + enqueues sync.
    func reorderPriority(taskId: String, newRank: Double?) {
        guard let ctx = modelContext,
              let task = try? ctx.fetch(FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == taskId })).first
        else { return }
        task.priorityRank = newRank
        task.needsSync = true
        try? ctx.save()
        enqueueTaskPriorityShare(taskId: taskId, rank: newRank)
    }

    /// Persist many ranks at once (divider sweep / normalization). One save, N enqueues.
    func bulkSetPriority(_ ranks: [String: Double?]) {
        guard let ctx = modelContext else { return }
        let ids = Array(ranks.keys)
        let tasks = (try? ctx.fetch(FetchDescriptor<ProjectTask>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        for task in tasks {
            if let newRank = ranks[task.id] {
                task.priorityRank = newRank
                task.needsSync = true
            }
        }
        try? ctx.save()
        for (id, rank) in ranks { enqueueTaskPriorityShare(taskId: id, rank: rank) }
    }

    /// Enqueue a project_tasks update carrying only priority_rank.
    private func enqueueTaskPriorityShare(taskId: String, rank: Double?) {
        // MIRROR the enqueue used by updateTaskSchedule (line 3837): build an
        // update SyncOperation for entity "project_tasks" / entityId taskId with
        // payload ["priority_rank": rank as Any]. Use NSNull() for nil so the
        // server clears the column.
        enqueueUpdateOperation(
            entityType: "project_tasks",
            entityId: taskId,
            payload: ["priority_rank": rank ?? NSNull()]
        )
    }
}
```

> Replace `enqueueUpdateOperation(entityType:entityId:payload:)` with the EXACT enqueue helper name used by `updateTaskSchedule`. If that method enqueues differently (e.g. via a `SyncOperation` initializer + `ctx.insert`), copy that call shape verbatim here.

- [ ] **Step 2: Compile**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual sync check (device/sim)**

Run the app, change a task's `priorityRank` via a temporary debug call, confirm a `project_tasks` row's `priority_rank` updates in Supabase (MCP `execute_sql`: `select id, priority_rank from project_tasks where id = '<id>'`).

- [ ] **Step 4: Commit**

```bash
git add OPS/Utilities/DataController.swift
git commit -m "feat(tasks): reorderPriority/bulkSetPriority with sync enqueue"
```

---

## Phase 4 — Shared core UI

### Task 8: `PriorityQueueViewModel`

**Files:**
- Create: `OPS/ViewModels/PriorityQueueViewModel.swift`

- [ ] **Step 1: Implement the view-model**

```swift
//
//  PriorityQueueViewModel.swift
//  OPS
//
//  Backs the shared PriorityQueueView: the ordered task list, the waterline
//  (ranked above / unranked below), drag-reorder → rank writes, and the
//  schedule runner. Reads/writes priority via DataController; scheduling via
//  the existing AutoScheduleManager entry points.
//

import Foundation
import SwiftUI

@MainActor
final class PriorityQueueViewModel: ObservableObject {
    @Published var ranked: [ProjectTask] = []        // above the waterline, priority order
    @Published var unranked: [ProjectTask] = []      // below the waterline, default order
    @Published var includeUnranked = false
    @Published var rescheduleScheduled = false
    @Published var anchorDate = Date()
    @Published var previewPlan: SchedulePlan?         // non-nil → present preview
    @Published var pendingConfirmCount = 0           // scheduled tasks a run would move

    private let dataController: DataController

    init(dataController: DataController) {
        self.dataController = dataController
        reload()
    }

    /// Load all active company tasks, split by waterline.
    func reload() {
        let active = dataController.getAllTasks().filter { $0.status == .active && $0.deletedAt == nil }
        ranked = active.filter { $0.priorityRank != nil }.sorted { ($0.priorityRank!, $0.id) < ($1.priorityRank!, $1.id) }
        unranked = active.filter { $0.priorityRank == nil }.sorted { ($0.lastSyncedAt ?? .distantPast) > ($1.lastSyncedAt ?? .distantPast) }
    }

    // MARK: Reorder

    /// Move a task within the ranked zone to `index` and persist a fractional rank.
    func moveRanked(taskId: String, to index: Int) {
        guard let current = ranked.firstIndex(where: { $0.id == taskId }) else { return }
        var working = ranked
        let task = working.remove(at: current)
        let clamped = min(max(index, 0), working.count)
        working.insert(task, at: clamped)
        ranked = working
        persistRank(forIndex: clamped, in: working)
    }

    /// Pull an unranked task above the waterline at `index`.
    func rank(taskId: String, at index: Int) {
        guard let task = unranked.first(where: { $0.id == taskId }) else { return }
        unranked.removeAll { $0.id == taskId }
        let clamped = min(max(index, 0), ranked.count)
        ranked.insert(task, at: clamped)
        persistRank(forIndex: clamped, in: ranked)
    }

    /// Drop a ranked task below the waterline (unrank).
    func unrank(taskId: String) {
        guard let task = ranked.first(where: { $0.id == taskId }) else { return }
        ranked.removeAll { $0.id == taskId }
        unranked.insert(task, at: 0)
        dataController.reorderPriority(taskId: taskId, newRank: nil)
    }

    /// Move the waterline so the first `count` of the current unranked list become ranked
    /// (divider dragged down), or the last `count` ranked become unranked (dragged up).
    func setWaterline(rankedCount newCount: Int) {
        let combined = ranked + unranked
        let clamped = min(max(newCount, 0), combined.count)
        let newRanked = Array(combined.prefix(clamped))
        let newUnranked = Array(combined.suffix(combined.count - clamped))
        ranked = newRanked
        unranked = newUnranked
        // Re-space ranked, clear unranked — one bulk write.
        var ranks: [String: Double?] = [:]
        let normalized = FractionalRank.normalize(orderedIds: newRanked.map(\.id))
        for (id, r) in normalized { ranks[id] = r }
        for t in newUnranked { ranks[t.id] = Double?.none }
        dataController.bulkSetPriority(ranks)
    }

    /// Assign a fractional rank to the task now at `index` in `list`, normalizing if tight.
    private func persistRank(forIndex index: Int, in list: [ProjectTask]) {
        let id = list[index].id
        let lower = index > 0 ? list[index - 1].priorityRank : nil
        let upper = index < list.count - 1 ? list[index + 1].priorityRank : nil
        if let l = lower, let u = upper, FractionalRank.needsNormalization(between: l, and: u) {
            let normalized = FractionalRank.normalize(orderedIds: list.map(\.id))
            var ranks: [String: Double?] = [:]
            for (k, v) in normalized { ranks[k] = v }
            dataController.bulkSetPriority(ranks)
            for (i, t) in list.enumerated() { t.priorityRank = normalized[t.id] ?? Double(i + 1) * FractionalRank.step }
        } else {
            let rank = FractionalRank.between(lower, upper)
            list[index].priorityRank = rank
            dataController.reorderPriority(taskId: id, newRank: rank)
        }
    }

    // MARK: Run

    /// Count already-scheduled, unlocked tasks a run would move (for the confirm dialog).
    func scheduledMoveCount() -> Int {
        let scope = rescheduleScheduled ? (ranked + (includeUnranked ? unranked : [])) : []
        return scope.filter { $0.startDate != nil && !$0.scheduleLocked }.count
    }

    /// Build the batch plan (Schedule All).
    func buildPlan() {
        previewPlan = dataController.autoSchedulePriorityQueue(
            orderedTaskIds: ranked.map(\.id), includeUnranked: includeUnranked, anchorDate: anchorDate)
    }

    /// Commit a built plan: write each placement via the existing schedule writer.
    func commit(plan: SchedulePlan) async {
        for p in plan.placements {
            guard let task = dataController.getAllTasks().first(where: { $0.id == p.id }) else { continue }
            try? await dataController.updateTaskSchedule(task: task, startDate: p.startDate, endDate: p.endDate, manualEdit: false)
        }
        previewPlan = nil
        reload()
    }

    /// One-at-a-time: schedule the top unscheduled ranked task immediately.
    func tapToPlaceNext() async {
        guard let task = ranked.first(where: { $0.startDate == nil }) else { return }
        let plan = dataController.autoScheduleSingleTask(task, teamMemberIds: Set(task.getTeamMemberIds()), anchorDate: anchorDate)
        if let p = plan.placements.first {
            try? await dataController.updateTaskSchedule(task: task, startDate: p.startDate, endDate: p.endDate, manualEdit: false)
        }
        reload()
    }
}
```

> Confirm the exact signature of `updateTaskSchedule` (line 3837) — `manualEdit:` default and `async throws`. Adjust the `await`/`try` to match. `getTeamMemberIds()` exists on `ProjectTask` (used across the codebase).

- [ ] **Step 2: Compile**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OPS/ViewModels/PriorityQueueViewModel.swift
git commit -m "feat(scheduling): PriorityQueueViewModel — waterline, reorder, run"
```

---

### Task 9: `PriorityQueueRow`

**Files:**
- Create: `OPS/Views/Components/Scheduling/PriorityQueueRow.swift`

- [ ] **Step 1: Implement the row** (real OPSStyle tokens; copy finalized in Task 16)

```swift
import SwiftUI

struct PriorityQueueRow: View {
    let task: ProjectTask
    let rankNumber: Int?     // 1-based position in the ranked zone; nil = unranked

    private var dateText: String {
        guard let start = task.startDate else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        if let end = task.endDate, end != start { return "\(f.string(from: start)) – \(f.string(from: end))" }
        return f.string(from: start)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Rank index (mono) or unranked dash
            Text(rankNumber.map(String.init) ?? "—")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(rankNumber == nil ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.displayTitle)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Text(task.project?.title ?? "—")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
            }

            Spacer()

            if task.getTeamMemberIds().isEmpty {
                // No-crew warning chip (engine will place-with-warning)
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }

            if task.startDate != nil {
                Text(dateText)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Image(systemName: "line.3.horizontal")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
    }
}
```

> Verify `task.displayTitle` exists (used by `AutoSchedulePreviewSheet`/`TaskListSheet` — it does). Verify `OPSStyle.Layout.touchTargetStandard` exists (used in `AutoSchedulePreviewSheet`).

- [ ] **Step 2: Compile**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Components/Scheduling/PriorityQueueRow.swift
git commit -m "feat(scheduling): PriorityQueueRow component"
```

---

### Task 10: `PriorityQueueView` (list + waterline + drag)

**Files:**
- Create: `OPS/Views/Components/Scheduling/PriorityQueueView.swift`

- [ ] **Step 1: Implement the view**

Use a SwiftUI `List` with `.onMove` for reliable reorder, an `EditMode` always-active environment, and a non-draggable `UNRANKED` section header acting as the waterline (crossing sections sets/clears rank). The run controls live in a bottom bar.

```swift
import SwiftUI

struct PriorityQueueView: View {
    enum DisplayMode { case fullScreen, inline }

    @EnvironmentObject private var dataController: DataController
    @StateObject private var vm: PriorityQueueViewModel
    let displayMode: DisplayMode
    var onClose: (() -> Void)? = nil

    @State private var showConfirm = false

    init(displayMode: DisplayMode, dataController: DataController, onClose: (() -> Void)? = nil) {
        self.displayMode = displayMode
        self.onClose = onClose
        _vm = StateObject(wrappedValue: PriorityQueueViewModel(dataController: dataController))
    }

    var body: some View {
        VStack(spacing: 0) {
            if displayMode == .fullScreen { header }
            toggles
            list
            runBar
        }
        .background(OPSStyle.Colors.background)
        .sheet(item: Binding(get: { vm.previewPlan.map { PlanBox(plan: $0) } }, set: { if $0 == nil { vm.previewPlan = nil } })) { box in
            PrioritySchedulePreviewSheet(plan: box.plan, anchorDate: vm.anchorDate) {
                Task { await vm.commit(plan: box.plan) }
            }
            .environmentObject(dataController)
        }
        .alert("Reschedule scheduled tasks?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Continue") { vm.buildPlan() }
        } message: {
            Text("This moves \(vm.pendingConfirmCount) already-scheduled tasks.")  // copy via ops-copywriter
        }
    }

    private var header: some View {
        HStack {
            Text("PRIORITIZE")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
            Button("DONE") { onClose?() }
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
        }
        .padding(16)
    }

    private var toggles: some View {
        HStack(spacing: 12) {
            toggleChip("INCLUDE UNRANKED", isOn: vm.includeUnranked) { vm.includeUnranked.toggle() }
            toggleChip("RESCHEDULE SCHEDULED", isOn: vm.rescheduleScheduled) { vm.rescheduleScheduled.toggle() }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var list: some View {
        List {
            Section {
                ForEach(Array(vm.ranked.enumerated()), id: \.element.id) { idx, task in
                    PriorityQueueRow(task: task, rankNumber: idx + 1)
                        .listRowBackground(Color.clear)
                }
                .onMove { from, to in
                    guard let f = from.first else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    vm.moveRanked(taskId: vm.ranked[f].id, to: to > f ? to - 1 : to)
                }
            } header: {
                Text("RANKED").font(OPSStyle.Typography.captionBold).foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Section {
                ForEach(vm.unranked, id: \.id) { task in
                    PriorityQueueRow(task: task, rankNumber: nil)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .leading) {
                            Button("Rank") { vm.rank(taskId: task.id, at: vm.ranked.count) }
                                .tint(OPSStyle.Colors.primaryAccent)
                        }
                }
            } header: {
                Text("UNRANKED — WATERLINE").font(OPSStyle.Typography.captionBold).foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
    }

    private var runBar: some View {
        HStack(spacing: 12) {
            Button { Task { await vm.tapToPlaceNext() } } label: {
                Text("PLACE NEXT").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryRunButtonStyle())
            .disabled(vm.ranked.allSatisfy { $0.startDate != nil })

            Button {
                let moves = vm.scheduledMoveCount()
                if moves > 0 { vm.pendingConfirmCount = moves; showConfirm = true } else { vm.buildPlan() }
            } label: {
                Text("SCHEDULE ALL").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryRunButtonStyle())
            .disabled(vm.ranked.isEmpty)
        }
        .padding(16)
    }

    @ViewBuilder
    private func toggleChip(_ label: String, isOn: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(isOn ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.secondaryText)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius).fill(isOn ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBackgroundDark))
                .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius).stroke(isOn ? Color.clear : OPSStyle.Colors.cardBorder, lineWidth: 1))
        }
    }
}

/// Identifiable box so SchedulePlan can drive a `.sheet(item:)`.
private struct PlanBox: Identifiable { let id = UUID(); let plan: SchedulePlan }

private struct PrimaryRunButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.button)
            .foregroundColor(.white)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.primaryAccent)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
private struct SecondaryRunButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.button)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius).stroke(OPSStyle.Colors.cardBorder, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
```

> The waterline-as-draggable-divider (dragging the section header to bulk rank/unrank) is refined in Task 17 with `animation-architect`; the `swipeActions` "Rank" affordance above is the functional baseline. `setWaterline(rankedCount:)` on the VM backs the divider drag.

- [ ] **Step 2: Compile**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Components/Scheduling/PriorityQueueView.swift
git commit -m "feat(scheduling): PriorityQueueView — ranked/unranked list, reorder, run bar"
```

---

## Phase 5 — Runner (preview + commit)

### Task 11: `PrioritySchedulePreviewSheet` (replace dead sheet)

**Files:**
- Create: `OPS/Views/Components/Scheduling/PrioritySchedulePreviewSheet.swift`
- Delete: `OPS/Views/Components/Scheduling/AutoSchedulePreviewSheet.swift`

- [ ] **Step 1: Delete the dead legacy sheet**

```bash
git rm OPS/Views/Components/Scheduling/AutoSchedulePreviewSheet.swift
```
(Confirm zero references first: `rg -n "AutoSchedulePreviewSheet" --type swift` returns only the file itself.)

- [ ] **Step 2: Create the new preview sheet** (built against `ScheduleTypes.TaskPlacement`)

```swift
import SwiftUI
import SwiftData

struct PrioritySchedulePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    let plan: SchedulePlan
    @State var anchorDate: Date
    let onConfirm: () -> Void

    private let df: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d"; return f }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AUTO-SCHEDULE").font(OPSStyle.Typography.captionBold).foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Text("\(plan.placements.count) tasks").font(OPSStyle.Typography.caption).foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, 16).padding(.top, 16)

            if plan.metadata.totalGapDays > 0 || plan.metadata.proximityGroupsFound > 0 {
                HStack(spacing: 12) {
                    if plan.metadata.totalGapDays > 0 {
                        Label("\(plan.metadata.totalGapDays) gap days", systemImage: "calendar.badge.clock")
                            .font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    if plan.metadata.proximityGroupsFound > 0 {
                        Label("\(plan.metadata.proximityGroupsFound) nearby", systemImage: "mappin.and.ellipse")
                            .font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(plan.placements.enumerated()), id: \.element.id) { idx, p in
                        row(p, idx: idx)
                    }
                }
                .padding(.vertical, 12)
            }

            Divider().background(OPSStyle.Colors.cardBorder)

            HStack(spacing: 12) {
                Button { dismiss() } label: { Text("CANCEL").frame(maxWidth: .infinity) }
                    .buttonStyle(.plain)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(OPSStyle.Colors.cardBackgroundDark).cornerRadius(OPSStyle.Layout.cardCornerRadius)
                Button { onConfirm(); dismiss() } label: {
                    Text("SCHEDULE ALL").font(OPSStyle.Typography.button).foregroundColor(.white).frame(maxWidth: .infinity)
                }
                .frame(height: OPSStyle.Layout.touchTargetStandard)
                .background(OPSStyle.Colors.primaryAccent).cornerRadius(OPSStyle.Layout.cardCornerRadius)
            }
            .padding(16)
        }
        .background(OPSStyle.Colors.background)
    }

    @ViewBuilder
    private func row(_ p: TaskPlacement, idx: Int) -> some View {
        let conflict = plan.conflicts.first { $0.id == p.id }
        HStack(spacing: 12) {
            Text("\(idx + 1)").font(OPSStyle.Typography.captionBold).foregroundColor(OPSStyle.Colors.tertiaryText).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(taskName(p.id)).font(OPSStyle.Typography.body).foregroundColor(OPSStyle.Colors.primaryText)
                Text("\(df.string(from: p.startDate)) – \(df.string(from: p.endDate))")
                    .font(OPSStyle.Typography.caption).foregroundColor(OPSStyle.Colors.primaryAccent)
                if let conflict { Text(conflict.message).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.warningStatus) }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(OPSStyle.Colors.cardBackgroundDark).cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .padding(.horizontal, 16)
    }

    private func taskName(_ id: String) -> String {
        guard let ctx = dataController.modelContext,
              let task = try? ctx.fetch(FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == id })).first
        else { return "Task" }
        return task.displayTitle
    }
}
```

- [ ] **Step 3: Compile**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add OPS/Views/Components/Scheduling/PrioritySchedulePreviewSheet.swift
git commit -m "feat(scheduling): PrioritySchedulePreviewSheet (replaces dead AutoSchedulePreviewSheet)"
```

---

## Phase 6 — Entry points

### Task 12: FAB "Prioritize" item

**Files:**
- Modify: `OPS/Views/Components/FloatingActionMenu.swift`

- [ ] **Step 1: Add the SCHEDULING-group item + sheet state**

Add a `@State private var showingPrioritize = false` near the other sheet flags (line ~103). In `menuGroups`, append to the SCHEDULING group items (line 557 group), before/after the existing items:

```swift
FABMenuItem(
    id: "prioritize",
    icon: "arrow.up.arrow.down",
    label: "Prioritize",
    permission: "tasks.edit",
    disabledInTutorial: true,
    action: {
        showCreateMenu = false
        showingPrioritize = true
    }
),
```

Add the presentation alongside the other `.sheet`s (e.g. near line 925):

```swift
.fullScreenCover(isPresented: $showingPrioritize) {
    PriorityQueueView(displayMode: .fullScreen, dataController: dataController) {
        showingPrioritize = false
    }
    .environmentObject(dataController)
}
```

- [ ] **Step 2: Compile + manual check**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` → SUCCEEDED.
Run app as office/admin → FAB → SCHEDULING → Prioritize opens the queue.

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Components/FloatingActionMenu.swift
git commit -m "feat(scheduling): add Prioritize action to FAB scheduling group"
```

---

### Task 13: JobBoard TASKS "PRIORITIZE" toggle

**Files:**
- Modify: `OPS/Views/JobBoard/JobBoardView.swift`

- [ ] **Step 1: Add toggle state + button**

Add `@State private var prioritizeMode = false` to `JobBoardView` (near line 25). In the action row (`HStack` at line 182), add — only for the tasks section with permission — a PRIORITIZE toggle button mirroring the `ACTIVE ONLY` button style:

```swift
if selectedSection == .tasks && permissionStore.can("tasks.edit") {
    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { prioritizeMode.toggle() } }) {
        Text("PRIORITIZE")
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(prioritizeMode ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.secondaryText)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius).fill(prioritizeMode ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBackgroundDark))
            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius).stroke(prioritizeMode ? Color.clear : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
    }
}
```

- [ ] **Step 2: Swap the tasks content when on**

In the `case .tasks:` branch (line 283), wrap:

```swift
case .tasks:
    if prioritizeMode {
        PriorityQueueView(displayMode: .inline, dataController: dataController)
            .padding(.horizontal, 16)
    } else {
        JobBoardTasksView(searchText: searchText, showingFilters: $showingFilters, showingFilterSheet: $showingTaskFilterSheet, assignedToMe: assignedToMe)
            .padding(.horizontal, 16)
    }
```

- [ ] **Step 3: Compile + manual check**

Build → SUCCEEDED. Office/admin → JobBoard → TASKS → PRIORITIZE flips to the reorderable queue.

- [ ] **Step 4: Commit**

```bash
git add OPS/Views/JobBoard/JobBoardView.swift
git commit -m "feat(scheduling): JobBoard TASKS prioritize-mode toggle"
```

---

## Phase 7 — Cross-cutting polish

### Task 14: Haptics + notification

**Files:**
- Modify: `OPS/ViewModels/PriorityQueueViewModel.swift`

- [ ] **Step 1: Add haptics on commit + tap-to-place**

In `commit(plan:)` after the loop: `UINotificationFeedbackGenerator().notificationOccurred(.success)`.
In `tapToPlaceNext()` after writing: `UIImpactFeedbackGenerator(style: .medium).impactOccurred()`.
(Drag pickup/drop haptics already fire in `PriorityQueueView.onMove`.)

- [ ] **Step 2: Post a notification on batch commit**

After a successful `commit(plan:)`, create an OPS notification ("Scheduled N tasks") with an action to the schedule/calendar. Mirror an existing call site of `NotificationManager` for a completed bulk action (see `NotificationManager.swift`). Use a standard (dismissible) notification, `actionUrl` to the calendar tab.

```swift
NotificationManager.shared.scheduleProjectNotification(/* mirror an existing standard notification call; title "Scheduled \(plan.placements.count) tasks" */)
```

> Replace with the exact `NotificationManager` API used elsewhere for a bulk/system notification; do not invent a signature.

- [ ] **Step 3: Compile + commit**

```bash
git add OPS/ViewModels/PriorityQueueViewModel.swift
git commit -m "feat(scheduling): haptics + notification on schedule commit"
```

---

### Task 15: Finalize copy via ops-copywriter

**Files:**
- Modify: the new views (labels/empty states/dialogs)

- [ ] **Step 1: Invoke `ops-copywriter`** for these strings (OPS voice — terse/tactical, UPPERCASE authority labels, sentence-case content, no emoji):
  - FAB item label: "Prioritize"
  - Section headers: "RANKED", "UNRANKED — WATERLINE"
  - Toggles: "INCLUDE UNRANKED", "RESCHEDULE SCHEDULED"
  - Buttons: "PLACE NEXT", "SCHEDULE ALL", "PRIORITIZE"
  - Confirm dialog title + body: "Reschedule scheduled tasks?" / "This moves N already-scheduled tasks."
  - Empty ranked-zone state (when `ranked.isEmpty`): instruct dragging tasks above the line / enabling INCLUDE UNRANKED.
  - Notification copy: "Scheduled N tasks".

- [ ] **Step 2: Replace placeholder strings** with the approved copy.

- [ ] **Step 3: Compile + commit**

```bash
git add -- OPS/Views/Components/Scheduling/PriorityQueueView.swift OPS/Views/Components/Scheduling/PriorityQueueRow.swift OPS/Views/Components/Scheduling/PrioritySchedulePreviewSheet.swift OPS/Views/Components/FloatingActionMenu.swift OPS/Views/JobBoard/JobBoardView.swift
git commit -m "copy(scheduling): finalize priority queue copy via ops-copywriter"
```

---

### Task 16: Motion via animation-architect (incl. draggable waterline)

**Files:**
- Modify: `OPS/Views/Components/Scheduling/PriorityQueueView.swift` (+ Row)

- [ ] **Step 1: Invoke `animation-studio:animation-architect`** then `ios-animations` to design:
  - Drag-reorder feel (the sanctioned no-bounce exception) — pickup lift, neighbor displacement, drop settle. One easing curve `cubic-bezier(0.22, 1, 0.36, 1)`; honor `prefers-reduced-motion`.
  - The **draggable `UNRANKED` divider**: a long-press-draggable header that, on drop, calls `vm.setWaterline(rankedCount:)` to bulk rank/unrank the swept slice (replaces the swipe-to-rank baseline).
  - "Task lands on its date" confirmation in the preview commit.

- [ ] **Step 2: Implement the approved motion + draggable divider.**

- [ ] **Step 3: Compile + commit**

```bash
git add OPS/Views/Components/Scheduling/PriorityQueueView.swift OPS/Views/Components/Scheduling/PriorityQueueRow.swift
git commit -m "feat(scheduling): drag-reorder motion + draggable waterline divider"
```

---

## Phase 8 — Docs + verification

### Task 17: Software Bible updates

**Files:**
- Modify: `ops-software-bible/03_DATA_ARCHITECTURE.md`, `ops-software-bible/07_SPECIALIZED_FEATURES.md`

- [ ] **Step 1:** In `03_DATA_ARCHITECTURE.md` § ProjectTask, add `priority_rank double precision NULL` to the `project_tasks` schema and the SwiftData field list; note "global manual priority, lower = higher, nil = unranked."
- [ ] **Step 2:** Correct the "scheduling is entirely manual" claim in `07_SPECIALIZED_FEATURES.md`: document `AutoScheduleManager` modes incl. `taskPriorityQueue`, the waterline model, the two entry points, the reschedule toggle.
- [ ] **Step 3: Commit**

```bash
git add ops-software-bible/03_DATA_ARCHITECTURE.md ops-software-bible/07_SPECIALIZED_FEATURES.md
git commit -m "docs(bible): document task priority_rank + taskPriorityQueue scheduling"
```

> Note: the bible is a separate repo concern — commit on `main` per OPS branch-scope rules if it is not part of `ops-ios`. Confirm the bible's repo/worktree before committing.

### Task 18: Full verification

- [ ] **Step 1: Device-target build**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Full test suite (logic)**

Run: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:OPSTests/FractionalRankTests -only-testing:OPSTests/PriorityQueueSchedulingTests -only-testing:OPSTests/AutoScheduleManagerTests`
Expected: PASS.

- [ ] **Step 3: Manual end-to-end (sim, office/admin user)**
  - FAB → Prioritize: drag to reorder; cross the waterline both ways; PLACE NEXT; SCHEDULE ALL → preview → commit; confirm dates land on tasks and a notification appears.
  - JobBoard → TASKS → PRIORITIZE toggle: same list, inline.
  - Toggle RESCHEDULE SCHEDULED on with a scheduled task ranked → confirm dialog appears before commit.
  - Verify `priority_rank` round-trips to Supabase (MCP `execute_sql`).

- [ ] **Step 4: Final commit (if any cleanup)**

```bash
git add -A && git commit -m "chore(scheduling): final cleanup for task priority queue"
```

---

## Self-Review (completed during planning)

**Spec coverage:** §5 waterline → Tasks 8,10,16. §6 data → 1,3. §7 engine → 4,5,6. §8 UI → 8,9,10,12,13. §9 runs → 10,11. §11 reschedule/lock → 8,10. §12 permissions → 12,13. §13 haptics/notif/copy/motion → 14,15,16. §14 sync → 3,7. §16 bible → 17. §17 tests → 2,5,18. All covered.

**Placeholder scan:** No "TBD/TODO". The three "mirror the exact existing API" notes (sync enqueue in Task 7, `NotificationManager` call in Task 14, `TaskTypeDependency` init in Task 5) point to concrete existing code the engineer copies verbatim — flagged because the precise call shape must match live code, not be invented.

**Type consistency:** `priorityRank`/`priority_rank`, `taskPriorityQueue(orderedTaskIds:includeUnranked:)`, `placeNext`, `RunState`, `PlacedRecord`, `autoSchedulePriorityQueue`, `reorderPriority`/`bulkSetPriority`, `FractionalRank.between/normalize/needsNormalization`, `PriorityQueueViewModel`/`PriorityQueueView`/`PriorityQueueRow`/`PrioritySchedulePreviewSheet` — names consistent across all tasks.
