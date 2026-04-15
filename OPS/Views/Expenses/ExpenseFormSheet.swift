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
    @State private var expenseDate = Date()
    @State private var selectedCategoryId: String? = nil
    @State private var paymentMethod: ExpensePaymentMethod = .personalCard
    @State private var expenseDescription = ""
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var showDocumentScanner = false
    @State private var showReceiptSourceSheet = false
    @State private var isScanning = false
    @State private var ocrUsed = false
    @State private var lastOCRResult: OCRResult? = nil
    @State private var projectAllocations: [(projectId: String, percentage: String)] = []
    @State private var isSaving = false
    @State private var validationErrors: [String] = []
    @State private var isViewMode = false

    // Project picker sheet state
    @State private var showProjectPicker = false
    @State private var projectPickerIndex: Int = 0

    // Multi-receipt queue state
    @State private var receiptQueue: [UIImage] = []
    @State private var queueIndex: Int = 0

    // Section expansion state (always expanded, non-collapsible)
    @State private var isDetailsExpanded = true
    @State private var isAllocationExpanded = true

    // Custom picker sheet state
    @State private var showCategoryPicker = false
    @State private var showPaymentPicker = false

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

    private var receiptImage: UIImage? {
        guard !receiptQueue.isEmpty, queueIndex < receiptQueue.count else { return nil }
        return receiptQueue[queueIndex]
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        // APPROVAL STATUS BANNER
                        if editing != nil {
                            approvalBanner
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
                    .disabled(isViewMode)
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
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .principal) {
                    Text(editing == nil ? "NEW EXPENSE" : (isViewMode ? "EXPENSE" : "EDIT EXPENSE"))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .sheet(isPresented: $showDocumentScanner) {
                DocumentScannerView(scannedImages: $receiptQueue) {
                    queueIndex = 0
                    Task { await runOCR() }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(
                    images: $selectedImages,
                    allowsEditing: false,
                    sourceType: .photoLibrary,
                    selectionLimit: 10,
                    onSelectionComplete: {
                        receiptQueue = selectedImages
                        selectedImages = []
                        queueIndex = 0
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
            .confirmationDialog("ADD RECEIPT", isPresented: $showReceiptSourceSheet, titleVisibility: .visible) {
                Button("Scan Receipt") { showDocumentScanner = true }
                Button("Choose from Library") { showImagePicker = true }
                Button("Cancel", role: .cancel) { }
            }
            .onAppear {
                // Load categories if not already loaded
                if viewModel.categories.isEmpty {
                    Task { await viewModel.loadCategories() }
                }

                if let exp = editing {
                    isViewMode = true
                    merchantName = exp.merchantName ?? ""
                    amount = exp.amount > 0 ? String(format: "%.2f", exp.amount) : ""
                    taxAmount = exp.taxAmount.map { String(format: "%.2f", $0) } ?? ""
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
                }
                if let pid = prefilledProjectId, projectAllocations.isEmpty {
                    projectAllocations = [(projectId: pid, percentage: "100")]
                }
            }
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
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            } else if let image = receiptImage {
                // Queue progress indicator
                if receiptQueue.count > 1 {
                    Text("RECEIPT \(queueIndex + 1) OF \(receiptQueue.count)")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                }

                // Thumbnail with retake
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipped()
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )

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
                            receiptQueue = []
                            queueIndex = 0
                            ocrUsed = false
                            showReceiptSourceSheet = true
                        } label: {
                            Text("RETAKE PHOTO")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }

                        if !ocrUsed {
                            Button {
                                Task { await runOCR() }
                            } label: {
                                Text("RETRY SCAN")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
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
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            } else {
                // Add receipt button
                Button {
                    showReceiptSourceSheet = true
                } label: {
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: OPSStyle.Icons.receipt)
                            .font(.system(size: OPSStyle.Layout.IconSize.xl))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Text("ADD RECEIPT PHOTO")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        if viewModel.settings?.requireReceiptPhoto == true {
                            Text("REQUIRED FOR SUBMISSION")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }
        }
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
                TextField("", text: $merchantName)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .merchant)
                    .placeholder(when: merchantName.isEmpty) {
                        Text("Business name")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.placeholderText)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
            }

            dividerLine

            // Amount
            detailRow(label: "AMOUNT") {
                HStack(spacing: 4) {
                    Text("$")
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

            // Tax
            detailRow(label: "TAX") {
                HStack(spacing: 4) {
                    Text("$")
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
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }

            HStack(spacing: OPSStyle.Layout.spacing3) {
                if isSaving {
                    ProgressView()
                        .tint(OPSStyle.Colors.primaryAccent)
                        .frame(maxWidth: .infinity)
                } else if editing == nil {
                    // NEW expense
                    if hasMoreReceipts {
                        Button {
                            Task { await saveAndAdvance() }
                        } label: {
                            Text("SAVE & NEXT (\(remainingReceiptCount) LEFT)")
                                .font(OPSStyle.Typography.button)
                        }
                        .opsPrimaryButtonStyle()
                    } else {
                        Button {
                            Task { await save(submit: false) }
                        } label: {
                            Text("SAVE DRAFT")
                                .font(OPSStyle.Typography.button)
                        }
                        .opsSecondaryButtonStyle()

                        Button {
                            Task { await save(submit: true) }
                        } label: {
                            Text("SUBMIT")
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
                    // View mode for draft/submitted/rejected — EDIT button + contextual action
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isViewMode = false }
                    } label: {
                        Text("EDIT")
                            .font(OPSStyle.Typography.button)
                    }
                    .opsSecondaryButtonStyle()

                    if expenseStatus == .draft {
                        Button {
                            Task { await save(submit: true) }
                        } label: {
                            Text("SUBMIT")
                                .font(OPSStyle.Typography.button)
                        }
                        .opsPrimaryButtonStyle()
                    } else if expenseStatus == .rejected {
                        Button {
                            Task { await save(submit: true) }
                        } label: {
                            Text("RESUBMIT")
                                .font(OPSStyle.Typography.button)
                        }
                        .opsPrimaryButtonStyle()
                    }
                } else {
                    // Edit mode for draft/submitted/rejected
                    if expenseStatus == .rejected {
                        Button {
                            Task { await save(submit: false) }
                        } label: {
                            Text("SAVE")
                                .font(OPSStyle.Typography.button)
                        }
                        .opsSecondaryButtonStyle()

                        Button {
                            Task { await save(submit: true) }
                        } label: {
                            Text("RESUBMIT")
                                .font(OPSStyle.Typography.button)
                        }
                        .opsPrimaryButtonStyle()
                    } else if expenseStatus == .submitted {
                        Button {
                            Task { await save(submit: false) }
                        } label: {
                            Text("SAVE")
                                .font(OPSStyle.Typography.button)
                        }
                        .opsPrimaryButtonStyle()
                    } else {
                        Button {
                            Task { await save(submit: false) }
                        } label: {
                            Text("SAVE DRAFT")
                                .font(OPSStyle.Typography.button)
                        }
                        .opsSecondaryButtonStyle()

                        Button {
                            Task { await save(submit: true) }
                        } label: {
                            Text("SUBMIT")
                                .font(OPSStyle.Typography.button)
                        }
                        .opsPrimaryButtonStyle()
                    }
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.vertical, OPSStyle.Layout.spacing3)
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

    private func approvalText(prefix: String, by person: String?) -> String {
        if let person = person, !person.isEmpty {
            return "\(prefix) BY \(person.uppercased())"
        }
        return prefix
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

    private func runOCR() async {
        guard !receiptQueue.isEmpty, queueIndex < receiptQueue.count else { return }
        let image = receiptQueue[queueIndex]
        isScanning = true
        defer { isScanning = false }
        if let result = await viewModel.scanReceipt(image: image) {
            lastOCRResult = result
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

    // MARK: - Validation

    private func validate() -> Bool {
        var errors: [String] = []

        let amountValue = Double(amount) ?? 0

        if merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Merchant name is required")
        }

        if amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amountValue == 0 {
            errors.append("Amount is required")
        } else if amountValue < 0 {
            errors.append("Amount cannot be negative")
        } else if amountValue > 10_000 {
            errors.append("Amount exceeds $10,000 limit")
        }

        if let taxValue = Double(taxAmount), taxValue > 0, amountValue > 0 {
            let taxPercent = (taxValue / amountValue) * 100
            if taxPercent > 20 {
                errors.append("Tax exceeds 20% of amount")
            }
        }

        if let taxValue = Double(taxAmount), taxValue < 0 {
            errors.append("Tax cannot be negative")
        }

        let fiveYearsAgo = Calendar.current.date(byAdding: .year, value: -5, to: Date()) ?? Date()
        if expenseDate < fiveYearsAgo {
            errors.append("Date cannot be more than 5 years ago")
        }

        let endOfToday = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        if expenseDate >= endOfToday {
            errors.append("Date cannot be in the future")
        }

        validationErrors = errors
        return errors.isEmpty
    }

    // MARK: - Save

    /// Performs the save without dismissing. Returns true on success.
    private func performSave(submit: Bool) async -> Bool {
        guard validate() else { return false }
        isSaving = true
        defer { isSaving = false }

        let companyId = dataController.currentUser?.companyId ?? ""
        let userId = dataController.currentUser?.id ?? ""
        let amountValue = Double(amount) ?? 0
        let taxValue = taxAmount.isEmpty ? nil : Double(taxAmount)
        let dateString = ISO8601DateFormatter().string(from: expenseDate)
        let descriptionValue = expenseDescription.isEmpty ? nil : expenseDescription

        let ocrData = lastOCRResult?.rawDataDict
        let ocrConfidence = lastOCRResult != nil ? Double(lastOCRResult!.overallConfidence) : nil

        if let exp = editing {
            // If editing a submitted expense, reset status to draft and clear batch
            let wasSubmitted = ExpenseStatus(rawValue: exp.status) == .submitted
            let fields = UpdateExpenseDTO(
                categoryId: selectedCategoryId,
                merchantName: merchantName.isEmpty ? nil : merchantName,
                description: descriptionValue,
                amount: amountValue,
                taxAmount: taxValue,
                expenseDate: dateString,
                paymentMethod: paymentMethod.rawValue,
                status: wasSubmitted ? ExpenseStatus.draft.rawValue : nil
            )
            await viewModel.updateExpense(exp.id, fields: fields)

            // Reset batch assignment separately if the expense was submitted
            if wasSubmitted {
                await viewModel.resetExpenseBatch(exp.id)
            }

            // Upload receipt if new image captured (not already uploaded)
            if viewModel.error == nil, !receiptQueue.isEmpty, exp.receiptImageUrl == nil {
                if queueIndex < receiptQueue.count {
                    let image = receiptQueue[queueIndex]
                    do {
                        let urls = try await S3UploadService.shared.uploadExpenseReceipt(
                            image, expenseId: exp.id, companyId: companyId
                        )
                        let imageFields = UpdateExpenseDTO(
                            receiptImageUrl: urls.url,
                            receiptThumbnailUrl: urls.thumbnailUrl
                        )
                        await viewModel.updateExpense(exp.id, fields: imageFields)
                    } catch {
                        print("[EXPENSE] Receipt upload failed: \(error.localizedDescription)")
                    }
                }
            }

            // Update allocations
            if viewModel.error == nil {
                let allocs = projectAllocations.compactMap { alloc -> CreateExpenseAllocationDTO? in
                    guard !alloc.projectId.isEmpty, let pct = Double(alloc.percentage) else { return nil }
                    return CreateExpenseAllocationDTO(
                        expenseId: exp.id,
                        projectId: alloc.projectId,
                        percentage: pct,
                        amount: nil
                    )
                }
                if !allocs.isEmpty {
                    await viewModel.setAllocations(exp.id, allocations: allocs)
                }
            }

            if submit && viewModel.error == nil {
                await viewModel.submitExpense(exp.id)
            }
        } else {
            let created = await viewModel.createExpense(
                companyId: companyId,
                submittedBy: userId,
                categoryId: selectedCategoryId,
                merchantName: merchantName.isEmpty ? nil : merchantName,
                description: descriptionValue,
                amount: amountValue,
                taxAmount: taxValue,
                expenseDate: dateString,
                paymentMethod: paymentMethod.rawValue,
                receiptImageUrl: nil,
                receiptThumbnailUrl: nil,
                ocrRawData: ocrData,
                ocrConfidence: ocrConfidence
            )

            if let created = created {
                // Upload receipt image now that we have the expense ID
                if !receiptQueue.isEmpty, queueIndex < receiptQueue.count {
                    let image = receiptQueue[queueIndex]
                    do {
                        let urls = try await S3UploadService.shared.uploadExpenseReceipt(
                            image, expenseId: created.id, companyId: companyId
                        )
                        let imageFields = UpdateExpenseDTO(
                            receiptImageUrl: urls.url,
                            receiptThumbnailUrl: urls.thumbnailUrl
                        )
                        await viewModel.updateExpense(created.id, fields: imageFields)
                    } catch {
                        print("[EXPENSE] Receipt upload failed: \(error.localizedDescription)")
                    }
                }

                let allocs = projectAllocations.compactMap { alloc -> CreateExpenseAllocationDTO? in
                    guard !alloc.projectId.isEmpty, let pct = Double(alloc.percentage) else { return nil }
                    return CreateExpenseAllocationDTO(
                        expenseId: created.id,
                        projectId: alloc.projectId,
                        percentage: pct,
                        amount: nil
                    )
                }
                if !allocs.isEmpty {
                    await viewModel.setAllocations(created.id, allocations: allocs)
                }

                if submit && viewModel.error == nil {
                    await viewModel.submitExpense(created.id)
                }
            }
        }

        return viewModel.error == nil
    }

    private func save(submit: Bool) async {
        let success = await performSave(submit: submit)
        if success { dismiss() }
    }

    /// Saves the current receipt as draft and advances to the next receipt in the queue.
    private func saveAndAdvance() async {
        let success = await performSave(submit: false)
        guard success else { return }

        // Advance to next receipt
        queueIndex += 1

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

        if prefilledProjectId == nil {
            projectAllocations = []
        }

        // Run OCR on next receipt
        Task { await runOCR() }
    }
}

// MARK: - Project Picker Sheet

private struct ExpenseProjectPickerSheet: View {
    let allProjects: [Project]
    let onSelect: (Project) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredProjects: [Project] {
        let sorted = allProjects.sorted { $0.title < $1.title }
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
                    .padding(.vertical, 12)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
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
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
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
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
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
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
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
