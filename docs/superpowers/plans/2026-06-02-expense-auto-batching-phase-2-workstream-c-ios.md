# Expense Auto-Batching — Phase 2 · Workstream C (iOS Field + Review) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline, chosen — the changes are tightly coupled through `ExpenseBatchStatus` and must compile together) or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) tracking.

**Goal:** Make the iOS app match the now server-authoritative expense-envelope model — stop client-side batching/auto-approve, treat the new `open` (filling) envelope phase correctly in review, collapse the draft/submit footer to a single **Add**, surface line state + envelope phase quietly to the crew, and make envelope status flips update live.

**Architecture:** The server owns placement (a `place_expense` trigger files every non-draft, unbatched expense by date) and submission (a daily `pg_cron` sweep auto-sends due envelopes, adopts orphans, auto-clears under-threshold lines, and fires one `expense_submitted` notification per envelope). iOS therefore (1) adds `open` to `ExpenseBatchStatus`, (2) deletes its client batching paths (`get_or_create_open_batch` placement, `ExpenseBatchPeriod` placement use, under-threshold auto-approve, the orphan-recovery banner, bulk submit + selection sheet + swipe-to-submit), (3) writes `status='submitted'` on a complete Add and lets the trigger place it, (4) reads each expense's batch phase to show "filling / with the office / approved" quietly, and (5) subscribes Realtime to `expense_batches` so flips render live. One small additive prod DDL enables the realtime broadcast.

**Tech Stack:** Swift / SwiftUI / SwiftData, Supabase Swift SDK (Realtime v2). Tokens: `OPS/Styles/OPSStyle.swift`. Prod DB `ijeekuhbatykdomumfjx` for the realtime DDL.

**Design System:** Every color/spacing/font traces to `OPSStyle` tokens (no hardcoded values). Quiet phases use `tertiaryText`; with-the-office uses `primaryAccent`; approved/paid uses `successStatus`; needs-fix uses `errorStatus`. No new motion (state display is static + existing `.contentTransition(.numericText())`), so `animation-architect` is not required.

**Required skills used:** `mobile-ux-design` (footer/card/nudge UX), `ops-copywriter` (all new strings, embedded below).

**Live-code path:** `ops-ios/OPS/…` (NOT `OPS/OPS/…`, an empty stub).

**Production safety:** Exactly one prod write — Task 11 (realtime publication + replica identity). Additive, reversible, negligible cost. User go-ahead obtained ("best UX" → publish both `expenses` + `expense_batches`). Mirror to `ops-software-bible/migrations/` + commit. No pushes.

**Verified server facts (this session, prod):**
- `expenses` trigger: only `trg_place_expense` (fires AFTER INSERT OR UPDATE OF status, expense_date, batch_id). An amount-only edit does NOT auto-recalc the batch total → the client recalcs after a submitted-line edit.
- `supabase_realtime` is a curated publication (25 tables, `puballtables=false`). `projects`/`notifications` are in it (REPLICA IDENTITY **full**); `expenses`/`expense_batches` are **not** (REPLICA IDENTITY **default/pk**). The existing iOS `expenses` realtime subscription is therefore silently dead today.
- `expense_batches` read policy `company_isolation` targets PUBLIC → the anon-role iOS client can read it (realtime will deliver once published).

---

## File / change map

