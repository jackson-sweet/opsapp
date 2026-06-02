# Expense Auto-Batching — Phase 2 (Client + Cross-Cutting) Design

**Date:** 2026-06-01
**Status:** Design — approved, pending implementation plans
**Surfaces:** Supabase (small server deltas) · OPS-Web (office) · iOS (field + review)
**Companion specs:** `2026-06-01-expense-auto-batching-design.md` (original design, §5 experience / §7 edge cases) and `../plans/2026-06-01-expense-auto-batching-phase-1-server.md` (Phase 1, shipped).

Phase 1 made the server authoritative for batching (placement trigger, daily sweep, `open`/`auto_approved` envelope phases, RLS approve-gating, deep-link notification). This Phase-2 design closes the end-to-end experience: it (1) fixes the client/cross-cutting fallout from Phase 1, and (2) builds the field (iOS) and office (OPS-Web) UX from the original spec §5/§7.

## Decisions locked (2026-06-01)

- **Back-compat:** ship the iOS fix; interim mis-render on 3.0.2 (filling `open` envelope shown as "PENDING," approvable early) is accepted — feature is barely used, blast radius is 1 Canpro approver / 1 envelope. No server-side interim guard.
- **Early-clear:** approve a single line → set `expenses.status='approved'` → trigger the existing `accounting-sync-expense` path → notify the submitter (reuse `dispatchExpenseApproved`). Line stays counted in its envelope; envelope stays `open`.
- **iOS stops client-side batching:** a completed Add creates the expense as `submitted`; the server trigger places it. Client no longer calls `get_or_create_open_batch` or uses `ExpenseBatchPeriod` for placement. (Offline is covered — the trigger fires when the expense syncs.)
- **Peek data-gate relaxation:** OPS-Web batch reads are currently hard-gated to `expenses.approve` holders; relax so a submitter can read their own filling envelope (peek). Approve actions stay gated to `expenses.approve`.
- **Sequencing:** Workstream A (server/cross-cutting) → B (OPS-Web, deploys immediately) → C (iOS, ships on App Store release).

## Workstream A — Server + cross-cutting fixes (prod writes; require user go-ahead)

**A1. Deep-link target.** The Phase-1 sweep emits `action_url='/expenses?batch=<id>'`, which 404s on web (no `/expenses` route; office UI is `/accounting?tab=expenses`, and `?batch=` is unconsumed). Re-apply `expense_envelope_sweep()` with `action_url='/accounting?tab=expenses&batch=' || v_batch.id`. Add a `/expenses → /accounting?tab=expenses` 308 redirect in `OPS-Web/src/middleware.ts` as a safety net for any other emitters (`notification-dispatch.ts` / `use-expense-approval.ts` also default to `/expenses`). iOS already routes `deep_link_type='expense'` correctly in-app; keep `deep_link_type='expense'`.

