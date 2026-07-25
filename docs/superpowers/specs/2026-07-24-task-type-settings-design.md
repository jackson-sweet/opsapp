# Task Type Settings — Design Specification

**Date:** 2026-07-24
**Bug:** `9a00f447-c555-41f0-ae35-b9b5469d704b`
**Surface:** iOS Settings → Tasks

## Outcome

Make task-type administration fast enough to scan and safe enough to use on a live company with hundreds of tasks. The screen must stop presenting every task type as a large standalone card, remove the persistent bottom action bar, simplify creation, and expose task usage with selective bulk reassignment.

## Ground truth

- The active company has 12 task types and 294 non-deleted tasks.
- A single type owns as many as 101 tasks across 91 projects.
- Every current type is in use, so usage management is a primary workflow rather than an edge case.
- Existing merge code changes only the SwiftData relationship. It leaves `taskTypeId` and `taskColor` stale, then deletes the source type.
- Live data already contains non-deleted tasks pointing at soft-deleted task types. The redesign must repair the write invariant rather than reuse the unsafe merge implementation.

## Operator job

The operator enters this surface to do one of three things:

1. Find a task type and inspect or edit it.
2. Add a task type.
3. See which tasks use a type and move some or all of them to another type.

Identity editing is frequent and simple. Dependency, product, and template configuration is advanced. Destructive merge/delete is exceptional.

## Explored layouts

### A. Compact rows with a permanent footer

The list becomes denser, but the footer still consumes prime space and duplicates the add action. Rejected.

### B. Compact rows with a floating add button

The list gains room, but a floating control obscures rows and competes with the app’s existing action grammar. Rejected.

### C. Compact grouped list with header and terminal add actions

One L1 surface contains 56pt task-type rows separated by inset hairlines. A 44pt add button sits in the top-right header and `ADD TASK TYPE` is the final row. The persistent footer disappears. Selected.

### D. Search-first task-type index

Useful at much larger scale, but unnecessary at 12 types and more cognitively expensive than direct scanning. Deferred by omission, not by incomplete implementation.

## Selected layout

### Task Types index

- Custom types first, defaults second, preserving existing ordering.
- One grouped L1 glass surface; no glass-per-row nesting.
- Each 56pt row contains:
  - a compact color marker;
  - sentence-case type name;
  - `DEFAULT` when applicable;
  - a monospaced active-task count;
  - a chevron.
- All rows open. Default rows open read-only identity controls while preserving task usage management.
- Header trailing action: 44×44 plus button, accessibility label `Add task type`.
- Last row: `ADD TASK TYPE`.
- No fixed bottom action bar.
- Long-press actions remain supplemental, not the only discoverable route.
- A fetch failure remains distinct from a legitimate empty company so the UI never invites duplicate defaults after a read error.

### Create / edit sheet

The form is reordered by frequency:

1. **Identity** — name and selected color.
2. **Tasks using type** — edit mode only; count, short task preview, and `MANAGE TASKS`.
3. **Workflow** — dependencies.
4. **Catalog links** — products and default sub-tasks.
5. **Destructive actions** — custom types only.

The oversized preview card is removed. The 35-color palette moves behind a compact color row into a dedicated picker sheet. Dependencies, products, and sub-tasks start collapsed. Create mode therefore opens as a short identity form rather than a configuration wall.

Default types:

- identity fields and save action are read-only;
- usage and reassignment remain available;
- merge and delete remain unavailable.

### Task usage manager

`MANAGE TASKS` opens a dedicated sheet for the selected type.

- Header reports the type and active count.
- Rows show task title, project/client context, status, and a 44pt selection control.
- `SELECT ALL` and `CLEAR` are explicit.
- A contextual bottom action appears only when selection is non-empty.
- `REASSIGN N` opens a target picker containing every other non-deleted type in the same company.
- Confirmation names the source, target, and task count.
- Reassignment never deletes the source type.
- After completion, the usage list and parent count update immediately.

At 101 tasks, the manager scrolls rather than attempting to render every task inside the editor.

## Data contract

For every selected non-deleted task:

- task company must equal source and target company;
- the task’s scalar `taskTypeId` must equal the source id at commit time;
- the task relationship must resolve to the source or be safely repairable from the scalar id;
- source and target ids must differ;
- target must be non-deleted.

A successful local reassignment updates all three representations atomically before saving:

- `task.taskTypeId = target.id`
- `task.taskType = target`
- `task.taskColor = target.color`

It also:

- sets `needsSync = true`;
- appends one durable `taskTypeMutation` command in the same SwiftData transaction;
- includes source, target, selected task ids, and an idempotency key;
- sends no independent per-task writes;
- triggers one background drain after the batch.

Invalid or stale selections fail before any mutation. Deleted tasks are excluded from usage and bulk operations.

The server executes selective reassignment in one Postgres transaction. It locks and revalidates every selected row, mirrors the current task-edit permission policy, updates id and color together, and reconciles type-driven reminders. A stale or unauthorized member rolls back the entire command. Replaying the idempotency key returns the original result.

The merge flow uses a separate all-or-nothing command because the phone may not cache every live reference. The server moves all non-deleted tasks plus mutable product, template, recurrence, and dependency references, retires source reminder templates, and soft-deletes the source last. Existing immutable estimate/invoice line items remain frozen. A source type may be deleted only after a fresh scalar check confirms no mutable live reference remains.

The pre-existing tasks that already reference deleted types are an independently discovered legacy defect. This bug adds guards against creating more; it does not silently backfill those rows.

## Offline and failure behavior

- Reads remain SwiftData-first.
- Reassignment completes locally while offline and queues one durable command.
- A local save or validation failure leaves all selected tasks on the source type and surfaces one concise error.
- A later sync failure keeps the command visible through existing pending-work recovery.
- No remote per-task loop blocks the UI.

## Accessibility

- Every interactive target is at least 44pt.
- Color is never the only signal; names, counts, selection glyphs, and labels carry state.
- Add, select, clear, manage, and reassign controls have explicit accessibility labels and values.
- Counts use tabular monospaced numerals.
- No new animation is introduced.

## Copy

- `TASK TYPES`
- `ADD TASK TYPE`
- `TASKS USING TYPE · N`
- `MANAGE TASKS`
- `SELECT ALL`
- `CLEAR`
- `REASSIGN N`
- `MOVE N TASKS?`

Copy stays terse, literal, and action-led. Destructive merge copy remains explicit that the source type will be deleted; ordinary reassignment never uses “merge.”

## Acceptance

- Twelve types fit as a readable grouped list without a permanent bottom bar.
- Add is reachable from the header and the end of the list.
- Create mode initially shows only the identity decision.
- Editing any type exposes its active usage, including defaults.
- An operator can reassign one, many, or all active tasks to another type.
- After reassignment, relationship, scalar id, color, and the single queued command agree.
- A server-side stale selection or permission failure changes no rows.
- Merge cannot delete a source while an active task still references its scalar id.
- Focused unit tests, iPhone 17 simulator tests, and a generic-device build pass.
- 390×844 visual proof passes the OPS mobile design audit.
