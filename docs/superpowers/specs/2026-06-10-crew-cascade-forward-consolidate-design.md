# Crew cascade — forward-only consolidate (bug efb57ffc)

**Status:** approved 2026-06-10 (owner sign-off in-session)
**Bug:** efb57ffc-826e-408a-ad4e-1a66ed8b48f9 — "Push quick-reschedule cascade ignores shared crew across jobs"

## Problem

Today's cascade is **dependency-based and single-project**: pushing a task only
moves tasks that *depend* on it (task-type dependencies) within the same project.
It never considers shared crew. If Charlie's Monday job slips, his Tuesday and
Wednesday jobs on *other* projects don't move — even though one person can't be
two places at once.

## Approved behavior — forward-only consolidate

When a task is pushed via an explicit **Cascade** action, the pushed task moves to
its new day, then every *other* active, unlocked task that **shares ≥1 crew member**
(across all projects, company-wide) **packs tightly forward** to close the gap the
push opens — but **no task is ever moved earlier than its current start**.

### Algorithm (`SchedulingEngine.calculateCrewConsolidation`)

1. `crew = pushedTask.schedulingTeamMemberIds`. If empty → no-op (only the existing
   dependency cascade runs).
2. **Candidates** = tasks where `id != pushedTask.id`, `schedulingIsActive`,
   shares ≥1 member with `crew`, and `startDate (start-of-day) >= pushedTask`'s
   **original** start. Ordered by current start, then displayOrder, then id.
   Locked tasks are kept in the timeline as **fixed obstacles** but never moved.
3. Place the pushed task at its new day (cursor = pushed new end).
4. Walk the moveable candidates in order. Each lands at
   `max(day-after-cursor, its-own-current-start)`, then bumped forward past any
   weekend (if the company skips weekends) and past any **locked** crew interval.
   `end = start + (duration − 1)`. Advance the cursor.
5. The `max(…, its-own-current-start)` clamp is the forward-only guarantee: jobs
   slide **later** to stay out of each other's way, but are **never pulled earlier**
   than where they already sit. Jobs far enough out that packing never reaches them
   don't move at all.

### Worked example

Charlie: A=Mon, B=Tue, C=Thu (gap Wed). Cascade-push **A +1**:
`A→Tue, B→Wed (fills the gap), C stays Thu, Fri freed.`
(Rigid would have shoved C to Fri; full-consolidate would have pulled C to Wed.
Forward-only does neither.)

## Rules

- **Trigger:** the explicit Cascade actions only (DayCanvas "+N Days" cascade items,
  the CalendarScheduler cascade toggle, the review-queue cascade). Plain +N/+1W
  buttons, swipe, and month-grid push stay single-task.
- **Direction:** cascade actions are all forward (+1/+2). A non-forward push (none
  exists in the cascade menu) does not ripple the crew.
- **Skips** locked (hand-edited) tasks — they stay put and act as obstacles the
  moved jobs pack around — and completed/cancelled tasks.
- **Cross-project:** evaluates the company's active tasks (the reporter's other jobs
  live on other projects).
- **Weekend-skip:** honored on every shifted start, like today's dependency cascade.
- **Collisions:** two **auto-moved** jobs can never land on the same day (sequential
  packing + locked-obstacle avoidance). The user's explicit push landing on a locked
  job is allowed (their choice).
- **Dependencies win when later:** the existing dependency cascade runs on top of the
  crew shifts (seeded), and can only push a task *further out*, never earlier — so no
  "can't start until X finishes" rule is violated.
- **Notifications:** every moved task pings its crew via the existing schedule-change
  path (`updateTaskSchedule(manualEdit: false)`), one push per moved task.

### Cross-project dependency boundary (known limitation)

The dependency cascade stays scoped to the **pushed task's project** (matching
predecessors by `taskTypeId` company-wide would create spurious cross-project
links). So a crew-shifted job on *another* project does not recursively cascade its
own in-project dependents. The reporter's scenario doesn't require it; documented
here as the intentional boundary for v1.

### Other known limitations

- **Merge reason fidelity.** When a task is crew-shifted *and then* pushed further
  by a dependency, the preview groups it under "Dependent tasks" (the binding
  constraint that determined its final date), not "Same crew". The date is correct;
  only the grouping reflects the last/binding cause.
- **Optimistic undo dates.** `undoCascade` restores each task to the start/end
  captured when the push was planned. If another client moves a cascaded task
  between the push and the undo, undo restores the pre-push date rather than the
  task's most-recent date. This is the pre-existing optimistic-undo contract (it
  predates the crew cascade and applies to the dependency cascade too); a
  conflict-aware undo is out of scope for this fix.

## Implementation surface

- `SchedulingEngine.swift` — `CascadeResult.TaskDateChange.reason` (`.crew` / `.dependency`);
  `calculateCrewConsolidation(...)`; `calculateCascade(..., seededDates:)` reads crew
  shifts as the baseline for dependency placement.
- `DataController.swift` — `getActiveTasksForCompany()` / `getCompanyTasks()`;
  `pushTaskWithCascade` captures original start, runs crew consolidation (forward
  pushes only) + dependency cascade, merges (dependency overrides crew when later),
  applies/​notifies across the company set; `undoCascade` restores across the company set.
- Preview/count call sites — `DayCanvasView`, `CalendarSchedulerSheet` (and the
  review-queue path) build the same company-wide candidate set so the preview matches
  the commit.
- `CascadePreviewSheet.swift` — a **"Same crew"** group distinct from the dependency
  group, driven by `reason`; copy via ops-copywriter; styling via existing OPSStyle tokens.
- Tests — `CrewCascadeTests` covering the reporter scenario, forward-only clamp,
  gap absorption, different-crew/locked/completed exclusion, weekend-skip, no-crew
  no-op, and dependency-overrides-crew.
