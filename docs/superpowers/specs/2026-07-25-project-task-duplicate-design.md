# Project Task Duplicate — Design

## Intent

A field or office operator should be able to repeat an existing project task
from the long-press menu they already use, without re-entering its work
definition and without creating a hidden double-booking.

The interaction stays terse and native:

1. Long-press a task in Project Details.
2. Choose `Duplicate Task`.
3. OPS creates the copy immediately, selects it, and shows
   `// TASK DUPLICATED`.

There is no confirmation sheet and no additional permanent control.

## Duplicate contract

The copy is a fresh, independent, active task appended to the project.

Copied:

- task type and custom title
- notes and task color
- assigned crew
- duration
- explicit dependency overrides, including an explicit empty override

Reset:

- identifier and creation timestamp
- status to active
- start/end dates and times
- estimate and line-item source links
- paired-task lineage
- schedule lock
- deletion state

The new task is selected after the local save. Normal task-pair automation may
run because the duplicate is a genuine new task, not a history clone.

## Permission and failure behavior

The menu action is visible only when the operator has full `tasks.create`
permission and the project is not open through mention-only access. This
matches the live insert policy rather than borrowing `projects.edit`.

OPS keeps the original task unchanged if the duplicate cannot be formed or
saved. Invalid stored dependency data fails closed instead of silently
changing scheduling behavior. The existing error-toast surface reports the
failure.

## Interface and design-system fit

The existing native context menu is the signature surface for detailed row
actions. The new row inherits its platform touch target, accessibility
semantics, typography, depth, and motion. It introduces no colors, spacing,
radii, fonts, modal chrome, or animation, so every visual value remains sourced
from the existing OPS task row and iOS system menu.

`doc.on.doc` is the current SF Symbols duplicate metaphor. It follows the
shipped iOS icon library while the future Carbon migration remains separate.

## Verification

A focused unit suite proves the payload preserves the approved task definition,
resets schedule/status/lineage, preserves explicit empty dependency overrides,
rejects corrupt overrides, and applies the create permission policy. A manual
pass confirms the menu row, immediate selection, and success toast.
