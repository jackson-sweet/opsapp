# Expense Auto-Batching — Phase 2a (iOS App) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Collapse the field expense flow to a single **Add** — the app stops doing client-side bundling/submission and simply writes `status = 'submitted'`; the Phase 1 server trigger places and schedules it.

**Architecture:** Adding an expense creates it as a draft, attaches receipt + allocations, then sets `status = 'submitted'` — which fires the server placement trigger. Multi-receipt quick-capture still saves drafts to finish later (the server sweep bundles leftovers). The manual "Submit Expenses" selection flow and per-expense submit affordances are removed. A new `open` (filling) batch phase is recognized read-only.

**Tech Stack:** SwiftUI, SwiftData, `ops-ios/OPS`. Build: `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` (device target); tests/runtime: `-destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`.

**Hard dependency:** **Phase 1 (server brain) must be live in the target environment first** — the app relies on the server placement trigger to bundle. Do not ship 2a to a build pointed at an environment without Phase 1.

**iOS TDD note:** logic changes get an XCTest; SwiftUI changes are verified by a clean `xcodebuild` compile + a scripted simulator runtime walkthrough (Task 7). Per `ops-ios/CLAUDE.md`, check for a parallel `xcodebuild` on the same DerivedData before building (`ps aux | grep xcodebuild`).

**Files touched:**
| File | Change |
|---|---|
| `OPS/DataModels/Enums/FinancialEnums.swift` | Add `open` case to `ExpenseBatchStatus` |
| `OPS/Views/Expenses/ExpensesListView.swift` | Handle `.open` in `batchStatusColor`; keep `open` out of review (already excluded) |
| `OPS/ViewModels/ExpenseViewModel.swift` | `createExpense` gains a `status` param |
| `OPS/Views/Expenses/ExpenseFormSheet.swift` | Footer → single **ADD**; `performSave` sets `status='submitted'` instead of calling `submitExpense` |
| `OPS/Views/Expenses/ExpenseCard.swift` | `submitted`→"PENDING" badge; drop swipe-to-submit + SUBMITTED overlay |
| `OPS/Views/Expenses/MyExpensesView.swift` | Remove the "Submit Expenses" button + selection sheet + overlay + edit-warning |

---

## Task 1: Recognize the `open` (filling) batch phase

**Files:**
- Modify: `OPS/DataModels/Enums/FinancialEnums.swift:166-187`
- Modify: `OPS/Views/Expenses/ExpensesListView.swift:579-588`

- [ ] **Step 1: Confirm the compile-breakers (failing build expectation)**

Adding a case to `ExpenseBatchStatus` breaks every exhaustive `switch`. The two exhaustive switches are `displayName` (FinancialEnums.swift:174) and `batchStatusColor` (ExpensesListView.swift:579). `needsReview`/`isApproved` use `==` (won't break, and correctly exclude `open`). `CrewInvoiceHistoryView.swift` switches over the raw `String`, not the enum (won't break).

- [ ] **Step 2: Add the case + displayName**

In `FinancialEnums.swift`, edit the enum:
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

    var needsReview: Bool { self == .pendingReview || self == .submitted }
    var isApproved: Bool { self == .approved || self == .autoApproved || self == .partiallyApproved }
    var isFilling: Bool { self == .open }
}
```
`open` is deliberately excluded from `needsReview` (still filling) and `isApproved`.

- [ ] **Step 3: Handle `.open` in the color switch**

In `ExpensesListView.swift:579`:
```swift
    private func batchStatusColor(_ status: ExpenseBatchStatus) -> Color {
        switch status {
        case .open:              return OPSStyle.Colors.tertiaryText
        case .pendingReview:     return OPSStyle.Colors.warningStatus
        case .submitted:         return OPSStyle.Colors.primaryAccent
        case .approved:          return OPSStyle.Colors.successStatus
        case .partiallyApproved: return OPSStyle.Colors.warningStatus
        case .rejected:          return OPSStyle.Colors.errorStatus
        case .autoApproved:      return OPSStyle.Colors.successStatus
        }
    }