| File | Change |
|---|---|
| `OPS/DataModels/Enums/FinancialEnums.swift` | Add `case open = "open"` to `ExpenseBatchStatus`; `displayName`/`needsReview`/`isApproved`/new `isFilling` handle it. |
| `OPS/ViewModels/ExpenseViewModel.swift` | Rewrite `submitExpense` to a thin "mark submitted"; add submitted-line edit recalc; delete `bundleInvoice`, `recoverOrphans`, `loadOrphanCount`, `orphanCount`; add `currentFillingTotal` + `batchStatus(for:)` + `loadMyBatches`. |
| `OPS/Views/Expenses/ExpenseFormSheet.swift` | Single **ADD** footer; edit a submitted line = SAVE (keep status, recalc); RESUBMIT a rejected line (clear batch → trigger re-files); drop the draft-revert + `resetExpenseBatch`. |
| `OPS/Views/Expenses/ExpenseCard.swift` | Remove swipe-right SUBMIT + "SUBMITTED" overlay; add quiet phase line driven by `batchStatus`. |
| `OPS/Views/Expenses/MyExpensesView.swift` | Remove bulk SUBMIT + selection sheet + submit overlay + swipe-to-submit + edit warning; add filling-total strip + "finish your receipt" nudge; wire card `batchStatus`. |
| `OPS/Views/Components/Project/Tabs/ProjectExpensesTabView.swift` | Drop the `onSwipeRight`/`submitExpense` wiring (ExpenseCard API change). |
| `OPS/Views/Expenses/ExpensesListView.swift` | Retire the orphan banner; move `auto_approved` to **History**; exclude `open` from review sections + hero totals + period pills; `batchStatusColor` handles `open`. |
| `OPS/Views/Expenses/ExpenseBatchDetailView.swift` | `isReviewable = status.needsReview` (filling envelopes not reviewable). |
| `OPS/Views/Expenses/CrewInvoiceHistoryView.swift` | Delete (dead — never instantiated). |
| `OPS/Network/Sync/RealtimeProcessor.swift` | Subscribe `expense_batches`; on `expenses`/`expense_batches` events post `.opsExpensesDidChange`. |
| `ops-software-bible/migrations/<ts>_expense_realtime_publication.sql` | New: replica identity full + add `expenses`,`expense_batches` to `supabase_realtime`. |
| `ops-software-bible/09_FINANCIAL_SYSTEM.md`, `02_USER_EXPERIENCE_AND_WORKFLOWS.md` | Document the iOS field/review behavior + realtime enablement. |

---

## Task 1 — `ExpenseBatchStatus.open` (data layer)

**Files:** `OPS/DataModels/Enums/FinancialEnums.swift`

- [ ] **Step 1:** Add the case + handle it in every computed property (back-compat: `ExpenseDTO`/`ExpenseBatchDTO.status` are `String`, so decoding never crashes; the only conversions are `ExpenseBatchStatus(rawValue:) ?? .pendingReview`, which now resolve `open`):

```swift
enum ExpenseBatchStatus: String, Codable, CaseIterable {
    case open              = "open"
    case pendingReview     = "pending_review"
    case submitted         = "submitted"
    case approved          = "approved"
    case partiallyApproved = "partially_approved"
    case rejected          = "rejected"
    case autoApproved      = "auto_approved"

    var displayName: String {
        switch self {
        case .open:              return "FILLING"
        case .pendingReview:     return "PENDING"
        case .submitted:         return "SUBMITTED"
        case .approved:          return "APPROVED"
        case .partiallyApproved: return "PARTIAL"
        case .rejected:          return "REJECTED"
        case .autoApproved:      return "AUTO-APPROVED"
        }
    }

    /// A filling envelope is current-period, silently accruing — peek-only,
    /// never reviewable. Server owns when it sends.
    var isFilling: Bool { self == .open }

    /// Sent to the office and awaiting an approve decision. A filling (`open`)
    /// envelope is NOT review-ready.
    var needsReview: Bool { self == .pendingReview || self == .submitted }

    var isApproved: Bool { self == .approved || self == .autoApproved || self == .partiallyApproved }
}
```

- [ ] **Step 2:** Commit `feat(expenses): add open (filling) envelope status to ExpenseBatchStatus`.

---

## Task 2 — ViewModel: drop client batching, add phase/total helpers

**Files:** `OPS/ViewModels/ExpenseViewModel.swift`

- [ ] **Step 1 — `submitExpense` becomes a thin "mark submitted".** The trigger places it; the daily sweep notifies once per envelope on send; under-threshold auto-clear is server-side. Replace the whole method (lines ~315–383):

