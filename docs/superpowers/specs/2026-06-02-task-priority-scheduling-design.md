# Task Priority Queue + Auto-Schedule — Design Spec

- **Date:** 2026-06-02
- **Surface:** iOS app (`ops-ios`). Web parity is a later phase — see §15.
- **Status:** Approved design, pending implementation plan.
- **Branch:** `feat/task-priority-scheduling`

---

## 1. Summary

Give the operator one place to **rank active tasks by priority** (drag-to-reorder, persisted) and then **auto-schedule them in that order** — all at once (preview → commit) or one at a time (tap-to-place). The ranking is a persistent attribute that also drives task sorting elsewhere and syncs to the backend (and, later, the web app).

**This feature does not rebuild scheduling.** It calls the existing `AutoScheduleManager` engine and makes exactly one adjustment to it: the order in which it considers candidate tasks is driven by the user's manual priority instead of the automatic project priority-date. All placement intelligence (dependency floor, crew-availability slotting, geographic-grouping suggestions, gap metadata) is invoked, not reimplemented.

---

## 2. Goal & non-goals

**Goal:** Let an office/admin operator express "do these in this order" and have the existing scheduler place them accordingly, respecting dependencies and crew availability.

**Non-goals (explicitly out of scope):**
- Rebuilding or replacing any part of the scheduling engine.
- **Proximity / route re-sequencing of the unranked tail.** The engine today *suggests* per-task geographic alternatives (Pass 3) and *sums* gap days (Pass 4); it does **not** globally re-order tasks by proximity. Building that is net-new optimizer work and is deferred until explicitly requested.
- The web prioritize UI (the Supabase column + sync land now for forward-compatibility; the web screen is a separate phase).
- Per-crew priority lists (priority is one global company-wide ranking — see §4).

---

## 3. Current state (what already exists — do not rebuild)

Verified by reading the code:

| Concern | Reality | Reference |
|---|---|---|
| Scheduling engine | Full engine: single-task, project-batch, multi-project-batch; 4 passes (dependency floor → crew slotting → geographic alternative → gap calc) | `OPS/Utilities/AutoScheduleManager.swift` |
| Engine I/O types | `ScheduleRequest.Mode` (`single` / `projectBatch` / `multiProjectBatch`), `ScheduleConstraints`, `SchedulePlan`, `TaskPlacement`, `ScheduleDataProvider` | `OPS/Utilities/ScheduleTypes.swift` |
| Engine entry (DataController) | `autoScheduleSingleTask` (6463), `autoScheduleProjectV2` (6478), `autoScheduleProjects` / multiProjectBatch (6489), `priorityDateForProject` (6421), `buildScheduleConstraints` (6458), `updateTaskSchedule` (3837), `allScheduledTasksForMembers` (6409) | `OPS/Utilities/DataController.swift` |
| Batch ordering today | `scheduleBatch` sorts **projects** by `priorityDateForProject` (won-date → estimate-approved → created), then topo-sorts tasks within each project | `AutoScheduleManager.swift:180` |
| Single-task auto-schedule (wired) | Swipe-card review (`autoScheduleTask` → `autoScheduleSingleTask`) and task form | `UnscheduledTaskReviewView.swift:880`, `TaskFormSheet.swift:1460` |
| Multi-project batch | Method exists, **not wired to any UI** | `DataController.autoScheduleProjects` |
| `SchedulableTask` protocol | `id, taskTypeId, startDate, endDate, duration, effectiveDependencies, displayOrder, schedulingTeamMemberIds, schedulingProjectId, schedulingLocked` | `SchedulingEngine.swift:15` |
| `ProjectTask` conformance | `extension ProjectTask: SchedulableTask {}` | `ProjectTask.swift:349` |
| Topological sort | `static func topologicalSort(tasks:) -> [any SchedulableTask]` | `SchedulingEngine.swift:229` |
| `AutoSchedulePreviewSheet` | Built against the **legacy** `SchedulingEngine.AutoScheduleResult` and **never presented anywhere** — dead code to replace | `OPS/Views/Components/Scheduling/AutoSchedulePreviewSheet.swift` |
| Office/admin company task list | TASKS section (`JobBoardTasksView`) shows all active company tasks with filters + an action row | `JobBoardView.swift:283` (section), `:682` (view), `:182` (action row) |
| Field-crew task list | `JobBoardMyTasksView` (per-user, assigned-to-me) | `JobBoardMyTasksView.swift` |
| FAB | Office/Admin only (`canShowFAB`); grouped items; SCHEDULING group at `:557`; each item opens a sheet/full-screen | `FloatingActionMenu.swift` |
| Migrations | Staged `SchemaMigrationPlan` (V1–V8, latest **V8**, mostly `MigrationStage.lightweight`) | `OPS/DataModels/Migrations/OPSMigrationPlan.swift` |
| Task sync | `TaskRepository` + `project_tasks` DTOs; dirty-flag (`needsSync`) outbound | `OPS/Network/Supabase/Repositories/TaskRepository.swift` |

