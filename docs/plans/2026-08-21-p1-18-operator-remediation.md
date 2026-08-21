# P1-18 Operator Editing and UI Remediation

## Scope lock

- Preserve the locally built Share Photos parent-before-child barrier and Lead Detail inline editing without changing their source.
- Replace Overdue Review's competing horizontal row with one vertical recovery ledger, responsive action placement, and an inline retryable failure state.
- Add one explicit primary sub-contact per project across Supabase, iOS cache/sync, scoped authorization, and the existing project contact sheet.
- Add the descriptor's representative photo or profile thumbnail to Trash quick view.
- Do not apply the migration, update live report rows, push, release, or touch P1-19/P1-20/onboarding/schedule-tray scope.

## Contracts and proof

### Primary project contact

1. Add a nullable `projects.primary_sub_client_id` FK with a validation trigger that rejects cross-client, cross-company, or deleted contacts.
2. Clear stale selections when an older client changes the project's parent client, and when a selected sub-contact is deleted or reparented.
3. Decode, cache, protect, and round-trip the wire field through every project inbound path.
4. Prefer the explicitly selected active sub-contact for project contact identity; otherwise use only the parent client, never an arbitrary first sub-contact.
5. Offer `USE FOR THIS PROJECT` / `REMOVE FROM PROJECT` inside the existing client contact sheet only when the operator has record-scoped `projects.edit` authority.
6. Keep failed writes visible and leave the previous selection intact.

Focused proof: migration contract tests, project contact policy/model tests, DTO/cache merge tests, and one scoped iOS build/test invocation.

### Overdue Review

1. Render one vertically scrolling ledger; rows constrain all text to the available width.
2. Separate project, task, and overdue metadata so long task labels never compete with the action.
3. Stack the action at accessibility sizes while retaining a 44-point minimum target.
4. Keep a failed task in the review, show `// COULD NOT MARK DONE`, and convert the action to `TRY AGAIN`.
5. Do not dismiss while the last optimistic completion is still unresolved.

Focused proof: layout/copy state tests at compact and accessibility Dynamic Type sizes, plus one focused iOS build/test invocation.

### Trash quick view

1. Reuse the exact representative thumbnail already resolved for the ledger row.
2. Show one restrained 64-point preview above metadata with the existing truthful fallback.
3. Keep restore eligibility and transaction behavior unchanged.

Focused proof: quick-view content contract plus the existing Trash recovery suite and visual render harness.

## Atomic delivery

1. Local OPS-Web commit: additive migration and its focused contract tests.
2. Local iOS commit: primary project contact end-to-end.
3. Local iOS commit: Overdue Review redesign.
4. Local iOS commit: Trash quick-view media.
5. Local Bible commit: current schema, sync, UX, and release-boundary documentation.