```swift
/// Mark a completed expense as submitted. The server `place_expense` trigger
/// files it into the right envelope by date; the daily sweep notifies the
/// office once per envelope on send, and auto-clears under-threshold lines.
/// The client no longer batches, notifies per-expense, or auto-approves.
func submitExpense(_ expenseId: String) async {
    guard let repo = repository else { return }
    do {
        let updated = try await repo.updateStatus(expenseId, status: .submitted)
        if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
            expenses[idx] = updated
        }
    } catch {
        self.error = error.localizedDescription
    }
}
```

- [ ] **Step 2 — submitted-line edit recalc.** Add a method the form calls after editing an already-submitted line, so the envelope total stays live (the trigger does not fire on amount-only edits) and a date change re-files via the trigger:

```swift
/// Re-file + recompute totals after editing a line that is already in an
/// envelope. Clearing batch_id makes the `place_expense` trigger re-file it by
/// its (possibly changed) date and recompute the destination envelope; the
/// previous envelope is recomputed too if the line moved.
func refileEditedExpense(_ expenseId: String, previousBatchId: String?) async {
    guard let repo = repository else { return }
    do {
        try await repo.clearBatchId(expenseId)               // → trigger re-files + recalcs new batch
        let updated = try await repo.fetchOne(expenseId)
        if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
            expenses[idx] = updated
        }
        if let prev = previousBatchId, prev != updated.batchId {
            try? await repo.recalculateBatchTotal(prev)      // old envelope lost a line
        }
    } catch {
        self.error = error.localizedDescription
    }
}
```

- [ ] **Step 3 — delete dead client-batching paths.** Remove entirely: `bundleInvoice(...)`, `recoverOrphans()`, `loadOrphanCount()`, the `@Published var orphanCount`, and `resetExpenseBatch(...)` (replaced by `refileEditedExpense`). Keep `approveInvoice`, `sendRevisions`, flag/unflag, `loadBatchesForReview` (admin path unchanged — direct writes still succeed for a real approver under the new RLS; the atomic RPC is web-scoped and would drop the iOS-needed accounting-sync + submitter notify).

- [ ] **Step 4 — crew phase/total helpers.** Add:

```swift
/// The current user's own batches (for the My Expenses phase line + filling total).
@Published var myBatches: [ExpenseBatchDTO] = []

func loadMyBatches() async {
    guard let repo = repository, let uid = storedUserId else { return }
    do { myBatches = try await repo.fetchBatchesByUser(uid) }
    catch { if !error.isCancellation { /* observability only */ } }
}

/// Resolved envelope status for an expense's batch (nil if unbatched/unresolved).
func batchStatus(for expense: ExpenseDTO) -> ExpenseBatchStatus? {
    guard let bid = expense.batchId,
          let batch = myBatches.first(where: { $0.id == bid }) else { return nil }
    return ExpenseBatchStatus(rawValue: batch.status)
}

/// Total of the user's current filling (open) envelope(s) + the period label,
/// for the low-key running-total strip. Nil when nothing is filling.
var currentFilling: (total: Double, periodLabel: String)? {
    let open = myBatches.filter { ExpenseBatchStatus(rawValue: $0.status) == .open }
    guard !open.isEmpty else { return nil }
    let total = open.compactMap(\.totalAmount).reduce(0, +)
    let label: String = {
        guard let start = open.sorted(by: { ($0.periodStart ?? "") > ($1.periodStart ?? "") }).first?.periodStart else { return "" }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withFullDate]
        guard let d = iso.date(from: start) else { return "" }
        let f = DateFormatter(); f.dateFormat = "MMMM"; return f.string(from: d).uppercased()
    }()
    return (total, label)
}
```

- [ ] **Step 5 — load `myBatches` in `loadAll`.** Append `async let myBatchesTask: () = loadMyBatches()` to `loadAll()` and await it.

- [ ] **Step 6:** Commit `refactor(expenses): server-authoritative submit — drop client batching, add phase/total helpers`.

