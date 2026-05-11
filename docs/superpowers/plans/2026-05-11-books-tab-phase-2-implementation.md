# BOOKS Tab — Phase 2 Implementation Plan (Ship-Ready Completion)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the BOOKS tab to 100% feature-complete for customer launch. Close dead FAB TODOs (InvoiceFormSheet + PaymentRecordSheet refactor), retrofit per-company `pipeline_stage_configs`, and ship deferred Pipeline UX surfaces (AI fields, images/lat-lng, scoped search, contact import).

**Architecture:** 7 sequential chunks, each spawned as a fresh agent worktree session sized for ~500k tokens. Order: 2A→2B→2C→2D→2E→2F→2G. The risky refactor (2C — replace `PipelineStage` enum with data-driven registry) is sandwiched after the visible-win Money chunks and before the additive Pipeline extensions, so subsequent chunks build on the stable data layer.

**Tech Stack:** SwiftUI · SwiftData · Supabase Swift client · Combine · MapKit · CoreLocation · Contacts · PhotosUI · XCTest. iOS-only.

**Spec:** [`docs/superpowers/specs/2026-05-11-books-tab-phase-2-design.md`](../specs/2026-05-11-books-tab-phase-2-design.md)

**Build verification:** Per `~/.claude/projects/-Users-jacksonsweet-Projects-OPS/memory/feedback_no_xcodebuild.md`: **no agent runs `xcodebuild`** in this project (parallel-session collisions). Each chunk completes by writing code + atomic commits, then reports to the PM. The PM coordinates with the user to run builds.

---

## Conventions

- **No xcodebuild from any agent.** When a task says "verify build," the agent commits + reports; the PM/user runs the build.
- **Tests:** Add XCTest unit tests under `OPSTests/Pipeline/` or `OPSTests/Books/`. Test files compile-checked via build-for-testing run by the user, not the agent.
- **Commits:** Atomic, descriptive, one logical change. **NEVER include Claude as co-author** (per `ops-ios/CLAUDE.md`). NEVER use `--no-verify`.
- **Tokens:** Every color/spacing/typography/animation must use `OPSStyle.*`. No hardcoded values. New BOOKS code never uses deprecated `cardBackgroundDark` — always `cardBackground` or glass surfaces.
- **Animation:** Only `OPSStyle.Animation.standard` and `.fast`. **No `.spring`** anywhere in Phase 2.
- **Date utilities:** Use `SupabaseDate.parse()` / `SupabaseDate.format()` — existing.
- **Working dirs:**
  - iOS work: `/Users/jacksonsweet/Projects/OPS/ops-ios`
  - Bible / migrations: `/Users/jacksonsweet/Projects/OPS/ops-software-bible`

---

## Chunk Index

| Chunk | Tasks | Risk | Files Created | Files Modified | Files Deleted |
|---|---|---|---|---|---|
| 2A | T1–T10 | Low | 4 | 3 | 0 |
| 2B | T11–T15 | Low | 0 | 2 | 0 |
| 2C | T16–T26 | **High** | 5 + 1 migration | ~15 | 1 |
| 2D | T27–T30 | Low | 0 | 4 | 0 |
| 2E | T31–T36 | Medium | 4 + 1 migration | 4 | 0 |
| 2F | T37–T39 | Low | 0 | 4 | 0 |
| 2G | T40–T44 | Medium | 2 | 2 | 0 |

---

## Chunk 2A — InvoiceFormSheet

### Task 1: Investigate how iOS estimates currently get their estimate_number

**Goal:** Resolve the open question from spec §19 — `EstimateRepository.create()` is a one-step insert with no `get_next_document_number` call, but `estimate_number` is NOT NULL on the DB. Find out how that works before mirroring for invoices.

**Files:**
- Read: `OPS/Network/Supabase/DTOs/EstimateDTOs.swift` (full body)
- Read: `OPS/Network/Supabase/Repositories/EstimateRepository.swift` (full body)
- Read: `OPS/Views/Estimates/EstimateFormSheet.swift` (full body, ~382 lines)

- [ ] **Step 1: Read `CreateEstimateDTO`**

Run: `grep -A30 "struct CreateEstimateDTO" OPS/Network/Supabase/DTOs/EstimateDTOs.swift`
Determine: does `CreateEstimateDTO` include `estimateNumber`? If yes, where is it computed?

- [ ] **Step 2: Read `EstimateFormSheet` save path**

Run: `grep -B2 -A30 "func save\|func submit\|onCreate\|repository.create" OPS/Views/Estimates/EstimateFormSheet.swift`
Determine: does the form call `get_next_document_number` before constructing the DTO? Or does it call some other helper?

- [ ] **Step 3: If number generation happens in the form (not repo), document the pattern**