```

- [ ] **Step 4: Build (verify it compiles)**

Run: `cd ops-ios && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
Expected: `BUILD SUCCEEDED`. (Confirms every exhaustive switch now handles `open`.)

- [ ] **Step 5: Commit**
```bash
git -C ops-ios add OPS/DataModels/Enums/FinancialEnums.swift OPS/Views/Expenses/ExpensesListView.swift
git -C ops-ios commit OPS/DataModels/Enums/FinancialEnums.swift OPS/Views/Expenses/ExpensesListView.swift -m "feat(expenses): recognize 'open' (filling) batch phase on iOS"
```

---

## Task 2: `createExpense` accepts a status (so Add can create submitted)

**Files:**
- Modify: `OPS/ViewModels/ExpenseViewModel.swift:210-252`
- Test: `OPSTests/ExpenseViewModelTests.swift` (create if absent)

- [ ] **Step 1: Write the failing test**

In `OPSTests/ExpenseViewModelTests.swift`:
```swift
import XCTest
@testable import OPS

final class ExpenseCreateStatusTests: XCTestCase {
    func test_createExpense_defaultsToDraft_andHonorsExplicitStatus() {
        // CreateExpenseDTO is the payload createExpense builds; assert the status field is threaded through.
        let draft = CreateExpenseDTO(companyId: "c", submittedBy: "u", status: "draft",
            categoryId: nil, merchantName: "M", description: nil, amount: 1, taxAmount: nil,
            currency: "USD", expenseDate: "2026-04-01", paymentMethod: "cash",
            receiptImageUrl: nil, receiptThumbnailUrl: nil, ocrRawData: nil, ocrConfidence: nil)
        XCTAssertEqual(draft.status, "draft")
        let submitted = CreateExpenseDTO(companyId: "c", submittedBy: "u", status: "submitted",
            categoryId: nil, merchantName: "M", description: nil, amount: 1, taxAmount: nil,
            currency: "USD", expenseDate: "2026-04-01", paymentMethod: "cash",
            receiptImageUrl: nil, receiptThumbnailUrl: nil, ocrRawData: nil, ocrConfidence: nil)
        XCTAssertEqual(submitted.status, "submitted")
    }
}
```

- [ ] **Step 2: Run it (expect compile/fail until the param exists)**

Run: `cd ops-ios && xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/ExpenseCreateStatusTests`
Expected: builds/passes if `CreateExpenseDTO.status` already exists (it does — `ExpenseDTOs.swift`). This test pins the contract before changing the VM signature.

- [ ] **Step 3: Add the `status` parameter to `createExpense`**

In `ExpenseViewModel.swift:210`, change the signature and the DTO line (`:230`):
```swift
    func createExpense(
        companyId: String,
        submittedBy: String,
        status: String = "draft",          // NEW — Add passes "submitted"; quick-capture keeps "draft"
        categoryId: String?,
        merchantName: String?,
        description: String?,
        amount: Double,
        taxAmount: Double?,
        currency: String?,
        expenseDate: String?,
        paymentMethod: String?,
        receiptImageUrl: String?,
        receiptThumbnailUrl: String?,
        ocrRawData: [String: String]?,
        ocrConfidence: Double?
    ) async -> ExpenseDTO? {
        guard let repo = repository else { return nil }
        let dto = CreateExpenseDTO(
            companyId: companyId,
            submittedBy: submittedBy,
            status: status,                 // was hardcoded "draft"
            categoryId: categoryId,
            // …unchanged…
```

- [ ] **Step 4: Build + run the test** — `xcodebuild test … -only-testing:OPSTests/ExpenseCreateStatusTests` → PASS.

