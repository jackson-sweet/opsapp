# In-App Feedback Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route every transient in-app "something happened" moment through the canonical `ToastCenter`, replacing ~50 error alerts, ~168 silent-success paths, and 27 bespoke feedback surfaces (including four parallel toast systems) with one tokenized, on-voice toast — while leaving blocking confirms, the notification inbox, and ambient status as-is.

**Architecture:** A central `Feedback` catalog (one place for all ~140 event labels, one `ops-copywriter` pass) feeds an upgraded `ToastCenter` (FIFO queue + coalescing + manual-hold for errors). A reusable `.errorToast(_:label:)` view modifier standardizes the error-alert → toast swap. Toasts fire **once, at the user-action boundary** (the public ViewModel method or the view action handler) — never inside loops or sync/merge paths.

**Tech Stack:** Swift / SwiftUI, SwiftData, `@MainActor` ObservableObject singleton, XCTest (simulator), `xcodebuild`.

**Spec:** `docs/superpowers/specs/2026-06-10-in-app-feedback-consolidation-design.md`

---

## Execution rules (read before any task)

1. **Branch:** all work on `feat/feedback-consolidation` (large feature buildout). Created in Task 0.
2. **Staging discipline — critical.** The working tree has heavy uncommitted WIP from sibling sessions, overlapping target files (Catalog, JobBoard especially). For any file that already has sibling WIP, **stage your hunks with `git add -p` and commit the index — never `git commit -- <path>`** (that commits the working tree and sweeps in their WIP). For brand-new files, `git add <exact/path>` is fine. Never `git add -A`/`git add .`. Never stash/reset/restore sibling WIP.
3. **One toast per user action.** Fire in the ViewModel's public action method **only if that method is exclusively user-invoked**; otherwise fire at the view call site. Never fire inside a `for`/loop, a batch primitive, or any inbound-sync / merge / restore path. Bulk actions emit one summary toast ("// 5 ITEMS DELETED"), not N.
4. **Build target:** device build = `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`. Test compile/run uses the simulator (`-destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`).
5. **No new colors/spacing/fonts.** Everything routes through existing `OPSStyle` tokens via the `Toast` component.
6. **Labels are provisional until Task 4.** Wire against the catalog symbol names; the strings are finalized in the `ops-copywriter` pass (Task 4), which runs before the domain sweeps.

---

## Wiring patterns (reference — used by every domain sweep)

**P1 — Silent success → toast.** At the user-action boundary, after the await/mutation succeeds:
```swift
// before: action completes, nothing shown
await viewModel.sendInvoice(invoice)

// after:
await viewModel.sendInvoice(invoice)
ToastCenter.shared.present(Feedback.Invoice.sent)
```
When the action lives in a VM method that's exclusively user-invoked, place the call at the end of that method's success path instead (covers all callers once).

**P2 — FYI error alert → error toast.** Replace the boilerplate alert with the modifier:
```swift
// before:
.alert("Error", isPresented: Binding(
    get: { viewModel.error != nil },
    set: { if !$0 { viewModel.error = nil } }
)) { Button("OK") { viewModel.error = nil } }
message: { Text(viewModel.error ?? "") }

// after:
.errorToast($viewModel.error, label: Feedback.Err.operationFailed)
```

**P3 — Single-action error → manual-hold error toast.** For errors with one recovery action (e.g. "Open Settings", "Create Task", "Retry"):
```swift
.errorToast($viewModel.error, label: Feedback.Err.locationRequired,
            actionLabel: "OPEN SETTINGS") { openAppSettings() }
```

**P4 — Kept confirm fires an outcome toast.** Leave the `.confirmationDialog`/destructive `.alert` blocking; on the confirmed action's success, present the outcome toast:
```swift
Button("Void Invoice", role: .destructive) {
    Task {
        await viewModel.voidInvoice(invoice)
        ToastCenter.shared.present(Feedback.Invoice.voided)
        dismiss()
    }
}
```

**P5 — Delete a bespoke feedback surface.** Remove the custom banner/overlay/toast view + its `@State`/manager, and replace its trigger points with a `ToastCenter.shared.present(...)` call. Persistent in-flight spinners (`isSaving`, `ProgressView`) stay during the operation; only the completion/error feedback becomes a toast.

---

## Task 0: Branch + baseline build

**Files:** none (git only)

- [ ] **Step 1: Create the feature branch**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios
git checkout -b feat/feedback-consolidation
```

- [ ] **Step 2: Confirm a clean baseline device build**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Confirm Secrets.xcconfig present** (worktrees don't inherit it)

Run: `ls OPS/Utilities/Secrets.xcconfig`
Expected: file exists. If missing: `cp` it from the main checkout before tests.

---

## Task 1: ToastCenter FIFO queue

**Files:**
- Modify: `OPS/Styles/Components/Toast.swift` (the `ToastCenter` class, ~line 125-160)
- Test: `OPSTests/Styles/ToastCenterQueueTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OPS

@MainActor
final class ToastCenterQueueTests: XCTestCase {
    private var center: ToastCenter { ToastCenter.shared }

