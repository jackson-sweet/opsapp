# iOS Expense Batch-Review Console — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or execute inline in this session) task-by-task.

**Goal:** Rebuild the owner-side iOS expense review around the four lifecycle buckets with person grouping, macro spend awareness, atomic-RPC approval, and the paid-out lifecycle.

**Architecture:** Pure derivation layer (`ExpenseBuckets.swift`, mirrors web `expense-buckets.ts` / `expense-metrics.ts`) feeds a rebuilt console (`ExpensesListView` + split subviews) and a reworked batch detail. All writes go through the four SECURITY DEFINER RPCs. Realtime `.expenseUpdated` finally gets a listener.

**Tech stack:** SwiftUI, supabase-swift PostgREST/RPC, SwiftData `@Query` for team-member names, XCTest (+ snapshot harness UIHostingController/UIWindow/drawHierarchy).

**Design system:** `ops-design-system/project/DESIGN.md` + `mobile/MOBILE.md`; iOS tokens = `OPS/Styles/OPSStyle.swift` (+ `Colors.olive/tan/rose`, `Typography.*`, `Layout.*`), Books idioms (`BooksPillView`, hairline ledger rows, `commandCard`, `OPSFloatingButtonBar`). Zero hardcoded color/spacing/font values.

**Required skills (loaded):** mobile-ux-design · animation-architect + ios-animations (Commitment/Transition beats, one easing curve, no spring) · ops-copywriter (terse tactical, "batch") · audit-design-system before done.

**Spec:** `docs/superpowers/specs/2026-07-11-expense-review-redesign-design.md`

---

## Task 1 — Data layer: DTOs + RPC wrappers

**Files:** Modify `OPS/Network/Supabase/DTOs/ExpenseDTOs.swift`, `OPS/Network/Supabase/Repositories/ExpenseRepository.swift`

1. `ExpenseBatchDTO`: add `let paidAt: String?` (`paid_at`), `let paidBy: String?` (`paid_by`).
2. `ExpenseSettingsDTO`: add `var autoSubmitGraceDays: Int?` (`auto_submit_grace_days`).
3. Repository RPC wrappers (all void-returning, `try await client.rpc(...).execute()`):
   - `approveBatchAtomic(_ batchId: String)` → `approve_expense_batch(p_batch_id)`
   - `markBatchPaid(_ batchId: String)` → `mark_expense_batch_paid(p_batch_id)`
   - `unmarkBatchPaid(_ batchId: String)` → `unmark_expense_batch_paid(p_batch_id)`
   - `earlyClearLine(_ expenseId: String)` → `early_clear_expense_line(p_expense_id)`

**Commit:** `feat(expenses): decode paid-out columns + wrap the approval/payout RPCs`

## Task 2 — Bucket/metrics derivation + unit tests (TDD)

**Files:** Create `OPS/DataModels/Helpers/ExpenseBuckets.swift`, `OPSTests/ExpenseBucketsTests.swift`

Pure API (exact web parity, `expense-buckets.ts` / `expense-approval.ts` / `expense-metrics.ts`):

```swift
enum ExpenseBucket { case review, pay, paid, crew }

struct ExpenseBatchLineStats { var count: Int; var flagged: Int }

enum ExpenseBuckets {
    static func isAwaitingPayout(_ batch: ExpenseBatchDTO) -> Bool      // approved-family && paidAt == nil
    static func isPaid(_ batch: ExpenseBatchDTO) -> Bool                 // paidAt != nil
    static func owedAmount(_ batch: ExpenseBatchDTO) -> Double           // partial → approvedAmount ?? total; else approvedAmount > 0 ? approvedAmount : total
    static func bucket(for batch: ExpenseBatchDTO, lineCount: Int?) -> ExpenseBucket?  // paid → review → pay → open→crew → rejected: lineCount==0 ? nil : crew → unknown: crew
    static func lineStats(_ expenses: [ExpenseDTO]) -> [String: ExpenseBatchLineStats] // keyed by batchId; flagged = flaggedBy != nil
    static func personGroups(_ batches: [ExpenseBatchDTO], amount: (ExpenseBatchDTO) -> Double) -> [ExpensePersonGroup]
    static func autoSendDate(_ batch: ExpenseBatchDTO, graceDays: Int) -> Date?        // periodEnd + graceDays; nil for per-job (scopeProjectId != nil)
    static func computeMetrics(batches: [ExpenseBatchDTO], expenses: [ExpenseDTO], now: Date) -> ExpenseConsoleMetrics
}
```

`ExpenseConsoleMetrics`: spendMTD, spendPrevMonth, spendTrendPct (nil when prev 0), spendByMonth [6], jobSpendMTD, overheadSpendMTD, reviewTotal/Count/People, payTotal/Count/People, paidMTDTotal/Count. Spend statuses = {submitted, approved, reimbursed} by `expense_date` month; job split = first allocation present.

Sorts: review people by oldest outstanding periodStart asc (batches oldest-first inside); pay people by owed desc; paid newest `paidAt` first; crew = filling by autoSend asc then returned.

