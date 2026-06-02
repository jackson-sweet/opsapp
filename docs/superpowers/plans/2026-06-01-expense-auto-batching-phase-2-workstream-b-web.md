# Expense Auto-Batching — Phase 2 · Workstream B (OPS-Web Office) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement task-by-task. Verify each in the browser preview.

**Goal:** Finish the office expense experience on OPS-Web: render the new `open`/`auto_approved` envelope phases correctly, route the notification deep-link to the right batch, add read-only **peek** of filling envelopes, and add **early-clear** of a single line — all on top of the Workstream-A server (RPCs + routable deep-link already shipped).

**Architecture:** Extend the existing review surface (`expense-review-dashboard`, `invoice-detail-panel`, `expense-batch-popover`, `expense-approval-service`, `use-expense-approval`). Approval switches from two direct table writes to the atomic `approve_expense_batch` RPC; early-clear uses `early_clear_expense_line`; both then best-effort invoke the `accounting-sync-expense` Edge Function (the web currently never syncs on approve). New UI reuses existing component tokens/patterns — military tactical minimalist; no new look.

**Tech Stack:** Next.js (App Router) + TypeScript, Supabase JS, TanStack Query, Tailwind (OPS design tokens). Repo: `/Users/jacksonsweet/Projects/OPS/OPS-Web`.

**Design System:** OPS design system (Tailwind tokens already in OPS-Web). New UI must match the existing expense components' classes/tokens — no hardcoded color/spacing; trace to existing patterns. Numbers in JetBrains Mono tabular. Copy via `ops-copywriter`.

**Required Skills:** `frontend-design` (component quality/patterns), `ops-copywriter` (any new labels/empty states), `audit-design-system` (token compliance check on new UI).

**Verification:** browser preview (`preview_start` the OPS-Web dev server) after each UI task — `preview_snapshot`/`preview_console_logs`/`preview_screenshot`. No prod writes in B (web app code; calls the already-shipped RPCs). CI red-on-main is pre-existing (lint gates tests) — verify locally, don't claim CI passed.

---

## Task B1: Status model — `open`/`auto_approved` + History bucketing

**Files:** `src/lib/types/expense-approval.ts` (status union + `BATCH_STATUS_DISPLAY`/`BATCH_STATUS_COLOR` + `isBatchNeedsReview`/`isBatchApproved`/`isBatchReviewable`); `src/components/expenses/expense-review-dashboard.tsx` (bucketing lines ~57–89); `src/components/expenses/invoice-detail-panel.tsx:184–185` (no-fallback map reads); `src/components/ops/expense-batch-popover.tsx`, `src/components/dashboard/widgets/my-expenses-widget.tsx` (label/color getters).