    override func setUp() { super.setUp(); center.reset() }

    func testShowsImmediatelyWhenIdle() {
        center.present(Toast(label: "// A", tone: .success))
        XCTAssertEqual(center.current?.label, "// A")
        XCTAssertTrue(center.queue.isEmpty)
    }

    func testSecondToastQueuesBehindCurrent() {
        center.present(Toast(label: "// A", tone: .success))
        center.present(Toast(label: "// B", tone: .success))
        XCTAssertEqual(center.current?.label, "// A")
        XCTAssertEqual(center.queue.count, 1)
    }

    func testCoalescesIdenticalLabels() {
        center.present(Toast(label: "// A", tone: .success))
        center.present(Toast(label: "// B", tone: .success))
        center.present(Toast(label: "// B", tone: .success)) // dup of queue.last
        XCTAssertEqual(center.queue.count, 1)
        center.present(Toast(label: "// A", tone: .success)) // dup of current
        XCTAssertEqual(center.queue.count, 1)
    }

    func testDismissAdvancesQueue() {
        center.present(Toast(label: "// A", tone: .success))
        center.present(Toast(label: "// B", tone: .success))
        center.dismiss()
        XCTAssertEqual(center.current?.label, "// B")
        center.dismiss()
        XCTAssertNil(center.current)
    }

    func testQueueCapDropsOldestAutoDismiss() {
        center.present(Toast(label: "// 0", tone: .success)) // current
        for i in 1...5 { center.present(Toast(label: "// \(i)", tone: .success)) }
        XCTAssertEqual(center.queue.count, 3)
    }

    func testManualHoldErrorDoesNotAutoSchedule() {
        center.present(Toast(label: "// ERR", tone: .error, autoDismissAfter: 0,
                             action: ToastAction(label: "RETRY", handler: {})))
        XCTAssertEqual(center.current?.label, "// ERR")
        center.dismiss()
        XCTAssertNil(center.current)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/ToastCenterQueueTests 2>&1 | tail -20`
Expected: FAIL — `center.queue` / `center.reset()` do not exist.

- [ ] **Step 3: Replace the `ToastCenter` body**

In `OPS/Styles/Components/Toast.swift`, replace the class internals with:

```swift
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published private(set) var current: Toast?

    /// Pending toasts behind `current`, FIFO. Readable for tests.
    private(set) var queue: [Toast] = []

    /// Max queued toasts (excludes the visible one). Overflow drops the oldest
    /// auto-dismissing entry; manual-dismiss (error) toasts are never dropped.
    private let maxQueue = 3

    /// When a backlog exists, auto-dismiss toasts compress to this interval so a
    /// burst drains quickly instead of holding the screen for 3s each.
    private let compressedInterval: TimeInterval = 1.2

    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Enqueue a toast. Identical consecutive labels are coalesced. If nothing
    /// is showing it appears immediately; otherwise it queues behind `current`.
    func present(_ toast: Toast) {
        if current?.label == toast.label { return }
        if queue.last?.label == toast.label { return }
        guard current != nil else { show(toast); return }
        queue.append(toast)
        trimQueue()
    }

    /// Dismiss the visible toast and advance to the next queued one. Called by
    /// tap and by the auto-dismiss timer.
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        if queue.isEmpty { current = nil }
        else { show(queue.removeFirst()) }
    }

