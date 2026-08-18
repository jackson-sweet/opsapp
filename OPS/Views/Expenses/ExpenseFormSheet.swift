//
//  ExpenseFormSheet.swift
//  OPS
//
//  Create or edit an expense — receipt capture, OCR auto-fill, details, project allocation.
//

import SwiftUI
import SwiftData
import UIKit
import VisionKit

private struct StagedExpenseReceipt {
    let url: String
    let thumbnailUrl: String
}

private struct ExpenseReceiptTarget {
    let url: String?
    let thumbnailUrl: String?
}

private struct ExpenseSaveInterruption {
    enum Kind {
        case receiptUpload
        case commitConfirmation
        case saveRejected
        case closeRequired
    }

    let kind: Kind
    let title: String
    let message: String
    let retryLabel: String

    var locksEditing: Bool { kind == .commitConfirmation }
}

/// The merchant input is deliberately identified as an organization name so
/// iOS does not offer credential or password AutoFill for an expense field.
struct ExpenseMerchantTextField: View {
    @Binding var text: String

    var body: some View {
        TextField("", text: $text)
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .multilineTextAlignment(.trailing)
            .textContentType(.organizationName)
            .textInputAutocapitalization(.words)
            .accessibilityIdentifier("expense.merchant")
            .placeholder(when: text.isEmpty) {
                Text("Business name")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.placeholderText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
    }
}

enum ExpenseOCRAutofill {
    static func description(current: String, suggestion: String?) -> String {
        guard current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let suggestion = suggestion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !suggestion.isEmpty else {
            return current
        }
        return suggestion
    }
}

struct ExpenseFormSheet: View {
    @ObservedObject var viewModel: ExpenseViewModel
    var prefilledProjectId: String? = nil
    var editing: ExpenseDTO? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Query private var allProjects: [Project]

    @State private var merchantName = ""
    @State private var amount = ""
    @State private var taxAmount = ""
    @State private var selectedCurrency: String = Self.defaultCurrencyCode()
    @State private var expenseDate = Date()
    @State private var selectedCategoryId: String? = nil
    @State private var paymentMethod: ExpensePaymentMethod = .personalCard
    @State private var expenseDescription = ""
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var showDocumentScanner = false
    @State private var showReceiptSourceSheet = false
    @State private var pendingScannerImages: [UIImage] = []
    @State private var isReplacingReceipt = false
    @State private var isScanning = false
    @State private var ocrUsed = false
    @State private var lastOCRResult: OCRResult? = nil
    @State private var projectAllocations: [(projectId: String, percentage: String)] = []
    @State private var isSaving = false
    @State private var validationErrors: [String] = []
    @State private var isViewMode = false
    @State private var workingExpenseId = UUID().uuidString.lowercased()
    /// Uploaded receipt URLs retained until the atomic database request is
    /// confirmed. They are never deleted on an ambiguous network result.
    @State private var stagedReceipt: StagedExpenseReceipt? = nil
    @State private var receiptUploadId = UUID().uuidString.lowercased()
    /// The exact command (including its ledger request id) is reused after an
    /// ambiguous response. Any operator edit creates a new request id.
    @State private var pendingAtomicCommand: ExpenseAtomicSaveCommand? = nil
    @State private var saveInterruption: ExpenseSaveInterruption? = nil
    @State private var resumeSubmissionAfterReceiptReason = false
    @State private var showDiscardReceiptDialog = false

    // Project picker sheet state
    @State private var showProjectPicker = false
    @State private var projectPickerIndex: Int = 0

    // Multi-receipt queue state
    @State private var receiptQueue: [UIImage] = []
    @State private var queueIndex: Int = 0

    // No-receipt escape hatch — surfaced when require_receipt_photo is on and no
    // photo is attached, so a genuinely receiptless purchase still files with a
    // reason the office can see.
    @State private var noReceiptReason: NoReceiptReason? = nil
    @State private var noReceiptNote: String = ""
    @State private var showReceiptRequiredDialog = false
    @State private var showNoReceiptSheet = false
    @State private var noProjectReason: NoProjectReason? = nil
    @State private var noProjectNote: String = ""
    @State private var showProjectRequiredDialog = false
    @State private var showNoProjectSheet = false

    // Section expansion state (always expanded, non-collapsible)
    @State private var isDetailsExpanded = true
    @State private var isAllocationExpanded = true

    // Custom picker sheet state
    @State private var showCategoryPicker = false
    @State private var showPaymentPicker = false
    @State private var showCurrencyPicker = false

    /// Resolves a sane default currency for new expenses: the user's locale
    /// first, falling back to USD. Existing expenses override this in
    /// `onAppear` from the persisted `currency` field.
    private static func defaultCurrencyCode() -> String {
        if let code = Locale.current.currency?.identifier, !code.isEmpty {
            return code.uppercased()
        }
        return "USD"
    }

    /// Returns true when the company is on per-job review and so each
    /// expense must be allocated to exactly one project.
    private var isPerJobMode: Bool {
        viewModel.settings?.reviewFrequency == "per_job"
    }

    /// Disable adding more allocations when per-job and one already exists.
    private var canAddMoreAllocations: Bool {
        !isPerJobMode || projectAllocations.isEmpty
    }

    /// Currency symbol for the selected ISO code (e.g. "$" for USD, "CA$"
    /// for CAD). Falls back to the ISO code itself if Foundation can't
    /// produce one.
    private var currencySymbol: String {
        BooksFormat.symbol(for: selectedCurrency)
    }

    // Keyboard state
    @FocusState private var focusedField: ExpenseField?

    private enum ExpenseField: Hashable {
        case description
        case merchant
        case amount
        case tax
        case allocationPercent(Int)
    }

    private var expenseStatus: ExpenseStatus {
        guard let exp = editing else { return .draft }
        return ExpenseStatus(rawValue: exp.status) ?? .draft
    }

    private var isLocked: Bool {
        expenseStatus == .approved || expenseStatus == .reimbursed
    }

    /// Uploader-only edit rule: an existing expense may be edited only by the
    /// person who submitted it — regardless of role. Owners / office review via
    /// approve / reject; they don't edit a teammate's line. A brand-new expense
    /// is always editable by its author. (Server RLS still grants edit to
    /// full-access roles — align it + web for true enforcement.)
    private var canEditExpense: Bool {
        guard let exp = editing else { return true }
        guard let uid = dataController.currentUser?.id, !uid.isEmpty else { return false }
        return exp.submittedBy == uid
    }

    /// Resolves a user id (submitter / approver / rejecter) to a display name
    /// for attribution lines. Nil when the user isn't cached locally — callers
    /// fall back to hiding the name rather than showing a raw id.
    private func personName(_ userId: String?) -> String? {
        guard let id = userId, !id.isEmpty else { return nil }
        return dataController.getUser(id: id)?.fullName
    }

    private var receiptImage: UIImage? {
        guard !receiptQueue.isEmpty, queueIndex < receiptQueue.count else { return nil }
        return receiptQueue[queueIndex]
    }

