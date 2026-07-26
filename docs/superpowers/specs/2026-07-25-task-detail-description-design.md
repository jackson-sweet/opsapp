# Task Detail Description Design

## Intent

An owner or crew lead opens a task from Project Details to understand the work before acting. The half sheet stays action-first; expanding it should expose the complete task description without opening another screen. The result should feel like the same tactical task console gaining depth, not a second interface appearing.

## Evidence and root cause

- The live `project_tasks` schema stores task prose in `task_notes`; there is no separate task-description column.
- `TaskDetailPopupSheet` currently renders `taskNotes` only as an optional, unlabeled, three-line header preview.
- When `taskNotes` is empty, that view is omitted entirely.
- The sheet already supports medium and large detents, but changing detents does not add any content. The large sheet therefore cannot reveal a description area.
- The OPS Software Bible specifies an expandable task-notes card on task details.

## Layout exploration

### Variant 1 — Header expansion

Keep the description directly below the task title and remove the three-line limit.

- Benefit: smallest code change.
- Rejected: long field notes compete with status and completion controls in the compact detent.

### Variant 2 — Description inside the date/team card

Append a third row beneath TEAM.

- Benefit: compact grouping.
- Rejected: task prose is not scheduling or assignment metadata, and long text would distort an interactive card.

### Variant 3 — Separate description card after actions

Place description below SELECT/CANCEL.

- Benefit: actions remain immediately available.
- Rejected: the requested information still lands after destructive controls and may remain offscreen at the large detent.

### Variant 4 — Progressive detail card

Keep the header limited to identity and status. Place a dedicated description card after the date/team card and before task actions.

```text
┌──────────────────────────────┐
│ TASK TYPE     STATUS         │
│ TASK TITLE                   │
├──────────────────────────────┤
│ MARK COMPLETE                │
├──────────────────────────────┤
│ DATES                        │
│ TEAM                         │
├──────────────────────────────┤
│ // DESCRIPTION               │
│ Full task prose, or —        │
├──────────────────────────────┤
│ SELECT THIS TASK             │
│ CANCEL TASK                  │
└──────────────────────────────┘
```

- Recommended: expansion reveals the lower-detail layer naturally, the information hierarchy stays intact, and the card follows existing OPS mobile sheet patterns.

## Behavior

- Remove the truncated prose preview from the identity header.
- Always render one `DESCRIPTION` card in the scroll surface.
- Render trimmed `taskNotes` in full with no line limit.
- Render the OPS empty-state token `—` for nil, empty, or whitespace-only text.
- Keep both existing detents and native pan/scroll behavior.
- Keep selection, completion, scheduling, team assignment, and cancellation behavior unchanged.

## Design-system mapping

- Canvas and glass surface: existing `OPSStyle.Colors.background` and `.glassSurface()`.
- Description label: `OPSStyle.Typography.smallCaption` and `OPSStyle.Colors.tertiaryText`.
- Description body: `OPSStyle.Typography.body` and `OPSStyle.Colors.primaryText`.
- Empty value: same body role with `OPSStyle.Colors.tertiaryText`.
- Insets and gaps: existing `OPSStyle.Layout` spacing tokens only.
- No new color, font, radius, spacing, icon, motion, or touch-target values.

## Verification

- A focused unit test proves meaningful prose is trimmed and preserved.
- A focused unit test proves nil, empty, and whitespace-only values produce `—`.
- A rendering harness captures the real expanded-height sheet with long prose and with an empty description for visual inspection.
- A design-system audit checks the changed Swift file for hardcoded visual values.