> The Software Bible currently documents scheduling as "entirely manual." That is **out of date** — the engine above is live. The bible must be corrected as part of this work (§16).

---

## 4. Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Unit of prioritization | **Tasks** (flat, cross-project) | User choice. |
| Persistence | **Persistent** `priorityRank` on the task, synced | User choice; "drives sorting elsewhere." |
| Scope of priority | **One global company-wide ranking** | One source of truth; filters focus the view without changing the global rank. |
| List population | **All active tasks**, with an opt-in to also reschedule already-scheduled ones (behind a confirm) | User choice. |
| One-at-a-time | **Tap-to-place, no per-item confirm** | Low-friction; mirrors the swipe-card flow. |
| Batch run | **Preview → confirm** | Safe for a bulk action that can move many dates. |
| Code structure | **Shared core** `PriorityQueueView` + view-model, two thin entry points | No duplicated reorder/schedule logic (perfection standard). |
| Engine integration | **Adjust candidate ordering only** — a priority-ordered front door into the existing placement machinery | "Call the engine, don't rebuild it." |
| Rank storage | **`Double` fractional rank + normalize pass** | One drag = one dirty row = one sync; SQL/SwiftData-sortable; conflict-tolerant under offline-first LWW. Linked-list rejected (corrupts under concurrent sync; not query-sortable). |
| Unranked + include | **INCLUDE UNRANKED toggle**; when on, unranked tail scheduled **after** the ranked zone in default (latest-edited) order using the existing engine | User choice; no new proximity optimizer (§2). |
| Entry points | **FAB "Prioritize"** (full-screen) + **JobBoard TASKS "PRIORITIZE" toggle** (inline) | User choice. |
| Permissions | `tasks.edit` + office/admin | Matches TASKS section + Unassigned Review gating. |

---

## 5. The waterline model

One vertical list of all active company tasks, split by a **draggable `UNRANKED` divider** (the "waterline"):

- **Above the waterline = ranked.** Ordered by `priorityRank` ascending (lower = higher priority). User-controlled, persisted.
- **Below the waterline = unranked.** `priorityRank == nil`. Shown in a stable default sort (latest-edited). Not yet prioritized.
- **Drag a task across the divider** → rank it (assign a fractional rank between its new neighbors) or unrank it (`priorityRank = nil`).
- **Drag the divider itself** → bulk operation: every row the divider sweeps past flips ranked↔unranked. Dragging the divider **down** ranks the swept unranked tasks in their current displayed order; dragging it **up** unranks the swept ranked tasks.
- The divider is also the **schedule cutoff**: the runner places the ranked zone top-to-bottom. Unranked tasks are scheduled only when **INCLUDE UNRANKED** is on (then appended after the ranked zone in default order).

Already-scheduled active tasks appear inline with a "scheduled" badge wherever their rank (or lack of it) places them; their interaction is governed by §11.

---

## 6. Data model changes

### 6.1 SwiftData (`ProjectTask`)
Add:
```swift
/// Global company-wide manual priority. Lower = higher priority.
/// nil = unranked (below the waterline). Fractional indexing: a moved task
/// receives a value strictly between its new neighbors so one reorder dirties
/// one row. Normalized (re-spaced) when neighbor gaps get too small.
var priorityRank: Double?
```
- Default `nil` (new tasks are unranked).
- Ranked sort: `priorityRank` ascending, ties broken by `id` (stable, conflict-safe).