    private var persistedReceiptURL: String? {
        editing?.receiptImageUrl
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        // APPROVAL STATUS BANNER + who added it
                        if editing != nil {
                            approvalBanner
                            submitterLine
                        }

                        // RECEIPT PHOTO
                        receiptSection
                            .padding(.top, editing != nil ? 0 : OPSStyle.Layout.spacing2)

                        // DETAILS
                        ExpandableSection(
                            title: "Details",
                            icon: "list.bullet",
                            isExpanded: $isDetailsExpanded,
                            collapsible: false
                        ) {
                            detailsContent
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                        // PROJECT ALLOCATION
                        ExpandableSection(
                            title: "Project Allocation",
                            icon: OPSStyle.Icons.folderFill,
                            isExpanded: $isAllocationExpanded,
                            collapsible: false
                        ) {
                            allocationContent
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                    }
                    .disabled(isViewMode || isSaving || saveInterruption?.locksEditing == true)
                    .padding(.top, OPSStyle.Layout.spacing2)
                    .padding(.bottom, 120)
                }
                .scrollDismissesKeyboard(.interactively)

                stickyFooter
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { requestDismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(isSaving ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .principal) {
                    Text(editing == nil ? "NEW EXPENSE" : (isViewMode ? "EXPENSE" : "EDIT EXPENSE"))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .sheet(isPresented: $showDocumentScanner) {
                DocumentScannerView(scannedImages: $pendingScannerImages) {
                    applySelectedReceipts(pendingScannerImages)
                    pendingScannerImages = []
                    Task { await runOCR() }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(
                    images: $selectedImages,
                    selectionLimit: editing == nil && !isReplacingReceipt ? 10 : 1,
                    onSelectionComplete: {
                        applySelectedReceipts(selectedImages)
                        selectedImages = []
                        Task { await runOCR() }
                    }
                )
            }
            .sheet(isPresented: $showProjectPicker) {
                ExpenseProjectPickerSheet(
                    allProjects: allProjects,
                    onSelect: { project in
                        if projectPickerIndex < projectAllocations.count {
                            projectAllocations[projectPickerIndex].projectId = project.id
                        }
                        showProjectPicker = false
                    }
                )
            }
            .sheet(isPresented: $showCategoryPicker) {
                ExpenseCategoryPickerSheet(
                    categories: viewModel.categories,
                    selectedId: selectedCategoryId,
                    onSelect: { catId in
                        selectedCategoryId = catId
                        showCategoryPicker = false
                    }
                )
            }
            .sheet(isPresented: $showPaymentPicker) {
                ExpensePaymentPickerSheet(
                    selected: paymentMethod,
                    onSelect: { method in
                        paymentMethod = method
                        showPaymentPicker = false
                    }
                )
            }
            .sheet(isPresented: $showCurrencyPicker) {
                ExpenseCurrencyPickerSheet(
                    selected: selectedCurrency,
                    onSelect: { code in
                        selectedCurrency = code
                        showCurrencyPicker = false
                    }
                )
            }
            .confirmationDialog("ADD RECEIPT", isPresented: $showReceiptSourceSheet, titleVisibility: .visible) {
                Button("Scan Receipt") { showDocumentScanner = true }
                Button("Choose from Library") { showImagePicker = true }
                Button("Cancel", role: .cancel) { }
            }
            .confirmationDialog("LEAVE WITHOUT RETRYING?", isPresented: $showDiscardReceiptDialog, titleVisibility: .visible) {
                Button("Keep Working", role: .cancel) { }
                Button("Close Form", role: .destructive) { dismiss() }
            } message: {
                Text("Your receipt and changes are still here. Close only if you don't want to retry.")
            }
            .confirmationDialog("RECEIPT REQUIRED", isPresented: $showReceiptRequiredDialog, titleVisibility: .visible) {
                Button("Add Receipt Photo") {
                    isReplacingReceipt = false
                    showReceiptSourceSheet = true
                }
                Button("No Receipt Available") {
                    resumeSubmissionAfterReceiptReason = true
                    showNoReceiptSheet = true
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This company requires a receipt to submit.")
            }
            .sheet(isPresented: $showNoReceiptSheet) {
                NoReceiptReasonSheet(
                    selected: noReceiptReason,
                    note: noReceiptNote,
                    onSubmit: { reason, note in
                        noReceiptReason = reason
                        noReceiptNote = note
                        showNoReceiptSheet = false
                        let shouldResume = resumeSubmissionAfterReceiptReason
                        resumeSubmissionAfterReceiptReason = false
                        if shouldResume {
                            Task { await save(submit: true) }
                        }
                    }
                )
            }
            .confirmationDialog("PROJECT REQUIRED", isPresented: $showProjectRequiredDialog, titleVisibility: .visible) {
                Button("Add Project") { addProjectFromGate() }
                Button("No Project Available") { showNoProjectSheet = true }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This company requires a project to submit.")
            }
            .sheet(isPresented: $showNoProjectSheet) {
                NoProjectReasonSheet(
                    selected: noProjectReason,
                    note: noProjectNote,
                    onSubmit: { reason, note in
                        noProjectReason = reason
                        noProjectNote = note
                        showNoProjectSheet = false
                        Task { await save(submit: true) }
                    }
                )
            }
            .onAppear {
                // Load categories if not already loaded
                if viewModel.categories.isEmpty {
                    Task { await viewModel.loadCategories() }
                }
                if !viewModel.hasLoadedSettings {
                    Task { await viewModel.loadSettings() }
                }

                if let exp = editing {
                    isViewMode = true
                    merchantName = exp.merchantName ?? ""
                    amount = exp.amount > 0 ? String(format: "%.2f", exp.amount) : ""
                    taxAmount = exp.taxAmount.map { String(format: "%.2f", $0) } ?? ""
                    if let currency = exp.currency, !currency.isEmpty {
                        selectedCurrency = currency.uppercased()
                    }
                    selectedCategoryId = exp.categoryId
                    paymentMethod = ExpensePaymentMethod(rawValue: exp.paymentMethod ?? "") ?? .personalCard
                    expenseDescription = exp.description ?? ""
                    if let dateStr = exp.expenseDate {
                        let iso = ISO8601DateFormatter()
                        iso.formatOptions = [.withFullDate]
                        if let d = iso.date(from: dateStr) {
                            expenseDate = d
                        } else if let d = ISO8601DateFormatter().date(from: dateStr) {
                            expenseDate = d
                        }
                    }
                    if let allocations = exp.allocations {
                        projectAllocations = allocations.map {
                            (projectId: $0.projectId, percentage: String(format: "%.0f", $0.percentage))
                        }
                    }
                    noReceiptReason = NoReceiptReason(code: exp.receiptMissingReason)
                    noReceiptNote = exp.receiptMissingNote ?? ""
                    noProjectReason = NoProjectReason(code: exp.projectMissingReason)
                    noProjectNote = exp.projectMissingNote ?? ""
                }
                if let pid = prefilledProjectId, projectAllocations.isEmpty {
                    projectAllocations = [(projectId: pid, percentage: "100")]
                }
            }
            .interactiveDismissDisabled(isSaving || saveInterruption != nil)
        }
    }

    // MARK: - Receipt Section

    private var receiptSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            if isScanning {
                HStack {
                    Spacer()
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        ProgressView()
                            .tint(OPSStyle.Colors.primaryAccent)
                        Text("SCANNING RECEIPT...")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    Spacer()
                }
                .frame(height: 160)
                .glassSurface()
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            } else if let image = receiptImage {
                // Queue progress indicator
                if receiptQueue.count > 1 {
                    Text("RECEIPT \(queueIndex + 1) OF \(receiptQueue.count)")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                }

                // Receipt preview — full receipt visible (no crop), capped height so it
                // doesn't dominate the form. Receipts are typically tall (1:3+ aspect),
                // so we use scaledToFit and cap at 360pt to keep the rest of the
                // form reachable while showing every line item.
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 360)
                        .glassSurface()
                        .contentShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))

                    if ocrUsed {
                        Text("AUTO-FILLED FROM RECEIPT")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.invertedText)
                            .padding(.horizontal, OPSStyle.Layout.spacing2)
                            .padding(.vertical, OPSStyle.Layout.spacing1)
                            .background(OPSStyle.Colors.successStatus)
                            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                            .padding(OPSStyle.Layout.spacing2)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                if !isViewMode {
                    HStack(spacing: OPSStyle.Layout.spacing3) {
                        Button {
                            isReplacingReceipt = true
                            showReceiptSourceSheet = true
                        } label: {
                            Text("REPLACE PHOTO")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)

                        if !ocrUsed {
                            Button {
                                Task { await runOCR() }
                            } label: {
                                Text("RETRY SCAN")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                }
            } else if let receiptURL = persistedReceiptURL, let url = URL(string: receiptURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(OPSStyle.Colors.loadingSpinner)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetStandard * 2)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: OPSStyle.Layout.formMediaPreviewMaxHeight)
                    case .failure:
                        receiptUnavailableState
                    @unknown default:
                        receiptUnavailableState
                    }
                }
                .glassSurface()
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .accessibilityLabel("Receipt photo")

