# Expense correction and crew feedback implementation plan

**Goal:** Let authorized office reviewers correct an unapproved teammate expense and return it with a permanent, understandable before/after record.

**Architecture:** A dedicated `correct_expense_for_review` command owns correction, rejection, audit, and notification atomically. Ordinary expense saves remain submitter-only. An immutable receipt confirms success; current expense data is fetched separately so replay cannot overwrite later work.

**Tech stack:** SwiftUI, typed Supabase RPC transport, existing expense view model.

**Design system:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md`, `mobile/MOBILE.md`, and iOS `OPSStyle` tokens.

**Skills:** mobile-ux-design, ops-design, interface-design, ops-copywriter, writing-plans, audit-design-system. Existing screen structure and native sheet presentation are retained; no new motion.

## Flow and states

Reviewer expands a crew expense in batch detail, chooses CORRECT & RETURN, edits existing business fields, optionally adds a crew note, and commits. Receipt/OCR stay immutable. The crew opens the returned expense, sees the note and recorded changed fields above existing details, then reviews or edits and resubmits through the existing submitter path. Existing flag-only review remains available.

The existing form leads with the correction purpose and note, then receipt/details/project split, with one primary footer action. Feedback uses vertically stacked field names and FROM/TO values for legibility on small screens; no dense horizontal table. All new spacing, fonts, surfaces, and colors use OPSStyle tokens.

An uncertain response locks the exact command for retry. A stale rejection offers an explicit baseline reload without replacing entered fields or the note. Definitive validation failures keep fields editable. Account changes reject dispatch or cache publication. A receipt is success evidence even if the independent refresh fails; historical receipt values never replace current expense data.

## Work

1. Add typed correction command, receipt, audit snapshots, eligibility, and diff presentation. Test full precision revision, nullable fields, forbidden receipt/approval keys, identity validation, and frozen labels.
2. Add repository RPC calls and injectable view-model seam. Test failed writes, mismatched receipts, replay after later state, refresh failure, and account switches without live writes.
3. Add correction mode to ExpenseFormSheet and entry point to ExpenseBatchDetailView. Preserve uploader-only ordinary edits, snapshot hydration, exact retries, correction note, stale reload, and receipt immutability.
4. Add reusable crew history component with loading/failure/retry states; use it in ordinary expense detail and expanded batch detail.
5. Review token use and parse changed Swift files. Root owns serial simulator/XCTest proof after integration; no agent build, device install, live correction, push, migration, or release.

## Source verification and handoff

Foundation-only typecheck passed for the exact DTO, policy, draft, numeric validation, money formatting, and enum files. Changed production/test Swift files parse; CRLF-aware diff check passes. No iOS build or test execution was run by this agent. Root runs ExpenseCorrectionContractTests, ExpenseCorrectionViewModelTests, ExpenseCorrectionSnapshotTests, existing expense submission/approval tests, and FeedbackCatalogTests.

Current eligibility is `expenses.approve(all)` and `expenses.view(all)`, non-self submitted/rejected expenses with no approval/accounting evidence, and an absent or exact matching, unreviewed, unpaid eligible envelope. Receipt inspection remains enabled; replacement/OCR controls are hidden. Batch detail supplies explicit correction mode. The ordinary office expense form also offers correction for eligible unbatched rows; ordinary uploader editing remains separate. Correction notes are optional; no-op content is rejected.

Snapshot attachments: expense-correction-crew-history-375, expense-correction-crew-history-390, expense-correction-without-note. Before/after values use Typography.caption (JetBrains Mono 14pt); new production UI uses only existing OPSStyle tokens and native presentation.