### 6.2 Migration
- **No new `VersionedSchema` or `MigrationStage` is required.** `priorityRank` is an optional property on the **live** `ProjectTask` (referenced by V4–V8 via `OPSSchemaCommon.v4TaskModels`). SwiftData lightweight auto-migration adds the nil column to existing stores on next open.
- Verified against git history: prior optional-property additions to live `ProjectTask` (commits `5d5800b0`, `8fe1e39d`, `ef1ce63b`) shipped with **zero** migration-file changes. The schema chain (V1–V8) is minted only for new *model types* (reminders, forecast, vinyl marker, catalog units), not for new properties. Do **not** add `OPSSchemaV9` for this.
- The frozen `OPSSchemaLegacyTaskModels.ProjectTask` (V1–V3 snapshot) is intentionally left unchanged.

### 6.3 Supabase
- New column `project_tasks.priority_rank double precision NULL`.
- Index: `CREATE INDEX idx_project_tasks_priority ON project_tasks (company_id, priority_rank) WHERE deleted_at IS NULL;`
- Add `priority_rank` to the `project_tasks` task DTO/coding keys used by `TaskRepository` (inbound + outbound). Confirm exact column type against the live schema via Supabase MCP before applying (per OPS precision rule).
- `updated_at` is server-maintained; the reorder write bumps `needs_sync` and flows through the existing outbound path.

### 6.4 Fractional indexing helper
A small pure helper (unit-tested):
- `rankBetween(_ lower: Double?, _ upper: Double?) -> Double` → midpoint; `lower+1`/`upper-1` at the ends; `0` for an empty list.
- `normalizeRanks(_ orderedIds: [String]) -> [String: Double]` → re-spaces all ranked tasks to evenly spaced values (e.g. `1024, 2048, …`) when any neighbor gap drops below an epsilon. Returns the rewritten ranks (a bounded multi-row write — rare).

---

## 7. Engine adjustment (the one change)

### 7.1 Refactor for reuse (no behavior change)
Extract the existing per-task placement body in `scheduleBatch` — Pass 1 floor, Pass 2 slot, Pass 3 alternative, Pass 4 bookkeeping, `placedTasks` virtual-commitment tracking — into a private shared helper, e.g.:
```swift
private static func placeNext(
    _ task: any SchedulableTask,
    anchor: Date,
    constraints: ScheduleConstraints,
    provider: ScheduleDataProvider,
    knownProjectTasks: [any SchedulableTask],
    placed: inout [PlacedRecord],   // existing tuple type, named
    conflicts: inout [ScheduleConflict],
    warnings: inout [String]
) -> TaskPlacement
```
The existing `scheduleBatch` is rewritten to call `placeNext`. **Existing tests for batch/single/multi must continue to pass unchanged** — this is a pure extraction.

### 7.2 New front door
`ScheduleTypes.swift`:
```swift
enum Mode {
    case single(task: any SchedulableTask, teamMemberIds: Set<String>)
    case projectBatch(projectId: String)
    case multiProjectBatch(projectIds: [String])
    case taskPriorityQueue(orderedTaskIds: [String], includeUnranked: Bool)   // NEW
}
```
`ScheduleDataProvider` gains a resolver so the engine stays pure (ids in, plan out):
```swift
func schedulableTasks(forIds ids: [String]) -> [any SchedulableTask]      // NEW
func unrankedActiveSchedulableTasks() -> [any SchedulableTask]            // NEW (for includeUnranked)
```
(DataController implements both from its SwiftData store.)