Write findings to a scratch file `/tmp/estimate-number-pattern.md` for reference. Note in the implementation report whether iOS:
- (a) Calls `get_next_document_number` from the form / view model and includes it in `CreateEstimateDTO`
- (b) Sends `nil` and relies on a database default we missed
- (c) Has a silent bug (estimates can't actually be created from iOS today)

If (c), STOP and report — InvoiceFormSheet has the same problem to solve from scratch, which changes Chunk 2A scope significantly.

- [ ] **Step 4: No commit. This is an investigation task.**

The findings inform Tasks 2–10. No code changes.

---

### Task 2: Add `CreateInvoiceDTO` to `InvoiceDTOs.swift`

**Files:**
- Modify: `OPS/Network/Supabase/DTOs/InvoiceDTOs.swift` (append at end)

- [ ] **Step 1: Confirm absence of existing struct**

Run: `grep -n "struct CreateInvoiceDTO" OPS/Network/Supabase/DTOs/InvoiceDTOs.swift`
Expected: empty. Confirms must-create.

- [ ] **Step 2: Append `CreateInvoiceDTO`**

Append to `OPS/Network/Supabase/DTOs/InvoiceDTOs.swift`:

```swift
// MARK: - Create Invoice

/// DTO for creating a new invoice. Matches the NOT NULL set on public.invoices.
/// `invoiceNumber` is required by schema — caller must populate it (typically
/// via `get_next_document_number(p_company_id, 'invoice')` RPC) before sending.
struct CreateInvoiceDTO: Codable {
    let companyId: String
    let clientId: String
    let invoiceNumber: String
    let issueDate: String              // YYYY-MM-DD
    let dueDate: String                // YYYY-MM-DD
    let status: String                 // InvoiceStatus rawValue
    let subtotal: Double
    let discountType: String?
    let discountValue: Double?
    let discountAmount: Double
    let taxRate: Double?
    let taxAmount: Double
    let total: Double
    let amountPaid: Double             // typically 0 on create
    let depositApplied: Double         // typically 0 on create
    let balanceDue: Double             // typically equal to total on create
    let subject: String?
    let clientMessage: String?
    let internalNotes: String?
    let footer: String?
    let terms: String?
    let paymentTerms: String?
    let projectId: String?
    let estimateId: String?
    let opportunityId: String?
    let templateId: String?
    let createdBy: String?

    enum CodingKeys: String, CodingKey {
        case companyId        = "company_id"
        case clientId         = "client_id"
        case invoiceNumber    = "invoice_number"
        case issueDate        = "issue_date"
        case dueDate          = "due_date"
        case status
        case subtotal
        case discountType     = "discount_type"
        case discountValue    = "discount_value"
        case discountAmount   = "discount_amount"
        case taxRate          = "tax_rate"
        case taxAmount        = "tax_amount"
        case total
        case amountPaid       = "amount_paid"
        case depositApplied   = "deposit_applied"
        case balanceDue       = "balance_due"
        case subject
        case clientMessage    = "client_message"
        case internalNotes    = "internal_notes"
        case footer
        case terms
        case paymentTerms     = "payment_terms"
        case projectId        = "project_id"
        case estimateId       = "estimate_id"
        case opportunityId    = "opportunity_id"
        case templateId       = "template_id"
        case createdBy        = "created_by"
    }
}
```

- [ ] **Step 3: Verify `CreateLineItemDTO` is reusable for invoices**

Run: `grep -A20 "struct CreateLineItemDTO" OPS/Network/Supabase/DTOs/EstimateDTOs.swift`
Read the struct. Determine: does it require `estimateId` only, or does it have a polymorphic `documentId` / both `estimateId` + `invoiceId`?

If estimate-only, append `CreateInvoiceLineItemDTO` to `InvoiceDTOs.swift` mirroring its shape but with `invoiceId: String` instead of `estimateId`. Use the actual `line_items` table column name (probably `invoice_id` for invoice-line-items — verify via Supabase if needed).

- [ ] **Step 4: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios
git add OPS/Network/Supabase/DTOs/InvoiceDTOs.swift
git commit -m "Add CreateInvoiceDTO matching invoices schema NOT NULL set"
```

---

### Task 3: Add `InvoiceRepository.create(_:)`

**Files:**
- Modify: `OPS/Network/Supabase/Repositories/InvoiceRepository.swift` (append method)

- [ ] **Step 1: Read existing methods to find the right insertion point**

Run: `grep -n "func " OPS/Network/Supabase/Repositories/InvoiceRepository.swift`

- [ ] **Step 2: Append `create(_:)` method (and number-allocation helper)**

Insert after `fetchOne(_:)` and before `recordPayment(_:)`:

```swift
// MARK: - Create

/// Allocate the next invoice number for this company via the
/// `get_next_document_number` RPC. Returns format `INV-YYYY-NNNNN`.
func nextInvoiceNumber() async throws -> String {
    struct Params: Encodable {
        let p_company_id: String
        let p_type: String
    }
    let params = Params(p_company_id: companyId, p_type: "invoice")
    let result: String = try await client
        .rpc("get_next_document_number", params: params)
        .execute()
        .value
    return result
}

/// Create a new invoice. Caller must populate `invoiceNumber` via
/// `nextInvoiceNumber()` first. Inserts the header row; line items are
/// inserted separately via `addLineItem(_:)`.
func create(_ dto: CreateInvoiceDTO) async throws -> InvoiceDTO {
    try await client
        .from("invoices")
        .insert(dto)
        .select()
        .single()
        .execute()
        .value
}

/// Append a line item to an existing invoice. Uses the same line_items
/// table that estimates use; column-naming-difference resolved in DTO.
func addLineItem(_ dto: CreateInvoiceLineItemDTO) async throws -> InvoiceLineItemDTO {
    try await client
        .from("line_items")
        .insert(dto)
        .select()
        .single()
        .execute()
        .value
}
```

(If Task 2 Step 3 found that the existing `CreateLineItemDTO` works for invoices, use it instead of `CreateInvoiceLineItemDTO`. Same for the response type — use `EstimateLineItemDTO` if line items aren't context-typed, or define `InvoiceLineItemDTO` if they are.)

- [ ] **Step 3: Commit**

```bash
git add OPS/Network/Supabase/Repositories/InvoiceRepository.swift
git commit -m "Add InvoiceRepository.create() and nextInvoiceNumber() RPC wrapper"
```

---

### Task 4: Read `EstimateFormSheet` to identify reusable form components

**Goal:** Identify which sub-components of `EstimateFormSheet` (line-item editor, client picker, discount/tax sections, etc.) can be reused for `InvoiceFormSheet` vs. need to be duplicated/extracted.

**Files:**
- Read: `OPS/Views/Estimates/EstimateFormSheet.swift`
- Read: `OPS/Views/Estimates/LineItemEditSheet.swift` (if exists)
- Read: `OPS/Views/Estimates/ProductPickerSheet.swift` (if exists)

- [ ] **Step 1: Catalog the sub-components used by EstimateFormSheet**

Run: `grep -nE "struct |^private struct |sheet\(|ContactPicker|LineItemEditSheet|ProductPickerSheet" OPS/Views/Estimates/EstimateFormSheet.swift`

- [ ] **Step 2: Document reusability decisions in a scratch file**

Write `/tmp/estimate-form-component-reuse.md` listing:
- Components that are already shared (used by both estimates and invoices) — reuse
- Components that are estimate-specific but generic in shape — extract to a shared location
- Components that are estimate-specific and contextual (e.g. payment milestones) — skip for invoices (per spec §4.5 + §18 #6)

- [ ] **Step 3: No commit (investigation task)**

---

### Task 5: Build `InvoiceFormSheet.swift` (skeleton)

**Files:**
- Create: `OPS/Views/Invoices/InvoiceFormSheet.swift`

- [ ] **Step 1: Create the file with the form skeleton**

```swift
//
//  InvoiceFormSheet.swift
//  OPS
//
//  Modal form for creating new invoices. Mirrors EstimateFormSheet.
//  Triggered from FloatingActionMenu (BOOKS Invoices segment) or InvoiceListView "+" button.
//

import SwiftUI

struct InvoiceFormSheet: View {
    @ObservedObject var viewModel: InvoiceViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    // MARK: - Form state

    @State private var clientId: String? = nil
    @State private var clientName: String = ""
    @State private var subject: String = ""
    @State private var clientMessage: String = ""
    @State private var internalNotes: String = ""
    @State private var lineItems: [EditableLineItem] = []
    @State private var discountType: DiscountType? = nil
    @State private var discountValue: String = ""
    @State private var taxRateText: String = ""
    @State private var issueDate: Date = Date()
    @State private var dueDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var paymentTerms: PaymentTerms = .net30
    @State private var projectId: String? = nil
    @State private var estimateId: String? = nil

    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var showClientPicker = false

    // MARK: - Optional prefill from estimate (when "convert to invoice" path)

    /// When set, line items + client are prefilled from the source estimate.
    var sourceEstimate: Estimate? = nil

    // MARK: - Computed pricing

    private var subtotal: Double {
        lineItems.reduce(0) { $0 + $1.lineTotal }
    }

    private var discountAmount: Double {
        guard let type = discountType, let val = Double(discountValue) else { return 0 }
        switch type {
        case .percentage: return subtotal * (val / 100)
        case .fixed:      return val
        }
    }

    private var taxableBase: Double { max(0, subtotal - discountAmount) }
    private var taxRate: Double? { Double(taxRateText) }
    private var taxAmount: Double { taxableBase * ((taxRate ?? 0) / 100) }
    private var total: Double { taxableBase + taxAmount }

    private var canSave: Bool {
        clientId != nil && !lineItems.isEmpty && !isSaving
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                        clientSection
                        contentSection
                        lineItemsSection
                        pricingSection
                        datesSection
                        notesSection
                        if let saveError {
                            Text(saveError)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .navigationTitle("NEW INVOICE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("CREATE") { Task { await save() } }
                        .foregroundColor(canSave ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { applySourceEstimateIfPresent() }
    }

    // MARK: - Subsections (declared in extensions below for organization)
}
```

- [ ] **Step 2: Commit (form skeleton compiles, sections stubbed)**

```bash
git add OPS/Views/Invoices/InvoiceFormSheet.swift
git commit -m "Add InvoiceFormSheet skeleton (state + body shell)"
```

---

### Task 6: Implement InvoiceFormSheet sections (client, content, line items, pricing, dates, notes)

**Files:**
- Modify: `OPS/Views/Invoices/InvoiceFormSheet.swift` (extend)

- [ ] **Step 1: Add subsection extensions**

Append to the same file (after the main `struct` body):

```swift
// MARK: - Sections

extension InvoiceFormSheet {

    private var clientSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("CLIENT *")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Button(action: { showClientPicker = true }) {
                HStack {
                    Text(clientName.isEmpty ? "SELECT A CLIENT…" : clientName.uppercased())
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(clientId == nil ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(OPSStyle.Layout.spacing2_5)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .background(OPSStyle.Colors.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            }
        }
        .sheet(isPresented: $showClientPicker) {
            // Reuse existing client picker; signature will need verification
            // against the actual ContactPicker / ClientPicker pattern in OPS.
            // Placeholder: assume a `ClientPicker` view exists with onSelect callback.
            // If the project uses ContactPicker for clients, adapt accordingly.
            Text("ClientPicker placeholder — replace with the project's actual client-pick sheet")
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("DETAILS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            labeledField("SUBJECT", text: $subject, placeholder: "Optional")
            labeledTextEditor("CLIENT MESSAGE", text: $clientMessage)
        }
    }

    private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text("LINE ITEMS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                Button("+ ADD") { addBlankLineItem() }
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            if lineItems.isEmpty {
                Text("No line items yet")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(OPSStyle.Layout.spacing2)
            } else {
                ForEach($lineItems) { $item in
                    lineItemRow($item)
                }
            }
        }
    }

    @ViewBuilder
    private func lineItemRow(_ item: Binding<EditableLineItem>) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            TextField("Description", text: item.description)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            HStack(spacing: OPSStyle.Layout.spacing2) {
                TextField("Qty", text: item.quantityText)
                    .keyboardType(.decimalPad)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: 60)
                Text("×")
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                TextField("Unit price", text: item.unitPriceText)
                    .keyboardType(.decimalPad)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                Text(item.wrappedValue.lineTotal, format: .currency(code: "USD"))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Button(action: { removeLineItem(id: item.wrappedValue.id) }) {
                    Image(systemName: "trash")
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                }
            }
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("PRICING")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            HStack {
                Text("SUBTOTAL")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Text(subtotal, format: .currency(code: "USD"))
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            // discount + tax inputs (compact; mirror EstimateFormSheet's exact layout)
            labeledField("DISCOUNT (%)", text: $discountValue, placeholder: "0", keyboard: .decimalPad)
            labeledField("TAX RATE (%)", text: $taxRateText, placeholder: "0", keyboard: .decimalPad)
            HStack {
                Text("TOTAL")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                Text(total, format: .currency(code: "USD"))
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
    }

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("DATES")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            DatePicker("Issue", selection: $issueDate, displayedComponents: .date)
                .colorScheme(.dark)
            DatePicker("Due", selection: $dueDate, in: issueDate..., displayedComponents: .date)
                .colorScheme(.dark)
            Picker("Payment terms", selection: $paymentTerms) {
                ForEach(PaymentTerms.allCases, id: \.self) { t in
                    Text(t.displayName).tag(t)
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("INTERNAL NOTES")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            labeledTextEditor("Internal", text: $internalNotes)
        }
    }

    // MARK: - Helpers

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String = "", keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(OPSStyle.Layout.spacing2_5)
                .background(OPSStyle.Colors.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        }
    }

    private func labeledTextEditor(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            TextEditor(text: text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .scrollContentBackground(.hidden)
                .padding(OPSStyle.Layout.spacing2)
                .frame(minHeight: 80)
                .background(OPSStyle.Colors.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        }
    }

    private func addBlankLineItem() {
        lineItems.append(EditableLineItem())
    }

    private func removeLineItem(id: String) {
        lineItems.removeAll { $0.id == id }
    }

    private func applySourceEstimateIfPresent() {
        guard let est = sourceEstimate else { return }
        clientId = est.clientId
        // Prefill line items from estimate.lineItems if available.
        // Implementation: depends on whether Estimate.lineItems are loaded — verify.
        subject = est.title ?? ""
        clientMessage = est.clientMessage ?? ""
        // Don't carry over internalNotes (different scope).
    }
}

// MARK: - Editable Line Item Model

struct EditableLineItem: Identifiable {
    let id: String = UUID().uuidString
    var description: String = ""
    var quantityText: String = "1"
    var unitPriceText: String = "0"

    var quantity: Double { Double(quantityText) ?? 0 }
    var unitPrice: Double { Double(unitPriceText) ?? 0 }
    var lineTotal: Double { quantity * unitPrice }
}
```

(If `EditableLineItem` already exists in the project — e.g. via `EstimateFormSheet` — extract to a shared file `OPS/Views/Common/EditableLineItem.swift` and import. Otherwise this file owns it.)

- [ ] **Step 2: Commit**

```bash
git add OPS/Views/Invoices/InvoiceFormSheet.swift
git commit -m "Build out InvoiceFormSheet sections (client, line items, pricing, dates, notes)"
```

---

### Task 7: Implement `InvoiceFormSheet.save()` flow

**Files:**
- Modify: `OPS/Views/Invoices/InvoiceFormSheet.swift` (add save method)

- [ ] **Step 1: Append `save()` to the extension**

Add inside the `extension InvoiceFormSheet` block:

```swift
// MARK: - Save

private func save() async {
    guard let companyId = dataController.currentUser?.companyId,
          let clientId = self.clientId else { return }
    isSaving = true
    saveError = nil
    defer { isSaving = false }

    let repo = InvoiceRepository(companyId: companyId)

    do {
        // 1. Allocate invoice number
        let invoiceNumber = try await repo.nextInvoiceNumber()

        // 2. Build header DTO
        let dto = CreateInvoiceDTO(
            companyId: companyId,
            clientId: clientId,
            invoiceNumber: invoiceNumber,
            issueDate: SupabaseDate.formatDate(issueDate),
            dueDate: SupabaseDate.formatDate(dueDate),
            status: InvoiceStatus.draft.rawValue,
            subtotal: subtotal,
            discountType: discountType?.rawValue,
            discountValue: discountValue.isEmpty ? nil : Double(discountValue),
            discountAmount: discountAmount,
            taxRate: taxRate,
            taxAmount: taxAmount,
            total: total,
            amountPaid: 0,
            depositApplied: 0,
            balanceDue: total,
            subject: subject.isEmpty ? nil : subject,
            clientMessage: clientMessage.isEmpty ? nil : clientMessage,
            internalNotes: internalNotes.isEmpty ? nil : internalNotes,
            footer: nil,
            terms: nil,
            paymentTerms: paymentTerms.rawValue,
            projectId: projectId,
            estimateId: estimateId,
            opportunityId: nil,
            templateId: nil,
            createdBy: dataController.currentUser?.id
        )

        // 3. Insert invoice header
        let inserted = try await repo.create(dto)

        // 4. Insert line items
        for item in lineItems where !item.description.isEmpty {
            let lineDTO = CreateInvoiceLineItemDTO(
                invoiceId: inserted.id,
                description: item.description,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                lineTotal: item.lineTotal
            )
            _ = try await repo.addLineItem(lineDTO)
        }

        // 5. Notify + dismiss
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        NotificationCenter.default.post(name: Notification.Name("InvoiceCreatedSuccess"), object: nil)
        dismiss()
    } catch {
        saveError = error.localizedDescription
    }
}
```

(If `SupabaseDate.formatDate(_:)` doesn't exist — check via `grep "func formatDate\|static func format" OPS/Network/Supabase/`. Use whatever YYYY-MM-DD formatting helper the project has, or inline a `DateFormatter`.)

- [ ] **Step 2: Commit**

```bash
git add OPS/Views/Invoices/InvoiceFormSheet.swift
git commit -m "Wire InvoiceFormSheet.save() — RPC for number, header insert, line items batch"
```

---

### Task 8: Wire FAB MONEY group's "New Invoice" action

**Files:**
- Modify: `OPS/Views/Components/FloatingActionMenu.swift` (replace TODO with active sheet)

- [ ] **Step 1: Locate the current TODO line and the existing `showingCreateInvoice` state**

Run: `grep -n "showingCreateInvoice\|InvoiceFormSheet\|TODO.*Invoice" OPS/Views/Components/FloatingActionMenu.swift`
Expected: state var declared at line 101, used as a flag at line 387 (action), commented `.sheet(...)` at lines 832-833.

- [ ] **Step 2: Replace the commented sheet wiring with active**

Replace:
```swift
// TODO: Wire up when InvoiceFormSheet is implemented
// .sheet(isPresented: $showingCreateInvoice) { InvoiceFormSheet() }
```

With:
```swift
.sheet(isPresented: $showingCreateInvoice) {
    InvoiceFormSheet(viewModel: invoiceViewModel)
        .environmentObject(dataController)
}
```

(`invoiceViewModel` is already a `@StateObject` declared at line ~114. Verify the variable name matches.)

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Components/FloatingActionMenu.swift
git commit -m "FAB: wire 'New Invoice' to InvoiceFormSheet (closes T36 Phase 1 follow-up)"
```

---

### Task 9: Listen for `InvoiceCreatedSuccess` in BOOKS Invoices segment

**Files:**
- Modify: `OPS/Views/Books/BooksTabView.swift` OR `OPS/Views/Invoices/InvoicesListView.swift` (whichever observes refresh today)

- [ ] **Step 1: Find where invoices reload happens**

Run: `grep -n ".task\|.onReceive\|loadData\|InvoiceViewModel.fetchAll" OPS/Views/Invoices/InvoicesListView.swift OPS/Views/Books/BooksTabView.swift`

- [ ] **Step 2: Add notification listener**

Inside the appropriate view's modifier chain (mirror the `LeadCreatedSuccess` listener pattern in `PipelineSectionView`):

```swift
.onReceive(NotificationCenter.default.publisher(for: Notification.Name("InvoiceCreatedSuccess"))) { _ in
    Task { await invoiceViewModel.loadData() }
}
```

(Adjust based on actual `InvoiceViewModel` API — could be `loadData()`, `refresh()`, `fetchAll()`, etc.)

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Invoices/InvoicesListView.swift OPS/Views/Books/BooksTabView.swift
git commit -m "Refresh Invoices segment on InvoiceCreatedSuccess notification"
```

---

### Task 10: Add unit test for `nextInvoiceNumber` format

**Files:**
- Create: `OPSTests/Books/InvoiceRepositoryTests.swift`

- [ ] **Step 1: Create the test file**

```swift
//
//  InvoiceRepositoryTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

/// Note: `InvoiceRepository.nextInvoiceNumber()` performs a real network call;
/// these tests focus on format expectations only — full integration test of
/// the RPC happens via the PM verifying live Supabase rows after build.
final class InvoiceRepositoryTests: XCTestCase {

    func test_CreateInvoiceDTO_encodesAllRequiredFields() throws {
        let dto = CreateInvoiceDTO(
            companyId: "co",
            clientId: "cli",
            invoiceNumber: "INV-2026-00001",
            issueDate: "2026-05-11",
            dueDate: "2026-06-10",
            status: "draft",
            subtotal: 1000,
            discountType: nil,
            discountValue: nil,
            discountAmount: 0,
            taxRate: 8.75,
            taxAmount: 87.5,
            total: 1087.5,
            amountPaid: 0,
            depositApplied: 0,
            balanceDue: 1087.5,
            subject: "Test invoice",
            clientMessage: nil,
            internalNotes: nil,
            footer: nil,
            terms: nil,
            paymentTerms: "net_30",
            projectId: nil,
            estimateId: nil,
            opportunityId: nil,
            templateId: nil,
            createdBy: nil
        )

        let data = try JSONEncoder().encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["company_id"] as? String, "co")
        XCTAssertEqual(json["client_id"] as? String, "cli")
        XCTAssertEqual(json["invoice_number"] as? String, "INV-2026-00001")
        XCTAssertEqual(json["issue_date"] as? String, "2026-05-11")
        XCTAssertEqual(json["due_date"] as? String, "2026-06-10")
        XCTAssertEqual(json["status"] as? String, "draft")
        XCTAssertEqual(json["subtotal"] as? Double, 1000)
        XCTAssertEqual(json["amount_paid"] as? Double, 0)
        XCTAssertEqual(json["balance_due"] as? Double, 1087.5)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add OPSTests/Books/InvoiceRepositoryTests.swift
git commit -m "Add CreateInvoiceDTO encoding test"
```

---

### Chunk 2A — Final report deliverables

When the spawned session finishes T1–T10, it must report:

1. **Investigation findings (T1)** — how iOS estimates currently get their number; whether the same pattern works for invoices
2. **Reusability decisions (T4)** — which estimate-form components could be reused, which were duplicated
3. **Commit list** — `git log --oneline 06bfbea..HEAD` (or whichever HEAD-marker is current after Chunk 1 closeout)
4. **Files created** — `OPS/Views/Invoices/InvoiceFormSheet.swift`, `OPSTests/Books/InvoiceRepositoryTests.swift`, plus any extracted shared component file
5. **Files modified** — `InvoiceDTOs.swift`, `InvoiceRepository.swift`, `FloatingActionMenu.swift`, BOOKS/Invoices view (whichever observes refresh)
6. **Build verification** — agent does NOT run xcodebuild. Reports "ready for PM build verification."
7. **Open questions / blockers** — any spec assumption that turned out to be wrong; any unresolved naming or API mismatch.

---

## Chunk 2B — PaymentRecordSheet refactor

### Task 11: Read existing `PaymentRecordSheet` to map current API

**Files:**
- Read: `OPS/Views/Invoices/PaymentRecordSheet.swift` (full body)
- Read: `OPS/Views/Invoices/InvoiceDetailView.swift` (find the existing sheet call site)

- [ ] **Step 1: Map the current init signature, callers, and view-model dependency**

```bash
grep -n "PaymentRecordSheet(" /Users/jacksonsweet/Projects/OPS/ops-ios/OPS -r --include='*.swift'
```

- [ ] **Step 2: Document what changes when `invoice` becomes optional**

Write findings to `/tmp/payment-sheet-refactor-notes.md`:
- Current required init: `PaymentRecordSheet(invoice: Invoice, viewModel: InvoiceViewModel)`
- Current callers and their context
- What needs to change in callers when `invoice: Invoice?`
- Whether `viewModel` carries the invoice list needed for the new picker, OR whether we need to fetch separately

- [ ] **Step 3: No commit (investigation)**

---

### Task 12: Refactor `PaymentRecordSheet.invoice` to optional + add picker state

**Files:**
- Modify: `OPS/Views/Invoices/PaymentRecordSheet.swift`

- [ ] **Step 1: Change the let to optional**

In the struct, change:
```swift
let invoice: Invoice
```
to:
```swift
let invoice: Invoice?
@State private var selectedInvoice: Invoice? = nil

private var resolvedInvoice: Invoice? { invoice ?? selectedInvoice }
```

- [ ] **Step 2: Update existing form references**

Every reference to `invoice` (e.g. `invoice.invoiceNumber`, `invoice.balanceDue`) becomes `resolvedInvoice?.invoiceNumber ?? ""` etc. The form ONLY renders when `resolvedInvoice != nil`.

- [ ] **Step 3: Add picker view state**

Add to the struct:
```swift
@State private var pickerSearchText: String = ""

private var pickableInvoices: [Invoice] {
    viewModel.invoices.filter { inv in
        inv.balanceDue > 0
            && inv.status != .void
            && inv.status != .paid
            && (pickerSearchText.isEmpty
                || inv.invoiceNumber.localizedCaseInsensitiveContains(pickerSearchText)
                || (inv.client?.name.localizedCaseInsensitiveContains(pickerSearchText) ?? false))
    }
    .sorted { $0.balanceDue > $1.balanceDue }
}
```

- [ ] **Step 4: Commit**

```bash
git add OPS/Views/Invoices/PaymentRecordSheet.swift
git commit -m "PaymentRecordSheet: make invoice optional + add picker state"
```

---

### Task 13: Build the picker UI + branch the body

**Files:**
- Modify: `OPS/Views/Invoices/PaymentRecordSheet.swift`

- [ ] **Step 1: Branch the `body`**

Wrap the existing form body in a conditional. Add the picker subview as the first branch:

```swift
var body: some View {
    NavigationStack {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            if resolvedInvoice == nil {
                pickerView
            } else {
                formView
            }
        }
        .navigationTitle(resolvedInvoice == nil ? "PICK AN INVOICE" : "RECORD PAYMENT")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }
    .presentationDetents([.large])
}
```

(`formView` = the existing form sub-tree extracted into a computed property. `toolbarContent` = the existing Cancel/Save toolbar, with Save disabled when `resolvedInvoice == nil`.)

- [ ] **Step 2: Add the `pickerView`**

```swift
private var pickerView: some View {
    VStack(spacing: 0) {
        // Search bar
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(OPSStyle.Colors.secondaryText)
            TextField("Search invoices…", text: $pickerSearchText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(OPSStyle.Layout.spacing2_5)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .padding(OPSStyle.Layout.spacing3)

        // Invoice rows
        if pickableInvoices.isEmpty {
            VStack(spacing: OPSStyle.Layout.spacing3) {
                Spacer()
                Text("NO OPEN INVOICES")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(pickableInvoices, id: \.id) { inv in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(OPSStyle.Animation.fast) {
                                selectedInvoice = inv
                                amount = "\(inv.balanceDue)"
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(inv.invoiceNumber)
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    Text(inv.client?.name ?? "")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                                Spacer()
                                Text("Balance: \(inv.balanceDue, format: .currency(code: "USD"))")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                            .padding(OPSStyle.Layout.spacing3)
                            .frame(minHeight: 88)
                            .background(OPSStyle.Colors.cardBackground)
                            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
        }
    }
}
```

(`inv.client?.name` may not be the exact accessor — verify against `Invoice` model. If `Invoice` only has `clientId`, the picker needs to look up client names via the `dataController` or accept a resolved name map.)

- [ ] **Step 2: Commit**

```bash
git add OPS/Views/Invoices/PaymentRecordSheet.swift
git commit -m "PaymentRecordSheet: add invoice picker view for FAB no-context entry"
```

---

### Task 14: Wire FAB MONEY group's "New Payment" action

**Files:**
- Modify: `OPS/Views/Components/FloatingActionMenu.swift`

- [ ] **Step 1: Replace the commented sheet wiring**

Replace:
```swift
// TODO: Wire up when RecordPaymentSheet is implemented
// .sheet(isPresented: $showingRecordPayment) { RecordPaymentSheet() }
```

With:
```swift
.sheet(isPresented: $showingRecordPayment) {
    PaymentRecordSheet(invoice: nil, viewModel: invoiceViewModel)
        .environmentObject(dataController)
}
```

- [ ] **Step 2: Commit**

```bash
git add OPS/Views/Components/FloatingActionMenu.swift
git commit -m "FAB: wire 'New Payment' to PaymentRecordSheet (no-context variant)"
```

---

### Task 15: Add `PaymentRecordedSuccess` notification + listener

**Files:**
- Modify: `OPS/Views/Invoices/PaymentRecordSheet.swift` (post notification on success)
- Modify: `OPS/Views/Books/BooksTabView.swift` OR `InvoicesListView.swift` (listener)

- [ ] **Step 1: Post on save success**

In `PaymentRecordSheet`'s save handler (find the existing `recordPayment` call in the form's submit action), after success add:

```swift
NotificationCenter.default.post(name: Notification.Name("PaymentRecordedSuccess"), object: nil)
```

- [ ] **Step 2: Add listener (mirror the InvoiceCreatedSuccess pattern from T9)**

```swift
.onReceive(NotificationCenter.default.publisher(for: Notification.Name("PaymentRecordedSuccess"))) { _ in
    Task { await invoiceViewModel.loadData() }
}
```

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Invoices/PaymentRecordSheet.swift OPS/Views/Books/BooksTabView.swift OPS/Views/Invoices/InvoicesListView.swift
git commit -m "PaymentRecordSheet: post PaymentRecordedSuccess; BOOKS Invoices refreshes"
```

---

### Chunk 2B — Final report deliverables

1. Commit list (`git log --oneline <last-2A>..HEAD`)
2. Confirmation: existing `InvoiceDetailView → Record Payment` flow still works (no regression)
3. Confirmation: FAB → New Payment opens picker, picker filters to open invoices
4. Build verification: agent reports "ready for PM build verification"
5. Open questions

---

## Chunk 2C — Per-company `pipeline_stage_configs` retrofit (HIGH RISK)

**Sequencing note:** This chunk is the riskiest in Phase 2 — it refactors `PipelineStage` from a Swift enum to a data-driven struct backed by a per-company database table. The build is intentionally in a transient broken state between Tasks 20 and 24. The PM should NOT request a build verification from the user mid-chunk; only after Task 26.

### Task 16: Write the migration for default-stage seeding

**Files:**
- Create: `ops-software-bible/migrations/2026-05-11-01-seed-default-pipeline-stages.sql`

- [ ] **Step 1: Write the migration**

```sql
-- Phase 2 / Chunk 2C — seed default pipeline_stage_configs for new companies
-- AND backfill existing companies that have zero rows.
--
-- Schema: matches the columns confirmed in the spec §6.2 verification.

-- 1. Backfill function — idempotent, callable for one company at a time.
CREATE OR REPLACE FUNCTION public.seed_default_pipeline_stages(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only seed if the company has zero rows (idempotent).
  IF EXISTS (SELECT 1 FROM pipeline_stage_configs WHERE company_id = p_company_id) THEN
    RETURN;
  END IF;

  INSERT INTO pipeline_stage_configs
    (company_id, slug, name, color, sort_order, default_win_probability, stale_threshold_days, is_won_stage, is_lost_stage, is_default)
  VALUES
    (p_company_id, 'new_lead',     'New Lead',     '#BCBCBC',  10,  10, 3, false, false, true),
    (p_company_id, 'qualifying',   'Qualifying',   '#8195B5',  20,  20, 7, false, false, false),
    (p_company_id, 'quoting',      'Quoting',      '#C4A868',  30,  40, 5, false, false, false),
    (p_company_id, 'quoted',       'Quoted',       '#B5A381',  40,  60, 7, false, false, false),
    (p_company_id, 'follow_up',    'Follow-Up',    '#A182B5',  50,  50, 3, false, false, false),
    (p_company_id, 'negotiation',  'Negotiation',  '#B58289',  60,  75, 2, false, false, false),
    (p_company_id, 'won',          'Won',          '#9DB582',  70, 100, 365, true,  false, false),
    (p_company_id, 'lost',         'Lost',         '#6B7280',  80,   0, 365, false, true,  false);
END;
$$;

GRANT EXECUTE ON FUNCTION public.seed_default_pipeline_stages(uuid) TO authenticated;

-- 2. Trigger — auto-seed on companies INSERT.
CREATE OR REPLACE FUNCTION public.companies_seed_pipeline_stages()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM seed_default_pipeline_stages(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_companies_seed_pipeline_stages ON public.companies;
CREATE TRIGGER trg_companies_seed_pipeline_stages
  AFTER INSERT ON public.companies
  FOR EACH ROW
  EXECUTE FUNCTION public.companies_seed_pipeline_stages();

-- 3. One-time backfill — run for every existing company that has zero rows.
DO $$
DECLARE
  c_id uuid;
BEGIN
  FOR c_id IN
    SELECT c.id FROM companies c
    WHERE NOT EXISTS (SELECT 1 FROM pipeline_stage_configs WHERE company_id = c.id)
  LOOP
    PERFORM seed_default_pipeline_stages(c_id);
  END LOOP;
END $$;
```

- [ ] **Step 2: Commit (in ops-software-bible repo)**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add migrations/2026-05-11-01-seed-default-pipeline-stages.sql
git commit -m "Add migration: default pipeline_stage_configs seed (trigger + backfill)"
```

---

### Task 17: Apply the migration via Supabase MCP

- [ ] **Step 1: Use Supabase MCP `apply_migration`**

Project: `ijeekuhbatykdomumfjx`
Name: `seed_default_pipeline_stages`
Query: the SQL from Task 16.

Expected: success.

- [ ] **Step 2: Verify backfill worked**

Use Supabase MCP `execute_sql`:

```sql
SELECT c.id, c.name, COUNT(psc.id) AS stage_count
FROM companies c
LEFT JOIN pipeline_stage_configs psc ON psc.company_id = c.id
GROUP BY c.id, c.name
ORDER BY stage_count;
```

Expected: every company has 8 rows minimum (more if they've customized).

- [ ] **Step 3: Verify trigger by simulating a new company insert**

```sql
-- ROLLBACK BLOCK: only test, do not commit
BEGIN;
  INSERT INTO companies (id, name) VALUES ('00000000-1111-2222-3333-444444444444', 'Test Co — DELETE ME');
  SELECT slug FROM pipeline_stage_configs WHERE company_id = '00000000-1111-2222-3333-444444444444' ORDER BY sort_order;
ROLLBACK;
```

Expected: 8 slugs in canonical order.

- [ ] **Step 4: No code commit (DB-only)**

---

### Task 18: Create `PipelineStageConfigDTOs.swift`

**Files:**
- Create: `OPS/Network/Supabase/DTOs/PipelineStageConfigDTOs.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  PipelineStageConfigDTOs.swift
//  OPS
//
//  Per-company pipeline stage configuration. One row per stage per company.
//

import Foundation

struct PipelineStageConfigDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let slug: String
    let name: String
    let color: String
    let icon: String?
    let sortOrder: Int
    let defaultWinProbability: Int?
    let staleThresholdDays: Int?
    let autoFollowUpDays: Int?
    let autoFollowUpType: String?
    let isWonStage: Bool?
    let isLostStage: Bool?
    let isDefault: Bool?
    let deletedAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId              = "company_id"
        case slug
        case name
        case color
        case icon
        case sortOrder              = "sort_order"
        case defaultWinProbability  = "default_win_probability"
        case staleThresholdDays     = "stale_threshold_days"
        case autoFollowUpDays       = "auto_follow_up_days"
        case autoFollowUpType       = "auto_follow_up_type"
        case isWonStage             = "is_won_stage"
        case isLostStage            = "is_lost_stage"
        case isDefault              = "is_default"
        case deletedAt              = "deleted_at"
        case createdAt              = "created_at"
    }

    func toModel() -> PipelineStage {
        PipelineStage(
            id: id,
            companyId: companyId,
            slug: slug,
            name: name,
            color: color,
            icon: icon,
            sortOrder: sortOrder,
            defaultWinProbability: defaultWinProbability ?? 0,
            staleThresholdDays: staleThresholdDays ?? Int.max,
            autoFollowUpDays: autoFollowUpDays,
            autoFollowUpType: autoFollowUpType,
            isWonStage: isWonStage ?? false,
            isLostStage: isLostStage ?? false
        )
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios
git add OPS/Network/Supabase/DTOs/PipelineStageConfigDTOs.swift
git commit -m "Add PipelineStageConfigDTO matching pipeline_stage_configs schema"
```

---

### Task 19: Create `PipelineStageConfigRepository.swift`

**Files:**
- Create: `OPS/Network/Supabase/Repositories/PipelineStageConfigRepository.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  PipelineStageConfigRepository.swift
//  OPS
//

import Foundation
import Supabase

class PipelineStageConfigRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchAll() async throws -> [PipelineStageConfigDTO] {
        try await client
            .from("pipeline_stage_configs")
            .select()
            .eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
            .order("sort_order", ascending: true)
            .execute()
            .value
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add OPS/Network/Supabase/Repositories/PipelineStageConfigRepository.swift
git commit -m "Add PipelineStageConfigRepository.fetchAll()"
```

---

### Task 20: Replace `PipelineStage` enum with a struct

**Files:**
- Create: `OPS/DataModels/Pipeline/PipelineStage.swift` (new location, struct definition)
- Delete: `OPS/DataModels/Enums/PipelineStage.swift` (the old enum file — DEFER deletion to Task 24)

**WARNING:** This task INTENTIONALLY puts the build into a broken state. Do not run a build until Task 24 finishes updating consumers. Do not commit until Task 24 either. Hold all work in the working tree.

- [ ] **Step 1: Create the directory + new file**

```bash
mkdir -p /Users/jacksonsweet/Projects/OPS/ops-ios/OPS/DataModels/Pipeline
```

`OPS/DataModels/Pipeline/PipelineStage.swift`:

```swift
//
//  PipelineStage.swift
//  OPS
//
//  Per-company pipeline stage. Replaces the hardcoded enum from Phase 1.
//  Loaded from `pipeline_stage_configs` via PipelineStageRegistry.
//

import Foundation

struct PipelineStage: Identifiable, Hashable, Codable {
    let id: String                       // pipeline_stage_configs.id (UUID)
    let companyId: String
    let slug: String                     // stable identifier — used in stage_transitions, opportunities.stage_slug
    let name: String                     // display name (mutable)
    let color: String                    // hex
    let icon: String?
    let sortOrder: Int
    let defaultWinProbability: Int       // 0..100
    let staleThresholdDays: Int
    let autoFollowUpDays: Int?
    let autoFollowUpType: String?
    let isWonStage: Bool
    let isLostStage: Bool

    // MARK: - Display helpers (replace the old enum's static helpers)

    var displayName: String { name.uppercased() }
    var isTerminal: Bool { isWonStage || isLostStage }
    var winProbability: Int { defaultWinProbability }

    // Hashable / Equatable by id
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: PipelineStage, rhs: PipelineStage) -> Bool { lhs.id == rhs.id }
}

// MARK: - Default slug constants
//
// Code that needs to refer to the canonical "won" / "lost" / "new_lead" stages
// uses these slug constants. The actual stage object is fetched from the
// PipelineStageRegistry by slug — companies can customize the *displayed* name
// without breaking these references.

extension PipelineStage {
    enum Slug {
        static let newLead     = "new_lead"
        static let qualifying  = "qualifying"
        static let quoting     = "quoting"
        static let quoted      = "quoted"
        static let followUp    = "follow_up"
        static let negotiation = "negotiation"
        static let won         = "won"
        static let lost        = "lost"
    }
}
```

- [ ] **Step 2: Hold — do NOT delete the old enum file yet, do NOT commit**

The old enum at `OPS/DataModels/Enums/PipelineStage.swift` stays in place temporarily. The new struct will conflict by name; this is expected. Task 24 will remove the enum after consumers are migrated, in a single coherent commit.

---

### Task 21: Create `PipelineStageRegistry.swift`

**Files:**
- Create: `OPS/DataModels/Pipeline/PipelineStageRegistry.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  PipelineStageRegistry.swift
//  OPS
//
//  Per-company stage cache. Loaded once on auth, refreshed on TTL or realtime.
//  Lookups are by slug (stable across renames) or id.
//

import SwiftUI

@MainActor
final class PipelineStageRegistry: ObservableObject {
    static let shared = PipelineStageRegistry()

    @Published private(set) var stages: [PipelineStage] = []
    @Published private(set) var loadError: String? = nil

    private var lastLoadAt: Date? = nil
    private let cacheTTL: TimeInterval = 5 * 60
    private var companyId: String? = nil

    private init() {}

    // MARK: - Load

    /// Load stages for a company. Idempotent within TTL.
    func load(for companyId: String, force: Bool = false) async {
        if !force,
           self.companyId == companyId,
           let last = lastLoadAt,
           Date().timeIntervalSince(last) < cacheTTL {
            return
        }
        self.companyId = companyId
        let repo = PipelineStageConfigRepository(companyId: companyId)
        do {
            let dtos = try await repo.fetchAll()
            stages = dtos.map { $0.toModel() }.sorted { $0.sortOrder < $1.sortOrder }
            lastLoadAt = Date()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Lookups

    func stage(slug: String) -> PipelineStage? {
        stages.first { $0.slug == slug }
    }

    func stage(id: String) -> PipelineStage? {
        stages.first { $0.id == id }
    }

    /// Active (non-terminal) stages, sorted.
    func activeStages() -> [PipelineStage] {
        stages.filter { !$0.isTerminal }
    }

    /// Terminal stages, sorted (Won then Lost typically).
    func terminalStages() -> [PipelineStage] {
        stages.filter { $0.isTerminal }
    }

    func wonStage() -> PipelineStage? {
        stages.first { $0.isWonStage }
    }

    func lostStage() -> PipelineStage? {
        stages.first { $0.isLostStage }
    }

    /// First non-terminal stage by sort order — the company's default new-lead stage.
    func defaultNewStage() -> PipelineStage? {
        activeStages().first
    }

    /// Next active stage after the given slug, by sort order. Returns nil if none.
    func nextStage(after slug: String) -> PipelineStage? {
        let active = activeStages()
        guard let idx = active.firstIndex(where: { $0.slug == slug }) else { return nil }
        let next = active.index(after: idx)
        return next < active.endIndex ? active[next] : nil
    }
}
```

- [ ] **Step 2: Hold — do NOT commit yet**

Same reason as Task 20. Coherent commit after Task 24.

---

### Task 22: Wire registry load into `DataController`

**Files:**
- Modify: `OPS/Utilities/DataController.swift` (add load call after auth)

- [ ] **Step 1: Find the auth-success path**

Run: `grep -n "isAuthenticated\|currentUser =\|loginSuccess\|onAuthChange" OPS/Utilities/DataController.swift | head -10`

Locate the function or property setter that fires when a user becomes authenticated and `currentUser?.companyId` is available.

- [ ] **Step 2: Add the load call**

In the appropriate place, add:

```swift
Task {
    if let companyId = currentUser?.companyId {
        await PipelineStageRegistry.shared.load(for: companyId)
    }
}
```

Also add an app-foregrounded refresh hook (in the existing `didBecomeActiveNotification` observer if one exists; otherwise create one):

```swift
NotificationCenter.default.addObserver(
    forName: UIApplication.didBecomeActiveNotification,
    object: nil,
    queue: .main
) { _ in
    Task {
        if let companyId = self.currentUser?.companyId {
            await PipelineStageRegistry.shared.load(for: companyId)  // honors TTL
        }
    }
}
```

- [ ] **Step 3: Hold — do NOT commit yet**

---

### Task 23: Add `stageSlug: String` to `Opportunity`; update DTO mapping

**Files:**
- Modify: `OPS/DataModels/Supabase/Opportunity.swift`
- Modify: `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift`
- Modify: `OPS/DataModels/Supabase/StageTransition.swift`

- [ ] **Step 1: Replace `var stage: PipelineStage` with `var stageSlug: String`**

In `Opportunity.swift`, change:
```swift
var stage: PipelineStage
```
to:
```swift
var stageSlug: String     // immutable identifier; resolves to PipelineStage via registry

/// Read-time resolution. Returns nil if registry hasn't loaded or if the
/// company has deleted/renamed the slug. Callers should fallback gracefully.
var stage: PipelineStage? {
    PipelineStageRegistry.shared.stage(slug: stageSlug)
}
```

Update the `init` to take `stageSlug: String = PipelineStage.Slug.newLead` instead of `stage: PipelineStage = .newLead`.

Update computed helpers:
- `weightedValue`: `let pct = winProbabilityOverride ?? stage?.winProbability ?? 0`
- `daysInStage`: stays the same (uses stageEnteredAt, not stage)
- `isStale`: `let threshold = stage?.staleThresholdDays ?? Int.max; return daysInStage > threshold`

- [ ] **Step 2: Update `OpportunityDTO.toModel()` to use stageSlug**

In `OpportunityDTOs.swift`'s `toModel()`:
```swift
let opp = Opportunity(
    id: id,
    companyId: companyId,
    contactName: contactName ?? "",
    stageSlug: stage,                  // `stage` is the slug string from DB
    stageEnteredAt: SupabaseDate.parse(stageEnteredAt) ?? Date(),
    createdAt: SupabaseDate.parse(createdAt) ?? Date(),
    updatedAt: SupabaseDate.parse(updatedAt) ?? Date()
)
```

- [ ] **Step 3: Update StageTransition similarly**

In `StageTransition.swift`, replace:
```swift
var fromStage: PipelineStage?
var toStage: PipelineStage
```
with:
```swift
var fromStageSlug: String?
var toStageSlug: String

var fromStage: PipelineStage? { fromStageSlug.flatMap { PipelineStageRegistry.shared.stage(slug: $0) } }
var toStage: PipelineStage? { PipelineStageRegistry.shared.stage(slug: toStageSlug) }
```

Update `init` to take slugs. Update `StageTransitionDTO.toModel()` accordingly.

- [ ] **Step 4: Hold — do NOT commit yet**

---

### Task 24: Sweep all 13 PipelineStage consumers + delete old enum file

**Files (verified consumer list — 13 files per spec §6.1):**
- `OPS/Views/Books/Pipeline/StageStripView.swift`
- `OPS/Views/Books/Pipeline/PipelineSectionView.swift`
- `OPS/Views/Books/Pipeline/LeadCardView.swift`
- `OPS/Views/Books/Pipeline/LeadDetailView.swift`
- `OPS/Views/Books/Pipeline/EditLeadSheet.swift`
- `OPS/Views/Books/Pipeline/LeadActionSheet.swift`
- `OPS/Views/Books/Pipeline/AddLeadSheet.swift`
- `OPS/ViewModels/PipelineViewModel.swift`
- `OPS/ViewModels/MoneyDashboardViewModel.swift`
- `OPS/Network/Supabase/Repositories/OpportunityRepository.swift`
- `OPSTests/Pipeline/PipelineViewModelTests.swift`
- `OPSTests/Pipeline/OpportunityDTOTests.swift`
- `OPS/DataModels/Enums/PipelineStage.swift` (DELETE this — the old enum)

- [ ] **Step 1: Replace every `PipelineStage.allCases` reference**

Grep first: `grep -rn "PipelineStage\.allCases" OPS OPSTests --include='*.swift'`

Replace with `PipelineStageRegistry.shared.stages` (all stages) or `.activeStages()` / `.terminalStages()` per context. Specifically:
- `StageStripView` private constants `activeStages` / `terminalStages` arrays — replace with calls to registry methods.
- `LeadActionSheet`'s `ForEach(PipelineStage.allCases)` for "Move to stage" submenu → `ForEach(PipelineStageRegistry.shared.stages)`.
- Any test fixture using `PipelineStage.allCases` — replace with hardcoded test fixtures.

- [ ] **Step 2: Replace every `.newLead` / `.qualifying` / etc. enum-case reference**

Grep: `grep -rEn "PipelineStage\.(newLead|qualifying|quoting|quoted|followUp|negotiation|won|lost)" OPS OPSTests --include='*.swift'`

Replace each with the corresponding slug constant + registry lookup:
- `PipelineStage.newLead` → `PipelineStageRegistry.shared.stage(slug: PipelineStage.Slug.newLead)`
  - Or, in contexts that just need the slug (not the full struct): `PipelineStage.Slug.newLead` directly.

- [ ] **Step 3: Replace `opportunity.stage.next` / `.isTerminal` / `.winProbability` patterns**

Grep: `grep -rn "opportunity\.stage\.\|opp\.stage\." OPS OPSTests --include='*.swift'`

For each callsite:
- `.next` → `PipelineStageRegistry.shared.nextStage(after: opportunity.stageSlug)`
- `.isTerminal` → `opportunity.stage?.isTerminal ?? false`
- `.winProbability` → `opportunity.stage?.winProbability ?? 0`
- `.displayName` → `opportunity.stage?.displayName ?? opportunity.stageSlug.uppercased()`
- `.staleThresholdDays` → `opportunity.stage?.staleThresholdDays ?? Int.max`

Where helpers are needed in many places (e.g. "next stage from this opp"), consider adding a top-level extension to `Opportunity`:
```swift
extension Opportunity {
    var nextStage: PipelineStage? { PipelineStageRegistry.shared.nextStage(after: stageSlug) }
}
```

- [ ] **Step 4: Update `OpportunityRepository.moveToStage(...)` signature**

Current sig (Phase 1):
```swift
func moveToStage(opportunityId: String, to stage: PipelineStage, userId: String?) async throws -> OpportunityDTO
```

Change to:
```swift
func moveToStage(opportunityId: String, to stageSlug: String, userId: String?) async throws -> OpportunityDTO
```

Update the inner RPC params: `p_to_stage: stageSlug` (already a slug — Phase 1's RPC was slug-keyed already).

Also update `markWon` / `markLost` to look up the won/lost stage from the registry:
```swift
func markWon(opportunityId: String, actualValue: Double?, projectId: String?, userId: String?) async throws -> OpportunityDTO {
    guard let wonStage = await PipelineStageRegistry.shared.wonStage() else {
        throw NSError(domain: "Pipeline", code: 0, userInfo: [NSLocalizedDescriptionKey: "No 'Won' stage configured for this company."])
    }
    _ = try await moveToStage(opportunityId: opportunityId, to: wonStage.slug, userId: userId)
    // … rest unchanged
}
```

(Similar for `markLost`.)

- [ ] **Step 5: Update PipelineViewModel + tests + every consumer**

Each file needs the same pattern: convert enum-case references to slug-string references via the registry.

The agent should work file-by-file, building a mental map of changes per file before editing. Recommended order:
1. `Opportunity.swift` (already changed in Task 23)
2. `OpportunityDTOs.swift` (already changed in Task 23)
3. `StageTransition.swift` (already changed in Task 23)
4. `OpportunityRepository.swift` (this task, Step 4)
5. `PipelineViewModel.swift`
6. `MoneyDashboardViewModel.swift`
7. `StageStripView.swift`
8. `PipelineSectionView.swift`
9. `LeadCardView.swift`
10. `LeadDetailView.swift`
11. `EditLeadSheet.swift`
12. `LeadActionSheet.swift`
13. `AddLeadSheet.swift`
14. `PipelineViewModelTests.swift`
15. `OpportunityDTOTests.swift`

- [ ] **Step 6: Delete the old enum file**

```bash
rm /Users/jacksonsweet/Projects/OPS/ops-ios/OPS/DataModels/Enums/PipelineStage.swift
```

(Project uses `PBXFileSystemSynchronizedRootGroup` per Phase 1 verification — deletion auto-syncs.)

- [ ] **Step 7: Single coherent commit for the whole refactor**

This is the only commit that lands across the whole sweep. One atomic change.

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios
git add OPS/DataModels/Pipeline/ \
        OPS/DataModels/Enums/PipelineStage.swift \
        OPS/DataModels/Supabase/Opportunity.swift \
        OPS/DataModels/Supabase/StageTransition.swift \
        OPS/Network/Supabase/DTOs/OpportunityDTOs.swift \
        OPS/Network/Supabase/DTOs/PipelineStageConfigDTOs.swift \
        OPS/Network/Supabase/Repositories/OpportunityRepository.swift \
        OPS/Network/Supabase/Repositories/PipelineStageConfigRepository.swift \
        OPS/Utilities/DataController.swift \
        OPS/ViewModels/PipelineViewModel.swift \
        OPS/ViewModels/MoneyDashboardViewModel.swift \
        OPS/Views/Books/Pipeline/ \
        OPSTests/Pipeline/
git commit -m "Refactor PipelineStage from enum to data-driven struct backed by pipeline_stage_configs"
```

(Stage 4–6 of Task 24 in one commit. The intermediate uncommitted state from Tasks 20–23 lives only in the working tree until this point.)

---

### Task 25: Add registry-load error UI in `PipelineSectionView`

**Files:**
- Modify: `OPS/Views/Books/Pipeline/PipelineSectionView.swift`

- [ ] **Step 1: Render a registry-error banner**

When `PipelineStageRegistry.shared.loadError != nil` OR `stages.isEmpty`, render a top banner:

```swift
@ObservedObject private var stageRegistry = PipelineStageRegistry.shared

// In body:
if stageRegistry.stages.isEmpty {
    VStack(spacing: OPSStyle.Layout.spacing3) {
        Spacer()
        Image(systemName: "exclamationmark.triangle")
            .font(.system(size: OPSStyle.Layout.IconSize.xl))
            .foregroundColor(OPSStyle.Colors.warningStatus)
        Text(stageRegistry.loadError == nil ? "STAGES NOT CONFIGURED" : "STAGES UNAVAILABLE")
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryText)
        if let err = stageRegistry.loadError {
            Text(err)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        Button("RETRY") {
            Task {
                if let cid = dataController.currentUser?.companyId {
                    await stageRegistry.load(for: cid, force: true)
                }
            }
        }
        .font(OPSStyle.Typography.bodyBold)
        .foregroundColor(OPSStyle.Colors.primaryAccent)
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
} else {
    // Existing Pipeline section content
}
```

- [ ] **Step 2: Disable Won/Lost actions when those stages aren't configured**

In `LeadCardView`, `LeadDetailView`, `LeadActionSheet`: gate the "WON" / "LOST" buttons on `stageRegistry.wonStage() != nil` / `lostStage() != nil` respectively. When unavailable, dim the button + display tooltip "No 'Won'/'Lost' stage configured."

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Books/Pipeline/PipelineSectionView.swift OPS/Views/Books/Pipeline/LeadCardView.swift OPS/Views/Books/Pipeline/LeadDetailView.swift OPS/Views/Books/Pipeline/LeadActionSheet.swift
git commit -m "Pipeline UI: registry empty/error state + Won/Lost button gating"
```

---

### Task 26: Smoke-test that customized stages render correctly

This is a verification-only task — no code changes. The PM coordinates with the user to test on device.

- [ ] **Step 1: Spawned session reports "ready for verification"**

The session writes a report and stops. The PM picks it up.

- [ ] **Step 2: PM script for the user**

Send the user this script:

```
1. Run a build of HEAD on device.
2. In Supabase MCP, customize one company's stages: rename `quoting` to `bidding`,
   change its color, set staleThresholdDays = 1.
3. On device, open BOOKS → Pipeline. Tap the previously-named "QUOTING" pill.
   - It should now display "BIDDING" with the new color.
   - A lead in that stage should mark stale after 1 day.
4. Try a stage move: advance a lead from "Bidding" → next stage.
   - Verify Supabase `stage_transitions` row uses slug "quoting" (the slug stays stable).
5. Test the won/lost actions still work.
6. Roll back the customization to verify the rollback works too.
```

- [ ] **Step 3: PM updates this checklist with results**

After user tests, the PM commits a verification log to the spec or a separate file.

---

### Chunk 2C — Final report deliverables

1. Migration committed in ops-software-bible (`9ee7089..HEAD` in that repo)
2. Commits in ops-ios — should be FOUR commits in this chunk:
   - DTO addition (T18)
   - Repository addition (T19)
   - The big refactor commit (T24, atomic across 15+ files)
   - UI error state + Won/Lost gating (T25)
3. Backfill verification SQL output (from T17 step 2)
4. Trigger verification SQL output (T17 step 3)
5. Customization smoke-test results (T26 — user-driven, PM compiles)
6. Build verification: agent reports "ready"
7. Open questions / blockers

---

## Chunk 2D — AI lead fields (read-side display)

### Task 27: Extend `Opportunity` SwiftData model with AI fields

**Files:**
- Modify: `OPS/DataModels/Supabase/Opportunity.swift` (additive properties)
- Modify: `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift` (DTO + toModel mapping)

- [ ] **Step 1: Add to `Opportunity`**

Inside the `@Model class Opportunity`, add (defer fields are deferred per spec §10.1 of Phase 1; this completes that deferral):

```swift
// AI-generated (web computes; iOS read-only)
var aiSummary: String?
var aiStageConfidence: Double?     // 0.0..1.0
var aiStageSignals: [String] = []
var detectedValue: Int?
```

- [ ] **Step 2: Add to `OpportunityDTO` + `CodingKeys`**

```swift
let aiSummary: String?
let aiStageConfidence: Double?
let aiStageSignals: [String]?
let detectedValue: Int?

// In CodingKeys:
case aiSummary           = "ai_summary"
case aiStageConfidence   = "ai_stage_confidence"
case aiStageSignals      = "ai_stage_signals"
case detectedValue       = "detected_value"
```

- [ ] **Step 3: Add to `OpportunityDTO.toModel()`**

```swift
opp.aiSummary = aiSummary
opp.aiStageConfidence = aiStageConfidence
opp.aiStageSignals = aiStageSignals ?? []
opp.detectedValue = detectedValue
```

- [ ] **Step 4: Commit**

```bash
git add OPS/DataModels/Supabase/Opportunity.swift OPS/Network/Supabase/DTOs/OpportunityDTOs.swift
git commit -m "Extend Opportunity model with AI fields (ai_summary, ai_stage_confidence, ai_stage_signals, detected_value)"
```

---

### Task 28: Add "AI SUMMARY" section to `LeadDetailView`

**Files:**
- Modify: `OPS/Views/Books/Pipeline/LeadDetailView.swift`

- [ ] **Step 1: Add the section view**

Append to the existing extension block:

```swift
@ViewBuilder
private var aiSummarySection: some View {
    if let summary = opportunity.aiSummary, !summary.isEmpty {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 6) {
                Text("🤖")
                Text("AI SUMMARY")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text(summary)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                if let confidence = opportunity.aiStageConfidence,
                   !opportunity.aiStageSignals.isEmpty {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text("Confidence: \(Int(confidence * 100))%")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Text("·")
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("Signals: \(opportunity.aiStageSignals.joined(separator: ", "))")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(2)
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackground)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(width: 1)
            }
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
        }
    }
}
```

- [ ] **Step 2: Insert into the body order**

In `LeadDetailView.body`, insert `aiSummarySection` between `header` and `quickActions`:

```swift
header
aiSummarySection
if canManage { quickActions }
// … rest unchanged
```

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Books/Pipeline/LeadDetailView.swift
git commit -m "LeadDetailView: render AI summary section when ai_summary present"
```

---

### Task 29: Add confidence badge to `LeadCardView`

**Files:**
- Modify: `OPS/Views/Books/Pipeline/LeadCardView.swift`

- [ ] **Step 1: Add the badge inside the existing card metadata row**

In the metadata `HStack` (next to the days-in-stage / stale text), add:

```swift
if let confidence = opportunity.aiStageConfidence, confidence > 0.7 {
    Text("\(Int(confidence * 100))%")
        .font(OPSStyle.Typography.smallCaption)
        .foregroundColor(OPSStyle.Colors.invertedText)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(OPSStyle.Colors.primaryAccent)
        .clipShape(Capsule())
}
```

- [ ] **Step 2: Commit**

```bash
git add OPS/Views/Books/Pipeline/LeadCardView.swift
git commit -m "LeadCardView: show AI confidence badge when > 70%"
```

---

### Task 30: Add unit test for AI fields decode

**Files:**
- Modify: `OPSTests/Pipeline/OpportunityDTOTests.swift` (extend existing)

- [ ] **Step 1: Add a test case**

Append to the test class:

```swift
func test_OpportunityDTO_decodesAIFields() throws {
    let json = """
    {
      "id": "x", "company_id": "co",
      "title": null, "contact_name": "Test",
      "contact_email": null, "contact_phone": null,
      "description": null, "address": null,
      "stage": "quoting",
      "stage_entered_at": "2026-05-11T00:00:00Z",
      "stage_manually_set": false,
      "assigned_to": null, "priority": null, "source": null, "quote_delivery_method": null,
      "estimated_value": null, "actual_value": null, "win_probability": null,
      "expected_close_date": null, "actual_close_date": null,
      "next_follow_up_at": null, "last_activity_at": null,
      "project_id": null, "client_id": null,
      "lost_reason": null, "lost_notes": null,
      "deleted_at": null, "archived_at": null,
      "tags": null, "source_email_id": null,
      "correspondence_count": null, "outbound_count": null, "inbound_count": null,
      "last_inbound_at": null, "last_outbound_at": null, "last_message_direction": null,
      "ai_summary": "Customer wants quote by Friday",
      "ai_stage_confidence": 0.92,
      "ai_stage_signals": ["urgency", "price"],
      "detected_value": 24000,
      "created_at": "2026-05-11T00:00:00Z",
      "updated_at": "2026-05-11T00:00:00Z"
    }
    """
    let dto = try JSONDecoder().decode(OpportunityDTO.self, from: json.data(using: .utf8)!)
    let opp = dto.toModel()
    XCTAssertEqual(opp.aiSummary, "Customer wants quote by Friday")
    XCTAssertEqual(opp.aiStageConfidence, 0.92, accuracy: 0.001)
    XCTAssertEqual(opp.aiStageSignals, ["urgency", "price"])
    XCTAssertEqual(opp.detectedValue, 24000)
}
```

- [ ] **Step 2: Commit**

```bash
git add OPSTests/Pipeline/OpportunityDTOTests.swift
git commit -m "Add AI-fields decode test for OpportunityDTO"
```

---

### Chunk 2D — Final report

1. Commit list (4 commits)
2. Confirmation: AI summary section renders only when present (no empty card)
3. Confirmation: confidence badge appears only above 70%
4. Build verification ready

---

## Chunk 2E — Lead images + lat/lng

### Task 31: Write Storage migration for `lead-images` bucket

**Files:**
- Create: `ops-software-bible/migrations/2026-05-11-02-lead-images-storage.sql`

- [ ] **Step 1: Read precedent**

Read `ops-software-bible/migrations/2026-05-08-product-thumbnails-storage-policy.sql` (referenced in `ProductThumbnailUploader.swift:47` — verify it exists; if at a different path, find via `find ops-software-bible -name '*storage*'`).

- [ ] **Step 2: Write the migration**

```sql
-- Create lead-images Storage bucket + per-company RLS policies.
-- Mirror of 2026-05-08-product-thumbnails-storage-policy.sql.

INSERT INTO storage.buckets (id, name, public)
VALUES ('lead-images', 'lead-images', false)
ON CONFLICT (id) DO NOTHING;

-- Read: any authenticated user in the company can view
CREATE POLICY "lead-images-read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'lead-images'
  AND (storage.foldername(name))[1] = (
    SELECT company_id::text FROM users WHERE id = auth.uid()
  )
);

-- Insert: authenticated user can upload to their company's folder
CREATE POLICY "lead-images-insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'lead-images'
  AND (storage.foldername(name))[1] = (
    SELECT company_id::text FROM users WHERE id = auth.uid()
  )
);

-- Update + Delete: authenticated user in same company
CREATE POLICY "lead-images-update"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'lead-images'
  AND (storage.foldername(name))[1] = (
    SELECT company_id::text FROM users WHERE id = auth.uid()
  )
);

CREATE POLICY "lead-images-delete"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'lead-images'
  AND (storage.foldername(name))[1] = (
    SELECT company_id::text FROM users WHERE id = auth.uid()
  )
);
```

(Adjust per actual auth schema — `users` table may be `app_users` or use `auth.users.raw_user_meta_data->>'company_id'` depending on the project's pattern. Verify by reading `2026-05-08-product-thumbnails-storage-policy.sql` first.)

- [ ] **Step 3: Apply via Supabase MCP**

`apply_migration` with name `lead_images_storage` + the SQL above.

- [ ] **Step 4: Commit migration**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add migrations/2026-05-11-02-lead-images-storage.sql
git commit -m "Add migration: lead-images Storage bucket + per-company RLS"
```

---

### Task 32: Build `LeadImageUploader.swift`

**Files:**
- Create: `OPS/Services/LeadImageUploader.swift`

- [ ] **Step 1: Read the precedent**

Read `OPS/Services/ProductThumbnailUploader.swift` in full (~121 lines). Note:
- Bucket constant
- Object naming convention
- Resize / encode logic
- Error enum

- [ ] **Step 2: Create the new file by mirroring**

Adapt `ProductThumbnailUploader` to:
- Bucket = `"lead-images"`
- Object naming = `"\(companyId)/\(opportunityId)/\(UUID().uuidString).jpg"`
- Same resize (1024 max long edge) + JPEG quality (0.85)
- Error enum named `LeadImageUploadError`

```swift
import Foundation
import UIKit

enum LeadImageUploadError: LocalizedError {
    case encodeFailed
    case missingPublicURL

    var errorDescription: String? {
        switch self {
        case .encodeFailed:    return "Could not encode the image."
        case .missingPublicURL: return "Upload finished but no public URL was returned."
        }
    }
}

final class LeadImageUploader {
    static let shared = LeadImageUploader()

    private let bucket = "lead-images"
    private let maxLongEdge: CGFloat = 1024
    private let jpegQuality: CGFloat = 0.85

    private init() {}

    /// Upload + return the storage object path (e.g. "co/opp/uuid.jpg").
    /// Caller stores this path in Opportunity.images; rendering resolves to a public URL.
    func upload(image: UIImage, companyId: String, opportunityId: String) async throws -> String {
        let resized = resize(image, to: maxLongEdge)
        guard let data = resized.jpegData(compressionQuality: jpegQuality) else {
            throw LeadImageUploadError.encodeFailed
        }

        let path = "\(companyId)/\(opportunityId)/\(UUID().uuidString).jpg"
        let client = SupabaseService.shared.client

        try await client.storage
            .from(bucket)
            .upload(path, data: data, options: .init(contentType: "image/jpeg"))

        return path
    }

    func deleteObject(path: String) async throws {
        try await SupabaseService.shared.client.storage.from(bucket).remove(paths: [path])
    }

    func publicURL(for path: String) throws -> URL {
        try SupabaseService.shared.client.storage.from(bucket).getPublicURL(path: path)
    }

    private func resize(_ image: UIImage, to maxEdge: CGFloat) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maxEdge else { return image }
        let scale = maxEdge / longEdge
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
```

(The Supabase Storage API call signatures may differ slightly per the SDK version — verify against `ProductThumbnailUploader.swift` and adapt.)

- [ ] **Step 3: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios
git add OPS/Services/LeadImageUploader.swift
git commit -m "Add LeadImageUploader (mirrors ProductThumbnailUploader; lead-images bucket)"
```

---

### Task 33: Extend `Opportunity` model + DTO with images, lat/lng

**Files:**
- Modify: `OPS/DataModels/Supabase/Opportunity.swift`
- Modify: `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift`

- [ ] **Step 1: Add to `Opportunity`**

```swift
var images: [String] = []
var latitude: Double?
var longitude: Double?
```

- [ ] **Step 2: Add to `OpportunityDTO` + CodingKeys + toModel**

```swift
let images: [String]?
let latitude: Double?
let longitude: Double?

// CodingKeys
case images
case latitude
case longitude

// toModel
opp.images = images ?? []
opp.latitude = latitude
opp.longitude = longitude
```

- [ ] **Step 3: Add to `UpdateOpportunityDTO` (so edits can patch them)**

```swift
var images: [String]?
var latitude: Double?
var longitude: Double?

// CodingKeys (add same case names as above)
```

- [ ] **Step 4: Commit**

```bash
git add OPS/DataModels/Supabase/Opportunity.swift OPS/Network/Supabase/DTOs/OpportunityDTOs.swift
git commit -m "Extend Opportunity with images + latitude/longitude (additive)"
```

---

### Task 34: Add image picker + location capture to `AddLeadSheet`

**Files:**
- Modify: `OPS/Views/Books/Pipeline/AddLeadSheet.swift`
- Add a new helper if needed: `OPS/Views/Books/Pipeline/MapPickerSheet.swift`

- [ ] **Step 1: Add `import PhotosUI` + state**

In `AddLeadSheet.swift`, add at top:

```swift
import PhotosUI
```

Add state inside the struct:

```swift
@State private var selectedPhotoItems: [PhotosPickerItem] = []
@State private var selectedImages: [UIImage] = []
@State private var capturedCoordinate: CLLocationCoordinate2D? = nil
@State private var isLocating = false

@StateObject private var locationManager = LocationManager.shared    // verify singleton vs init
```

(If `LocationManager` isn't a singleton, instantiate locally.)

- [ ] **Step 2: Add image-picker section**

Inside the form's `VStack`, after the description field:

```swift
VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
    Text("IMAGES")
        .font(OPSStyle.Typography.captionBold)
        .foregroundColor(OPSStyle.Colors.tertiaryText)

    PhotosPicker(
        selection: $selectedPhotoItems,
        maxSelectionCount: 10,
        matching: .images
    ) {
        HStack {
            Image(systemName: "photo.badge.plus")
            Text("ADD IMAGES")
                .font(OPSStyle.Typography.captionBold)
        }
        .foregroundColor(OPSStyle.Colors.primaryAccent)
        .padding(OPSStyle.Layout.spacing2_5)
        .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    if !selectedImages.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, img in
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                        .overlay(alignment: .topTrailing) {
                            Button(action: { selectedImages.remove(at: idx) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                                    .background(Circle().fill(.white))
                            }
                            .offset(x: 4, y: -4)
                        }
                }
            }
        }
    }
}
.onChange(of: selectedPhotoItems) { _, newItems in
    Task {
        var loaded: [UIImage] = []
        for item in newItems {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                loaded.append(img)
            }
        }
        selectedImages = loaded
    }
}
```

- [ ] **Step 3: Add location capture section**

```swift
VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
    Text("LOCATION")
        .font(OPSStyle.Typography.captionBold)
        .foregroundColor(OPSStyle.Colors.tertiaryText)

    Button(action: { Task { await captureLocation() } }) {
        HStack {
            Image(systemName: capturedCoordinate == nil ? "location" : "location.fill")
            if let c = capturedCoordinate {
                Text(String(format: "%.4f, %.4f", c.latitude, c.longitude))
            } else {
                Text("CAPTURE LOCATION")
            }
        }
        .foregroundColor(OPSStyle.Colors.primaryAccent)
        .padding(OPSStyle.Layout.spacing2_5)
        .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }
    .disabled(isLocating)
}

// helper
private func captureLocation() async {
    isLocating = true
    defer { isLocating = false }
    locationManager.requestPermissionIfNeeded(requestAlways: false) { _ in }
    // wait briefly for location to populate
    try? await Task.sleep(nanoseconds: 1_500_000_000)
    if let loc = locationManager.location {
        capturedCoordinate = loc.coordinate
    }
}
```

- [ ] **Step 4: Update `save()` to include images + lat/lng**

After the existing opportunity create succeeds, upload images + PATCH:

```swift
// After: let resultDTO = try await repo.create(dto)
// Upload images now that we have an opportunityId
var uploadedPaths: [String] = []
for img in selectedImages {
    if let path = try? await LeadImageUploader.shared.upload(
        image: img,
        companyId: companyId,
        opportunityId: resultDTO.id
    ) {
        uploadedPaths.append(path)
    }
}

if !uploadedPaths.isEmpty || capturedCoordinate != nil {
    var patch = UpdateOpportunityDTO()
    patch.images = uploadedPaths.isEmpty ? nil : uploadedPaths
    patch.latitude = capturedCoordinate?.latitude
    patch.longitude = capturedCoordinate?.longitude
    _ = try? await repo.update(resultDTO.id, fields: patch)
}
```

- [ ] **Step 5: Commit**

```bash
git add OPS/Views/Books/Pipeline/AddLeadSheet.swift
git commit -m "AddLeadSheet: image picker + location capture; two-step upload after opportunity create"
```

---

### Task 35: Add gallery + map sections to `LeadDetailView`

**Files:**
- Modify: `OPS/Views/Books/Pipeline/LeadDetailView.swift`
- Create: `OPS/Views/Books/Pipeline/LeadImageGallery.swift`

- [ ] **Step 1: Create the gallery view**

```swift
import SwiftUI

struct LeadImageGallery: View {
    let imagePaths: [String]
    @State private var fullScreenURL: URL? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(imagePaths, id: \.self) { path in
                    if let url = try? LeadImageUploader.shared.publicURL(for: path) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Color.gray.opacity(0.2)
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            case .failure:
                                Image(systemName: "photo.badge.exclamationmark")
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                            @unknown default:
                                Color.gray.opacity(0.2)
                            }
                        }
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                        .onTapGesture { fullScreenURL = url }
                    }
                }
            }
        }
        .fullScreenCover(item: Binding(
            get: { fullScreenURL.map { IdentifiedURL(url: $0) } },
            set: { fullScreenURL = $0?.url }
        )) { wrapped in
            FullScreenImageViewer(url: wrapped.url)
        }
    }
}

private struct IdentifiedURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct FullScreenImageViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().aspectRatio(contentMode: .fit)
                } else {
                    ProgressView().tint(.white)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 32))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}
```

- [ ] **Step 2: Add gallery + map sections to LeadDetailView**

In the body extension:

```swift
@ViewBuilder
private var imagesSection: some View {
    if !opportunity.images.isEmpty {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("IMAGES (\(opportunity.images.count))")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            LeadImageGallery(imagePaths: opportunity.images)
        }
    }
}

@ViewBuilder
private var locationSection: some View {
    if let lat = opportunity.latitude, let lng = opportunity.longitude {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("LOCATION")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Map(coordinateRegion: .constant(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )), annotationItems: [LeadPin(coord: CLLocationCoordinate2D(latitude: lat, longitude: lng))]) { pin in
                MapMarker(coordinate: pin.coord, tint: OPSStyle.Colors.primaryAccent)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))

            if let addr = opportunity.address {
                Text(addr)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
    }
}

private struct LeadPin: Identifiable {
    let id = UUID()
    let coord: CLLocationCoordinate2D
}
```

(Add `import MapKit` at the top of `LeadDetailView.swift`.)

In `body`, insert after `aiSummarySection`:

```swift
imagesSection
locationSection
```

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Books/Pipeline/LeadDetailView.swift OPS/Views/Books/Pipeline/LeadImageGallery.swift
git commit -m "LeadDetailView: render image gallery + location map sections"
```

---

### Task 36: Add image management + location to `EditLeadSheet`

**Files:**
- Modify: `OPS/Views/Books/Pipeline/EditLeadSheet.swift`

- [ ] **Step 1: Mirror the pattern from `AddLeadSheet`**

Add the same image picker + location capture sections. Key difference: pre-populate from the existing opportunity:

```swift
@State private var existingImagePaths: [String] = []   // from opportunity.images
@State private var newImagesToUpload: [UIImage] = []
@State private var imagePathsToDelete: [String] = []
@State private var capturedCoordinate: CLLocationCoordinate2D? = nil

// In init:
_existingImagePaths = State(initialValue: opportunity.images)
if let lat = opportunity.latitude, let lng = opportunity.longitude {
    _capturedCoordinate = State(initialValue: CLLocationCoordinate2D(latitude: lat, longitude: lng))
}
```

In the gallery render, mark `existingImagePaths` items with a delete button that adds to `imagePathsToDelete` (and removes from local state).

- [ ] **Step 2: Update `save()` to handle delta**

```swift
// 1. Upload new images
var newPaths: [String] = []
for img in newImagesToUpload {
    if let path = try? await LeadImageUploader.shared.upload(
        image: img,
        companyId: opportunity.companyId,
        opportunityId: opportunity.id
    ) {
        newPaths.append(path)
    }
}

// 2. Delete removed images from Storage
for path in imagePathsToDelete {
    try? await LeadImageUploader.shared.deleteObject(path: path)
}

// 3. PATCH opportunity with merged paths + new lat/lng
let mergedPaths = existingImagePaths + newPaths   // existingImagePaths has had deleted ones removed
var patch = UpdateOpportunityDTO()
// … existing fields …
patch.images = mergedPaths
patch.latitude = capturedCoordinate?.latitude
patch.longitude = capturedCoordinate?.longitude
let updated = try await repo.update(opportunity.id, fields: patch)
```

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Books/Pipeline/EditLeadSheet.swift
git commit -m "EditLeadSheet: image add/remove + location update with delta-PATCH"
```

---

### Chunk 2E — Final report

1. Migration committed in ops-software-bible
2. Commits in ops-ios (5 commits)
3. Confirmation: PhotosPicker integration works on device
4. Confirmation: location capture returns coordinates
5. Confirmation: gallery + map render in LeadDetailView
6. Build verification ready

---

## Chunk 2F — Segment-scoped search

### Task 37: Add `SearchScope` to `UniversalSearchSheet`

**Files:**
- Modify: `OPS/Views/JobBoard/UniversalSearchSheet.swift`

- [ ] **Step 1: Add the enum + parameter**

At the top of `UniversalSearchSheet.swift`:

```swift
enum SearchScope: Equatable {
    case global
    case books(BooksSection)

    var titleSuffix: String? {
        switch self {
        case .global: return nil
        case .books(let seg): return "in \(seg.rawValue)"
        }
    }
}
```

Add to the struct:

```swift
var scope: SearchScope = .global
```

- [ ] **Step 2: Filter results based on scope**

Find the existing result-filtering logic (likely a `var filteredResults` computed). Add scope filtering:

```swift
private var scopedResults: [SearchResult] {
    switch scope {
    case .global:
        return allResults
    case .books(.pipeline):
        return allResults.filter { $0.kind == .opportunity }
    case .books(.estimates):
        return allResults.filter { $0.kind == .estimate }
    case .books(.invoices):
        return allResults.filter { $0.kind == .invoice }
    case .books(.expenses):
        return allResults.filter { $0.kind == .expense }
    }
}
```

(`SearchResult.kind` may not be the exact API — verify by reading the existing structure.)

- [ ] **Step 3: Update navigation title to show scope**

```swift
.navigationTitle(scope.titleSuffix.map { "Search \($0)" } ?? "Search")
```

- [ ] **Step 4: Commit**

```bash
git add OPS/Views/JobBoard/UniversalSearchSheet.swift
git commit -m "UniversalSearchSheet: accept SearchScope param + filter results by scope"
```

---

### Task 38: Pass scope through `AppState`

**Files:**
- Modify: `OPS/Utilities/AppState.swift` (or wherever `showingUniversalSearch` lives)

- [ ] **Step 1: Add the pending scope property**

```swift
@Published var pendingSearchScope: SearchScope = .global
```

- [ ] **Step 2: Update the consumer of `showingUniversalSearch`**

In `MainTabView` (or `ContentView` — wherever the universal search sheet is presented), update the `.sheet` wrapper:

```swift
.sheet(isPresented: $appState.showingUniversalSearch) {
    UniversalSearchSheet(scope: appState.pendingSearchScope)
        .environmentObject(dataController)
}
.onChange(of: appState.showingUniversalSearch) { _, isShowing in
    if !isShowing {
        // Reset to global so the next manual open from a non-BOOKS tab is unscoped
        appState.pendingSearchScope = .global
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add OPS/Utilities/AppState.swift OPS/Views/MainTabView.swift OPS/Views/ContentView.swift
git commit -m "AppState: pendingSearchScope drives UniversalSearchSheet from any tab"
```

---

### Task 39: Wire `BooksTabView`'s magnifying glass to set scope

**Files:**
- Modify: `OPS/Views/Books/BooksTabView.swift`
- Modify: `OPS/Views/Components/Common/AppHeader.swift` (verify the search-tap callback path)

- [ ] **Step 1: Read the existing AppHeader search action**

`grep -A6 "appState.showingUniversalSearch = true" OPS/Views/Components/Common/AppHeader.swift`

The search button in AppHeader sets `appState.showingUniversalSearch = true` directly. To inject scope, BooksTabView needs to either:
- (a) Override the search button via a custom `onSearchTapped` closure (if AppHeader supports one — it does per Phase 1 verification: `var onSearchTapped: (() -> Void)? = nil`)
- (b) Set `appState.pendingSearchScope = .books(currentSegment)` BEFORE the user can tap (e.g. on segment change)

Option (b) is cleaner — set it eagerly whenever the user is in BOOKS.

- [ ] **Step 2: In BooksTabView, set scope on appear + segment change**

```swift
.onAppear {
    appState.pendingSearchScope = .books(selectedSegment)
}
.onChange(of: selectedSegmentRaw) { _, _ in
    appState.pendingSearchScope = .books(selectedSegment)
}
.onDisappear {
    appState.pendingSearchScope = .global
}
```

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Books/BooksTabView.swift
git commit -m "BooksTabView: set search scope to active segment on appear and segment change"
```

---

### Chunk 2F — Final report

1. Commit list (3 commits)
2. Confirmation: magnifying glass on Pipeline segment searches only opportunities
3. Confirmation: same icon on JobBoard tab still searches globally (no regression)
4. Build verification ready

---

## Chunk 2G — Import contacts → leads

### Task 40: Add `NSContactsUsageDescription` to Info.plist

**Files:**
- Modify: `OPS/Info.plist`

- [ ] **Step 1: Verify if already present**

```bash
grep "NSContactsUsageDescription" /Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Info.plist
```

- [ ] **Step 2: If missing, add**

Inside the top-level `<dict>`:

```xml
<key>NSContactsUsageDescription</key>
<string>OPS uses your contacts to import leads into your pipeline.</string>
```

(Match the existing copy style — terse, explains why, no marketing.)

- [ ] **Step 3: Commit**

```bash
git add OPS/Info.plist
git commit -m "Add NSContactsUsageDescription for lead import flow"
```

---

### Task 41: Build `ContactImportViewModel`

**Files:**
- Create: `OPS/ViewModels/ContactImportViewModel.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  ContactImportViewModel.swift
//  OPS
//
//  Bulk-create opportunities from device Contacts. One CreateOpportunityDTO
//  per selected contact; failures isolated per row.
//

import SwiftUI
import Contacts

@MainActor
final class ContactImportViewModel: ObservableObject {
    struct Candidate: Identifiable {
        let id: String          // CNContact.identifier
        var name: String        // editable in preview
        var email: String?
        var phone: String?
        var include: Bool = true
    }

    @Published var candidates: [Candidate] = []
    @Published var isImporting = false
    @Published var progressDone: Int = 0
    @Published var progressTotal: Int = 0
    @Published var failedNames: [String] = []
    @Published var permissionDenied = false

    func loadFromContacts(_ contacts: [CNContact]) {
        candidates = contacts.map { c in
            let displayName = "\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces)
            return Candidate(
                id: c.identifier,
                name: displayName.isEmpty ? "Unnamed Contact" : displayName,
                email: c.emailAddresses.first?.value as String?,
                phone: c.phoneNumbers.first?.value.stringValue
            )
        }
    }

    func importSelected(companyId: String, defaultStageSlug: String) async {
        let toImport = candidates.filter { $0.include && !$0.name.isEmpty }
        guard !toImport.isEmpty else { return }

        isImporting = true
        progressDone = 0
        progressTotal = toImport.count
        failedNames = []
        defer { isImporting = false }

        let repo = OpportunityRepository(companyId: companyId)
        for c in toImport {
            let dto = CreateOpportunityDTO(
                companyId: companyId,
                title: nil,
                contactName: c.name,
                contactEmail: c.email,
                contactPhone: c.phone,
                description: nil,
                address: nil,
                estimatedValue: nil,
                source: nil,
                priority: nil,
                assignedTo: nil,
                expectedCloseDate: nil,
                quoteDeliveryMethod: nil,
                clientId: nil
            )
            do {
                _ = try await repo.create(dto)
            } catch {
                failedNames.append(c.name)
            }
            progressDone += 1
        }

        NotificationCenter.default.post(name: Notification.Name("LeadCreatedSuccess"), object: nil)
    }
}
```

(The `defaultStageSlug` parameter is read by callers but not directly used here — `CreateOpportunityDTO` lets the DB default to `'new_lead'` per the trigger from Phase 1A. If after Chunk 2C we want to honor the registry's `defaultNewStage().slug` explicitly, set it on the DTO.)

- [ ] **Step 2: Commit**

```bash
git add OPS/ViewModels/ContactImportViewModel.swift
git commit -m "Add ContactImportViewModel for bulk lead-from-contact creation"
```

---

### Task 42: Build `ImportContactsSheet`

**Files:**
- Create: `OPS/Views/Books/Pipeline/ImportContactsSheet.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  ImportContactsSheet.swift
//  OPS
//

import SwiftUI
import Contacts
import ContactsUI

struct ImportContactsSheet: View {
    @StateObject private var viewModel = ContactImportViewModel()
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .picking

    enum Phase {
        case picking         // CNContactPickerViewController is showing
        case preview         // candidate list, editable
        case importing       // progress shown
        case done            // success summary
        case denied          // permission denied
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                content
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .task { await requestAccess() }
    }

    // MARK: - Phases

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .picking:
            ProgressView().tint(OPSStyle.Colors.primaryAccent)
        case .preview:
            previewView
        case .importing:
            importingView
        case .done:
            doneView
        case .denied:
            deniedView
        }
    }

    private var previewView: some View {
        ScrollView {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                Text("\(viewModel.candidates.filter { $0.include }.count) of \(viewModel.candidates.count) selected")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                ForEach($viewModel.candidates) { $cand in
                    HStack {
                        Toggle(isOn: $cand.include) { EmptyView() }
                            .labelsHidden()
                            .tint(OPSStyle.Colors.primaryAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Name", text: $cand.name)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            if let e = cand.email {
                                Text(e)
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }
                        Spacer()
                    }
                    .padding(OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                }
            }
            .padding(OPSStyle.Layout.spacing3)
        }
    }

    private var importingView: some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            Spacer()
            TacticalLoadingBarAnimated()
            Text("Creating \(viewModel.progressDone) of \(viewModel.progressTotal)…")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
        }
    }

    private var doneView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.successStatus)
            Text("\(viewModel.progressDone - viewModel.failedNames.count) LEADS CREATED")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            if !viewModel.failedNames.isEmpty {
                Text("\(viewModel.failedNames.count) COULD NOT IMPORT:")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                ForEach(viewModel.failedNames, id: \.self) { name in
                    Text(name)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            Spacer()
        }
        .padding(OPSStyle.Layout.spacing4)
    }

    private var deniedView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.warningStatus)
            Text("CONTACTS PERMISSION DENIED")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text("Enable Contacts access in Settings to import leads.")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
            Button("OPEN SETTINGS") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            Spacer()
        }
        .padding(OPSStyle.Layout.spacing4)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("CANCEL") { dismiss() }
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        if phase == .preview {
            ToolbarItem(placement: .topBarTrailing) {
                Button("CREATE") {
                    Task {
                        guard let companyId = dataController.currentUser?.companyId else { return }
                        let defaultSlug = PipelineStageRegistry.shared.defaultNewStage()?.slug ?? PipelineStage.Slug.newLead
                        phase = .importing
                        await viewModel.importSelected(companyId: companyId, defaultStageSlug: defaultSlug)
                        phase = .done
                    }
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
        if phase == .done {
            ToolbarItem(placement: .topBarTrailing) {
                Button("DONE") { dismiss() }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
    }

    private var navTitle: String {
        switch phase {
        case .picking, .preview: return "IMPORT CONTACTS"
        case .importing: return "IMPORTING…"
        case .done: return "IMPORT COMPLETE"
        case .denied: return "PERMISSION NEEDED"
        }
    }

    // MARK: - Permission

    private func requestAccess() async {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized, .limited:
            // For Phase 2: load all contacts directly via store.unifiedContacts.
            // The picker phase advances to preview after load.
            await loadContactsFromStore(store)
        case .notDetermined:
            do {
                let granted = try await store.requestAccess(for: .contacts)
                if granted {
                    await loadContactsFromStore(store)
                } else {
                    phase = .denied
                }
            } catch {
                phase = .denied
            }
        case .denied, .restricted:
            phase = .denied
        @unknown default:
            phase = .denied
        }
    }

    private func loadContactsFromStore(_ store: CNContactStore) async {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var loaded: [CNContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                loaded.append(contact)
            }
            viewModel.loadFromContacts(loaded)
            phase = .preview
        } catch {
            phase = .denied
        }
    }
}
```

(Note: the spec mentioned multi-select via existing `ContactPicker`. Phase 2's simplest implementation loads all contacts and lets the user toggle them in the preview list. If the project later wants a system-style picker, refactor to `CNContactPickerViewController` with multi-select.)

- [ ] **Step 2: Commit**

```bash
git add OPS/Views/Books/Pipeline/ImportContactsSheet.swift
git commit -m "Add ImportContactsSheet (full-list preview with per-row toggle)"
```

---

### Task 43: Wire CTA in Pipeline-empty state + AddLeadSheet toolbar

**Files:**
- Modify: `OPS/Views/Books/Pipeline/PipelineSectionView.swift`
- Modify: `OPS/Views/Books/Pipeline/AddLeadSheet.swift`

- [ ] **Step 1: Activate the Pipeline-empty CTA**

Find the existing `pipelineEmptyState` view in `PipelineSectionView.swift`. Add an "Import from Contacts" button alongside the existing "ADD YOUR FIRST LEAD" CTA:

```swift
@State private var showImportContacts = false

// In pipelineEmptyState body:
VStack(spacing: OPSStyle.Layout.spacing3) {
    // Existing: "ADD YOUR FIRST LEAD" with Add Lead button
    // Add:
    Button(action: { showImportContacts = true }) {
        HStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.plus")
            Text("IMPORT FROM CONTACTS")
        }
        .font(OPSStyle.Typography.captionBold)
        .foregroundColor(OPSStyle.Colors.secondaryText)
    }
}

// Add sheet on the section view:
.sheet(isPresented: $showImportContacts) {
    ImportContactsSheet().environmentObject(dataController)
}
```

- [ ] **Step 2: Add toolbar button to AddLeadSheet**

In `AddLeadSheet.swift` toolbar:

```swift
ToolbarItem(placement: .topBarLeading) {
    Menu {
        Button(action: { dismiss() }) {
            Label("Cancel", systemImage: "xmark")
        }
        Button(action: { /* present ImportContactsSheet via parent — see step 3 */ }) {
            Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
        }
    } label: {
        Text("CANCEL")
            .foregroundColor(OPSStyle.Colors.secondaryText)
    }
}
```

(Since `ImportContactsSheet` and `AddLeadSheet` would both want to be modal at the same time — they can't be. Cleanest: add a separate "+ IMPORT" button in PipelineSectionView's empty state AND in AddLeadSheet's toolbar that DISMISSES `AddLeadSheet` first, posts a notification, and the parent presents `ImportContactsSheet` next. OR simpler: just put it in the Pipeline-empty state — skip the AddLeadSheet entrypoint for Phase 2 and revisit if users ask for it.)

For Phase 2 minimum-viable: only Pipeline-empty state CTA. Skip AddLeadSheet toolbar integration.

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Books/Pipeline/PipelineSectionView.swift
git commit -m "Pipeline empty state: activate Import from Contacts CTA"
```

---

### Task 44: Smoke-test on device

This is verification — no code. PM coordinates with user.

- [ ] **PM script for user:**

```
1. Run a build of HEAD on device.
2. Reset BOOKS / Pipeline state (or use a test company with empty pipeline).
3. Open BOOKS → Pipeline. Tap "IMPORT FROM CONTACTS" in the empty state.
4. Approve the contacts permission prompt.
5. Confirm preview list shows all device contacts with toggle defaulted to ON.
6. Toggle off some contacts; tap CREATE.
7. Watch progress; confirm final "X LEADS CREATED" screen.
8. Dismiss; confirm Pipeline section refreshes with the new leads in the default new-lead stage (per registry).
9. Verify in Supabase that opportunities rows were created with contact_name pulled from device.
```

- [ ] **PM consolidates results into a verification log**

---

### Chunk 2G — Final report

1. Commits (4 commits across T40, T41, T42, T43; T44 is verification only)
2. Confirmation: NSContactsUsageDescription added to Info.plist
3. Permission flow tested (allow + deny paths)
4. Bulk create works for N≥10 contacts
5. Pipeline section refreshes via existing LeadCreatedSuccess notification
6. Build verification ready

---

## Phase 2 — Final closeout

After all 7 chunks ship + their commits land + the user verifies on device:

1. **Bible updates** per spec §13:
   - §9.85 (Opportunity Entity) — append AI / images / lat-lng iOS-parity paragraph
   - §9.66 (Pipeline Stages) — note iOS reads pipeline_stage_configs per-company
   - §9.83 (Per-company stage configuration) — note iOS parity, link to migration `2026-05-11-01`
   - §9.174 (Stage Transitions) — note slug-based storage on iOS
   - §9 InvoiceService — add iOS InvoiceRepository.create(...) to equivalence
   - §9 PaymentService — note both contexts now supported on iOS
   - New "iOS BOOKS Phase 2 (May 2026)" subsection
2. **Spec drift register closeout** in `docs/superpowers/specs/2026-05-11-books-tab-phase-2-design.md` §12 — mark items 1–8 + 10 RESOLVED with implementing commit hashes; #9 STAYS OPEN (web parity, not iOS)
3. **Phase 1 spec drift item #15** (per-company stages) — mark RESOLVED in `docs/superpowers/specs/2026-05-07-books-tab-design.md` with reference to Chunk 2C commit hash

---

## Self-Review

After writing this plan, run a fresh-eyes pass against the spec:

**Spec coverage:**
- ✅ Spec §4 (Chunk 2A InvoiceFormSheet) → T1–T10
- ✅ Spec §5 (Chunk 2B PaymentRecordSheet refactor) → T11–T15
- ✅ Spec §6 (Chunk 2C per-company stages) → T16–T26
- ✅ Spec §7 (Chunk 2D AI fields) → T27–T30
- ✅ Spec §8 (Chunk 2E images + lat/lng) → T31–T36
- ✅ Spec §9 (Chunk 2F segment-scoped search) → T37–T39
- ✅ Spec §10 (Chunk 2G import contacts) → T40–T44
- ✅ Spec §11 schema/RPC additions → T16, T31 migrations
- ✅ Spec §12 drift register → tracked in chunks; final closeout §"Phase 2 — Final closeout"
- ✅ Spec §13 bible updates → final closeout
- ✅ Spec §14 animation discipline → conventions section + per-chunk reminders
- ✅ Spec §15 accessibility → enforced via OPSStyle tokens + per-chunk acceptance criteria
- ✅ Spec §16 phase-level acceptance → embedded in chunk reports
- ✅ Spec §17 out of scope (Phase 3+) → not built

**Placeholder scan:** All steps have either complete code blocks or specific investigation instructions with grep commands. No "TBD" or "implement later" markers.

**Type consistency:**
- `CreateInvoiceDTO` — defined in T2, used in T7 — fields match
- `PipelineStage` struct — defined in T20, used in T21–T25 — same shape
- `PipelineStageRegistry` — defined in T21, used in T22–T26 — same API
- `LeadImageUploader` — defined in T32, used in T34, T35, T36 — same `upload(image:companyId:opportunityId:)` signature
- `SearchScope` — defined in T37, used in T38, T39 — same enum cases
- `ContactImportViewModel.Candidate` — defined in T41, used in T42 — same fields
- `Notification.Name("LeadCreatedSuccess")` — already from Phase 1; reused in T41

No type-name drift detected.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-11-books-tab-phase-2-implementation.md`.

**Two execution options:**

**1. Subagent-Driven (recommended)** — PM dispatches a fresh subagent per chunk via `mcp__ccd_session__spawn_task`. Each chunk runs in its own worktree. PM reviews between chunks, sends user-verification asks where required (Chunks 2C T26, 2E T34-36 device test, 2G T44).

**2. Inline Execution** — PM executes chunks in this session using `executing-plans`. Slower because no parallel build verification (per the no-xcodebuild memory rule, builds are user-driven anyway).

**Recommend (1)** — same pattern that worked for Phase 1's 5 chunks. Each chunk fits comfortably under the ~500k token budget the user specified.