**A2. RLS approve-path integrity.** Verify the office approve write succeeds for a properly-permissioned **anon-role** user under the new `expense_batches_approve_scope` RESTRICTIVE policy (it targets `public`, so anon is covered). Two existing-code risks to repair (OPS-Web):
- `approveExpenses()` sets `expenses.status='approved'` and is gated by `expenses.edit` (migration `016`), while batch approval needs `expenses.approve` — a user with approve-but-not-edit half-completes. 
- `useApproveBatch` runs batch-update + line-update as a non-transactional `Promise.all` (partial failure leaves the batch `approved` but lines un-approved).
Repair: move whole-envelope approval into a single `SECURITY DEFINER` RPC `approve_expense_batch(batch_id)` that updates the batch + its lines atomically and checks `expenses.approve` via `has_permission`. Web calls the RPC instead of two direct writes. (Also used by early-clear's per-line variant: `early_clear_expense_line(expense_id)`.)

**A3. per_job completion send.** The sweep currently sends `open` envelopes on `period_end + grace`. For `per_job` companies (single-day period = expense date), that's wrong — the spec wants send N days after the **job** completes. Modify the sweep's auto-send selection: for envelopes whose company `review_frequency='per_job'` (or `scope_project_id IS NOT NULL`), gate on `projects.completed_at + grace <= now()` (join `scope_project_id → projects.id`); an envelope whose project is not yet complete stays `open` (office can still send manually). Verify `projects.completed_at` is the completion field. No current company is per_job (Canpro monthly, Maverick weekly) — correctness for completeness.

**A4. Auto-approve threshold (server-side; latent).** Today iOS auto-approves under-threshold expenses client-side by **bypassing** the batch (`draft → approved`, no envelope). The original spec (§7) wants under-threshold lines to still LAND in the envelope (books stay complete) and auto-clear on the spot. Move this server-side: on placement, if `amount < expense_settings.auto_approve_threshold`, set the line `approved` (auto-cleared) while it remains in its `open` envelope and counted in the total. Implement in/alongside `place_expense`. Latent — Canpro has no threshold set — but it completes the feature. Verify the threshold column name in `expense_settings`.

## Workstream B — OPS-Web office (Phase 2b + web breakage)

Key files (from code audit): `src/lib/types/expense-approval.ts` (status union + `BATCH_STATUS_DISPLAY`/`_COLOR` + `isBatch*` helpers), `src/components/expenses/expense-review-dashboard.tsx`, `invoice-detail-panel.tsx`, `expense-line-item-table.tsx`, `src/components/ops/expense-batch-popover.tsx` + `expense-review-list-popover.tsx`, `src/lib/api/services/expense-approval-service.ts`, `src/lib/hooks/use-expense-approval.ts`, `src/app/(dashboard)/accounting/page.tsx`, `src/lib/notifications/notification-meta.ts`.

**B1. Status model + History.** Add `open` to `ExpenseBatchStatus` and to `BATCH_STATUS_DISPLAY`/`BATCH_STATUS_COLOR` (no undefined pill/color). Add a fallback for unknown statuses. Bucket `open` as "filling" (peek-only, never in review/approve lists). Move `auto_approved` to the **History** tab consistently (dashboard currently shows it under review; the popover already treats it as history). Ensure `open` batches don't inflate the review-tab period totals.

**B2. Batch-scoped review.** `accounting/page.tsx` reads `?batch=` and opens/scrolls `ExpenseReviewDashboard` to that batch (prop or store wiring). Closes the deep-link loop with A1.

**B3. Peek.** Read-only view of any `open` (filling) envelope: live total, line list, no approve/flag controls. Reuse `expense-batch-popover` in a `readOnly` mode. Relax `useExpenseBatches`/`useAllExpenses` `enabled: canApprove` gating so a submitter loads their own filling envelope (scope the query to own `submitted_by` when not an approver). Approvers can peek anyone's.

**B4. Early-clear.** In the peek/popover and review detail, a per-line "clear/approve" action calls `early_clear_expense_line(expense_id)` RPC (A2): sets the line `approved`, runs accounting sync, notifies the submitter (`dispatchExpenseApproved`), leaves the envelope `open` and the line counted. Gated to `expenses.approve`.

## Workstream C — iOS field + review (Phase 2a + iOS breakage)

Key files (from code audit): `DataModels/Enums/FinancialEnums.swift` (`ExpenseBatchStatus`), `Network/Sync/RealtimeProcessor.swift`, `ViewModels/ExpenseViewModel.swift` (`submitExpense`/`recoverOrphans`/`approveInvoice`), `Network/Supabase/Repositories/ExpenseRepository.swift`, `DataModels/Helpers/ExpenseBatchPeriod.swift`, `Views/Expenses/{ExpenseFormSheet,MyExpensesView,ExpenseCard,ExpensesListView,ExpenseBatchDetailView}.swift`, `Views/MainTabView.swift`, `Views/Notifications/NotificationListView.swift`, `AppDelegate.swift`.

**C1. Status model + review correctness.** Add `open` to `ExpenseBatchStatus`. Treat `open` as filling: exclude from `needsReviewBatches` and make `isReviewable` false (no APPROVE on a filling envelope); exclude from pending totals. Move `auto_approved` from the NEEDS REVIEW section to the existing **History** tab of `ExpensesListView` (`autoApprovedBatches` → History bucket); retire the dead `CrewInvoiceHistoryView` (never instantiated). Subscribe `RealtimeProcessor` to `expense_batches` so status flips (`open→pending_review`, `auto_approved`) update live. Stop the orphan "BUNDLE" banner from racing the trigger: drive it only off true long-lived orphans (or retire it, since the server safety net now owns recovery).

**C2. Single Add.** Replace the draft/submit footer in `ExpenseFormSheet` with a single **Add**. A complete Add writes `status='submitted'` (no client `get_or_create_open_batch`; the trigger places it). Snap-a-stack quick-capture still writes `draft`s. Remove `MyExpensesView` bulk **SUBMIT EXPENSES** + selection sheet + swipe-to-submit. Add a gentle **"finish your receipt"** nudge for unfinished drafts (copy via `ops-copywriter`). Delete/retire the now-unused client batching path (`submitExpense`'s get-or-create branch + `ExpenseBatchPeriod` placement use). Client-side under-threshold auto-approve is also removed — the server now auto-clears under-threshold lines on placement (A4), so books stay complete without the client bypassing the envelope.

**C3. State display.** `ExpenseCard` shows the line's state (pending → approved → paid) + its month + envelope phase quietly ("April · with the office" / "filling"). A low-key running total for the current filling envelope on `MyExpensesView` (needs a batch lookup by current period for the user). Honor `OPSStyle` tokens; no new colors.

## Out of scope / not in this design
- The actual iOS App Store submission (user-driven).
- Rebuilding the office line-item review UI (reused).
- Multi-currency envelope reconciliation (unchanged).
- Removing the dead `accounting-batch-create` Edge Function (manual dashboard step, documented).

## Testing / verification
- **Server (A):** rollback-wrapped `DO`-block assertions on prod for the new RPCs + sweep change; advisor scan; deep-link verified against the real web route.
- **Web (B):** preview tools — peek renders read-only; early-clear approves one line + notifies + leaves envelope open; `open`/`auto_approved` render correctly; `?batch=` opens the batch; History placement; approve path works as an anon-role approver.
- **iOS (C):** `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` builds clean; simulator run-through of single-Add → expense appears placed; review hub excludes filling envelopes; History shows auto-approved; realtime status flip visible.

## Migration / RLS notes
- New RPCs `approve_expense_batch` / `early_clear_expense_line` are additive; mirror to `ops-software-bible/migrations/` and update `04_API_AND_INTEGRATION.md` + `09_FINANCIAL_SYSTEM.md`. Honors the iOS additive-only cross-release constraint.
- All prod writes (A1/A2/A3) require explicit user go-ahead (the Task-9-style prod gate the classifier enforces).