> Note: `getOrCreateOpenBatch`, `recalculateBatchTotal`, `clearBatchId`, `fetchBatchesByUser`, `assignExpensesToBatch`, `fetchOrphanExpenses`, `fetchUnbatchedExpenses` stay in `ExpenseRepository` (used by `approveInvoice`/`sendRevisions`/`refileEditedExpense`, or harmless). Do not delete repository methods that the review path still uses.

---

## Task 3 — ExpenseFormSheet: single ADD footer + server-authoritative edit

**Files:** `OPS/Views/Expenses/ExpenseFormSheet.swift`

- [ ] **Step 1 — footer.** Replace `stickyFooter`'s button block (lines ~795–902) so the only paths are: capture-stack advance, single ADD, locked badge, view-mode EDIT (+ ADD/RESUBMIT), edit-mode SAVE/ADD/RESUBMIT:

```swift
} else if editing == nil {
    if hasMoreReceipts {
        Button { Task { await saveAndAdvance() } } label: {
            Text("SAVE & NEXT (\(remainingReceiptCount) LEFT)").font(OPSStyle.Typography.button)
        }.opsPrimaryButtonStyle()
    } else {
        Button { Task { await save(submit: true) } } label: {
            Text("ADD").font(OPSStyle.Typography.button)
        }.opsPrimaryButtonStyle()
    }
} else if isLocked {
    // unchanged status badge
} else if isViewMode {
    Button { withAnimation(.easeInOut(duration: 0.2)) { isViewMode = false } } label: {
        Text("EDIT").font(OPSStyle.Typography.button)
    }.opsSecondaryButtonStyle()
    if expenseStatus == .draft {
        Button { Task { await save(submit: true) } } label: { Text("ADD").font(OPSStyle.Typography.button) }.opsPrimaryButtonStyle()
    } else if expenseStatus == .rejected {
        Button { Task { await save(submit: true) } } label: { Text("RESUBMIT").font(OPSStyle.Typography.button) }.opsPrimaryButtonStyle()
    }
} else {
    // edit mode
    if expenseStatus == .submitted {
        Button { Task { await save(submit: false) } } label: { Text("SAVE").font(OPSStyle.Typography.button) }.opsPrimaryButtonStyle()
    } else if expenseStatus == .rejected {
        Button { Task { await save(submit: true) } } label: { Text("RESUBMIT").font(OPSStyle.Typography.button) }.opsPrimaryButtonStyle()
    } else {
        Button { Task { await save(submit: true) } } label: { Text("ADD").font(OPSStyle.Typography.button) }.opsPrimaryButtonStyle()
    }
}
```

- [ ] **Step 2 — edit save logic (`performSave`, editing branch, lines ~1081–1139).** Drop the "revert submitted → draft + `resetExpenseBatch`" block. New behavior:
  - Build `UpdateExpenseDTO` WITHOUT forcing status (no `status: wasSubmitted ? .draft`).
  - `let wasSubmitted = ExpenseStatus(rawValue: exp.status) == .submitted`
  - `let wasRejected   = ExpenseStatus(rawValue: exp.status) == .rejected`
  - After `updateExpense` + receipt upload + allocations:
    - If `submit` and `wasRejected`: `await viewModel.submitExpense(exp.id)` then `await viewModel.refileEditedExpense(exp.id, previousBatchId: exp.batchId)` (rejected → re-file into the current open envelope).
    - Else if `submit` and `expenseStatus == .draft`: `await viewModel.submitExpense(exp.id)` (draft finalized → trigger places it).
    - Else if `wasSubmitted` (SAVE on a pending line): `await viewModel.refileEditedExpense(exp.id, previousBatchId: exp.batchId)` (keep status submitted; re-file + recalc so the envelope total stays live).
  - New-expense branch (`editing == nil`): unchanged except `submit` is always `true` from ADD (drafts only via `saveAndAdvance`).

