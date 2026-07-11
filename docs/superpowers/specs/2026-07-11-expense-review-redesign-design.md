# iOS Expense Review Redesign — Design

**Date:** 2026-07-11
**Surface:** ops-ios — owner-side expense review (Books → EXPENSES → batch console)
**Counterpart:** OPS-Web Books EXPENSES segment (2026-07-10) — same vocabulary and server contract, NOT the same UI.

## 1 · The two jobs (product brief)

1. **Macro spend awareness** — "how much are we spending on job expenses" — a couple of simple metrics, not a data dump.
2. **Batch review** — review each team member's submitted batches; see at a glance what needs approval, what's approved-but-unpaid, what's been paid out; drill in as much or as little as wanted; approve everything at once or line-by-line; flag lines with comments. Batches the crew is still filling are findable but never in the way.

User: the owner (`expenses.approve`), one-handed on a phone between site visits. Sunlight, gloves, distraction.

## 2 · Audit findings (what's wrong today)

- `ExpensesListView` = period pills + NEEDS REVIEW / HISTORY tabs. Month scoping + a "history" concept that treats approved batches as done — but approved ≠ paid. No TO PAY, no PAID, no WITH CREW.
- Hero card sums `approvedAmount` across batches — wrong: `approve_expense_batch` never writes it. On live demo data 39 auto-approved batches carry `approved_amount = 0.00` against $45.5k total. The math shows $0 owed where $45.5k is owed.
- No person grouping, no bulk approve, no mark-paid.
- Whole-batch approve = two direct writes (`updateBatchStatus` + per-line `approve`) instead of the atomic `approve_expense_batch` RPC.
- RealtimeProcessor posts `.expenseUpdated` for `expenses` + `expense_batches`, but **no view listens** — the hub is not live.
- "Invoice" vocabulary everywhere user-facing (notifications "Invoice Approved", `invoice_detail` deep links).
- `expense_paid` notifications (live in prod since web shipped) render via default fallbacks — bell icon, no deep link.
- Crew side (`MyExpensesView`, `ExpenseCard`) already speaks the right language ("filling" / "with the office" / "approved" / "paid" / "needs fix") — minimal changes.

## 3 · Alternatives weighed

**A — Port the web console** (workbar chips + instrument row + hover actions). Rejected: hover doesn't exist; a chips-row plus a separate metrics strip duplicates surface on 390pt; desktop chrome.

**B — One stacked scroll, all four buckets as sections.** Rejected: TO PAY drowns below a long TO REVIEW list; PAID reference data pollutes the working set; "at a glance" dies by scrolling.

