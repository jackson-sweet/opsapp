# Shared Project Task Composer Design

## Outcome

Project Form and Projects Needing Tasks use the same task-adding element. Suggested tasks add with one tap, manual entry has full-width controls, and every added task remains visible for later editing or deletion.

## User And Context

The operator is an owner or office lead working quickly on an iPhone, often between job-site interruptions. The primary action is to give a project a usable task plan without opening a chain of nested forms. The interface should feel compact while scanning and uncramped while editing.

## Layout Variants Considered

### 1. Dense single row

Keep task type, crew, date, edit, and delete in one horizontal line. This is compact but repeats the current failure: labels truncate and touch targets compete for width.

### 2. Always-open task cards

Render every task as three stacked full-width fields. This is clear but becomes too tall as soon as a project has several tasks.

### 3. Separate task editor sheet

Keep compact rows and open a half sheet for every add or edit. This gives fields room but weakens the visual relationship to the project and recreates modal-on-modal friction in Project Form.

### 4. Persistent list with inline expansion

Show suggested tasks first, then persistent two-line task summaries. Only the new or edited task expands into full-width controls. This keeps the list compact, preserves project association, and gives the active task enough room. Selected.

## Component

`ProjectTaskComposer` owns the visible interaction and binds to `[LocalTask]` supplied by its parent.

- Suggested cards show task type and suggested active crew. One tap commits the task and moves it into the task list.
- Added tasks render as compact summaries with task type, crew, and schedule metadata.
- Tapping a summary opens a full-width editor for that task.
- `ADD TASK` opens the same editor with a blank draft.
- The editor uses three stacked selector rows: task type, crew, and schedule.
- `ADD` or `SAVE` commits through an async parent callback. `DELETE` uses a separate async callback.
- Only one task can be edited at a time.

Project Form uses local callbacks, so task changes remain staged until the project is saved. Projects Needing Tasks uses persistence callbacks, so each add, edit, or delete is written immediately while the task remains visible in the card.

## States

- Empty: suggestions when available, plus `ADD TASK`.
- Saving: active commit button disabled with an inline progress indicator.
- Error: concise inline error above the editor actions; the draft remains intact.
- Offline: existing DataController queue behavior remains authoritative; the composer does not add a second sync model.
- Success: committed task appears in the persistent list and remains editable.

## Design System

- `OPSStyle.Colors.background`, `surfaceInput`, `line`, `text`, `text2`, `text3`, `oliveTextM`, and semantic error/destructive tokens.
- `OPSStyle.Layout` spacing, touch targets, radii, borders, and icon sizes only.
- `OPSStyle.Typography` roles only; no raw font sizes.
- SF Symbols through `OPSStyle.Icons`.
- L2 nested surfaces for suggestion cards, summary rows, and the active editor. No shadows or decorative color.
- Minimum 44pt controls; primary selector rows target 56pt.

## Copy

Authority labels remain terse: `// SUGGESTED`, `// TASKS`, `ADD TASK`, `ADD`, `SAVE`, `CANCEL`, `DELETE`, `UNASSIGNED`, and `NOT SCHEDULED`.

## Acceptance Criteria

1. Both target screens render `ProjectTaskComposer`.
2. Suggestions include the proposed crew and add in one tap.
3. Added tasks remain in the list after add.
4. Added tasks can be reopened, edited, and deleted.
5. Manual fields use full-width stacked controls.
6. Project Form still stages tasks until project save.
7. Projects Needing Tasks persists each task mutation and keeps the project card open until `DONE`.
8. All new visual values use OPS tokens and meet mobile touch requirements.