- [ ] **Step 3 — keep** `approvalBanner`, validation, OCR, `saveAndAdvance` (snap-a-stack draft capture), `.opsExpensesDidChange` post. `saveAndAdvance` still calls `performSave(submit: false)` (draft).

- [ ] **Step 4:** Commit `feat(expenses): single Add footer + server-authoritative edit in ExpenseFormSheet`.

---

## Task 4 — ExpenseCard: drop swipe-to-submit + overlay, add quiet phase line

**Files:** `OPS/Views/Expenses/ExpenseCard.swift`

- [ ] **Step 1 — API.** Remove the `onSwipeRight` parameter (and from `init`); add `var batchStatus: ExpenseBatchStatus? = nil`. Remove `canSwipeRight`, the swipe-right reveal (lines ~83–95), and the `onSwipeRight()` branch in the drag `.onEnded`. Keep swipe-left DELETE + `canSwipeLeft`.

- [ ] **Step 2 — remove the "SUBMITTED" overlay + 0.5 opacity** (lines ~190–215, and `.opacity(isSubmitted ? 0.5 : 1.0)`); a submitted line is normal, not greyed.

- [ ] **Step 3 — phase line.** Replace `statusBadge` with a quiet phase descriptor driven by `(expenseStatus, batchStatus)`:

