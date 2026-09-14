# Crew expense correction implementation plan

> Execute with custom-skills:executing-plans. Existing bug-batch delegation and local implementation are authorized. Production migrations, real financial writes and releases remain separate.

**Goal:** An authorized office reviewer can correct an unapproved crew expense and return it with immutable before-and-after feedback; the crew can review and resubmit it.

**Report:** `c381520d-84fa-40ea-ba66-67de14c717ce`.

**Architecture:** A dedicated correction command binds the reviewer, company, submitter, expense, revision, request UUID and intended fields. The server commits the return state, immutable snapshots and one notification atomically. Replay proves the original correction without copying historical values over a newer expense. Normal uploader-only editing and flag-only review remain separate existing actions.

**Stack:** SwiftUI, XCTest, Supabase/PostgreSQL17. No SwiftData schema change.

**Design system:** `ops-design-system/project/DESIGN.md`, `mobile/MOBILE.md`, and iOS `OPSStyle`. Reuse existing form, glass surface, primary/secondary button styles, Layout spacing tokens, Typography body/sectionLabel/caption and primary/secondary text tokens. Caption values are JetBrains Mono. No new animation.

**Skills:** Supabase, systematic-debugging, custom-skills:writing-plans, custom-skills:executing-plans, test-driven-development, verification-before-completion. UI owner uses mobile-ux-design, interface-design, ops-design and ops-copywriter; audit-design-system before completion.

## Server command and custody

Owner: IOS BUGS - P7-1, isolated server worktree. Pending migration `20260914214748_expense_admin_correction_review.sql` depends on the P5 expense authority, accounting lifecycle and payroll compatibility migrations.

- Inspect exact live schema, permissions and released save/placement behavior before SQL. Preserve ordinary uploader-only save authority.
- Permit only the exact active company reviewer and a different active submitter. Reject stale revisions, identity changes, no-op corrections, approved/paid/exported history and unsafe envelopes.
- Store exact original and corrected values, including category/project labels, plus an optional note. An empty note remains valid because the before-and-after record supplies required feedback.
- Return the expense for crew review without approval, payment, accounting events or provider writes. Preserve that state through automatic envelope placement/sweeps until explicit crew resubmission.
- Serialize exact request replay and concurrent financial decisions. Prove rollback, no duplicate notification, no duplicate correction and immutable history with synthetic rows and actual database roles.

## iOS form and history

Owner: IOS BUGS - P7-2, isolated iOS worktree. Files: ExpenseFormSheet, ExpenseBatchDetailView, ExpenseCorrectionHistoryView, ExpenseRepository, ExpenseViewModel, correction command/snapshot/policy/draft helpers, Feedback catalog and focused tests.

- Add CORRECT & RETURN at eligible office review detail, using the existing expense form. The receipt remains inspectable while receipt/OCR mutation stays unavailable.
- Show an optional crew note and explain that the expense returns for review. Show changed fields as readable FROM/TO values in existing crew detail, with actor/date and immutable labels.
- Keep edits through stale reload, adopt fresh values only for untouched fields and identify overlapping changes for review. A lost response retains the exact original command for retry.
- Validate receipt identity and intended contents. Recheck account/company after suspension; generation-guard current row/batch refresh so late reads cannot replace newer data.
- Test command field boundaries, authority/lifecycle eligibility, stale draft merge, ambiguous replay, account changes, refresh ordering and history presentation. Add synthetic rendered evidence without real financial writes.

## Root verification and integration

- Review each isolated diff and SQL fixtures against the actual pending P5 stack. Lead Details and separately owned expense bugs are excluded.
- Integrate only owned commits. Root retains the serial iOS build baton and reuses the verified P6 build cache.
- Run focused correction tests plus relevant expense decision/save/accounting guards. Inspect rendered before-and-after feedback. Record exact source, counts and limitations.
- Mirror pending SQL byte-for-byte and update the Bible's data/API/expense chapters in the same session. Commit source and evidence separately; do not close live reports or claim customer availability before authorized release and acceptance.