**Changes:**
- Add `open` to `ExpenseBatchStatus`. Add `BATCH_STATUS_DISPLAY.open = 'Filling'` and a `BATCH_STATUS_COLOR.open` using an existing muted/neutral token (match the design system's "in-progress/neutral" treatment used elsewhere). Add a safe fallback for unknown status in any `BATCH_STATUS_DISPLAY[x]`/`_COLOR[x]` read (invoice-detail-panel:184–185) so no `undefined`/`undefined22`.
- `isBatchNeedsReview` must be FALSE for `open` (filling envelopes are peek-only, never in the review queue). `isBatchReviewable` FALSE for `open`.
- Dashboard bucketing: `open` → a "filling/peek" bucket (not review, not history). Move `auto_approved` into the **History** tab consistently (it currently shows under review). Ensure `open` batches are excluded from review-tab period totals.

**Acceptance:** an `open` batch renders a "Filling" pill (not blank/broken), never appears in the review queue or its totals; `auto_approved` appears under History. Preview: load `/accounting?tab=expenses`, console clean, snapshot shows correct buckets.

---

## Task B2: Approve via RPC + accounting-sync invocation

**Files:** `src/lib/api/services/expense-approval-service.ts` (`approveBatch`, `approveExpenses`); `src/lib/hooks/use-expense-approval.ts` (`useApproveBatch`).

**Changes:**
- Replace the two direct writes in `useApproveBatch`/`approveBatch` with a single `supabase.rpc('approve_expense_batch', { p_batch_id })`. Removes the non-transactional `Promise.all` + the edit-vs-approve permission mismatch (the RPC checks `expenses.approve` + writes atomically).
- After a successful approve, **best-effort** invoke the `accounting-sync-expense` Edge Function for the approved expenses (the web never synced on approve before). Match iOS's invocation contract — grep `ops-ios/OPS` for `accounting-sync-expense` to get the exact payload (likely `{ expenseId }` or `{ batchId }`). Wrap in try/catch; a missing accounting connection or sync error must NOT fail the approval (log + continue). Keep `dispatchExpenseApproved` (submitter notification).

**Acceptance:** approving a batch flips it + lines to approved via the RPC (network shows the rpc call); sync invoked best-effort (no-op/graceful when no connection); a non-approver's approve button is hidden (existing) and a forced call is rejected by the RPC. Preview: approve a (test) `pending_review` batch, network shows `rpc/approve_expense_batch`, batch moves to History.

---

## Task B3: `?batch=` deep-link consume

**Files:** `src/app/(dashboard)/accounting/page.tsx` (reads `?tab=` ~line 347; add `?batch=`); `src/components/expenses/expense-review-dashboard.tsx` (accept an `initialBatchId` / open-batch prop or store wiring).

**Changes:** the accounting page reads `?batch=<id>`; when present (and `tab=expenses`), select/open that batch in `ExpenseReviewDashboard` (set the detail panel to it; if it's a different period, switch the period pill to the batch's month). Also add the `/expenses → /accounting?tab=expenses` 308 redirect in `src/middleware.ts` as a safety net for any legacy `/expenses` links.

**Acceptance:** visiting `/accounting?tab=expenses&batch=<id>` opens that batch's detail; `/expenses` redirects. Preview: navigate with a real batch id, snapshot shows that batch selected.

---

## Task B4: Peek — read-only filling envelope

**Files:** `src/components/ops/expense-batch-popover.tsx` (add a `readOnly` mode — hide approve/flag/return controls, show live total + line list); `src/lib/hooks/use-expense-approval.ts` (`useExpenseBatches`/`useAllExpenses` `enabled: canApprove` gate — relax so a submitter loads their OWN filling envelope: when not an approver, scope the query to `submitted_by = currentUser.id`); a peek entry point (e.g., from `my-expenses-widget` for the submitter, and approvers can peek any `open` batch from the dashboard).

**Changes:** read-only peek of an `open` envelope: live total, lines, phase label "Filling"; no approve/flag. Approvers peek anyone's; a submitter peeks their own. Reuse the popover's existing layout/tokens; just gate the action controls behind `!readOnly && canApprove`.

**Acceptance:** opening an `open` envelope shows read-only contents (no approve controls); a non-approver submitter can see their own filling envelope; an approver can peek any. Preview: open a peek, snapshot shows totals + no approve button.

---

## Task B5: Early-clear — single-line approve

**Files:** `src/components/ops/expense-batch-popover.tsx` + `src/components/expenses/invoice-detail-panel.tsx`/`expense-line-item-table.tsx` (per-line "clear" action); `src/lib/api/services/expense-approval-service.ts` + `use-expense-approval.ts` (a `useEarlyClearLine` mutation).

**Changes:** a per-line action (visible to `expenses.approve` holders, including from the peek and the review detail) calls `supabase.rpc('early_clear_expense_line', { p_expense_id })`, then best-effort `accounting-sync-expense` for that line. The RPC approves the line, leaves the envelope `open`, recalcs, and notifies the submitter (server-side). On success, invalidate the batch query so the line shows approved + the envelope total updates. Copy for the action label via `ops-copywriter` (e.g., `CLEAR` / `CLEAR & PAY`).

**Acceptance:** clearing one line marks it approved, leaves the envelope open, updates the total, notifies the submitter; other lines unaffected. Preview: clear a line in a peek, snapshot shows that line approved + envelope still open.

---

## Task B6: Full preview verification + commit

- [ ] Run the OPS-Web dev server (`preview_start`); exercise B1–B5 end-to-end in the browser; console + network clean.
- [ ] `audit-design-system` pass on the new/changed UI (token compliance).
- [ ] Commit each task atomically in OPS-Web (`feat(expenses): …` / `fix(expenses): …`), staged by name, no AI attribution. No push.

## Out of scope
- Server changes (done in Workstream A).
- iOS (Workstream C).
- Rebuilding the line-item review (reused).

## Notes / risks
- Verify the OPS-Web approve path works as an **anon-role** approver under the Workstream-A RPCs (the RPC checks `expenses.approve`; account-holders/company-admins derive perms client-side — ensure the DB grant exists too, per the known client-catalog-vs-DB-grants issue).
- `scope_project_id` is unmapped in the web `ExpenseBatch` interface — map it if peek/per-job needs it.