    /// Test/teardown hook — clears all state.
    func reset() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
        queue.removeAll()
    }

    private func show(_ toast: Toast) {
        current = toast
        let base = toast.autoDismissAfter
        guard base > 0 else { return } // manual-dismiss (error + action)
        let interval = queue.isEmpty ? base : compressedInterval
        let id = toast.id
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.current?.id == id else { return }
                self.dismiss()
            }
        }
    }

    private func trimQueue() {
        while queue.count > maxQueue {
            if let idx = queue.firstIndex(where: { $0.autoDismissAfter > 0 }) {
                queue.remove(at: idx)
            } else {
                queue.removeFirst()
            }
        }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/ToastCenterQueueTests 2>&1 | tail -20`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add OPS/Styles/Components/Toast.swift OPSTests/Styles/ToastCenterQueueTests.swift
git commit -m "feat(toast): FIFO queue with coalescing + manual-hold errors in ToastCenter"
```

---

## Task 2: Feedback catalog

**Files:**
- Create: `OPS/Styles/Components/Feedback.swift`
- Test: `OPSTests/Styles/FeedbackCatalogTests.swift` (create)

- [ ] **Step 1: Write the failing test (label contract)**

```swift
import XCTest
@testable import OPS

final class FeedbackCatalogTests: XCTestCase {
    func testEveryLabelFollowsVoiceContract() {
        for toast in Feedback.all {
            XCTAssertTrue(toast.label.hasPrefix("// "), "missing // prefix: \(toast.label)")
            let body = toast.label.replacingOccurrences(of: "//", with: "").trimmingCharacters(in: .whitespaces)
            XCTAssertEqual(body, body.uppercased(), "label not uppercase: \(toast.label)")
            XCTAssertFalse(body.isEmpty, "empty label body")
        }
    }

    func testGenericHelpersFormatCorrectly() {
        XCTAssertEqual(Feedback.saved("invoice").label, "// INVOICE SAVED")
        XCTAssertEqual(Feedback.deleted("tag").label, "// TAG DELETED")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/FeedbackCatalogTests 2>&1 | tail -20`
Expected: FAIL — `Feedback` undefined.

- [ ] **Step 3: Create the catalog scaffold**

`OPS/Styles/Components/Feedback.swift` — the single source of truth. Establish the structure with the Invoices/Estimates + Sync + error namespaces; each later domain task appends its own nested enum and adds its events to `all`.

```swift
import Foundation

/// Central catalog of every in-app feedback event. One place for all toast
/// copy (one ops-copywriter pass). Call sites reference these, never inline strings.
enum Feedback {

    // MARK: Generic helpers (long tail)
    static func saved(_ noun: String) -> Toast { Toast(label: "// \(noun.uppercased()) SAVED", tone: .success) }
    static func deleted(_ noun: String) -> Toast { Toast(label: "// \(noun.uppercased()) DELETED", tone: .success) }
    static func created(_ noun: String) -> Toast { Toast(label: "// \(noun.uppercased()) CREATED", tone: .success) }
    static func updated(_ noun: String) -> Toast { Toast(label: "// \(noun.uppercased()) UPDATED", tone: .success) }

    // MARK: Error labels (used by .errorToast)
    enum Err {
        static let operationFailed = "// OPERATION FAILED"
        static let saveFailed      = "// SAVE FAILED"
        static let deleteFailed    = "// DELETE FAILED"
        // domain tasks append their specific error labels here
    }

    enum Invoice {
        static let sent            = Toast(label: "// INVOICE SENT", tone: .success)
        static let voided          = Toast(label: "// INVOICE VOIDED", tone: .success)
        static let writtenOff      = Toast(label: "// WRITTEN OFF", tone: .success)
        static let paymentRecorded = Toast(label: "// PAYMENT RECORDED", tone: .success)
        static let approved        = Toast(label: "// INVOICE APPROVED", tone: .success)
    }

    enum Estimate {
        static let created        = Toast(label: "// ESTIMATE CREATED", tone: .success)
        static let updated        = Toast(label: "// ESTIMATE UPDATED", tone: .success)
        static let saved          = Toast(label: "// ESTIMATE SAVED", tone: .success)
        static let sent           = Toast(label: "// ESTIMATE SENT", tone: .success)
        static let converted      = Toast(label: "// ESTIMATE CONVERTED", tone: .success)
        static let progressInvoice = Toast(label: "// PROGRESS INVOICE CREATED", tone: .success)
        static let lineItemAdded   = Toast(label: "// LINE ITEM ADDED", tone: .success)
        static let lineItemUpdated = Toast(label: "// LINE ITEM UPDATED", tone: .success)
        static let lineItemDeleted = Toast(label: "// LINE ITEM DELETED", tone: .success)
    }

    enum Sync {
        static let restored = Toast(label: "// CONNECTION RESTORED", tone: .success)
        static func failed(retry: @escaping () -> Void) -> Toast {
            Toast(label: "// SYNC FAILED", tone: .error, autoDismissAfter: 0,
                  action: ToastAction(label: "RETRY", handler: retry))
        }
    }

    /// Audit list — every static event toast. Domain tasks append their entries.
    static let all: [Toast] = [
        Invoice.sent, Invoice.voided, Invoice.writtenOff, Invoice.paymentRecorded, Invoice.approved,
        Estimate.created, Estimate.updated, Estimate.saved, Estimate.sent, Estimate.converted,
        Estimate.progressInvoice, Estimate.lineItemAdded, Estimate.lineItemUpdated, Estimate.lineItemDeleted,
        Sync.restored,
    ]
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/FeedbackCatalogTests 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add OPS/Styles/Components/Feedback.swift OPSTests/Styles/FeedbackCatalogTests.swift
git commit -m "feat(toast): Feedback catalog scaffold + label contract test"
```

---

## Task 3: `.errorToast` view modifier

**Files:**
- Create: `OPS/Styles/Components/View+ErrorToast.swift`
- Test: covered indirectly; no separate unit test (it's a thin SwiftUI bridge — verified by build + domain smoke checks)

- [ ] **Step 1: Create the modifier**

```swift
import SwiftUI

extension View {
    /// Bridges a ViewModel error string to an auto-dismiss error toast. When the
    /// binding becomes non-nil/non-empty, presents an error toast with `label`
    /// and clears the binding. Replaces the `.alert("Error", isPresented:)` boilerplate.
    func errorToast(_ trigger: Binding<String?>, label: String) -> some View {
        modifier(ErrorToastModifier(trigger: trigger, label: label, actionLabel: nil, action: nil))
    }

    /// Single-action variant: manual-dismiss error toast with a tap-through.
    func errorToast(_ trigger: Binding<String?>, label: String,
                    actionLabel: String, action: @escaping () -> Void) -> some View {
        modifier(ErrorToastModifier(trigger: trigger, label: label, actionLabel: actionLabel, action: action))
    }
}

private struct ErrorToastModifier: ViewModifier {
    @Binding var trigger: String?
    let label: String
    let actionLabel: String?
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        content.onChange(of: trigger) { _, newValue in
            guard let v = newValue, !v.isEmpty else { return }
            if let actionLabel, let action {
                ToastCenter.shared.present(
                    Toast(label: label, tone: .error, autoDismissAfter: 0,
                          action: ToastAction(label: actionLabel, handler: action)))
            } else {
                ToastCenter.shared.present(Toast(label: label, tone: .error))
            }
            trigger = nil
        }
    }
}
```

- [ ] **Step 2: Verify it compiles (device build)**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add OPS/Styles/Components/View+ErrorToast.swift
git commit -m "feat(toast): .errorToast view modifier for alert→toast swap"
```

---

## Task 4: Copy pass (ops-copywriter)

**Files:** `OPS/Styles/Components/Feedback.swift` (labels only)

- [ ] **Step 1: Run the full provisional label set through `ops-copywriter`**

Compile the ~140 provisional labels (from this plan's domain tables) into one list and run the `ops-copywriter` skill over them in a single pass. Lock each to terse, uppercase, OPS-voice, `//`-prefixed copy. Resolve near-duplicates (e.g. `// CREW JOINED` vs `// JOINED CREW`, `// SIGNING IN` is an in-progress state → reconsider tone/whether it toasts at all).

- [ ] **Step 2: Apply the locked copy to the catalog as each domain enum is created**

The locked strings become the catalog source of truth. Domain tasks (5–18) use the finalized strings.

- [ ] **Step 3: Commit the locked baseline catalog**

```bash
git add OPS/Styles/Components/Feedback.swift
git commit -m "feat(toast): lock Feedback catalog copy (ops-copywriter pass)"
```

---

## Domain sweeps (Tasks 5–18)

Each sweep, per file: apply patterns P1–P5 to the listed sites, add the domain's catalog entries to `Feedback`, build, commit. **Stage with `git add -p` on any file carrying sibling WIP** (Execution rule 2). After each sweep run the device build and confirm `** BUILD SUCCEEDED **` before committing.

### Task 5: Invoices + Estimates

**Catalog adds:** `Feedback.Invoice.*` and `Feedback.Estimate.*` already scaffolded in Task 2 — verify all present.

**P1 silent successes:**
- `OPS/ViewModels/InvoiceViewModel.swift:106` recordPayment → `Invoice.paymentRecorded`
- `…:118` voidInvoice → `Invoice.voided` · `…:127` sendInvoice → `Invoice.sent` · `…:130` writeOffInvoice → `Invoice.writtenOff`
- `OPS/ViewModels/EstimateViewModel.swift:204` createEstimate → `Estimate.created` · `:260` addLineItem → `Estimate.lineItemAdded` · `:276` updateLineItem → `Estimate.lineItemUpdated` · `:285` deleteLineItem → `Estimate.lineItemDeleted` · `:295` updateTitle → `Estimate.updated` · `:309` sendEstimate → `Estimate.sent` · `:384` convertToInvoice → `Estimate.converted` · `:403` createProgressInvoice → `Estimate.progressInvoice`
- Fire in the VM methods above (exclusively user-invoked). The sheet sites `PaymentRecordSheet.swift:172`, `EstimateFormSheet.swift:307/377` are the same actions — do NOT double-fire; confirm the VM method is what they call and leave the sheets alone.

**P2 error alerts → `.errorToast`:** `InvoicesListView.swift:137`, `InvoiceDetailView.swift:102`, `EstimatesListView.swift:95`, `EstimateDetailView.swift:120` → `.errorToast($viewModel.error, label: Feedback.Err.operationFailed)`.

**P4 confirm outcomes:** `InvoicesListView.swift:115`→`Invoice.voided`, `:125`→`Invoice.writtenOff`; `InvoiceDetailView.swift:77`→`Invoice.voided`, `:88`→`Invoice.writtenOff`; `EstimatesListView.swift:85`→`Estimate.converted`; `EstimateDetailView.swift:89`→`Estimate.converted`.

**P5 fold-ins:** `PaymentRecordSheet`/`ProgressInvoiceSheet`/`EstimateFormSheet` `isSaving`/`isCreating` spinners stay during the op; completion now toasts via the VM path. `EstimateDetailView` `approvalStateBanner` stays ambient.

- [ ] Build (`generic/platform=iOS`) → SUCCEEDED. Commit `feat(invoices): route invoice/estimate feedback through Toast`.

### Task 6: Expenses

**Catalog adds (`Feedback.Expense`):** saved `// EXPENSE SAVED`, changesSaved `// CHANGES SAVED`, submitted `// EXPENSE SUBMITTED`, deleted `// EXPENSE DELETED`, approved `// EXPENSE APPROVED`, rejected `// EXPENSE REJECTED`[warning], flagged `// EXPENSE FLAGGED`[warning], flagCleared `// FLAG CLEARED`, categoryCreated `// CATEGORY CREATED`, categoryUpdated `// CATEGORY UPDATED`, settingsSaved `// SETTINGS SAVED`, allocationsSaved `// ALLOCATIONS SAVED`, invoiceApproved `// INVOICE APPROVED`, revisionsSent `// REVISIONS SENT`, ruleCreated `// RULE CREATED`, ruleUpdated `// RULE UPDATED`, ruleDeleted `// RULE DELETED`.

**P1:** `OPS/ViewModels/ExpenseViewModel.swift` — :253 createExpense, :297 updateExpense, :314 refileEditedExpense (→ changesSaved), :362 submitExpense, :341 deleteExpense, :374 approveExpense, :388 rejectExpense, :501 flagExpense, :515 unflagExpense, :418 createCategory, :434 toggleCategory, :446 saveSettings, :402 setAllocations, :536 approveInvoice, :595 sendRevisions, :701 createAutoApproveRule, :721 toggleAutoApproveRule, :731 deleteAutoApproveRule.

**P2 errors → `.errorToast`:** `MyExpensesView.swift:93`→`operationFailed`, `ExpenseSettingsView.swift:84`→`// SETTINGS UPDATE FAILED`, `ExpenseCategorySettingsView.swift:60`→`// CATEGORY UPDATE FAILED`, `ExpenseBatchDetailView.swift:110`→`// BATCH UPDATE FAILED`.

**P5:** `ExpenseFormSheet` `ApprovalBanner` + `OCRStatusBadge` stay ambient.

- [ ] Build → SUCCEEDED. Commit `feat(expenses): route expense feedback through Toast`.

### Task 7: JobBoard core

**Catalog adds (`Feedback.JobBoard`):** taskTypeCreated `// TASK TYPE CREATED`, taskTypeUpdated `// TASK TYPE UPDATED`, statusChanged `// STATUS CHANGED`, teamUpdated `// TEAM UPDATED`, clientCreated `// CLIENT CREATED`, clientUpdated `// CLIENT UPDATED`, deleted `// DELETED`.

**P1:** `TaskTypeSheet.swift:1691`/`:1778`, `ProjectManagementSheets.swift:116`/`:743`, `ClientSheet.swift:571`/`:639`, `UniversalJobBoardCard.swift:1884` (bulk delete → one toast), `TaskManagementSheets.swift:134`/`:437`.

**P2 errors:** `TaskTypeSheet.swift:239`→`saveFailed`, `:269`→`deleteFailed`, `ProjectManagementSheets.swift:319`→`// CONVERSION FAILED`, `ClientSheet.swift:380`→`saveFailed`.

**Gap-fill (Task 0 inventory):** `JobBoardView.swift:195`/`:203` (tutorial info) → toast-fyi; `ProjectFormSheet.swift:820`→`saveFailed`; `:828` DUPLICATE NAME (3-choice) → **stays modal**; `UniversalJobBoardCard.swift:388` "no tasks" → P3 single-action `actionLabel: "CREATE TASK"`; `ProjectFormSheet.swift:2167` photo source → **stays menu**.

**P5:** `UniversalJobBoardCard` `customAlert overlay` → delete, replace with `ToastCenter`.

- [ ] Build → SUCCEEDED. Commit `feat(jobboard): route project/client/task-type feedback through Toast`.

### Task 8: JobBoard tasks

**Catalog adds (`Feedback.Task`):** subTaskCreated/Updated/Deleted `// SUB-TASK …`, created `// TASK CREATED`, productAttached `// PRODUCT ATTACHED`, teamUpdated (reuse), rescheduled `// TASK RESCHEDULED`, deleted `// TASK DELETED`, statusUpdated `// STATUS UPDATED`, datesCleared `// DATES CLEARED`.

**P1:** `TaskTemplateEditSheet.swift:253/275/297`, `TaskFormSheet.swift:79`, `LinkedProductsAttachSheet.swift:278`, `TaskDetailPopupSheet.swift:419`, `TaskListView.swift:197/247`, `TaskDetailsView.swift:759/1269/1046/1101`.

**P2 errors:** `TaskFormSheet.swift:519`→`saveFailed`.

**P5:** `TaskDetailsView` `saveNotificationOverlay` (notes-saved banner) → delete, replace with `Feedback.Task` toast / `// NOTE POSTED`. `PushInMessage` team-update notification → stays ambient.

- [ ] Build → SUCCEEDED. Commit `feat(jobboard-tasks): route task feedback through Toast`.

### Task 9: Catalog

**Catalog adds (`Feedback.Catalog`):** optionMoved/Removed/Saved, priceRuleRemoved/Saved, orderUpdated, itemUpdated/Removed, orderStatusChanged, draftDeleted, materialRemoved, inventoryModeUpdated, unitSaved/Removed, tagSaved/Removed, categorySaved/Removed (labels per inventory dump).

**P1:** `ProductOptionAuthoringSheet.swift:379/422/447/873/1262`, `OrderDetailView.swift:544/593/624/643/675`, `RecipeManageSheet.swift:381`, `InventoryModeControl.swift:98`, `UnitsManageSheet.swift:258/299`, `TagsManageSheet.swift:205/230`, `CategoriesManageSheet.swift:278/321`.

**P4 outcomes:** `OrderDetailView.swift:114` (cancel-order confirm, stays modal) → `// ORDER CANCELLED`; `InventoryModeControl.swift:143` → `// INVENTORY TRACKING OFF`.

**Gap-fill confirms (stay modal):** `CategoriesManageSheet.swift:253`, `TagsManageSheet.swift:185`, `UnitsManageSheet.swift:235`, `GuidedStockSetupFlow.swift:41` (resume-draft).

**P5 fold-ins:** delete the 6 inline `errorMessage` displays (`ProductOptionAuthoringSheet`, `OrderDetailView`, `RecipeManageSheet`, `InventoryModeControl` actionError, `UnitsManageSheet`, `TagsManageSheet`, `CategoriesManageSheet`) → `.errorToast`. **Heavy sibling WIP here — `git add -p`.**

- [ ] Build → SUCCEEDED. Commit `feat(catalog): route catalog feedback through Toast`.

### Task 10: Inventory

**Catalog adds (`Feedback.Inventory`):** tagRenamed `// TAG RENAMED`, tagDeleted `// TAG DELETED`, itemCreated `// ITEM CREATED`, itemSaved `// ITEM SAVED`, itemsDeleted `// ITEMS DELETED`.

**P1:** `InventoryManageTagsSheet.swift:108/126`, `Import/ImportPreviewView.swift:572/815`, `InventoryFormSheet.swift:878` (+action) `/824`, `InventoryView.swift:991` (bulk → one toast) `/920/954`.

**P2 errors / gap-fill:** `InventoryListView.swift` alert; `InventorySettingsView.swift:151` "Add Unit" (text input) → **stays modal**.

- [ ] Build → SUCCEEDED. Commit `feat(inventory): route inventory feedback through Toast`.

### Task 11: Settings A (general/profile/team)

**Catalog adds (`Feedback.Settings`):** betaRequestSent, voteCounted, defaultTypesCreated, loggedOut, mergeComplete, profileUpdated, roleAssigned, memberRemoved, invitationRevoked, invitationsSent (+action), accountDeleted, resetLinkSent, issueReported, requestSubmitted, featureInTesting[warning].

**P1:** `WhatsNewView.swift:315/251`, `TaskSettingsView.swift:287`, `SettingsView.swift:424`, `TaskTypeMergeSheet.swift:298`, `ProfileSettingsView.swift:705/734/589`, `ManageTeamView.swift:914/966/988/1306`.

**P2 errors:** `WhatsNewView.swift:159`→`// VOTE FAILED`/`:179`→`// REQUEST FAILED`, `TaskSettingsView.swift:199`→`deleteFailed`, `SettingsView.swift:429`→`// FEATURE IN TESTING`[warning], `TaskTypeMergeSheet.swift:100`→`// MERGE FAILED`, `ProfileSettingsView.swift:289`→`saveFailed`, `ReportIssueView.swift:135`→`// ISSUE REPORTED`[success]/`:142`→`// REPORT FAILED`, `FeatureRequestView.swift:137`→`// REQUEST SUBMITTED`/`:144`→`// REQUEST FAILED`.

**Gap-fill (stay modal):** `MapSettingsView.swift:483` → P3 single-action `OPEN SETTINGS`; `LaserMeterSettingsView.swift:56` (forget device), `DataStorageSettingsView.swift:103` (clear cache), `InventorySettingsView.swift:151` (input) → stay.

**P5:** `ManageTeamView` `PushInMessage(TeamInvitesSent)` → fold into `invitationsSent` toast. Company-code copy feedback + the two loadingOverlays stay ambient.

- [ ] Build → SUCCEEDED. Commit `feat(settings): route general/profile/team feedback through Toast`.

### Task 12: Settings B (storage/permissions/subscription)

**Catalog adds (`Feedback.Settings` cont.):** spaceFreed, photosRemoved, photosPinned, photosSaved, roleUpdated, permissionUpdated, permissionsSaved, roleCreated, roleRenamed, roleDuplicated, roleDeleted, seatsUpdated, seatGranted, seatRevoked.

**P1:** `PhotoStorageManagementView.swift:465/498`, `AllPhotosGalleryView.swift:903/888`, `UserPermissionDetailView.swift:564/511`, `RoleDetailView.swift:828`, `RoleListView.swift:356`(create/rename)`/388/417`, `SeatManagementView.swift:395`, `SubscriptionLockoutView.swift:815` (granted/revoked).

**P2 errors:** `TrashView.swift:85`→`// RESTORE FAILED`, `UserPermissionDetailView.swift:122`/`RoleDetailView.swift:434`→`// FEATURE NOT AVAILABLE`, `SeatManagementView.swift:89`→`operationFailed`, `AllPhotosGalleryView.swift:319` informational → toast-fyi.

**P4:** `RoleListView.swift:149` delete confirm → `// ROLE DELETED`.

- [ ] Build → SUCCEEDED. Commit `feat(settings): route storage/permissions/subscription feedback through Toast`.

### Task 13: Project / Notes / Activity

**Catalog adds (`Feedback.Project`):** titleSaved, descriptionSaved, taskCompleted, taskCancelled, projectCompleted, projectClosed, notePosted.

**P1:** `ProjectDetailsViewModel.swift:396/429/277/312/337/362`, `ProjectNotesViewModel.swift:165`.

**P2/P3 errors:** `ProjectActionBar.swift:152` → P3 (single-action, warning); `MeasureActionButton.swift:75`, `SharePhotoToProjectSheet.swift:89` → P2.

**P5:** `ProjectDetailsView` `saveNotificationOverlay` → delete → `Project.titleSaved`/`descriptionSaved`. `ProjectActionBar` `processingImage overlay` stays ambient.

- [ ] Build → SUCCEEDED. Commit `feat(project): route project/notes feedback through Toast`.

### Task 14: Common / Client / Images / User components

**Catalog adds (`Feedback.Contact`/`Feedback.Photo`):** subContactSaved, subContactDeleted[warning], calling, messageSent, emailReady, photoAdded, photoCaptured, photoUploaded, photoRemoved, annotationSaved, commentPosted, visibilityUpdated, roleUpdated (reuse), fieldUpdated.

**P1:** `SubClientEditSheet.swift:454`, `ContactDetailSheet.swift:128/135/142`, `ProjectPhotosGrid.swift:1001`, `CameraBatchView.swift:206`, `ProfileImageUploader.swift:296/321`, `ContactDetailView.swift:1521/1571/1350/979`, `PhotoCommentViewer.swift:361/668/780`.

**P2 errors:** `FloatingActionMenu.swift:769`(warning)/`774`(success)/`781`(success), `AppHeader.swift:582`(warning), `ProjectPhotosGrid.swift:213`→`// UPLOAD FAILED`, `ProfileImageUploader.swift:117`→`// UPLOAD FAILED`.

**P4:** `ContactDetailSheet.swift:110` call confirm → `// CALLING`. Gap-fill: `SubClientEditSheet.swift:209/241(DeletionSheet)` → P2; `:214` import-conflict (2-choice) → stays modal; `PhotoCommentViewer.swift:1014` delete-comment → stays confirm.

**P5:** `Loading Overlay` (ProjectPhotosGrid) stays ambient.

- [ ] Build → SUCCEEDED. Commit `feat(components): route contact/photo feedback through Toast`.

### Task 15: Onboarding + Auth

**Catalog adds (`Feedback.Onboarding`):** codeAccepted, profileUpdated (reuse), joinedCrew, crewJoined→reconcile to ONE (`joinedCrew`), signingIn (reconsider — in-progress; likely drop or warning), accessGranted, accountCreated, companyCreated.

**P1:** `CodeEntryScreen.swift:158`, `ProfileJoinScreen.swift:329/332`, `CompanyConfirmationScreen.swift:392`, `LoginView.swift:214`, `LandingView.swift:405/498/554`, `SimplePINEntryView.swift:120`, `OnboardingViewModel.swift:512/690/1182`. **De-dup `// SIGNING IN` across 4 sites → single helper; reconsider whether sign-in success should toast at all (the app transitions screens).**

**P2/P3 errors:** `PermissionsView.swift:118`→P3 `OPEN SETTINGS` (location), `:129`→P3 `OPEN SETTINGS` (notifications); `CodeEntryScreen.swift:129`→`// INVALID CODE`, `ProfileJoinScreen.swift:53`/`CompanyConfirmationScreen.swift:241`→`// JOIN FAILED`, `LoginView.swift:192`/`LandingView.swift:371`→`// SIGN IN FAILED`, `OnboardingContainer.swift:62`→`operationFailed`.

**P4:** `CodeEntryScreen.swift:121` → `// SWITCHED TO COMPANY SETUP`[warning].

- [ ] Build → SUCCEEDED. Commit `feat(onboarding): route auth/onboarding feedback through Toast`.

### Task 16: DeckBuilder + AR (deletes a parallel toast system)

**Catalog adds (`Feedback.Deck`):** designRenamed, designCleared, houseEdgeMaterialSet, railingApplied, wallMaterialSet, railingUpdated, itemRemoved, surfacesLabeled, footprintLabeled, edgeLabeled, levelCreatedSurfacesMoved, surfacesMoved, edgesMoved, levelCreatedEdgesMoved, saved `// SAVED`.

**P1:** `DeckBuilderViewModel.swift:3108/3115/2122/2145/2167/2207/2501/2519/2536/2549/2565/2609/2645/2661/2979`.

**P2 errors:** `DeckBuilderView.swift:470`→`// SCALE REQUIRED`, `LevelTabBar.swift:46`→`// CONNECTIONS PREVENT DELETE`, `MaterialPickerSheet.swift:188` informational → keep/convert per context.

**P4:** `ARPerimeterView.swift:162` → `// AR WALK SAVED`[warning].

**P5 — delete the parallel toast system:** remove DeckBuilder's `Laser Toasts (4 variants)`, `Estimate Created Overlay`, `Save Error Overlay`, `Undo Affects All Levels Toast` → replace each with `ToastCenter.shared.present(...)`. AR Dimensions Banner / Visualization Status Bar / Tactical HUD stay ambient; Vertex Popover Menu stays.

- [ ] Build → SUCCEEDED. Commit `feat(deckbuilder): route feedback through Toast, delete bespoke laser/save overlays`.

### Task 17: Review + Calendar (deletes a parallel toast system)

**Catalog adds (`Feedback.Review`):** taskCompleted (reuse), projectClosed (reuse), reminderSent, writtenOff (reuse), scheduled `// SCHEDULED`, datesCleared (reuse).

**P1:** `TaskCompletionReviewView.swift:372`, `ProjectPaymentReviewView.swift:429/438/444`, `CalendarEventCard.swift:300/325`, `MonthGridView.swift:842`.

**P4:** `ProjectPaymentReviewView.swift:148` → `// WRITTEN OFF`. Gap-fill: `CalendarEventCard.swift:208`, `MonthGridView.swift:1752` quick-action menus → stay menu.

**P5:** delete `UnscheduledTaskReviewView` `Review Toast Overlay (Custom)` → `ToastCenter`.

- [ ] Build → SUCCEEDED. Commit `feat(review): route review/calendar feedback through Toast`.

### Task 18: Sync surfaces + measurement chips + Leads parity

**Catalog adds (`Feedback.Sync` cont. / `Feedback.Measure` / `Feedback.Lead`):** Sync.restored (done), Sync.failed (done); dimensionsSaved (+action), pdfReady; leadArchived[warning], stageAdvanced.

**P1:** `LeadsTabView.swift:186/456`, `PipelineStageListView.swift:100/174` (Leads parity — these still go through the legacy NotificationCenter bridge; standardize to `Feedback.Lead.*`). `DimensionedAnnotationView.swift:220` (+action `// DIMENSIONS SAVED`), `:224` `// PDF READY`.

**P2 errors:** `DimensionedAnnotationView.swift:33/100` (no-depth / dynamic) → error toasts.

**P5 — fold transient sync events into Toast:** `SyncRestoredAlert` (`SyncStatusIndicator.swift`) → `Feedback.Sync.restored` toast (delete the bespoke banner). `BooksSyncBanner` transient restored/failed → toasts (the persistent in-flight chip stays). Measurement `AnnotationFeedbackToast` → `ToastCenter`; `AnnotationSaveStateBanner`/`HelperTextOverlay` persistent mode states **stay ambient**.

**Stays (no change):** `NetworkStatusIndicator`, avatar `SyncStatusSection` + overlay, `ImageSyncProgressView`, `GeofenceBannerView`, `AppMessageView`, `WizardBanner`, the Supabase notification inbox.

- [ ] Build → SUCCEEDED. Commit `feat(sync): fold transient sync/measurement events into Toast; Leads parity`.

---

## Task 19: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Full test suite (queue + catalog)**

Run: `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/ToastCenterQueueTests -only-testing:OPSTests/FeedbackCatalogTests 2>&1 | tail -20`
Expected: all PASS.

- [ ] **Step 2: Confirm parallel toast systems are gone**

Run: `grep -rniE "laserToast|estimateCreatedOverlay|saveErrorOverlay|saveNotificationOverlay|customAlert|reviewToastOverlay|AnnotationFeedbackToast" --include='*.swift' OPS`
Expected: no matches (or only the catalog/ToastCenter). Investigate any remaining hit.

- [ ] **Step 3: Confirm no orphaned generic error alerts remain**

Run: `grep -rn '\.alert("Error"' --include='*.swift' OPS | wc -l`
Expected: 0 (all converted or intentionally-kept blocking errors re-titled). Reconcile against the spec's stays-modal list.

- [ ] **Step 4: Clean device build**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Update the catalog `all` audit array**

Confirm every domain enum's events are appended to `Feedback.all` so `FeedbackCatalogTests` covers them. Re-run Task 19 Step 1.

- [ ] **Step 6: Update the OPS Software Bible**

Add an "In-app feedback" subsection to the relevant bible doc documenting `ToastCenter` as the single feedback surface, the `Feedback` catalog, the tiered-error policy, and the action-boundary rule.

- [ ] **Step 7: Final commit**

```bash
git add ops-software-bible/<edited-doc>.md
git commit -m "docs(bible): document ToastCenter as the single in-app feedback surface"
```

---

## Self-review notes
- **Spec coverage:** every spec §4 unit (catalog, queue, errorToast, deletions), the policy matrix (§3), all 14 domains, sync surfaces, and the copy pass map to tasks. ✓
- **Type consistency:** `ToastCenter.present(_:)`, `.reset()`, `.queue`, `Toast(label:tone:autoDismissAfter:action:)`, `ToastAction(label:handler:)`, `Feedback.*` used consistently across Tasks 1–19. ✓
- **Known dedup work:** `// SIGNING IN` (×4), `joinedCrew`/`crewJoined`, `teamUpdated`, `statusChanged` reused across domains — reconciled in Task 4 (copy) and referenced, not redefined. ✓
- **Counts are provisional per-site;** exact final toast/modal split confirmed during each sweep against the live code (line numbers may drift ±a few from sibling WIP).