- [ ] **Step 5: Commit**
```bash
git -C ops-ios add OPS/ViewModels/ExpenseViewModel.swift OPSTests/ExpenseViewModelTests.swift
git -C ops-ios commit OPS/ViewModels/ExpenseViewModel.swift OPSTests/ExpenseViewModelTests.swift -m "feat(expenses): createExpense accepts status (default draft)"
```

---

## Task 3: Form footer → single ADD; placement via server (not client submit)

**Files:**
- Modify: `OPS/Views/Expenses/ExpenseFormSheet.swift` (footer `:795-902`; `performSave` `:1137-1192`)

The behavioral core: **Add** creates a draft, attaches receipt + allocations, then sets `status='submitted'` — the Phase 1 trigger places it. We no longer call `viewModel.submitExpense` (that was client-side bundling, now the server's job).

- [ ] **Step 1: Replace the new-expense footer (`:795-821`)**
```swift
                } else if editing == nil {
                    // NEW expense — single Add. Server places & schedules; no manual submit.
                    if hasMoreReceipts {
                        Button { Task { await saveAndAdvance() } } label: {
                            Text("SAVE & NEXT (\(remainingReceiptCount) LEFT)")
                                .font(OPSStyle.Typography.button)
                        }
                        .opsPrimaryButtonStyle()
                    } else {
                        Button { Task { await save(submit: true) } } label: {
                            Text("ADD").font(OPSStyle.Typography.button)
                        }
                        .opsPrimaryButtonStyle()
                    }
                }
```
(`saveAndAdvance` already creates drafts — unchanged. The single `ADD` uses `save(submit: true)`, whose meaning changes in Step 3.)

- [ ] **Step 2: Simplify the edit-mode footer (`:859-901`)** — drop SUBMIT/RESUBMIT (server owns submission); editing a pending or rejected expense just saves:
```swift
                } else {
                    // Edit mode for draft/submitted/rejected — Save only. Server keeps/refreshes placement.
                    Button { Task { await save(submit: false) } } label: {
                        Text("SAVE").font(OPSStyle.Typography.button)
                    }
                    .opsPrimaryButtonStyle()
                }
```
Also in the `isViewMode` branch (`:842-858`), delete the `if expenseStatus == .draft { SUBMIT }` and `else if .rejected { RESUBMIT }` buttons — leave only the `EDIT` button.

- [ ] **Step 3: `performSave` — set `status='submitted'` instead of client bundling**

In `ExpenseFormSheet.swift`, the new-expense branch (`:1141-1191`): pass the create status and replace the submit call. Create as draft first (so receipt + allocations attach), then flip to submitted:
```swift
        } else {
            let created = await viewModel.createExpense(
                companyId: companyId,
                submittedBy: userId,
                status: "draft",                         // create draft; flip to submitted after attachments
                categoryId: selectedCategoryId,
                merchantName: merchantName.isEmpty ? nil : merchantName,
                description: descriptionValue,
                amount: amountValue,
                taxAmount: taxValue,
                currency: selectedCurrency,
                expenseDate: dateString,
                paymentMethod: paymentMethod.rawValue,
                receiptImageUrl: nil,
                receiptThumbnailUrl: nil,
                ocrRawData: ocrData,
                ocrConfidence: ocrConfidence
            )

            if let created = created {
                // …existing receipt upload block unchanged…
                // …existing allocations block unchanged…

                if submit && viewModel.error == nil {
                    // Server places via the expenses placement trigger when status -> submitted.
                    await viewModel.updateExpense(created.id,
                        fields: UpdateExpenseDTO(status: ExpenseStatus.submitted.rawValue))
                }
            }
        }
```
And in the editing branch (`:1137-1139`), replace `if submit { await viewModel.submitExpense(exp.id) }` with the same `updateExpense(... status: submitted ...)` call so a re-saved rejected expense re-places via the server. The existing `wasSubmitted` reset-to-draft logic (`:1082-1100`) stays — editing a submitted expense still resets it to draft + clears `batch_id`, and the server re-places it on the subsequent submitted flip.

- [ ] **Step 4: Build** — `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` → `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**
```bash
git -C ops-ios add OPS/Views/Expenses/ExpenseFormSheet.swift
git -C ops-ios commit OPS/Views/Expenses/ExpenseFormSheet.swift -m "feat(expenses): single Add — server-side placement replaces client submit"
```

---

## Task 4: Card — PENDING badge, no manual-submit affordances

**Files:**
- Modify: `OPS/Views/Expenses/ExpenseCard.swift`

- [ ] **Step 1: Badge wording — `submitted` reads "PENDING" (not "SUBMITTED")**

In the `badgeColor`/`displayName` usage: `ExpenseStatus.displayName` is `rawValue.uppercased()` → "SUBMITTED". Add a card-local label so a placed expense reads as *pending the office*. In `ExpenseCard.swift`, replace `statusBadge`'s `Text(expenseStatus.displayName)` with:
```swift
            Text(expenseStatus == .submitted ? "PENDING" : expenseStatus.displayName)
```

- [ ] **Step 2: Remove swipe-to-submit**

`canSwipeRight` (`:51-53`) currently enables a SUBMIT swipe for drafts. In the single-Add model there's no manual submit; a draft is an unfinished capture you *complete* by tapping. Set:
```swift
    private var canSwipeRight: Bool { false }
```
and delete the swipe-right reveal block (`:82-95`) and its branch in `.onEnded` (`:119-121`). Keep swipe-left (delete) intact.

- [ ] **Step 3: Drop the "SUBMITTED" overlay**

Delete the `if isSubmitted { … "SUBMITTED" overlay … }` block (`:192-215`) and the `.opacity(isSubmitted ? 0.5 : 1.0)` dimming (`:190`) — a pending expense is normal, not dimmed. Keep the accent border for `isSubmitted` if desired, or simplify to the standard border.

- [ ] **Step 4: Build** → `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**
```bash
git -C ops-ios add OPS/Views/Expenses/ExpenseCard.swift
git -C ops-ios commit OPS/Views/Expenses/ExpenseCard.swift -m "feat(expenses): card shows PENDING, drops manual-submit affordances"
```

---

## Task 5: Strip manual submission from MyExpensesView

**Files:**
- Modify: `OPS/Views/Expenses/MyExpensesView.swift`

- [ ] **Step 1: Remove the "Submit Expenses" entry point**

Delete the `submitForReviewButton` call in the body (`:61-62`) and the property (`:181-207`); delete `submitExpensesForReview()` (`:209-255`), `submitLoadingOverlay` (`:258-297`), `submitSelectionSheet` (`:301-474`), the `.sheet(isPresented: $showSubmitSelectionSheet)` (`:99-101`), the `.overlay { if showSubmitLoadingOverlay … }` (`:86-92`), and the now-unused `@State` (`isSubmitting`, `showSubmitLoadingOverlay`, `submitLoadingComplete`, `showSubmitSelectionSheet`, `selectedExpenseIdsForSubmit`) and helpers (`draftExpenses`, `selectedExpensesWithIssues`, `canSubmitSelected`).

- [ ] **Step 2: Remove the edit-cancels-submission warning**

Delete the `.confirmationDialog("Editing will cancel your current submission…")` (`:110-131`) and the `showEditWarning`/`pendingEditExpense`/`hideEditWarning` state. In `expenseCardView`'s `onEdit` (`:601-609`) and `onSwipeRight` (`:610-614`): drop the warning branch and the swipe-submit. `onEdit` becomes just `{ editingExpense = expense }`; remove `onSwipeRight`'s body (card no longer swipes right per Task 4) — pass an empty closure or update the `ExpenseCard` call site to match its (now swipe-right-less) API.

- [ ] **Step 3: Build** → `BUILD SUCCEEDED`. (Confirms all removed symbols are fully unwired.)

- [ ] **Step 4: Commit**
```bash
git -C ops-ios add OPS/Views/Expenses/MyExpensesView.swift
git -C ops-ios commit OPS/Views/Expenses/MyExpensesView.swift -m "feat(expenses): remove manual submit flow — Add is the only action"
```

---

## Task 6: Office review hub — confirm `open` stays out of review

**Files:**
- Modify (verify): `OPS/Views/Expenses/ExpensesListView.swift`

- [ ] **Step 1: Confirm `open` batches don't surface as needing review**

`needsReviewBatches` (`:44-46`) filters `batchStatus($0).needsReview`. With Task 1, `open.needsReview == false`, so filling envelopes never appear in the office "NEEDS REVIEW" list. No code change needed — assert by reading. The orphan-recovery banner (`:138-189`) stays as defense-in-depth; with the Phase 1 safety net it should report `0` and stay hidden.

- [ ] **Step 2: Build** (no-op build to confirm nothing regressed) → `BUILD SUCCEEDED`.

(No commit if no change. If you optionally added an `open` "still filling" peek section, commit it here.)

---

## Task 7: Runtime walkthrough + bible + final verification

**Files:**
- Modify: `ops-software-bible/09_FINANCIAL_SYSTEM.md` (iOS single-Add UX + server placement)

- [ ] **Step 1: Runtime walkthrough on the simulator** (Phase 1 must be live in the pointed environment)

Run: `cd ops-ios && xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` then launch the app in the simulator. Verify:
1. New expense form shows a single **ADD** (no SAVE DRAFT / SUBMIT). Tapping ADD dismisses; the expense appears with a **PENDING** badge.
2. In Supabase (MCP `execute_sql`), the new expense has `status='submitted'` and a non-null `batch_id` in an `open` envelope — confirming the server trigger placed it.
3. `MyExpensesView` has no "Submit Expenses" button; drafts (from multi-capture) are completable by tapping.
4. Office `ExpensesListView` does **not** show the `open` envelope under "NEEDS REVIEW".

- [ ] **Step 2: Update the bible** — in `09_FINANCIAL_SYSTEM.md`, document the iOS single-Add flow and that placement/submission is server-authoritative (the app sets `status='submitted'`; the trigger bundles). Date it `(2026-06-01)`. Reference the Phase 1 plan + this plan.
```bash
git -C ops-software-bible add 09_FINANCIAL_SYSTEM.md
git -C ops-software-bible commit 09_FINANCIAL_SYSTEM.md -m "docs(bible): iOS single-Add expense flow (server-authoritative placement)"
```

---

## Self-review (against the spec)

- **Spec §5.1 single Add** → Task 3 footer + `performSave`. ✔
- **Spec §5.1 drafts for quick-capture** → `SAVE & NEXT` retained (Task 3); draft completion via tap (Task 5). ✔
- **Spec §3 `open` phase recognized** → Task 1. ✔
- **Spec §5.1 card states (pending)** → Task 4. ✔
- **Manual-submit removed** → Tasks 3, 4, 5. ✔
- **Server owns placement** → `submitExpense` replaced by `updateExpense(status:submitted)` (Task 3). ✔
- **No client double-placing** → the app no longer calls `get_or_create_open_batch`/`assignExpensesToBatch`; the trigger is the only placer. ✔
- **Placeholder scan:** the one judgment step (optional `open` peek section, Task 6) is explicitly optional, not a gap. ✔
- **Edge — per_job scope timing:** Add creates draft → attaches allocations → flips to submitted, so the trigger sees allocations when placing per-job scope. ✔

**Open follow-ups (not blockers):** `viewModel.submitExpense(_:)` and `recoverOrphans()` become near-vestigial once Phase 1 is live (the server never strands). Leave as defense-in-depth; a later cleanup can remove them. Noted, not deferred work for this plan's goal.

**Depends on:** Phase 1 (server) live. **Paired with:** Phase 2b (web office peek + early-clear).