### 7.3 Priority-respecting topological traversal
`AutoScheduleManager.schedulePriorityQueue(...)`:
1. Resolve `orderedTaskIds` → candidate tasks in **priority order**. If `includeUnranked`, append `unrankedActiveSchedulableTasks()` (default latest-edited order).
2. Filter the candidate set by the reschedule policy (§11): default keeps only tasks with no dates; when "reschedule scheduled" is on, also include scheduled tasks where `!schedulingLocked`.
3. Traverse with a **ready-set + priority** rule (standard list scheduling):
   - A task is *ready* when every predecessor (same project, matched by `effectiveDependencies` → `taskTypeId`, existing logic) is either already placed in this run or already has fixed dates outside the candidate set.
   - Among ready tasks, pick the one with the **lowest priority index** (its position in the candidate order). Place it via `placeNext`. Repeat.
   - If no task is ready (cycle / predecessor missing), fall back to placing the remaining candidates in priority order — `calculateDependencyFloor` already degrades gracefully when a predecessor has no `startDate`.
   This guarantees **dependencies first, priority among the feasible set** — priority never breaks a dependency.
4. Tasks **not** in the candidate set (unranked when toggle off, or `scheduleLocked`, or out-of-scope) are fed as virtual commitments via the existing `allScheduledTasksForMembers`, so the engine routes around them — unchanged behavior.
5. Return the standard `SchedulePlan` (placements + conflicts + metadata). No new output types.

### 7.4 DataController entry
```swift
func autoSchedulePriorityQueue(orderedTaskIds: [String], includeUnranked: Bool,
                               anchorDate: Date = Date()) -> SchedulePlan
```
Builds the `ScheduleRequest` with `buildScheduleConstraints()` and calls `AutoScheduleManager.schedule`. One-at-a-time continues to call the **existing** `autoScheduleSingleTask` per tap.

---

## 8. UI architecture

### 8.1 Shared core
- **`PriorityQueueViewModel`** (`@MainActor`, `ObservableObject`): owns the ordered task list, the waterline index, the toggles (`includeUnranked`, `rescheduleScheduled`), drag-reorder → rank writes (via `DataController.reorderPriority`), and the schedule actions. No view logic in DataController; no scheduling logic in the view.
- **`PriorityQueueView`**: the list + waterline + run controls. Used in two host contexts (full-screen and inline) via a `displayMode` parameter; the body is identical.
- **`PriorityQueueRow`**: one task row — drag handle, task title + project, crew avatars, scheduled badge/date if any, conflict badge (e.g. "no crew"). Reuses existing styling tokens (`OPSStyle`) and, where practical, the visual language of `UniversalJobBoardCard` without inheriting its swipe behavior.

### 8.2 Drag-to-reorder
- Use SwiftUI `List` + `.onMove` in an `EditMode`-style reorder, OR the established custom `DragGesture` + offset pattern already used in `FloatingActionMenu` (`commitItemReorder`/`itemVisualOffset`) if `List` styling can't match the card design. Decide during implementation; default to the native `.onMove` for reliability and pick the custom pattern only if the card visuals require it.
- On drop: compute `rankBetween(neighborAbove, neighborBelow)`, write via `DataController.reorderPriority(taskId:newRank:)` (sets `priorityRank`, `needsSync`). Crossing the waterline sets/clears the rank. Dragging the divider performs the bounded bulk rewrite.
- Drag-reorder is the **sanctioned exception** to the no-spring/no-bounce motion rule (per root CLAUDE.md). Final motion designed via `animation-studio:animation-architect` → `ios-animations`.

### 8.3 DataController reorder API
```swift
func reorderPriority(taskId: String, newRank: Double?) // single move / cross-waterline
func bulkSetPriority(_ ranks: [String: Double?])        // divider sweep + normalize
```
Both mark affected tasks `needsSync` and persist.

### 8.4 Entry point — FAB
Add a `FABMenuItem` `id: "prioritize"` to the **SCHEDULING** group in `FloatingActionMenu.menuGroups` (`:557`), `permission: "tasks.edit"`, presenting `PriorityQueueView(displayMode: .fullScreen)` as a `.sheet`/full-screen cover. Respects the existing customize/hide/reorder FAB machinery automatically.

### 8.5 Entry point — JobBoard TASKS toggle
In `JobBoardView`, add a **`PRIORITIZE`** toggle button to the action row (`:182`), shown only when `selectedSection == .tasks` and `permissionStore.can("tasks.edit")`. When on, the `.tasks` branch renders `PriorityQueueView(displayMode: .inline)` instead of `JobBoardTasksView`'s sorted card list. The existing filter chips (status / task type / team member / search) **focus the view** (which tasks are visible) without changing the global rank — dragging a filtered subset still writes global fractional ranks relative to the full list.