                if !isViewMode {
                    Button {
                        isReplacingReceipt = true
                        showReceiptSourceSheet = true
                    } label: {
                        Text("REPLACE RECEIPT")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .accessibilityHint("Choose a new receipt photo")
                }
            } else if isViewMode {
                // No receipt — show placeholder in view mode
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: OPSStyle.Icons.photo)
                        .font(.system(size: OPSStyle.Layout.IconSize.xl))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("NO RECEIPT")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .glassSurface()
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            } else {
                // Add receipt button
                Button {
                    isReplacingReceipt = false
                    showReceiptSourceSheet = true
                } label: {
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: OPSStyle.Icons.receipt)
                            .font(.system(size: OPSStyle.Layout.IconSize.xl))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Text("ADD RECEIPT PHOTO")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        if viewModel.submissionRequirements.requireReceiptPhoto {
                            Text("REQUIRED FOR SUBMISSION")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .glassSurface()
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }

            if !hasReceipt, let reason = noReceiptReason {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text("// NO RECEIPT · \(reason.label.uppercased())")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.warningStatus)

                    if !noReceiptNote.isEmpty {
                        Text(noReceiptNote)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }

                    if !isViewMode {
                        Button {
                            resumeSubmissionAfterReceiptReason = false
                            showNoReceiptSheet = true
                        } label: {
                            Text("CHANGE REASON")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OPSStyle.Layout.spacing3)
                .glassSurface()
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }

            if let saveInterruption {
                HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: OPSStyle.Icons.exclamationmarkCircleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text(saveInterruption.title)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                        Text(saveInterruption.message)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    Spacer()
                }
                .padding(OPSStyle.Layout.spacing3)
                .glassSurface(borderColor: OPSStyle.Colors.errorStatus)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var receiptUnavailableState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: OPSStyle.Icons.exclamationmarkTriangle)
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.warningStatus)
            Text("RECEIPT UNAVAILABLE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: OPSStyle.Layout.touchTargetStandard * 2)
    }

    // MARK: - Details Content (inside ExpandableSection)

    private var detailsContent: some View {
        VStack(spacing: 0) {
            // Description (item name)
            detailRow(label: "DESCRIPTION") {
                TextField("", text: $expenseDescription)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .description)
                    .placeholder(when: expenseDescription.isEmpty) {
                        Text("Hammer, nails, etc.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.placeholderText)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
            }

            dividerLine

            // Merchant
            detailRow(label: "MERCHANT") {
                ExpenseMerchantTextField(text: $merchantName)
                    .focused($focusedField, equals: .merchant)
            }

            dividerLine

            // Amount
            detailRow(label: "AMOUNT") {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text(currencySymbol)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    TextField("", text: $amount)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .amount)
                        .placeholder(when: amount.isEmpty) {
                            Text("0.00")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.placeholderText)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                }
            }

            dividerLine

            // Currency
            detailRow(label: "CURRENCY") {
                Button {
                    showCurrencyPicker = true
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Text(selectedCurrency)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Image(systemName: "chevron.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }

            dividerLine

            // Tax
            detailRow(label: "TAX") {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text(currencySymbol)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    TextField("", text: $taxAmount)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .tax)
                        .placeholder(when: taxAmount.isEmpty) {
                            Text("0.00")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.placeholderText)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                }
            }

            dividerLine

            // Date
            detailRow(label: "DATE") {
                DatePicker("", selection: $expenseDate, displayedComponents: .date)
                    .labelsHidden()
                    .colorScheme(.dark)
            }

            dividerLine

            // Category
            detailRow(label: "CATEGORY") {
                Button {
                    showCategoryPicker = true
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        if let catId = selectedCategoryId,
                           let cat = viewModel.categories.first(where: { $0.id == catId }) {
                            if let icon = cat.icon {
                                Image(systemName: icon)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                            Text(cat.name)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        } else {
                            Text("Select")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.placeholderText)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }

            dividerLine

            // Payment Method
            detailRow(label: "PAYMENT") {
                Button {
                    showPaymentPicker = true
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Text(paymentMethod.displayName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Image(systemName: "chevron.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func detailRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 100, alignment: .leading)
            Spacer()
            content()
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorder)
            .frame(height: 1)
    }

    // MARK: - Project Allocation Content (inside ExpandableSection)

    private var allocationContent: some View {
        VStack(spacing: 0) {
            if projectAllocations.isEmpty && viewModel.settings?.requireProjectAssignment == true {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Image(systemName: OPSStyle.Icons.exclamationmarkTriangleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    Text("REQUIRED FOR SUBMISSION")
                        .font(OPSStyle.Typography.smallCaption)
                }
                .foregroundColor(OPSStyle.Colors.warningStatus)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)
            }

            ForEach(projectAllocations.indices, id: \.self) { index in
                if index > 0 {
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorder)
                        .frame(height: 1)
                }
                allocationRow(index: index)
            }

            if !isViewMode {
                if !projectAllocations.isEmpty {
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorder)
                        .frame(height: 1)
                }

                if canAddMoreAllocations {
                    Button {
                        projectAllocations.append((projectId: "", percentage: "100"))
                        // Immediately open picker for the new row
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            projectPickerIndex = projectAllocations.count - 1
                            showProjectPicker = true
                        }
                    } label: {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Image(systemName: OPSStyle.Icons.plus)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            Text("ADD PROJECT")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            Spacer()
                        }
                        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // per_job mode — exactly one project per expense.
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: OPSStyle.Icons.exclamationmarkTriangleFill)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        Text("PER-JOB COMPANIES ALLOW ONE PROJECT PER EXPENSE")
                            .font(OPSStyle.Typography.smallCaption)
                    }
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                }
            }
        }
    }

    @ViewBuilder
    private func allocationRow(index: Int) -> some View {
        let hasProject = !projectAllocations[index].projectId.isEmpty
        let project = hasProject ? allProjects.first(where: { $0.id == projectAllocations[index].projectId }) : nil

        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: OPSStyle.Icons.folderFill)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if hasProject {
                // Show selected project — tap to change
                VStack(alignment: .leading, spacing: 2) {
                    Text(project?.title ?? "Unknown Project")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    if let clientName = project?.effectiveClientName, !clientName.isEmpty {
                        Text(clientName)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isViewMode {
                        projectPickerIndex = index
                        showProjectPicker = true
                    }
                }
            } else {
                // No project selected — tap to pick
                Button {
                    projectPickerIndex = index
                    showProjectPicker = true
                } label: {
                    Text("Select project...")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.placeholderText)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Spacer()

            // Percentage field
            TextField("100", text: allocationPercentBinding(index: index))
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .allocationPercent(index))
                .frame(width: 44)

            Text("%")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if !isViewMode {
                Button {
                    projectAllocations.remove(at: index)
                } label: {
                    Image(systemName: OPSStyle.Icons.xmark)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
    }

    private func allocationPercentBinding(index: Int) -> Binding<String> {
        Binding(
            get: { index < projectAllocations.count ? projectAllocations[index].percentage : "" },
            set: { if index < projectAllocations.count { projectAllocations[index].percentage = $0 } }
        )
    }

    // MARK: - Sticky Footer

    private var hasMoreReceipts: Bool {
        receiptQueue.count > 1 && queueIndex < receiptQueue.count - 1
    }

    private var remainingReceiptCount: Int {
        receiptQueue.count - queueIndex - 1
    }

    private var stickyFooter: some View {
        OPSFloatingButtonBar {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                if !validationErrors.isEmpty {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        ForEach(validationErrors, id: \.self) { error in
                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                Image(systemName: OPSStyle.Icons.exclamationmarkCircleFill)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                                Text(error)
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: OPSStyle.Layout.spacing3) {
                if isSaving {
                    ProgressView()
                        .tint(OPSStyle.Colors.primaryAccent)
                        .frame(maxWidth: .infinity)
                } else if editing == nil {
                    // NEW expense — one Add. Snap-a-stack still saves drafts via
                    // SAVE & NEXT; the last/single receipt is added (submitted).
                    if hasMoreReceipts {
                        Button {
                            Task { await saveAndAdvance() }
                        } label: {
                            Text(saveButtonLabel("SAVE & NEXT (\(remainingReceiptCount) LEFT)"))
                                .font(OPSStyle.Typography.button)
                        }
                        .opsPrimaryButtonStyle()
                    } else {
                        Button {
                            Task { await save(submit: true) }
                        } label: {
                            Text(saveButtonLabel("ADD"))
                                .font(OPSStyle.Typography.button)
                        }
                        .opsPrimaryButtonStyle()
                    }
                } else if isLocked {
                    // Approved / Reimbursed — status badge only
                    HStack {
                        Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                            .foregroundColor(OPSStyle.Colors.successStatus)
                        Text(expenseStatus == .reimbursed ? "REIMBURSED" : "APPROVED")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.successStatus)
                    }
                    .frame(maxWidth: .infinity)
                } else if isViewMode {
                    if canEditExpense {
                        // Viewing your own draft/submitted/rejected — EDIT + the one finalize action.
                        Button {
                            withAnimation(OPSStyle.Animation.panel) { isViewMode = false }
                        } label: {
                            Text("EDIT")
                                .font(OPSStyle.Typography.button)
                        }
                        .opsSecondaryButtonStyle()

                        if expenseStatus == .draft {
                            Button {
                                Task { await save(submit: true) }
                            } label: {
                                Text(saveButtonLabel("ADD"))
                                    .font(OPSStyle.Typography.button)
                            }
                            .opsPrimaryButtonStyle()
                        } else if expenseStatus == .rejected {
                            Button {
                                Task { await save(submit: true) }
                            } label: {
                                Text(saveButtonLabel("RESUBMIT"))
                                    .font(OPSStyle.Typography.button)
                            }
                            .opsPrimaryButtonStyle()
                        }
                    } else {
                        // A teammate's expense — view only. Owners/office act via
                        // approve/reject, not by editing the submitter's line.
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Image(systemName: OPSStyle.Icons.lockFill)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text("VIEW ONLY")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    // Editing draft/submitted/rejected.
                    if expenseStatus == .submitted {
                        // Pending line — save edits in place; the trigger re-files + recalcs.
                        Button {
                            Task { await save(submit: false) }
                        } label: {
                            Text(saveButtonLabel("SAVE"))
                                .font(OPSStyle.Typography.button)
                        }
                        .opsPrimaryButtonStyle()
                    } else if expenseStatus == .rejected {
                        Button {
                            Task { await save(submit: true) }
                        } label: {
                            Text(saveButtonLabel("RESUBMIT"))
                                .font(OPSStyle.Typography.button)
                        }
                        .opsPrimaryButtonStyle()
                    } else {
                        Button {
                            Task { await save(submit: true) }
                        } label: {
                            Text(saveButtonLabel("ADD"))
                                .font(OPSStyle.Typography.button)
                        }
                        .opsPrimaryButtonStyle()
                    }
                }
                }
            }
        }
    }

    private func saveButtonLabel(_ normalLabel: String) -> String {
        saveInterruption?.retryLabel ?? normalLabel
    }

    // MARK: - Approval Banner

    @ViewBuilder
    private var approvalBanner: some View {
        switch expenseStatus {
        case .submitted:
            approvalBannerCard(
                icon: OPSStyle.Icons.clockFill,
                color: OPSStyle.Colors.primaryAccent,
                text: "AWAITING REVIEW"
            )
        case .approved:
            approvalBannerCard(
                icon: OPSStyle.Icons.checkmarkCircleFill,
                color: OPSStyle.Colors.successStatus,
                text: approvalText(prefix: "APPROVED", by: editing?.approvedBy)
            )
        case .rejected:
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                approvalBannerCard(
                    icon: OPSStyle.Icons.xmarkCircleFill,
                    color: OPSStyle.Colors.errorStatus,
                    text: approvalText(prefix: "REJECTED", by: editing?.rejectedBy)
                )
                if let reason = editing?.rejectionReason, !reason.isEmpty {
                    Text(reason)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                }
            }
        case .reimbursed:
            approvalBannerCard(
                icon: OPSStyle.Icons.banknoteFill,
                color: OPSStyle.Colors.successStatus,
                text: "REIMBURSED"
            )
        default:
            EmptyView()
        }
    }

    private func approvalText(prefix: String, by personId: String?) -> String {
        if let name = personName(personId) {
            return "\(prefix) BY \(name.uppercased())"
        }
        return prefix
    }

    // MARK: - Submitter Attribution

    /// "ADDED BY {NAME}" — surfaces who created the expense on every state
    /// (drafts included, where there's no approval banner). Hidden when the
    /// submitter can't be resolved locally.
    @ViewBuilder
    private var submitterLine: some View {
        if let name = personName(editing?.submittedBy) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.teamMember)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text("ADDED BY \(name.uppercased())")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing3)
        }
    }

    private func approvalBannerCard(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.md))
                .foregroundColor(color)
            Text(text)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(color)
            Spacer()
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(color.opacity(0.1))
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(color.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    // MARK: - OCR

    private func requestDismiss() {
        if saveInterruption != nil {
            showDiscardReceiptDialog = true
        } else {
            dismiss()
        }
    }

    /// Apply a completed scanner/library choice without destroying the current
    /// queue first. A replacement changes only the active receipt; a canceled
    /// picker never calls this method, so every queued image remains intact.
    private func applySelectedReceipts(_ images: [UIImage]) {
        guard let first = images.first else { return }

        if isReplacingReceipt {
            if receiptQueue.indices.contains(queueIndex) {
                receiptQueue[queueIndex] = first
            } else {
                receiptQueue = [first]
                queueIndex = 0
            }
        } else if editing != nil {
            receiptQueue = [first]
            queueIndex = 0
        } else {
            receiptQueue = images
            queueIndex = 0
        }

        isReplacingReceipt = false
        ocrUsed = false
        lastOCRResult = nil
        stagedReceipt = nil
        receiptUploadId = UUID().uuidString.lowercased()
        pendingAtomicCommand = nil
        saveInterruption = nil
    }

    private func runOCR() async {
        guard !receiptQueue.isEmpty, queueIndex < receiptQueue.count else { return }
        let image = receiptQueue[queueIndex]
        isScanning = true
        defer { isScanning = false }
        if let result = await viewModel.scanReceipt(image: image) {
            lastOCRResult = result
            expenseDescription = ExpenseOCRAutofill.description(
                current: expenseDescription,
                suggestion: result.descriptionSuggestion
            )
            if let merchant = result.merchantName, !merchant.isEmpty {
                merchantName = merchant
            }
            if let total = result.total {
                amount = String(format: "%.2f", total)
            }
            if let tax = result.taxAmount {
                taxAmount = String(format: "%.2f", tax)
            }
            if let date = result.date {
                expenseDate = date
            }
            ocrUsed = true
        }
    }

    // MARK: - Receipt gate

    /// A receipt is present when a new photo is queued or the existing expense
    /// already carries one.
    private var hasReceipt: Bool {
        !receiptQueue.isEmpty || persistedReceiptURL != nil
    }

    /// A submit needs either a receipt or an explicit no-receipt reason when the
    /// company requires a photo. Returns false and raises the fork (add photo /
    /// no receipt) when neither is present. Only gates submits — saving a draft
    /// or an in-place edit never blocks.
    private func receiptGatePassed(submit: Bool) -> Bool {
        let passed = ExpenseSubmissionGate.passes(
            submit: submit,
            policyResolved: viewModel.hasLoadedSettings,
            required: viewModel.submissionRequirements.requireReceiptPhoto,
            hasArtifact: hasReceipt,
            hasReason: noReceiptReason != nil
        )
        guard passed else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showReceiptRequiredDialog = true
            return false
        }
        return true
    }

    /// A project is present when at least one allocation resolves to a real
    /// project (a fresh pick or a hydrated existing allocation).
    private var hasProject: Bool {
        projectAllocations.contains { !$0.projectId.isEmpty }
    }

    /// A submit needs either a project or an explicit no-project reason when
    /// the company requires one. Same submit-only gate as receipts.
    private func projectGatePassed(submit: Bool) -> Bool {
        let passed = ExpenseSubmissionGate.passes(
            submit: submit,
            policyResolved: viewModel.hasLoadedSettings,
            required: viewModel.submissionRequirements.requireProjectAssignment,
            hasArtifact: hasProject,
            hasReason: noProjectReason != nil
        )
        guard passed else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showProjectRequiredDialog = true
            return false
        }
        return true
    }

    /// 'Add Project' from the fork — append a blank allocation and open the
    /// picker, mirroring the ADD PROJECT button.
    private func addProjectFromGate() {
        projectAllocations.append((projectId: "", percentage: "100"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            projectPickerIndex = projectAllocations.count - 1
            showProjectPicker = true
        }
    }

    // MARK: - Validation

    private func validate() -> Bool {
        var errors: [String] = []

        let amountValue = Double(amount) ?? 0
        func hasMoreThanTwoDecimalPlaces(_ value: String) -> Bool {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = trimmed.firstIndex(of: ".") else { return false }
            return trimmed.distance(from: trimmed.index(after: separator), to: trimmed.endIndex) > 2
        }

        if merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Merchant name is required")
        }

        if amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amountValue == 0 {
            errors.append("Amount is required")
        } else if amountValue < 0 {
            errors.append("Amount cannot be negative")
        } else if amountValue > 10_000 {
            errors.append("Amount exceeds $10,000 limit")
        } else if hasMoreThanTwoDecimalPlaces(amount) {
            errors.append("Amount can use up to 2 decimal places")
        }

        if let taxValue = Double(taxAmount), taxValue > 0, amountValue > 0 {
            let taxPercent = (taxValue / amountValue) * 100
            if taxPercent > 20 {
                errors.append("Tax exceeds 20% of amount")
            }
        }

        if let taxValue = Double(taxAmount), taxValue < 0 {
            errors.append("Tax cannot be negative")
        } else if !taxAmount.isEmpty && hasMoreThanTwoDecimalPlaces(taxAmount) {
            errors.append("Tax can use up to 2 decimal places")
        }

        let fiveYearsAgo = Calendar.current.date(byAdding: .year, value: -5, to: Date()) ?? Date()
        if expenseDate < fiveYearsAgo {
            errors.append("Date cannot be more than 5 years ago")
        }

        let endOfToday = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        if expenseDate >= endOfToday {
            errors.append("Date cannot be in the future")
        }

        // Allocation invariants (per bible 09: "Percentages must sum to 100% if
        // any allocations exist").
        let resolvedAllocations = projectAllocations.filter { !$0.projectId.isEmpty }
        if !resolvedAllocations.isEmpty {
            let total = resolvedAllocations.compactMap { Double($0.percentage) }.reduce(0, +)
            if !ExpenseAllocationPercentageTotal.isExactlyComplete(
                resolvedAllocations.map { $0.percentage }
            ) {
                errors.append("Project allocations must sum to 100% (currently \(Int(total))%)")
            }
            if resolvedAllocations.contains(where: { hasMoreThanTwoDecimalPlaces($0.percentage) }) {
                errors.append("Project percentages can use up to 2 decimal places")
            }
        }

        // per_job constraint: companies on per-job review allow exactly one
        // project per expense.
        if isPerJobMode && resolvedAllocations.count > 1 {
            errors.append("Per-job companies allow one project per expense")
        }

        validationErrors = errors
        return errors.isEmpty
    }

    // MARK: - Save

    /// Uploads the receipt, then commits the complete desired expense state in
    /// one idempotent database transaction. The caller may close the sheet only
    /// for `.complete`; an ambiguous response retains the exact command, staged
    /// URLs, and local image for a safe replay.
    private func performSave(submit: Bool) async -> ExpenseSaveOutcome {
        if saveInterruption?.kind == .closeRequired {
            dismiss()
            return .failed
        }
        guard !isSaving else { return .failed }
        isSaving = true
        defer { isSaving = false }

        saveInterruption = nil
        validationErrors = []

        if submit, !viewModel.hasLoadedSettings {
            guard await viewModel.ensureSettingsLoaded() else {
                return saveFailure("Couldn't verify company expense rules. Check your connection and try again.")
            }
        }

        guard validate() else { return .failed }
        guard receiptGatePassed(submit: submit) else { return .failed }
        guard projectGatePassed(submit: submit) else { return .failed }

        guard let companyId = dataController.currentUser?.companyId, !companyId.isEmpty,
              let userId = dataController.currentUser?.id, !userId.isEmpty else {
            return saveFailure("Couldn't verify your account. Close the form and try again.")
        }

        let amountValue = Double(amount) ?? 0
        let taxValue = taxAmount.isEmpty ? nil : Double(taxAmount)
        let dateString = SupabaseDate.formatDate(expenseDate)
        let descriptionValue = expenseDescription.isEmpty ? nil : expenseDescription
        let expenseId = editing?.id ?? workingExpenseId

        guard let receiptTarget = await resolveReceiptTarget(
            expenseId: expenseId,
            companyId: companyId
        ) else {
            return receiptRetryFailure()
        }

        let allocations = projectAllocations.compactMap { allocation -> ExpenseAtomicAllocationCommand? in
            guard !allocation.projectId.isEmpty, let percentage = Double(allocation.percentage) else { return nil }
            return ExpenseAtomicAllocationCommand(
                projectId: allocation.projectId,
                percentage: percentage,
                amount: nil
            )
        }

        let hasCommittedReceipt = receiptTarget.url != nil
        let missingReason = hasCommittedReceipt ? nil : noReceiptReason?.code
        let missingNote = (hasCommittedReceipt || noReceiptNote.isEmpty) ? nil : noReceiptNote
        let missingProjectReason = allocations.isEmpty ? noProjectReason?.code : nil
        let missingProjectNote = (!allocations.isEmpty || noProjectNote.isEmpty) ? nil : noProjectNote
        let ocrData = lastOCRResult?.rawDataDict ?? (receiptImage == nil ? editing?.ocrRawData : nil)
        let ocrConfidence = lastOCRResult.map { Double($0.overallConfidence) }
            ?? (receiptImage == nil ? editing?.ocrConfidence : nil)

        func makeCommand(requestId: String) -> ExpenseAtomicSaveCommand {
            ExpenseAtomicSaveCommand(
                requestId: requestId,
                expenseId: expenseId,
                companyId: companyId,
                submittedBy: userId,
                expectedStatus: editing?.status,
                expectedUpdatedAt: editing?.updatedAt,
                categoryId: selectedCategoryId,
                merchantName: merchantName.isEmpty ? nil : merchantName,
                description: descriptionValue,
                amount: amountValue,
                taxAmount: taxValue,
                currency: selectedCurrency.uppercased(),
                expenseDate: dateString,
                paymentMethod: paymentMethod.rawValue,
                receiptImageUrl: receiptTarget.url,
                receiptThumbnailUrl: receiptTarget.thumbnailUrl,
                receiptMissingReason: missingReason,
                receiptMissingNote: missingNote,
                projectMissingReason: missingProjectReason,
                projectMissingNote: missingProjectNote,
                ocrRawData: ocrData,
                ocrConfidence: ocrConfidence,
                allocations: allocations,
                submit: submit
            )
        }

        let candidate = makeCommand(
            requestId: pendingAtomicCommand?.requestId ?? UUID().uuidString.lowercased()
        )
        let command: ExpenseAtomicSaveCommand
        if let pendingAtomicCommand, pendingAtomicCommand.hasSameIntent(as: candidate) {
            command = pendingAtomicCommand
        } else {
            command = makeCommand(requestId: UUID().uuidString.lowercased())
        }
        pendingAtomicCommand = command

        var committed: ExpenseDTO?
        var atomicError: Error?
        do {
            committed = try await viewModel.saveExpenseAtomically(command)
        } catch {
            atomicError = error
            committed = nil
        }
        if committed == nil,
           let observed = await viewModel.fetchExpense(command.expenseId),
           ExpenseAtomicSaveReadback.matches(command: command, expense: observed) {
            committed = observed
        }

        guard let committed else {
            // A timeout or 5xx can race a committing server transaction. Keep
            // the exact request id and every uploaded object; replaying the
            // same command reads the private request ledger without duplicating
            // allocation or placement side effects.
            return saveConfirmationFailure(atomicError)
        }

        if let stagedReceipt, let previous = editing,
           committed.receiptImageUrl == stagedReceipt.url {
            deleteSupersededReceiptObjects(previous: previous, replacement: stagedReceipt)
        }
        pendingAtomicCommand = nil
        if committed.receiptImageUrl != nil {
            noReceiptReason = nil
            noReceiptNote = ""
        }
        if !(committed.allocations ?? []).isEmpty {
            noProjectReason = nil
            noProjectNote = ""
        }

        saveInterruption = nil
        if submit {
            ToastCenter.shared.present(Feedback.Expense.submitted)
        } else if editing == nil {
            ToastCenter.shared.present(Feedback.Expense.saved)
        } else {
            ToastCenter.shared.present(Feedback.Expense.changesSaved)
        }

        // Broadcast so every visible expense list (My Expenses, review
        // batches) refreshes. The global FAB no longer shares the list's view
        // model, so this is what keeps a create reflected without a pull.
        NotificationCenter.default.post(name: .opsExpensesDidChange, object: nil)
        return .complete
    }

    private func save(submit: Bool) async {
        let outcome = await performSave(submit: submit)
        if outcome.shouldDismiss { dismiss() }
    }

    /// Saves the current receipt as draft and advances to the next receipt in the queue.
    private func saveAndAdvance() async {
        let outcome = await performSave(submit: false)
        guard outcome == .complete else { return }

        // Advance to next receipt
        queueIndex += 1
        workingExpenseId = UUID().uuidString.lowercased()
        stagedReceipt = nil
        receiptUploadId = UUID().uuidString.lowercased()
        pendingAtomicCommand = nil
        saveInterruption = nil

        // Reset form fields for next receipt (keep allocations if prefilled)
        expenseDescription = ""
        merchantName = ""
        amount = ""
        taxAmount = ""
        expenseDate = Date()
        selectedCategoryId = nil
        ocrUsed = false
        lastOCRResult = nil
        validationErrors = []
        noReceiptReason = nil
        noReceiptNote = ""
        noProjectReason = nil
        noProjectNote = ""

        if prefilledProjectId == nil {
            projectAllocations = []
        }

        // Run OCR on next receipt
        Task { await runOCR() }
    }

    /// Resolve the exact receipt URLs for the atomic command. A selected image
    /// uploads to deterministic object names once; retries reuse both those
    /// objects and the same database request id. No database row is created or
    /// patched before the complete command is ready.
    private func resolveReceiptTarget(
        expenseId: String,
        companyId: String
    ) async -> ExpenseReceiptTarget? {
        guard let image = receiptImage else {
            return ExpenseReceiptTarget(
                url: editing?.receiptImageUrl,
                thumbnailUrl: editing?.receiptThumbnailUrl
            )
        }

        if stagedReceipt == nil {
            do {
                let uploaded = try await PresignedURLUploadService.shared.uploadExpenseReceipt(
                    image,
                    expenseId: expenseId,
                    companyId: companyId,
                    uploadId: receiptUploadId
                )
                stagedReceipt = StagedExpenseReceipt(url: uploaded.url, thumbnailUrl: uploaded.thumbnailUrl)
            } catch {
                print("[EXPENSE] Receipt upload failed: \(error.localizedDescription)")
                return nil
            }
        }

        guard let stagedReceipt else { return nil }
        return ExpenseReceiptTarget(url: stagedReceipt.url, thumbnailUrl: stagedReceipt.thumbnailUrl)
    }

    private func deleteSupersededReceiptObjects(
        previous: ExpenseDTO,
        replacement: StagedExpenseReceipt
    ) {
        deleteReceiptObjects(
            ExpenseReceiptCleanup.supersededURLs(
                previousImageURL: previous.receiptImageUrl,
                previousThumbnailURL: previous.receiptThumbnailUrl,
                replacementImageURL: replacement.url,
                replacementThumbnailURL: replacement.thumbnailUrl
            )
        )
    }

    private func deleteReceiptObjects(_ urls: [String]) {
        guard !urls.isEmpty else { return }
        Task {
            for url in urls {
                do {
                    try await PresignedURLUploadService.shared.deleteImage(url: url)
                } catch {
                    print("[EXPENSE] Superseded receipt cleanup failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func receiptRetryFailure() -> ExpenseSaveOutcome {
        saveInterruption = ExpenseSaveInterruption(
            kind: .receiptUpload,
            title: "// RECEIPT UPLOAD FAILED",
            message: "Receipt wasn't uploaded. Your changes are still here. Replace it or try again.",
            retryLabel: "RETRY RECEIPT"
        )
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        ToastCenter.shared.present(Feedback.Expense.receiptUploadFailed)
        return .receiptRetryRequired
    }

    private func saveConfirmationFailure(_ error: Error?) -> ExpenseSaveOutcome {
        if let error {
            print("[EXPENSE] Atomic save wasn't confirmed: \(error.localizedDescription)")
            let errorKind = UploadErrorClassifier.classify(error)
            if let rejection = ExpenseAtomicSaveFailurePolicy.rejection(for: errorKind) {
                // A permanent PostgREST/4xx rejection proves the transaction
                // rolled back. Release the immutable retry command, unlock the
                // fields, and clean only this attempt's staged objects. The
                // selected local image remains so the corrected save can
                // re-upload to a fresh user-owned deterministic key that the
                // asynchronous cleanup below cannot race and delete.
                if let stagedReceipt {
                    receiptUploadId = ExpenseReceiptRetryIdentity.rotatedUploadID(
                        after: receiptUploadId
                    )
                    deleteReceiptObjects(
                        ExpenseReceiptCleanup.supersededURLs(
                            previousImageURL: stagedReceipt.url,
                            previousThumbnailURL: stagedReceipt.thumbnailUrl,
                            replacementImageURL: nil,
                            replacementThumbnailURL: nil
                        )
                    )
                }
                stagedReceipt = nil
                pendingAtomicCommand = nil
                saveInterruption = ExpenseSaveInterruption(
                    kind: rejection.requiresClose ? .closeRequired : .saveRejected,
                    title: rejection.title,
                    message: rejection.message,
                    retryLabel: rejection.requiresClose ? "CLOSE FORM" : "TRY AGAIN"
                )
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                ToastCenter.shared.present(Feedback.Expense.saveRejected)
                return .failed
            }
        }
        saveInterruption = ExpenseSaveInterruption(
            kind: .commitConfirmation,
            title: "// SAVE NOT CONFIRMED",
            message: "Your receipt and changes are locked here for a safe retry. Try again or close to reload.",
            retryLabel: "RETRY SAVE"
        )
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        ToastCenter.shared.present(Feedback.Expense.saveNotConfirmed)
        return .failed
    }

    private func saveFailure(_ message: String) -> ExpenseSaveOutcome {
        validationErrors = [message]
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        return .failed
    }

}

extension Notification.Name {
    /// Posted after any expense is created / updated / submitted so visible
    /// expense lists (My Expenses, review batches) can refresh. The app-wide
    /// global FAB doesn't share their view models, so this notification is the
    /// refresh bridge.
    static let opsExpensesDidChange = Notification.Name("OPSExpensesDidChange")
}

// MARK: - Project Picker Sheet

private struct ExpenseProjectPickerSheet: View {
    let allProjects: [Project]
    let onSelect: (Project) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    /// Bug b79abf79 — the picker leads with the most recently touched job.
    private var filteredProjects: [Project] {
        let sorted = ProjectRecency.pickerOrdered(allProjects)
        if searchText.isEmpty { return sorted }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.effectiveClientName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        TextField("", text: $searchText)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .placeholder(when: searchText.isEmpty) {
                                Text("Search projects...")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.placeholderText)
                            }
                    }
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.surfaceInput)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing3)

                    // Project list
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredProjects), id: \.id) { (project: Project) in
                                Button {
                                    onSelect(project)
                                } label: {
                                    HStack(spacing: OPSStyle.Layout.spacing3) {
                                        // Color indicator
                                        Circle()
                                            .fill(project.statusColor)
                                            .frame(width: 10, height: 10)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(project.title)
                                                .font(OPSStyle.Typography.body)
                                                .foregroundColor(OPSStyle.Colors.primaryText)
                                                .lineLimit(1)
                                            if !project.effectiveClientName.isEmpty {
                                                Text(project.effectiveClientName)
                                                    .font(OPSStyle.Typography.smallCaption)
                                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    }
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                }
                                .buttonStyle(PlainButtonStyle())

                                Rectangle()
                                    .fill(OPSStyle.Colors.cardBorder)
                                    .frame(height: 1)
                                    .padding(.leading, OPSStyle.Layout.spacing3_5)
                            }
                        }
                        .padding(.top, OPSStyle.Layout.spacing2)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .principal) {
                    Text("SELECT PROJECT")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Category Picker Sheet

private struct ExpenseCategoryPickerSheet: View {
    let categories: [ExpenseCategoryDTO]
    let selectedId: String?
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        // "None" option
                        Button {
                            onSelect(nil)
                        } label: {
                            HStack(spacing: OPSStyle.Layout.spacing3) {
                                Text("None")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                Spacer()
                                if selectedId == nil {
                                    Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                                        .foregroundColor(OPSStyle.Colors.text)
                                }
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Rectangle()
                            .fill(OPSStyle.Colors.cardBorder)
                            .frame(height: 1)
                            .padding(.leading, OPSStyle.Layout.spacing3_5)

                        ForEach(categories, id: \.id) { cat in
                            Button {
                                onSelect(cat.id)
                            } label: {
                                HStack(spacing: OPSStyle.Layout.spacing3) {
                                    if let icon = cat.icon {
                                        Image(systemName: icon)
                                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                            .frame(width: 24)
                                    }
                                    Text(cat.name)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    Spacer()
                                    if selectedId == cat.id {
                                        Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                                            .foregroundColor(OPSStyle.Colors.text)
                                    }
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Rectangle()
                                .fill(OPSStyle.Colors.cardBorder)
                                .frame(height: 1)
                                .padding(.leading, OPSStyle.Layout.spacing3_5)
                        }
                    }
                    .padding(.top, OPSStyle.Layout.spacing2)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .principal) {
                    Text("SELECT CATEGORY")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Payment Method Picker Sheet

private struct ExpensePaymentPickerSheet: View {
    let selected: ExpensePaymentMethod
    let onSelect: (ExpensePaymentMethod) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(ExpensePaymentMethod.allCases, id: \.self) { method in
                            Button {
                                onSelect(method)
                            } label: {
                                HStack(spacing: OPSStyle.Layout.spacing3) {
                                    Image(systemName: paymentIcon(for: method))
                                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                        .frame(width: 24)
                                    Text(method.displayName)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    Spacer()
                                    if selected == method {
                                        Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                                            .foregroundColor(OPSStyle.Colors.text)
                                    }
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            }
                            .buttonStyle(PlainButtonStyle())

                            if method != ExpensePaymentMethod.allCases.last {
                                Rectangle()
                                    .fill(OPSStyle.Colors.cardBorder)
                                    .frame(height: 1)
                                    .padding(.leading, OPSStyle.Layout.spacing3_5)
                            }
                        }
                    }
                    .padding(.top, OPSStyle.Layout.spacing2)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .principal) {
                    Text("PAYMENT METHOD")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func paymentIcon(for method: ExpensePaymentMethod) -> String {
        switch method {
        case .cash: return "banknote"
        case .personalCard: return "creditcard"
        case .companyCard: return "creditcard.fill"
        }
    }
}

// MARK: - Document Scanner

private struct DocumentScannerView: UIViewControllerRepresentable {
    @Binding var scannedImages: [UIImage]
    var onComplete: () -> Void
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView

        init(_ parent: DocumentScannerView) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            DispatchQueue.main.async {
                self.parent.scannedImages = images
                self.parent.onComplete()
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.presentationMode.wrappedValue.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Currency Picker Sheet

private struct ExpenseCurrencyPickerSheet: View {
    let selected: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    /// A short curated head followed by the full ISO 4217 list. Trades-first:
    /// the currencies most OPS field crews encounter (USD/CAD primarily) sit
    /// at the top so they're tappable without a search.
    private static let prioritized: [String] = ["USD", "CAD", "MXN", "EUR", "GBP", "AUD"]

    private var allCodes: [String] {
        // Foundation's known ISO codes, deduped + sorted, with prioritized
        // entries lifted to the top.
        let known = Set(Locale.commonISOCurrencyCodes.map { $0.uppercased() })
        let priority = Self.prioritized.filter { known.contains($0) }
        let rest = known.subtracting(priority).sorted()
        return priority + rest
    }

    private var filtered: [String] {
        let q = searchText.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty else { return allCodes }
        return allCodes.filter { code in
            code.contains(q) || (currencyName(for: code) ?? "").uppercased().contains(q)
        }
    }

    private func currencyName(for code: String) -> String? {
        Locale.current.localizedString(forCurrencyCode: code)
    }

    private func currencySymbol(for code: String) -> String {
        BooksFormat.symbol(for: code)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        TextField("", text: $searchText)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.characters)
                            .placeholder(when: searchText.isEmpty) {
                                Text("Search currency...")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.placeholderText)
                            }
                    }
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.surfaceInput)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing3)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered, id: \.self) { code in
                                Button { onSelect(code) } label: {
                                    HStack(spacing: OPSStyle.Layout.spacing3) {
                                        Text(currencySymbol(for: code))
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                            .frame(width: 36, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(code)
                                                .font(OPSStyle.Typography.bodyBold)
                                                .foregroundColor(OPSStyle.Colors.primaryText)
                                            if let name = currencyName(for: code) {
                                                Text(name)
                                                    .font(OPSStyle.Typography.smallCaption)
                                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        if selected.uppercased() == code {
                                            Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                                                .font(.system(size: OPSStyle.Layout.IconSize.md))
                                                .foregroundColor(OPSStyle.Colors.text)
                                        }
                                    }
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                }
                                .buttonStyle(PlainButtonStyle())

                                Rectangle()
                                    .fill(OPSStyle.Colors.cardBorder)
                                    .frame(height: 1)
                                    .padding(.leading, OPSStyle.Layout.spacing3_5)
                            }
                        }
                        .padding(.top, OPSStyle.Layout.spacing2)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .principal) {
                    Text("CURRENCY")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - No-Receipt Reason Sheet

/// Escape hatch for require_receipt_photo — the crew picks why a receipt is
/// missing (and optionally adds a note) so the line still files and the office
/// sees the reason instead of an unexplained blank. Confirm submits the expense.
private struct NoReceiptReasonSheet: View {
    let onSubmit: (NoReceiptReason, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: NoReceiptReason?
    @State private var note: String
    @FocusState private var noteFocused: Bool

    init(selected: NoReceiptReason?, note: String, onSubmit: @escaping (NoReceiptReason, String) -> Void) {
        self.onSubmit = onSubmit
        self._selected = State(initialValue: selected)
        self._note = State(initialValue: note)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        Text("Why is there no receipt?")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.top, OPSStyle.Layout.spacing3)

                        VStack(spacing: 0) {
                            ForEach(Array(NoReceiptReason.allCases.enumerated()), id: \.element.id) { index, reason in
                                if index > 0 {
                                    Rectangle()
                                        .fill(OPSStyle.Colors.cardBorder)
                                        .frame(height: 1)
                                        .padding(.leading, OPSStyle.Layout.spacing3_5)
                                }
                                Button {
                                    selected = reason
                                } label: {
                                    HStack(spacing: OPSStyle.Layout.spacing3) {
                                        Text(reason.label)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                        Spacer()
                                        if selected == reason {
                                            Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                                                .font(.system(size: OPSStyle.Layout.IconSize.md))
                                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                        }
                                    }
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                    .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("NOTE")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            TextField("", text: $note, axis: .vertical)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .focused($noteFocused)
                                .lineLimit(1...3)
                                .placeholder(when: note.isEmpty) {
                                    Text("Add a note (optional)")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.placeholderText)
                                }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    }
                    .padding(.top, OPSStyle.Layout.spacing2)
                    .padding(.bottom, 120)
                }
                .scrollDismissesKeyboard(.interactively)

                stickyConfirm
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .principal) {
                    Text("NO RECEIPT")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var stickyConfirm: some View {
        OPSFloatingButtonBar {
            Button {
                guard let selected else { return }
                onSubmit(selected, note)
            } label: {
                Text("SUBMIT WITHOUT RECEIPT")
                    .font(OPSStyle.Typography.button)
            }
            .opsPrimaryButtonStyle()
            .disabled(selected == nil)
            .opacity(selected == nil ? 0.4 : 1)
        }
    }
}

// MARK: - No-Project Reason Sheet

/// Escape hatch for require_project_assignment — the crew picks why an expense
/// has no project (overhead, shop supplies) so the line still files and the
/// office sees the reason. Confirm submits the expense. Mirrors
/// NoReceiptReasonSheet.
private struct NoProjectReasonSheet: View {
    let onSubmit: (NoProjectReason, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: NoProjectReason?
    @State private var note: String
    @FocusState private var noteFocused: Bool

    init(selected: NoProjectReason?, note: String, onSubmit: @escaping (NoProjectReason, String) -> Void) {
        self.onSubmit = onSubmit
        self._selected = State(initialValue: selected)
        self._note = State(initialValue: note)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        Text("Why is there no project?")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.top, OPSStyle.Layout.spacing3)

                        VStack(spacing: 0) {
                            ForEach(Array(NoProjectReason.allCases.enumerated()), id: \.element.id) { index, reason in
                                if index > 0 {
                                    Rectangle()
                                        .fill(OPSStyle.Colors.cardBorder)
                                        .frame(height: 1)
                                        .padding(.leading, OPSStyle.Layout.spacing3_5)
                                }
                                Button {
                                    selected = reason
                                } label: {
                                    HStack(spacing: OPSStyle.Layout.spacing3) {
                                        Text(reason.label)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                        Spacer()
                                        if selected == reason {
                                            Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                                                .font(.system(size: OPSStyle.Layout.IconSize.md))
                                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                        }
                                    }
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                    .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("NOTE")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            TextField("", text: $note, axis: .vertical)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .focused($noteFocused)
                                .lineLimit(1...3)
                                .placeholder(when: note.isEmpty) {
                                    Text("Add a note (optional)")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.placeholderText)
                                }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    }
                    .padding(.top, OPSStyle.Layout.spacing2)
                    .padding(.bottom, 120)
                }
                .scrollDismissesKeyboard(.interactively)

                stickyConfirm
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .principal) {
                    Text("NO PROJECT")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var stickyConfirm: some View {
        OPSFloatingButtonBar {
            Button {
                guard let selected else { return }
                onSubmit(selected, note)
            } label: {
                Text("SUBMIT WITHOUT PROJECT")
                    .font(OPSStyle.Typography.button)
            }
            .opsPrimaryButtonStyle()
            .disabled(selected == nil)
            .opacity(selected == nil ? 0.4 : 1)
        }
    }
}
