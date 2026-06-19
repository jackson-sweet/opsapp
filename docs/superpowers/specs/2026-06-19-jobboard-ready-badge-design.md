# JobBoard "READY" task badge — design (item ba35b7c0)

## Problem

A crew member (e.g. Jake) opens his task list. Some of his tasks can't start
yet because a predecessor is unfinished — Jake's "rail" task waits on the
"vinyl" task. Today nothing tells him which of his tasks are actually
actionable, so he either guesses or pings the office. The request: badge a task
**READY** once its predecessor tasks are complete.

## The "ready" rule

A task is **ready to start** (`ProjectTask.isReadyToStart`) when ALL of:

1. `status == .active` — open work, not done/cancelled.
2. It declares dependencies — `effectiveDependencies` is non-empty (per-task
   override JSON, else the task type's `dependencies`).
3. Predecessor tasks of those dependency types **exist on the same project**
   (non-deleted, non-cancelled). If none exist, nothing was ever blocking, so
   there's nothing to "unblock" → not ready (no badge).
4. **Every** such predecessor task is `completed`.

When any condition fails, the task shows no badge. READY therefore means
exactly "the work blocking this is done — go," never decoration on every row.
We deliberately do **not** add a "WAITING/BLOCKED" badge: absence of READY plus
visible incomplete predecessors already communicates that, and labelling every
state clutters the scan surface (ruthless omission).

## Placement

- **My Tasks list** (`JobBoardMyTasksView`) — the surface in the request. Each
  task renders via `UniversalJobBoardCard(cardType: .task)`, so the badge goes
  in that card's badge overlay (one change covers the list).
- **Project details task rows** (`DetailsTabView.TaskListSection`) — same badge,
  for consistency wherever a task is listed with its status.
- **Kanban** renders *project* cards (`UniversalJobBoardCard(.project)`), not
  tasks, so a per-task READY badge does not apply there — out of scope.

## Component

`TaskReadyBadge` — a small text-only chip ("READY", `successStatus` green = go),
styled to match the existing task status / UNSCHEDULED badges (smallCaption,
0.1 fill, hairline stroke). Text-only, no decorative icon, per the design
system.

## Task-type ownership — assessed, out of build scope

The request also floats "let a team member own a task type." Task types already
carry `default_team_member_ids` (synced; in `validTaskTypeColumns`), which is
the working form of ownership: a task of that type can default-assign those
members. Building a parallel ownership model would duplicate this. Recommended
path: lean on `default_team_member_ids`. The net-new value the request is
really after — knowing which of *my* tasks are go-now — is delivered by the
READY badge. No new ownership model in this change.

## Permissions / data

Read-only derivation over already-synced data (`ProjectTask`, `TaskType`). No
schema change, no migration, no permission gate (it reflects the user's own
visible tasks). No notification (no async event).