---

## 9. Run modes

### 9.1 Schedule all → preview → commit
- Button **`SCHEDULE ALL`** → `dataController.autoSchedulePriorityQueue(orderedTaskIds:includeUnranked:anchorDate:)` → `SchedulePlan`.
- Present a **new** `PrioritySchedulePreviewSheet` (replacing the dead `AutoSchedulePreviewSheet`), built against `ScheduleTypes.TaskPlacement`:
  - Anchor-date picker ("Starting from").
  - Ordered placement rows: task name, project, proposed dates, crew; conflict rows flagged (e.g. "no crew assigned — scheduled on earliest valid day").
  - Metadata footer: total gap days, proximity suggestions count.
  - Per-task geographic *alternative* surfaced as an optional hint (from Pass 3) — informational only.
- **Commit** writes every placement via the existing `DataController.updateTaskSchedule(task:startDate:endDate:manualEdit:)` (so cascade/locking semantics are consistent), inside one batched save → single sync wave. Success haptic + a notification (§13).

### 9.2 One at a time → tap-to-place
- Primary control schedules the **top unscheduled task in the ranked zone** via the existing `autoScheduleSingleTask`, writes immediately (no confirm), advances. Each tap = medium haptic. Continue down the ranked zone (then into unranked if INCLUDE UNRANKED is on).
- No new engine path — this is the existing single-task flow driven from the queue.

### 9.3 Include unranked
- `INCLUDE UNRANKED` toggle on the runner. Off: ranked zone only. On: the candidate set extends into unranked tasks (default order); the engine places them after the ranked zone using its existing per-task behavior. No proximity re-sequencing (§2).

---

## 10. Failure / edge handling

- **No crew on a task:** existing engine behavior — placed on the dependency floor with a `noCrewAssigned` conflict; surfaced in the preview and as a row badge. Not blocked (consistent with tap-to-place ethos).
- **No valid slot within 365 days:** existing fallback returns the start date; surfaced as a conflict.
- **Cycle / missing predecessor:** traversal falls back to priority order; floor logic degrades gracefully.
- **Empty ranked zone:** `SCHEDULE ALL` disabled; copy explains drag tasks above the line (or enable INCLUDE UNRANKED).
- **Precision exhaustion:** `normalizeRanks` re-spaces; bounded multi-row write, rare.
- **Concurrent reorder (two devices/users):** independent ranks → at worst a transient debatable order between two tasks, resolved by id tiebreak; self-heals on next drag. No structural corruption.

---

## 11. Already-scheduled tasks & the reschedule toggle

- Default: already-scheduled active tasks are **locked commitments** — shown with a scheduled badge, excluded from the candidate set, fed to the engine as virtual commitments so new placements route around them.
- **`RESCHEDULE SCHEDULED`** toggle: includes already-scheduled active tasks in the candidate set **except** those with `schedulingLocked == true` (manual edits are never auto-moved).
- Before committing a batch that would move any already-scheduled task, show a **confirmation dialog**: "This moves N already-scheduled tasks." Tap-to-place on a single already-scheduled task likewise confirms once for that task.

---

## 12. Permissions

- Gate the FAB item, the JobBoard toggle, and all schedule actions on `permissionStore.can("tasks.edit")`.
- Both host surfaces are already office/admin-only (FAB `canShowFAB`; TASKS section via `job_board.manage_sections`), so field crew never see this.

---

## 13. Cross-cutting

- **Haptics (mandatory):** light on drag pickup; medium on drop / each tap-to-place; success notification on Schedule-All commit. No haptic spam.
- **Notification rail:** on a committed batch schedule, create a standard notification ("Scheduled N tasks") with an `actionUrl` to the schedule/calendar — per the OPS notification system. Long single-tap-to-place runs do not each notify.
- **Copy:** every label, toggle, empty state, dialog, and notification string is **placeholder** here and must be written via `ops-copywriter` before ship (terse/tactical OPS voice; UPPERCASE authority labels, sentence-case content, no emoji, formatted numbers).
- **Motion:** drag-reorder, waterline sweep, and the "task lands on its date" preview feedback designed via `animation-studio:animation-architect` then `ios-animations`. One easing curve; honor reduced-motion; bounce only on the reorder drag.
- **Numbers/format:** JetBrains Mono tabular for any counts/dates per design system.