```swift
private struct Phase { let text: String; let color: Color }

private var phase: Phase {
    switch expenseStatus {
    case .draft:      return Phase(text: "unfinished",      color: OPSStyle.Colors.tertiaryText)
    case .rejected:   return Phase(text: "needs fix",       color: OPSStyle.Colors.errorStatus)
    case .approved:   return Phase(text: "approved",        color: OPSStyle.Colors.successStatus)
    case .reimbursed: return Phase(text: "paid",            color: OPSStyle.Colors.successStatus)
    case .submitted:
        switch batchStatus {
        case .some(.open):           return Phase(text: "filling",          color: OPSStyle.Colors.tertiaryText)
        case .some(.pendingReview):  return Phase(text: "with the office",   color: OPSStyle.Colors.primaryAccent)
        case .some(.approved), .some(.autoApproved), .some(.partiallyApproved):
                                     return Phase(text: "approved",          color: OPSStyle.Colors.successStatus)
        default:                     return Phase(text: "pending",           color: OPSStyle.Colors.primaryAccent)
        }
    }
}
```
Render: a `Circle().fill(phase.color)` dot + `Text(phase.text)` in `smallCaption`/`phase.color` on the left of row 3; keep `formattedDate` on the right (carries the month). `isSubmitted` is no longer needed for opacity — keep only if used elsewhere (it isn't after Step 2; remove it and the action-sheet gate on it → tap always calls `onTap`).

- [ ] **Step 4:** Commit `feat(expenses): quiet line-state + envelope phase on ExpenseCard`.

---

## Task 5 — MyExpensesView: remove submit machinery, add total strip + nudge

**Files:** `OPS/Views/Expenses/MyExpensesView.swift`

- [ ] **Step 1 — delete:** `submitForReviewButton`, `submitExpensesForReview()`, `submitLoadingOverlay`, `submitSelectionSheet`, `draftExpenses`/`selectedExpensesWithIssues`/`canSubmitSelected` (selection-only), and state `isSubmitting`, `showSubmitLoadingOverlay`, `submitLoadingComplete`, `showSubmitSelectionSheet`, `selectedExpenseIdsForSubmit`. Remove the `.sheet(isPresented: $showSubmitSelectionSheet)` and the `.overlay { submitLoadingOverlay }`.

- [ ] **Step 2 — edit warning.** Remove the `showEditWarning`/`pendingEditExpense`/`hideEditWarning` confirmation dialog and the `onEdit` branch that triggers it — editing a pending line is now allowed (it re-files + recalcs, no resubmit needed). `onEdit`/`onTap` just set `editingExpense = expense`.

- [ ] **Step 3 — card wiring.** In `expenseCardView`, remove `onSwipeRight`; add `batchStatus: viewModel.batchStatus(for: expense)`. Keep `onSwipeLeft` delete (draft/rejected only).

- [ ] **Step 4 — filling-total strip** (low-key, hidden when nothing is filling). Replace `submitForReviewButton` in `expensesScrollContent` with:

```swift
@ViewBuilder private var fillingStrip: some View {
    if let f = viewModel.currentFilling {
        HStack {
            Text("FILLING\(f.periodLabel.isEmpty ? "" : " · \(f.periodLabel)")")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            Text(f.total, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
    }
}
```

- [ ] **Step 5 — "finish your receipt" nudge** (gentle; only when drafts exist). Add `draftCount` (`viewModel.expenses.filter { $0.status == ExpenseStatus.draft.rawValue }.count`) and:

```swift
@ViewBuilder private var finishNudge: some View {
    if draftCount > 0 {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: OPSStyle.Icons.receipt)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(draftCount) RECEIPT\(draftCount == 1 ? "" : "S") TO FINISH")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text("Add the details to send \(draftCount == 1 ? "it" : "them") in.")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            Spacer()
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
    }
}
```
Put `finishNudge` then `fillingStrip` at the top of `expensesScrollContent` (after `searchAndFilter`).

- [ ] **Step 6:** Verify `loadAll` now also loads `myBatches` (Task 2 Step 5) so the strip + phases populate; the `.opsExpensesDidChange` receiver already calls `loadAll`.

- [ ] **Step 7:** Commit `feat(expenses): My Expenses — drop bulk submit, add filling total + finish nudge`.

---

## Task 6 — ProjectExpensesTabView: drop swipe-to-submit

**Files:** `OPS/Views/Components/Project/Tabs/ProjectExpensesTabView.swift`

- [ ] **Step 1:** In the `ExpenseCard(...)` at line ~111, remove the `onSwipeRight:` closure (the `submitExpense` call). Leave `onTap`/`onSwipeLeft`. `batchStatus` defaults to `nil` here (project tab doesn't load batches → card shows line-state phase: `pending`/`approved`/`needs fix`/`paid`/`unfinished`, no filling/with-office split, which is correct for this surface).

- [ ] **Step 2:** Commit `refactor(expenses): drop swipe-to-submit from project expenses tab`.

---

## Task 7 — ExpensesListView: retire orphan banner, History for auto-approved, exclude filling

**Files:** `OPS/Views/Expenses/ExpensesListView.swift`

- [ ] **Step 1 — retire orphan banner.** Delete `orphanRecoveryBanner` (lines ~153–199), its use in `body` (line ~94), and the `await viewModel.loadOrphanCount()` call (line ~141). (Server trigger + daily sweep own recovery now.)

- [ ] **Step 2 — exclude filling from the review hub.** Make `batchesForPeriod` drop `open` so it never appears in sections, hero totals, or period pills:

```swift
private var batchesForPeriod: [ExpenseBatchDTO] {
    viewModel.reviewBatches.filter { batch in
        guard batchStatus(batch) != .open else { return false }   // filling = peek-only, no iOS peek surface
        guard !selectedPeriod.isEmpty else { return true }
        return periodKey(for: batch) == selectedPeriod
    }
}
```
And in `computeAvailablePeriods()` skip `open` batches (`guard batchStatus(batch) != .open else { continue }`).

- [ ] **Step 3 — auto-approved → History.** In `needsReviewContent`, remove the `autoApprovedBatches` section (and from its empty-state guard). In `historyContent`, add it first:

```swift
private var needsReviewContent: some View {
    Group {
        if needsReviewBatches.isEmpty { emptyState }
        else { batchSection(title: "\(needsReviewBatches.count) NEED REVIEW", batches: needsReviewBatches) }
    }
}
private var historyContent: some View {
    Group {
        if autoApprovedBatches.isEmpty && approvedBatches.isEmpty && rejectedBatches.isEmpty { emptyState }
        else {
            VStack(spacing: OPSStyle.Layout.spacing3) {
                if !autoApprovedBatches.isEmpty { batchSection(title: "\(autoApprovedBatches.count) AUTO-APPROVED", batches: autoApprovedBatches) }
                if !approvedBatches.isEmpty { batchSection(title: "APPROVED", batches: approvedBatches) }
                if !rejectedBatches.isEmpty { batchSection(title: "REJECTED", batches: rejectedBatches) }
            }
        }
    }
}
```

- [ ] **Step 4 — `batchStatusColor` exhaustive for `open`.** Add `case .open: return OPSStyle.Colors.tertiaryText` (quiet; safety only — `open` is excluded from the hub).

- [ ] **Step 5:** Commit `feat(expenses): review hub excludes filling envelopes, auto-approved moves to History`.

---

## Task 8 — ExpenseBatchDetailView: filling envelopes not reviewable

**Files:** `OPS/Views/Expenses/ExpenseBatchDetailView.swift`

- [ ] **Step 1:** Make `isReviewable` use the shared enum rule so the hub filter and the detail screen never diverge (and `open` → not reviewable, no footer/flags):

```swift
private var isReviewable: Bool {
    (ExpenseBatchStatus(rawValue: batch.status) ?? .pendingReview).needsReview
}
```

- [ ] **Step 2:** Commit `fix(expenses): filling envelopes are not reviewable in batch detail`.

---

## Task 9 — RealtimeProcessor: subscribe expense_batches + refresh on batch/expense events

**Files:** `OPS/Network/Sync/RealtimeProcessor.swift`

- [ ] **Step 1 — subscribe.** Add `"expense_batches"` to `companyFilteredTables` (it has `company_id`; subscribed via the existing `company_id=eq.<companyId>` loop).

- [ ] **Step 2 — handlers.** In all four switch sites (`handleUpsert`, `handleDelete`, `dispatchUpsertToActor`, `dispatchDeleteToActor`): add an `"expense_batches"` case that posts `.opsExpensesDidChange`, and change the existing `"expenses"` case to ALSO post `.opsExpensesDidChange` (today it posts `.expenseUpdated`, which has zero observers — keep it, add the one the views actually listen to). Example (each site):

```swift
case "expenses", "expense_batches":
    NotificationCenter.default.post(name: .expenseUpdated, object: nil)
    NotificationCenter.default.post(name: .opsExpensesDidChange, object: nil)
```
(`.opsExpensesDidChange` is the global name defined in `ExpenseFormSheet.swift`; `ExpensesListView` → `loadBatchesForReview`, `MyExpensesView` → `loadAll`, both already observe it.)

- [ ] **Step 3:** Commit `feat(expenses): realtime subscription for expense_batches → live envelope status`.

---

## Task 10 — Delete dead CrewInvoiceHistoryView

**Files:** `OPS/Views/Expenses/CrewInvoiceHistoryView.swift`

- [ ] **Step 1:** `git rm` the file (verified: only self-references; never instantiated). Auto-approved history now lives in `ExpensesListView` History; crew see line state on their cards.
- [ ] **Step 2:** Commit `chore(expenses): remove dead CrewInvoiceHistoryView`.

---

## Task 11 — Prod realtime enablement (REQUIRES USER GO-AHEAD — obtained: "best UX" → both tables)

**Files:** `ops-software-bible/migrations/<ts>_expense_realtime_publication.sql`

- [ ] **Step 1 — recon (read-only):** re-confirm neither table is published (`pg_publication_tables`) before writing.
- [ ] **Step 2 — apply** (Supabase MCP `apply_migration`, name `expense_realtime_publication`, prod `ijeekuhbatykdomumfjx`):

```sql
-- Realtime-filtered tables need REPLICA IDENTITY FULL so company_id is present
-- on UPDATE/DELETE WAL records (matches projects/notifications). Additive.
alter table public.expenses        replica identity full;
alter table public.expense_batches replica identity full;
alter publication supabase_realtime add table public.expenses;
alter publication supabase_realtime add table public.expense_batches;
```

- [ ] **Step 3 — verify:** `select tablename from pg_publication_tables where pubname='supabase_realtime' and tablename in ('expenses','expense_batches')` returns both; advisor scan clean.
- [ ] **Step 4:** Mirror SQL to `ops-software-bible/migrations/<ts>_expense_realtime_publication.sql`; commit (in the bible repo, stage by name) `feat(expenses): enable realtime for expenses + expense_batches`.

---

## Task 12 — Bible updates (same session)

**Files:** `ops-software-bible/09_FINANCIAL_SYSTEM.md`, `ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md`

- [ ] **Step 1 — `09_FINANCIAL_SYSTEM.md`** § Expense Tracking / Server-Authoritative Envelopes: document the iOS field flow (single Add → submitted → trigger places; snap-a-stack drafts + finish nudge; line state + envelope phase display; filling running total), the review-hub rules (filling excluded, auto-approved in History, filling not reviewable), and the realtime enablement. Date `(2026-06-02)`.
- [ ] **Step 2 — `02_USER_EXPERIENCE_AND_WORKFLOWS.md`** if it documents the expense field flow: update to the single-Add model.
- [ ] **Step 3:** If these files carry a sibling session's uncommitted WIP, patch-stage only own hunks. Commit `docs(bible): iOS server-authoritative expense field + review flow`.

---

## Task 13 — Build + verify

- [ ] **Step 1 — parallel-session check:** `ps aux | grep xcodebuild` / `git -C ops-ios worktree list`. Build in a dedicated worktree with worktree-local DerivedData (copy `OPS/Utilities/Secrets.xcconfig` in first).
- [ ] **Step 2 — device build (DoD):** `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` → clean.
- [ ] **Step 3 — tests compile:** `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build-for-testing` (catches any test that referenced removed methods, e.g. `ExpenseBatchPeriod`/bulk-submit). Fix references; `ExpenseBatchPeriod.swift` stays (display math), so its tests, if any, keep passing.
- [ ] **Step 4 — optional sim walkthrough** (clean/erased sim; don't relaunch mid-login — Firebase throttling): Add → line shows "filling"; admin hub excludes filling, shows auto-approved under History; flip a batch server-side → card/hub update live.

---

## Self-review (against the spec)

- **C1 status model + review correctness** → Task 1 (`open` + `isFilling`/`needsReview`), Task 7 (exclude filling, auto-approved→History, color), Task 8 (`isReviewable=needsReview`), Task 9 (realtime), Task 10 (retire dead view), Task 7 Step 1 (retire orphan banner). ✔
- **C2 single Add** → Task 3 (ADD footer), Task 2 (`submitExpense` thin; drop client batching/auto-approve/per-submit notify), Task 5 (drop bulk submit/selection/swipe + nudge), Task 4/Task 6 (drop swipe-to-submit). Snap-a-stack drafts preserved (`saveAndAdvance`). ✔
- **C3 state display** → Task 4 (phase line), Task 5 (filling total strip). ✔
- **Server contract match** → no client `get_or_create_open_batch`/`ExpenseBatchPeriod` placement; no client under-threshold auto-approve; `open`/`auto_approved` decode safely (String DTO + `?? .pendingReview`). ✔
- **Additive/back-compat** → enum add only; DTOs unchanged; DDL additive. ✔
- **Placeholder scan** → all copy embedded; the one "confirm" (parallel-session/build) is an explicit verification step. ✔
- **Type consistency** → `batchStatus(for:)`, `refileEditedExpense`, `currentFilling`, `myBatches`, `phase`, `isFilling`, `needsReview` used identically across tasks. ✔

**Open/again-confirm at execution:** `OPSStyle.Icons.receipt` exists (used in ExpenseFormSheet) ✔; `opsPrimaryButtonStyle`/`opsSecondaryButtonStyle` exist ✔; `OPSStyle.Typography.button` exists (used in current footer) ✔.