**Tests first, watch them fail, then implement.** Truth table: every status × paid_at combination; owed rule incl. legacy `approved_amount > 0` full approvals; rejected drain (0 lines → nil); unknown status → crew; metrics MTD/trend/split; auto-send derivation (period + per-job).

Run: `xcodebuild test … -only-testing:OPSTests/ExpenseBucketsTests`

**Commit:** `feat(expenses): lifecycle bucket + owed-amount + spend-metrics derivation`

## Task 3 — ViewModel: console state, RPC actions, realtime

**Files:** Modify `OPS/ViewModels/ExpenseViewModel.swift`

1. `loadConsole()` — async-let `fetchBatches()` + `fetchAll()` + `fetchSettings()`; publish `consoleBatches`, keep `expenses`; derived bucket lists + metrics as computed properties over the published arrays.
2. Actions (all haptic-paired at call sites, toast on completion, reload after):
   - `approveBatch(_ batch:)` → RPC + per-line `triggerAccountingSync` + submitter notification (`expense_approved`, "Expenses Approved" / "Your batch N was approved") + push via renamed OneSignal method.
   - `approveBatches(_ batches:)` → sequential RPC loop (bulk), single summary toast, per-batch notifications.
   - `markPaid(_ batch:)` → RPC + `expense_paid` notification ("Expenses Paid Out" / "Your expense batch N has been paid out") + push; toast `// PAID OUT` **with UNDO action** → `unmarkPaid`.
   - `markPaidBatches(_ batches:)` bulk analog (no per-batch undo toast; summary toast).
   - `unmarkPaid(_ batch:)` → RPC, toast `// PAYOUT UNDONE`, no notification (web parity).
   - `earlyClearLine(_ expense:)` → RPC (server notifies), reload detail lines, toast `// LINE CLEARED`.
   - Retire `approveInvoice` (replace call sites); `sendRevisions` kept but recopied → notification type `expense_rejected`, "Expenses Sent Back" / "n expenses on N need fixes".
3. Realtime: `startRealtimeRefresh()` — Combine/NotificationCenter listener on `.expenseUpdated` with 500ms debounce → `loadConsole()`. Console view also keeps `.opsExpensesDidChange`.

**Commit:** `feat(expenses): console view-model — atomic approve, paid-out lifecycle, live refresh`

## Task 4 — Console rebuild (ExpensesListView + subviews)

**Files:** Rewrite `OPS/Views/Expenses/ExpensesListView.swift`; create `OPS/Views/Expenses/Console/ExpenseInstrumentStrip.swift`, `OPS/Views/Expenses/Console/ExpenseBucketQueue.swift`

- Keep type name + `deepLinkBatchId` param (drop unused `embedded`). Header: back + `BATCHES` + gear + plus (44pt targets, max 2 trailing icons).
- `ExpenseInstrumentStrip` (pure, testable): spend hero card (`// SPEND · THIS MONTH`, Mohave hero via `Typography.title`, `.contentTransition(.numericText())`, MoM delta olive-down/rose-up, 6-bar micro chart in `fillNeutral`/`Colors.text` current month, `JOBS $X · OVERHEAD $Y` line) + 3 stat tiles (TO REVIEW / TO PAY / PAID) with $ + subline; selected tile = active-segment treatment (`surfaceActive` bg + `Colors.text` border per MOBILE.md §4.1); selection haptic.
- `ExpenseBucketQueue` (pure): person sections (name + subline + trailing `APPROVE n` / `PAY n` 44pt compact button) over hairline ledger rows (BooksLedgerRows idiom: Mohave-Medium 15 primary, JetBrainsMono-Medium 15 amount, 9.5 metadata, `lineSoft` divider). Rows: batch number, period range, flag chip (`flag.fill` + count, tan) when flagged, `AUTO` pill on auto_approved, `PARTIAL` pill + `OF $total` on partial; PAID bucket = month subheaders by payout date + `PAID JUL 11` metadata. Swipe leading (olive): APPROVE / MARK PAID via existing `BooksSwipeRow`. Row tap → detail push.
- WITH CREW: quiet expandable footer row `// WITH CREW · 2 FILLING · 1 SENT BACK` → inline rows (person, running total, `AUTO-SENDS JUL 15` / `SENDS AFTER JOB WRAPS` / `SENT BACK · n LINES LEFT`), tap → detail.
- Floating CTA (`OPSFloatingButtonBar`): TO REVIEW → `APPROVE ALL · $X` (clean batches only); TO PAY → `PAY ALL · $Y`; hidden on PAID/empty. Confirmation dialogs: `Approve n Batches` / "Total $X. Flagged batches stay put." and `Mark n Batches Paid` / "Records $Y paid out. Lines flip to paid."
- Default bucket on appear: review if nonempty else pay else paid. Empty states per spec (MOBILE.md §10). `.hidesGlobalTabBar()`. Permission gating: actions only when `permissionStore.can("expenses.approve")`.
- Motion: bucket switch + row departure animate with `OPSStyle.Animation.panel/fast` only; reduce-motion falls back (existing pattern).
- Deep link: resolve `deepLinkBatchId` against all batches → push detail.

**Commit:** `feat(expenses): rebuild the review hub as the four-bucket batch console`