---

## 14. Sync

- Reorder/normalize writes set `needsSync` and flow through the existing `TaskRepository` outbound path; `priority_rank` added to the DTO mapping (§6.3).
- Inbound: `priority_rank` hydrated onto `ProjectTask` on pull.
- Schedule commits reuse `updateTaskSchedule` → existing dirty/sync semantics; no new sync surface.

---

## 15. Web parity

- The Supabase column + iOS sync mapping ship **now** so ranks persist and round-trip, and so the web app is forward-compatible (it can read/sort by `priority_rank` immediately).
- The **web prioritize UI** is a **separate later phase** (user: "start with iOS"). Out of scope here beyond the column.

---

## 16. Software Bible updates (same session as implementation)

- Correct the "scheduling is entirely manual" claim — document the live `AutoScheduleManager` engine and its modes.
- Add a **Task Priority & Auto-Schedule** section: the `priorityRank` field, the waterline model, the `taskPriorityQueue` mode, the two entry points, the reschedule toggle.
- Update the `project_tasks` schema doc with `priority_rank`.

---

## 17. Testing

- **Engine (unit, `OPSTests/AutoScheduleManagerTests.swift` style with `MockTask`/mock provider):**
  - `placeNext` extraction is behavior-preserving — existing batch/single/multi tests still green.
  - `taskPriorityQueue`: places ranked tasks in order; dependency-respecting traversal schedules a predecessor before a higher-ranked successor; crew-availability slotting around virtual commitments; `scheduleLocked` never moved; `includeUnranked` appends the tail; no-crew conflict surfaced.
- **Fractional indexing (unit):** `rankBetween` end/middle/empty; repeated midpoint inserts trigger `normalizeRanks`; tie-by-id ordering.
- **Migration:** none required (lightweight auto-migration). A model test asserts `priorityRank` defaults `nil` and round-trips; manual check that a pre-existing store opens clean after the property add.
- **View (snapshot, per the SwiftUI ImageRenderer harness):** ranked + unranked + waterline; scheduled badges; conflict badges; empty ranked zone.
- **DataController:** `reorderPriority` / `bulkSetPriority` set ranks + `needsSync`; `autoSchedulePriorityQueue` returns a plan and commit writes dates.

---

## 18. Build sequence (high level — detailed plan via writing-plans)

1. **Data + sync:** `priorityRank` on `ProjectTask` (no schema-version bump), Supabase column + index, DTO + converter + `validProjectTaskColumns` mapping (mirror `display_order`), fractional-index helper (+ tests).
2. **Engine:** extract `placeNext` (behavior-preserving, tests green), add `taskPriorityQueue` mode + provider resolvers + `DataController.autoSchedulePriorityQueue` (+ tests).
3. **Reorder API:** `reorderPriority` / `bulkSetPriority` + normalization (+ tests).
4. **Shared core UI:** `PriorityQueueViewModel`, `PriorityQueueView`, `PriorityQueueRow`, waterline, drag-reorder.
5. **Runner:** `PrioritySchedulePreviewSheet` (replaces dead `AutoSchedulePreviewSheet`), Schedule-All commit, tap-to-place, INCLUDE UNRANKED, reschedule toggle + confirm.
6. **Entry points:** FAB "Prioritize" item; JobBoard TASKS "PRIORITIZE" toggle.
7. **Cross-cutting:** copy (ops-copywriter), motion (animation-architect), haptics, notification.
8. **Bible** updates; snapshot/integration verification on device-target build.

---

## 19. Open items to confirm during implementation

- Exact `project_tasks` column type/constraints against the live Supabase schema (via MCP) before migration.
- Native `List`/`.onMove` vs. the custom FAB-style drag pattern for the reorder gesture (pick by which matches the card visuals without sacrificing reliability).
