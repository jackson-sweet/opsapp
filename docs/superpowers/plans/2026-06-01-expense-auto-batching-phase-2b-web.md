# Expense Auto-Batching — Phase 2b (Web Office) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Give the office a read-only **peek** at still-`open` (filling) envelopes, the ability to **early-clear** a single expense line outside whole-batch approval, and a review queue that **reacts** to the server's one-per-envelope notification.

**Architecture:** Web approval is already a direct `supabase.from().update()` (no RPC/API route). We add `open` to the TS status model (no DB migration — `expense_batches.status` is unconstrained `text`), a line-scoped `approveExpense` service+hook+button, a read-only filling lane in the review dashboard, and a Supabase realtime subscription so the `open→pending_review` flip refreshes the queue without a manual reload.

**Tech Stack:** Next.js (App Router, `--turbopack`), TanStack Query, Supabase JS, TypeScript, `OPS-Web/`. Package manager **npm**. Verify: `npm run type-check`, `npm run lint`, `npm test` (vitest); runtime via the preview tools.

**Hard dependency:** Phase 1 (server) live (it creates `open` batches and flips them). Pairs with Phase 2a (iOS). The early-clear and batch-approve paths must keep working under Phase 1 Task 6's new restrictive RLS — verified in Task 8.

**Files touched:**
| File | Change |
|---|---|
| `OPS-Web/src/lib/types/expense-approval.ts` | `Open` enum value + display/color maps + `isBatchOpen` |
| `OPS-Web/src/components/expenses/expense-review-list-popover.tsx` | Exclude `open` from the History bucket (bug fix) |
| `OPS-Web/src/components/expenses/expense-review-dashboard.tsx` | Read-only "filling" peek lane |
| `OPS-Web/src/lib/api/services/expense-approval-service.ts` | `approveExpense(expenseId, approvedBy)` |
| `OPS-Web/src/lib/hooks/use-expense-approval.ts` | `useApproveExpense` + realtime invalidation |
| `OPS-Web/src/components/expenses/expense-line-item-table.tsx` | `onApproveLine` prop + button + cleared pill |
| `OPS-Web/src/components/expenses/invoice-detail-panel.tsx` | Wire early-clear |
| `OPS-Web/src/lib/hooks/use-expense-batches-realtime.ts` (new) | Realtime subscription → invalidate queries |

---

## Task 1: Add the `open` (filling) status to the web model

**Files:**
- Modify: `OPS-Web/src/lib/types/expense-approval.ts:18-54,162-177`

- [ ] **Step 1: Failing check — type-check is the safety net**

`BATCH_STATUS_DISPLAY` and `BATCH_STATUS_COLOR` are `Record<ExpenseBatchStatus, string>` (exhaustive). Adding the enum value without map entries fails `tsc`.