**C — Person-first navigation** (people list → person's batches). Rejected: adds a hop to every review for the common case (a handful of crew, one or two batches each). Grouping gives the person context without the extra level.

**D — Instrument tiles that ARE the bucket switcher** ← chosen. The three money states (TO REVIEW / TO PAY / PAID) render as stat tiles in a row — they are simultaneously the "couple of simple metrics" and the segmented control for the queue below. One structure serves both jobs. This is the Books command-grid idiom (KPI tiles over a ledger) applied to the console; state-aware (defaults to the first bucket with work), and prominence tracks frequency: working buckets get tiles, WITH CREW gets one quiet hairline row.

## 4 · The design

### 4.1 Structure (pushed screen, full-screen focus)

```
┌──────────────────────────────────────┐
│ ← BOOKS        BATCHES          [⚙] │  nav bar (existing header idiom)
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ // SPEND · THIS MONTH        ▂▄▆ │ │  hero: Mohave hero number,
│ │ $12,480             ↑ 12% vs JUN │ │  MoM delta (rose ↑ = cost up),
│ │ JOBS $9,120 · OVERHEAD $3,360    │ │  6-mo micro bars, jobs/overhead
│ └──────────────────────────────────┘ │
│ ┌──────────┬───────────┬───────────┐ │
│ │TO REVIEW │ TO PAY    │ PAID      │ │  stat tiles = bucket switcher
│ │ $1,240   │ $983      │ $2,105    │ │  (selected = active-segment
│ │ 3 BATCHES│ 2 PEOPLE  │ THIS MONTH│ │  treatment; count sublines)
│ └──────────┴───────────┴───────────┘ │
│                                      │
│ MARCUS WEBB              APPROVE 2  │  person header + per-person bulk
│ ──────────────────────────────────  │
│  EXP-BATCH-0041   JUN 1–30    $412  │  hairline ledger rows
│  EXP-BATCH-0044   JUL 1–14    $340  │  (swipe → APPROVE / MARK PAID)
│ DIEGO RUIZ               APPROVE 1  │
│  EXP-BATCH-0043 ⚑2 JUL 1–14  $488  │  flag count surfaces on the row
│                                      │
│ // WITH CREW · 2 FILLING · 1 BACK   │  quiet expandable footer row
│                                      │
│ ┌──────────────────────────────────┐ │
│ │        APPROVE ALL · $752        │ │  floating CTA (clean batches
│ └──────────────────────────────────┘ │  only; confirm dialog)
└──────────────────────────────────────┘
```

- **Entry:** Books EXPENSES segment ledger-marker link (approvers only), now state-aware: `BATCHES · 3 TO REVIEW` (tan) → `BATCHES · 2 TO PAY` → `BATCHES`. Settings entry + deep links unchanged.
- **No period pills, no tabs.** Cross-period is the rule. The four buckets are the organization.

### 4.2 Buckets (exact web parity, `ExpenseBuckets.swift` pure helpers)

| Bucket | Rule | Sort / group |
|---|---|---|
| TO REVIEW | `pending_review` + legacy `submitted` | person groups by oldest outstanding period asc; batches oldest-first |
| TO PAY | `approved` / `partially_approved` / `auto_approved` AND `paid_at IS NULL` | person groups by largest owed desc |
| PAID | `paid_at IS NOT NULL` | flat, newest payout first, month subheaders by payout date |
| WITH CREW | `open` (filling, shows auto-send date = `period_end + auto_submit_grace_days`; per-job: "sends after the job wraps") + `rejected` still holding ≥1 line (drained → disappears) | filling first (soonest auto-send), then returned |

**Owed amount rule** (`batchOwedAmount`): `approved_amount` authoritative only for `partially_approved`; a zero/absent figure on any other approved state means the whole envelope → `total_amount`. Used by TO PAY tile, person totals, rows, detail, PAY ALL sums.

**Metrics** (`ExpenseMetrics` parity with web `expense-metrics.ts`): spend = lines with status ∈ {submitted, approved, reimbursed} by `expense_date` month; MTD hero + MoM trend + jobs/overhead split (allocation presence) + 6-month mini bars. Computed from the same two fetches that render the queue (`fetchAll` lines + `fetchBatches`) so strip and queue can never disagree.

### 4.3 Actions

| Where | Action | Mechanism |
|---|---|---|
| Row swipe (leading, olive) | APPROVE (TO REVIEW, unflagged batches) / MARK PAID (TO PAY) | RPC per batch |
| Person header | `APPROVE n` / `PAY n` compact button | confirm dialog → sequential RPCs |
| Floating CTA | `APPROVE ALL · $X` / `PAY ALL · $Y` | confirm dialog; **flagged batches always excluded** and the dialog says so |
| Batch detail (TO REVIEW) | APPROVE ALL (n) / SEND BACK n (flag-driven) | RPC / existing amendment flow |
| Batch detail (TO PAY) | MARK PAID · $owed | `mark_expense_batch_paid` |
| Batch detail (PAID) | `PAID JUL 11 · BY JACKSON` line + UNDO ghost | `unmark_expense_batch_paid` |
| Mark-paid toast | `// PAID · EXP-BATCH-0042` with UNDO action | ToastCenter action |
| WITH CREW detail line | CLEAR NOW (expanded card, quiet) | `early_clear_expense_line` |
| Flag / comment | unchanged flag toggle + comment field + RejectConfirmationView (recopied) | direct writes (existing) |

Approve migrates to the atomic `approve_expense_batch` RPC + best-effort per-line `accounting-sync-expense` (web parity). Reject/amendment flow keeps its existing client transaction (web ported the same flow). Non-approvers who can reach the hub (full-access `expenses.view` without `expenses.approve`) get a read-only console: no swipes, no CTAs, no detail actions.

### 4.4 Notifications (submitter-facing; types are cross-platform contract)

| Event | Type | Title / body |
|---|---|---|
| Whole-batch approve | `expense_approved` (was `invoice_approved`) | "Expenses Approved" / "Your batch EXP-BATCH-0042 was approved" |
| Send back | `expense_rejected` (was `invoice_revisions`) | "Expenses Sent Back" / "3 expenses on EXP-BATCH-0042 need fixes" |
| Mark paid | `expense_paid` (new dispatch on iOS) | "Expenses Paid Out" / "Your expense batch EXP-BATCH-0042 has been paid out" (exact web parity) |

iOS rail gains first-class `expense_paid` handling: icon (banknote, olive), action label, batch-aware routing; `expensePaid` push type routed in AppDelegate. Legacy `invoice_*` rows keep their existing fallbacks — zero regression. OneSignal methods renamed to batch vocabulary with a new `notifyBatchPaid`.

### 4.5 Live surface

The console subscribes to `.expenseUpdated` (already posted by RealtimeProcessor for `expenses` + `expense_batches`; previously nobody listened) with a short debounce → reload batches + lines. `.opsExpensesDidChange` retained for local mutations.

### 4.6 Motion & haptics (animation-architect brief)

- **Beats:** approve/pay = Commitment→Achievement (medium impact on commit, success notification on completion — a stamp, not a parade); bucket switch = Transition (existing `OPSStyle.Animation` curve, no spring); row departure on state change = Transition (list diff animates with the standard curve); totals roll with `.contentTransition(.numericText())`.
- One easing curve (`OPSStyle.Animation.*` tokens only). Reduced motion: crossfade fallbacks via `accessibilityReduceMotion` (existing app pattern).
- No celebration effects. The row leaving the queue IS the reward.

### 4.7 States

- **Loading:** skeleton rows (existing TacticalLoadingBar for first load).
- **Empty per bucket:** `$0` hero + `// NOTHING WAITING ON YOU` (TO REVIEW), `// NOBODY OWED` (TO PAY), `—` + `// NO PAYOUTS RECORDED` (PAID). WITH CREW row hidden at zero.
- **Error:** existing errorToast pattern (`// BATCH UPDATE FAILED`).
- **Offline:** data renders from last load; action failures surface the error toast. RPCs require network by nature.

### 4.8 Crew side (minimal)

`ExpenseCard` already renders `reimbursed` as "paid". One addition: submitted-line phase copy for a batch that is approved-but-unpaid stays "approved" (correct). No layout changes. `MyExpensesView` untouched.

## 5 · Components & files

| File | Change |
|---|---|
| `OPS/DataModels/Helpers/ExpenseBuckets.swift` | NEW — bucket derivation, owed amount, person grouping, line stats, metrics. Pure, unit-tested. |
| `OPS/Network/Supabase/DTOs/ExpenseDTOs.swift` | `paidAt`/`paidBy` on batch DTO; `autoSubmitGraceDays` on settings DTO |
| `OPS/Network/Supabase/Repositories/ExpenseRepository.swift` | RPC wrappers: `approveBatchAtomic`, `markBatchPaid`, `unmarkBatchPaid`, `earlyClearLine` |
| `OPS/ViewModels/ExpenseViewModel.swift` | bucket/metrics publishing, RPC actions + notifications, realtime listener, retire `approveInvoice` |
| `OPS/Views/Expenses/ExpensesListView.swift` | REBUILT — the console (same type name; `embedded` + `deepLinkBatchId` API preserved) |
| `OPS/Views/Expenses/ExpenseBatchDetailView.swift` | owed display, MARK PAID / UNDO, WITH CREW read-only + CLEAR NOW, copy |
| `OPS/Views/Expenses/RejectConfirmationView.swift` | copy only ("send back" vocabulary) |
| `OPS/Views/Books/BooksTabView.swift` + `BooksLedgerControls.swift` | state-aware BATCHES link |
| `OPS/Views/Notifications/NotificationListView.swift` | `expense_paid` icon + labels + routing |
| `OPS/AppDelegate.swift` | `expense_paid` / `expensePaid` push routing |
| `OPS/Services/OneSignalService.swift` | batch vocabulary + `notifyBatchPaid` |
| `OPS/Styles/Components/Feedback.swift` | `Feedback.Batch` tokens |
| `OPSTests/…` | bucket/owed/metrics unit tests + snapshot suite for every console/detail state |

## 6 · Out of scope / honest notes

- No schema changes (none needed — verified live: `paid_at`/`paid_by`, `auto_submit_grace_days`, all four RPCs present).
- `ExpenseFormSheet`, capture flow, settings screens: untouched beyond what the console requires.
- Web's `has_permission` override gap (bible-flagged) is inherited parity, not fixed here.