## Task 5 — Batch detail rework

**Files:** Modify `OPS/Views/Expenses/ExpenseBatchDetailView.swift`, `OPS/Views/Expenses/RejectConfirmationView.swift`

- Header stats: TO PAY/PAID batches show OWED (owed rule) + `OF $total` when partial; review batches show TOTAL.
- Footers by bucket: review → `APPROVE ALL (n)` (RPC) + `SEND BACK n` when flagged; pay → `MARK PAID · $owed`; paid → no footer bar; `PAID JUL 11 · JACKSON` line + `UNDO` ghost under header; crew-open → no footer, `AUTO-SENDS …` line, per-line `CLEAR NOW` ghost in expanded card (RPC); crew-rejected → read-only with flag comments.
- Haptics: medium impact on commit, success notification on completion (commit beat); warning on send-back.
- RejectConfirmationView: copy → `SEND BACK n` button, context line "n expenses go back to NAME with your notes."; sheet keeps flow.

**Commit:** `feat(expenses): batch detail — owed truth, mark paid / undo, early clear, send-back copy`

## Task 6 — Notifications: expense_paid first-class + vocabulary

**Files:** Modify `OPS/Views/Notifications/NotificationListView.swift`, `OPS/AppDelegate.swift`, `OPS/Services/OneSignalService.swift`, `OPS/Utilities/NotificationManager.swift` (local-notification category if needed), `OPS/Styles/Components/Feedback.swift`

- Rail: `expense_paid` icon (`banknote`, olive), `typeImpliesDeepLink` + legacy-fallback routing → `routeExpenseNotification(batchId:)`, action label VIEW EXPENSES.
- AppDelegate push switch: `"expense_paid", "expensePaid"` → batch-aware OpenExpenseBatch/OpenExpenses.
- OneSignal: rename to batch vocabulary (`notifyBatchApproved`, `notifyBatchSentBack`) + new `notifyBatchPaid(userId:batchNumber:batchId:)` (title "Expenses Paid Out", data type `expense_paid`).
- `Feedback.Batch` enum: approved `// BATCH APPROVED`, allApproved `// ALL CLEAR`, paid `// PAID OUT`, paidUndone `// PAYOUT UNDONE`, sentBack `// SENT BACK`, lineCleared `// LINE CLEARED`.

**Commit:** `feat(notifications): first-class expense_paid + batch vocabulary on the expense family`

## Task 7 — Books entry point

**Files:** Modify `OPS/Views/Books/BooksTabView.swift`, `OPS/Views/Books/Ledger/BooksLedgerControls.swift`

`BooksReviewBatchesLink` → state-aware: `BATCHES · n TO REVIEW` (tan) when review > 0, else `BATCHES · n TO PAY` when pay > 0, else `BATCHES`. Counts derived via `ExpenseBuckets` over `expenseVM.batches` (needs `loadBatches` already in Books refresh — verify).

**Commit:** `feat(books): state-aware batches link into the expense console`

## Task 8 — Snapshot suite

**Files:** Create `OPSTests/Views/ExpenseConsoleSnapshotTests.swift`

Harness = DeckMaterialsSnapshotTests pattern (UIHostingController + UIWindow + drawHierarchy, dark, 390×844, PNGs + attachments). Fixture DTOs (pure structs) drive `ExpenseInstrumentStrip` + `ExpenseBucketQueue` + detail states: review queue (flags, multi-person), pay queue (AUTO/PARTIAL pills), paid ledger (month headers), with-crew expanded, empty buckets, detail review/pay/paid/crew states. Export via xcresulttool → `docs/artifacts/expense-console/`.

**Commit:** `test(expenses): snapshot the console + detail states`

## Task 9 — Verification

1. `xcodebuild build` `-scheme OPS -destination 'generic/platform=iOS'` + worktree DerivedData + `-clonedSourcePackagesDirPath .spm-local` (copy Secrets.xcconfig first; check lsof for parallel builds). Grep log for `BUILD SUCCEEDED`.
2. Full-ish test pass: `xcodebuild test` sim iPhone 17 / OS 26.5 — at minimum ExpenseBucketsTests + ExpenseSubmissionGateTests + snapshot suites; triage any env-launch flakes vs baseline.
3. Prod RPC exercise on MAVERICK PROJECTS LTD (demo company) via Supabase MCP as a simulated approver (`set_config` JWT pattern where needed): approve a staged pending_review batch → verify status + lines; mark paid → verify `paid_at`/`paid_by` + lines `reimbursed`; unmark → verify reversal; early-clear a staged open-envelope line. Stage + clean up test rows; leave demo data coherent.
4. CRLF check on modified files (`file` / `git diff --stat` sanity — no ending flips).

## Task 10 — Design audit + bible + report

1. `custom-skills:audit-design-system` pass over new/modified views (zero hardcoded values; verify vs OPSStyle tokens + Books idioms).
2. Bible `09_FINANCIAL_SYSTEM.md`: rewrite "iOS field + review" section (console, RPC migration, expense_paid handling, realtime listener) + RPC table note (iOS now calls approve RPC).
3. Plain-English report to Jackson with screenshots.