- [ ] **Step 2: Add the enum value, maps, predicate**
```ts
export enum ExpenseBatchStatus {
  Open = "open",                       // NEW — silent filling phase; read-only peek
  PendingReview = "pending_review",
  Submitted = "submitted",
  Approved = "approved",
  PartiallyApproved = "partially_approved",
  Rejected = "rejected",
  AutoApproved = "auto_approved",
}

export const BATCH_STATUS_DISPLAY: Record<ExpenseBatchStatus, string> = {
  [ExpenseBatchStatus.Open]: "FILLING",
  [ExpenseBatchStatus.PendingReview]: "PENDING",
  // …rest unchanged…
};

export const BATCH_STATUS_COLOR: Record<ExpenseBatchStatus, string> = {
  [ExpenseBatchStatus.Open]: "#7A8290",   // muted steel — not actionable
  [ExpenseBatchStatus.PendingReview]: "#D99A3E",
  // …rest unchanged…
};
```
Add the predicate next to `isBatchNeedsReview` (`:172`):
```ts
export function isBatchOpen(status: ExpenseBatchStatus): boolean {
  return status === ExpenseBatchStatus.Open;
}
```
Confirm `isBatchReviewable` (`:162-169`) and `isBatchNeedsReview` (`:172-177`) do **not** list `Open` (they don't) — so no approve/reject UI renders for a filling envelope.

- [ ] **Step 3: type-check** — `cd OPS-Web && npm run type-check` → no errors (the maps now cover `Open`).

- [ ] **Step 4: Commit**
```bash
git -C OPS-Web add src/lib/types/expense-approval.ts
git -C OPS-Web commit src/lib/types/expense-approval.ts -m "feat(expenses): add 'open' filling batch status to web model"
```

---

## Task 2: Fix the History-bucket bug (open must not show as history)

**Files:**
- Modify: `OPS-Web/src/components/expenses/expense-review-list-popover.tsx:316-333`

The popover defines `historyBatches = batches.filter(b => !isBatchNeedsReview(b.status))`. Once `open` exists, every still-filling envelope wrongly lands in **History**. Exclude it.

- [ ] **Step 1: Exclude `open` from history**
```tsx
  const needsReviewBatches = batches.filter((b) => isBatchNeedsReview(b.status));
  const historyBatches = batches.filter(
    (b) => !isBatchNeedsReview(b.status) && !isBatchOpen(b.status)
  );
```
Import `isBatchOpen` from `@/lib/types/expense-approval`.

- [ ] **Step 2: type-check + lint** → clean.

- [ ] **Step 3: Commit**
```bash
git -C OPS-Web add src/components/expenses/expense-review-list-popover.tsx
git -C OPS-Web commit src/components/expenses/expense-review-list-popover.tsx -m "fix(expenses): keep filling envelopes out of the review-list History tab"
```

- [ ] **Step 4: Dashboard — move `auto_approved` into History (confirmed decision)**

Auto-approved batches don't need review, so they belong in **History** on every surface. The popover already buckets them there (via `!isBatchNeedsReview`). Fix the dashboard: in `expense-review-dashboard.tsx:57-89`, move `autoApprovedBatches` out of the Review-tab array into the History-tab array — Review tab = `reviewBatches` only; History tab = `[...approvedBatches, ...rejectedBatches, ...autoApprovedBatches]`. (Read `:57-89` first to match the exact variable/tab names.) `open` is already excluded from all four arrays by omission.

- [ ] **Step 5: type-check + lint + commit**
```bash
git -C OPS-Web add src/components/expenses/expense-review-list-popover.tsx src/components/expenses/expense-review-dashboard.tsx
git -C OPS-Web commit src/components/expenses/expense-review-list-popover.tsx src/components/expenses/expense-review-dashboard.tsx -m "fix(expenses): filling out of History; auto-approved into History"
```

---

## Task 3: Read-only "filling" peek lane on the review dashboard

**Files:**
- Modify: `OPS-Web/src/components/expenses/expense-review-dashboard.tsx:57-89,~185`

- [ ] **Step 1: Derive the open batches**

Alongside `reviewBatches` (`:57-89`):
```tsx
  const openBatches = useMemo(
    () => batches.filter((b) => isBatchOpen(b.status)),
    [batches]
  );
```
Import `isBatchOpen`.

- [ ] **Step 2: Render a read-only section above the review list (~`:185`)**

A muted "STILL FILLING — N" header + the existing `InvoiceCard` per open batch (the card already colors by `BATCH_STATUS_COLOR`, so it renders muted). Selecting one opens `InvoiceDetailPanel`, whose approve/reject footer is already hidden for non-reviewable batches (`isBatchReviewable(open) === false`) — so the office sees a live running total with **no action buttons**. No new detail component needed.
```tsx
  {openBatches.length > 0 && (
    <section>
      <h3 className="font-mono text-micro uppercase tracking-wider text-muted-foreground px-2 py-1">
        Still filling — {openBatches.length}
      </h3>
      {openBatches.map((b) => (
        <InvoiceCard key={b.id} batch={b} selected={selectedBatchId === b.id}
          onSelect={() => setSelectedBatchId(b.id)} />
      ))}
    </section>
  )}
```
(Match the actual `InvoiceCard` prop names from `invoice-card.tsx` — confirm before wiring.)

- [ ] **Step 3: type-check + lint + runtime peek**

Run the dev server via the preview tools; with a Phase-1 `open` batch present, confirm a "STILL FILLING" section shows a live total and the detail pane has no approve/reject buttons.

- [ ] **Step 4: Commit**
```bash
git -C OPS-Web add src/components/expenses/expense-review-dashboard.tsx
git -C OPS-Web commit src/components/expenses/expense-review-dashboard.tsx -m "feat(expenses): read-only peek at still-filling envelopes"
```

---

## Task 4: `approveExpense` service (single-line early-clear)

**Files:**
- Modify: `OPS-Web/src/lib/api/services/expense-approval-service.ts:312-330`
- Test: `OPS-Web/src/lib/api/services/__tests__/expense-approval-service.test.ts`

- [ ] **Step 1: Write the vitest (failing)**
```ts
import { describe, it, expect, vi } from "vitest";
// Mock requireSupabase to capture the update payload.
describe("approveExpense", () => {
  it("updates one expense to approved with approver + timestamp", async () => {
    const update = vi.fn().mockReturnValue({ eq: vi.fn().mockResolvedValue({ error: null }) });
    vi.doMock("@/lib/supabase/client", () => ({ requireSupabase: () => ({ from: () => ({ update }) }) }));
    const { ExpenseApprovalService } = await import("../expense-approval-service");
    await ExpenseApprovalService.approveExpense("exp-1", "user-9");
    expect(update).toHaveBeenCalledWith(expect.objectContaining({ status: "approved", approved_by: "user-9" }));
  });
});
```
Run: `cd OPS-Web && npm test -- expense-approval-service` → FAIL (method missing). (Match the existing mock style in the repo's service tests if one exists; otherwise this establishes it.)

- [ ] **Step 2: Add the method (model on `approveExpenses` :312-330)**
```ts
  async approveExpense(expenseId: string, approvedBy: string): Promise<void> {
    const supabase = requireSupabase();
    const { error } = await supabase
      .from("expenses")
      .update({
        status: "approved",
        approved_by: approvedBy,
        approved_at: new Date().toISOString(),
      })
      .eq("id", expenseId);
    if (error) throw new Error(`Failed to approve expense: ${error.message}`);
  },
```
Note: this deliberately does **not** touch `expense_batches.status` — early-clear is line-scoped; the envelope keeps filling.

- [ ] **Step 3: Run the test** → PASS.

- [ ] **Step 4: Commit**
```bash
git -C OPS-Web add src/lib/api/services/expense-approval-service.ts src/lib/api/services/__tests__/expense-approval-service.test.ts
git -C OPS-Web commit src/lib/api/services/expense-approval-service.ts src/lib/api/services/__tests__/expense-approval-service.test.ts -m "feat(expenses): approveExpense — single-line early-clear service"
```

---

## Task 5: `useApproveExpense` hook

**Files:**
- Modify: `OPS-Web/src/lib/hooks/use-expense-approval.ts:90`

- [ ] **Step 1: Add the mutation (mirror `useApproveBatch` :90-127)**
```ts
export function useApproveExpense() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ expenseId, approvedBy }: {
      expenseId: string; approvedBy: string;
      companyId: string; submittedBy: string; merchant: string; amount: number;
    }) => ExpenseApprovalService.approveExpense(expenseId, approvedBy),
    onSuccess: (_d, { companyId, submittedBy, merchant, amount }) => {
      queryClient.invalidateQueries({ queryKey: queryKeys.expenseBatches.all });
      dispatchExpenseLineCleared({ companyId, userId: submittedBy, merchant, amount });
    },
  });
}
```
**Notify the submitter (confirmed):** add a line-level `dispatchExpenseLineCleared` to `notification-dispatch.ts`, mirroring the existing `dispatch*` helpers (POST `/api/notifications/dispatch`, which auto-excludes the caller). The body names merchant + amount ("Your $X expense at <merchant> was approved") — route the exact wording through `ops-copywriter`. Don't reuse the batch-worded `dispatchExpenseApproved` for a single line.

- [ ] **Step 2: type-check** → clean. **Commit**
```bash
git -C OPS-Web add src/lib/hooks/use-expense-approval.ts
git -C OPS-Web commit src/lib/hooks/use-expense-approval.ts -m "feat(expenses): useApproveExpense hook"
```

---

## Task 6: Early-clear control in the line-item table

**Files:**
- Modify: `OPS-Web/src/components/expenses/expense-line-item-table.tsx:16-23,135-151,261-310`
- Modify: `OPS-Web/src/components/expenses/invoice-detail-panel.tsx:~96,~122`

- [ ] **Step 1: Add the prop (`:16-23`)**
```ts
interface ExpenseLineItemTableProps {
  expenses: ExpenseLineItem[];
  onFlag: (expenseId: string, comment: string) => void;
  onUnflag: (expenseId: string) => void;
  onApproveLine: (expenseId: string) => void;   // NEW
  onReceiptClick: (imageUrl: string) => void;
  canReview: boolean;
}
```

- [ ] **Step 2: Add an "APPROVE LINE" button in the review block (`:261-310`)**

Beside the flag UI, shown when `canReview && expense.status !== "approved"`:
```tsx
                {canReview && expense.status !== "approved" && (
                  <button
                    onClick={() => onApproveLine(expense.id)}
                    className="inline-flex items-center gap-1 px-2 py-1 rounded-md bg-[rgba(157,181,130,0.15)] text-[#9DB582] font-mono text-micro uppercase tracking-wider"
                  >
                    <Check className="w-[10px] h-[10px]" />
                    Approve line
                  </button>
                )}
```
The status pill (`:135-151`) already renders `APPROVED` for `expense.status === "approved"`, so a cleared line reflects immediately after invalidation.

- [ ] **Step 3: Wire it in `invoice-detail-panel.tsx`** — add `const approveLine = useApproveExpense();` near `handleFlag` (`:96`) and pass the handler (with submitter-notification context) to `<ExpenseLineItemTable />`:
```tsx
onApproveLine={(id) => {
  const e = expenses.find((x) => x.id === id);
  approveLine.mutate({
    expenseId: id, approvedBy: currentUserId,
    companyId, submittedBy: batch.submittedBy,
    merchant: e?.merchantName ?? "expense", amount: e?.amount ?? 0,
  });
}}
```
(Reuse the `currentUserId` / `companyId` / `batch` the panel already passes to `useApproveBatch` at `:122`.)

- [ ] **Step 4: type-check + lint + runtime** — clear one line in a `pending_review` batch; confirm only that line flips to APPROVED, the batch stays pending, and the running total is unchanged (early-cleared line stays counted).

- [ ] **Step 5: Commit**
```bash
git -C OPS-Web add src/components/expenses/expense-line-item-table.tsx src/components/expenses/invoice-detail-panel.tsx
git -C OPS-Web commit src/components/expenses/expense-line-item-table.tsx src/components/expenses/invoice-detail-panel.tsx -m "feat(expenses): early-clear a single line from the review detail"
```

- [ ] **Step 6: Mirror early-clear in the floating batch popover (confirmed)**

`expense-batch-popover.tsx` renders lines with its own `ExpenseRow` (`:81-214`), independent of `ExpenseLineItemTable`. Add the same "Approve line" control there, wired to `useApproveExpense` with the popover's current user, `batch.submittedBy`, and the row's merchant/amount. Commit:
```bash
git -C OPS-Web add src/components/ops/expense-batch-popover.tsx
git -C OPS-Web commit src/components/ops/expense-batch-popover.tsx -m "feat(expenses): early-clear control in the floating batch popover"
```

---

## Task 7: Make the queue react to the server's one-per-envelope flip

**Files:**
- Create: `OPS-Web/src/lib/hooks/use-expense-batches-realtime.ts`
- Modify: `OPS-Web/src/components/expenses/expense-review-dashboard.tsx` (mount the hook)

The rail is **poll-only** (no realtime on `notifications`). To refresh the queue the moment the server flips `open→pending_review`, subscribe to `expense_batches` for the company and invalidate the batch query (every review surface reads `useExpenseBatches`, so one invalidation refreshes all).

- [ ] **Step 1: Create the realtime hook** (align channel/cleanup with the existing pattern in `src/components/lockout/hooks/use-realtime-company.ts`)
```ts
"use client";
import { useEffect } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { requireSupabase } from "@/lib/supabase/client";
import { queryKeys } from "@/lib/api/query-client";

export function useExpenseBatchesRealtime(companyId: string | undefined) {
  const queryClient = useQueryClient();
  useEffect(() => {
    if (!companyId) return;
    const supabase = requireSupabase();
    const channel = supabase
      .channel(`expense_batches:${companyId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "expense_batches", filter: `company_id=eq.${companyId}` },
        () => {
          queryClient.invalidateQueries({ queryKey: queryKeys.expenseBatches.all });
        }
      )
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [companyId, queryClient]);
}
```

- [ ] **Step 2: Mount it in the review dashboard** — call `useExpenseBatchesRealtime(companyId)` near the top of `expense-review-dashboard.tsx` (using the same `companyId` it already passes to `useExpenseBatches`).

- [ ] **Step 3: Runtime verify** — with the dashboard open, run the Phase 1 sweep (`select public.expense_envelope_sweep();` via MCP on the branch) to flip an `open` batch; confirm it moves from "STILL FILLING" into "NEEDS REVIEW" without a manual reload.

- [ ] **Step 4: type-check + lint + Commit**
```bash
git -C OPS-Web add src/lib/hooks/use-expense-batches-realtime.ts src/components/expenses/expense-review-dashboard.tsx
git -C OPS-Web commit src/lib/hooks/use-expense-batches-realtime.ts src/components/expenses/expense-review-dashboard.tsx -m "feat(expenses): realtime — review queue reacts to envelope sends"
```

---

## Task 8: Cross-check Phase 1 RLS against the web approve paths

**Files:** none (verification)

Phase 1 Task 6 adds a RESTRICTIVE policy gating `expense_batches` updates-to-`approved` to `expenses.approve` holders. The web approves via a direct client `.update()` as the logged-in user — confirm it still works for approvers and is blocked for non-approvers.

- [ ] **Step 1: As an approver**, approve a batch and early-clear a line from the UI → both succeed (rows update).
- [ ] **Step 2: As a non-approver** (a Crew user, or via `execute_sql` impersonating one), attempt `update expense_batches set status='approved'` → blocked by RLS; the UI never exposes the control anyway (`canReview` / `isBatchReviewable`).
- [ ] **Step 3:** If approvers are unexpectedly blocked, the policy's `private.get_current_user_id()` is not resolving for the web's auth context — reconcile with Phase 1 Task 6 before shipping. (Note: this mirrors the known iOS "anon role" RLS caveat — verify the web's role/JWT resolves the permission helper.)

---

## Task 9: Verify + bible + close out

**Files:**
- Modify: `ops-software-bible/07_SPECIALIZED_FEATURES.md` §14, `ops-software-bible/09_FINANCIAL_SYSTEM.md`

- [ ] **Step 1: Full verify** — `cd OPS-Web && npm run type-check && npm run lint && npm test`. All green.
- [ ] **Step 2: Runtime** — peek shows filling envelopes read-only; early-clear flips a single line; the queue reacts live to a sweep flip.
- [ ] **Step 3: Bible** — document the office peek, early-clear, and the realtime queue in `09_FINANCIAL_SYSTEM.md`; record the one-per-envelope `expense_submitted` notification consumption in `07_SPECIALIZED_FEATURES.md` §14. Date `(2026-06-01)`. Commit (separate from code).

---

## Self-review (against the spec)

- **Spec §5.2 peek (read-only filling)** → Tasks 1, 3 (+ bug fix Task 2). ✔
- **Spec §5.2 early-clear single line** → Tasks 4, 5, 6. ✔ (Does not touch batch status; line stays counted.)
- **Spec §5.2 one notification per envelope → reactive queue** → Task 7 (server inserts via Phase 1; web reacts via realtime). ✔
- **Spec §9 additive / no DB migration on web** → status is unconstrained `text`; `open` is app-only. ✔
- **RLS compatibility** → Task 8 cross-checks Phase 1 Task 6. ✔
- **Placeholder scan:** the "confirm prop names" (Task 3) verify step and the concrete realtime hook (Task 7) are explicit/real; the popover early-clear (Task 6 Step 6) and submitter notification (Task 5) are now required steps, not deferrals. ✔
- **Type consistency:** `isBatchOpen`, `approveExpense`, `useApproveExpense`, `useExpenseBatchesRealtime`, `onApproveLine` used identically across tasks. ✔

**Decisions folded in (2026-06-01):** auto-approved batches bucket to **History** on every surface (Task 2, Step 4); early-clear is **mirrored in the floating batch popover** (Task 6, Step 6); early-clear **notifies the submitter** (Task 5). Matching iOS change: auto-approved moves to History in `ExpensesListView` (Phase 2a, Task 6).

**Depends on:** Phase 1 (server) live. **Pairs with:** Phase 2a (iOS).
