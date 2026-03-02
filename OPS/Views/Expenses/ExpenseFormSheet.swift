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
    @State private var notes = ""
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var showDocumentScanner = false
    @State private var showReceiptSourceSheet = false
    @State private var isScanning = false
    @State private var ocrUsed = false
    @State private var projectAllocations: [(projectId: String, percentage: String)] = []
    @State private var isSaving = false
    @State private var validationErrors: [String] = []
    @State private var isViewMode = false

    // Project auto-suggest state
    @State private var projectSearchTexts: [Int: String] = [:]
    @State private var activeSearchIndex: Int? = nil

    // Multi-receipt queue state
    @State private var receiptQueue: [UIImage] = []
    @State private var queueIndex: Int = 0

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

    private func filteredProjects(for searchText: String) -> ArraySlice<Project> {
        let sorted = allProjects.sorted { $0.title < $1.title }
        if searchText.isEmpty { return sorted.prefix(5) }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.effectiveClientName.localizedCaseInsensitiveContains(searchText)
        }.prefix(5)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        // APPROVAL STATUS BANNER
                        if editing != nil {
                            approvalBanner
                        }

                        // RECEIPT PHOTO
                        receiptSection
                            .padding(.top, editing != nil ? 0 : OPSStyle.Layout.spacing3)

                        // DETAILS
                        sectionHeader("DETAILS", icon: "list.bullet")
                        detailsCard

                        // PROJECT ALLOCATION
                        sectionHeader("PROJECT ALLOCATION", icon: OPSStyle.Icons.folderFill)
                        allocationCard

                        // NOTES
                        sectionHeader("NOTES", icon: OPSStyle.Icons.notes)
                        notesCard
                    }
                    .disabled(isViewMode)
                    .padding(.bottom, 100)
                }

                stickyFooter
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .principal) {
                    Text(editing == nil ? "NEW EXPENSE" : (isViewMode ? "EXPENSE" : "EDIT EXPENSE"))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
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
            .confirmationDialog("ADD RECEIPT", isPresented: $showReceiptSourceSheet, titleVisibility: .visible) {
                Button("Scan Receipt") { showDocumentScanner = true }
                Button("Choose from Library") { showImagePicker = true }
                Button("Cancel", role: .cancel) { }
            }
            .onAppear {
                if let exp = editing {
                    isViewMode = true
                    merchantName = exp.merchantName ?? ""
                    amount = exp.amount > 0 ? String(format: "%.2f", exp.amount) : ""
                    taxAmount = exp.taxAmount.map { String(format: "%.2f", $0) } ?? ""
                    selectedCategoryId = exp.categoryId
                    paymentMethod = ExpensePaymentMethod(rawValue: exp.paymentMethod ?? "") ?? .personalCard
                    notes = exp.description ?? ""
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
                    if let project = allProjects.first(where: { $0.id == pid }) {
                        projectSearchTexts[0] = project.title
                    }
                }
            }
        }
    }

    // MARK: - Receipt Section

    private var receiptSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            sectionHeader("RECEIPT PHOTO", icon: OPSStyle.Icons.receipt)

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
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            } else if let image = receiptImage {
                // Queue progress indicator
                if receiptQueue.count > 1 {
                    Text("RECEIPT \(queueIndex + 1) OF \(receiptQueue.count)")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
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
                .padding(.horizontal, OPSStyle.Layout.spacing3)

                if !isViewMode {
                    HStack(spacing: OPSStyle.Layout.spacing3) {
                        Button {
                            receiptQueue = []
                            queueIndex = 0
                            ocrUsed = false
                            showReceiptSourceSheet = true
                        } label: {
                            Text("RETAKE PHOTO")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }

                        if !ocrUsed {
                            Button {
                                Task { await runOCR() }
                            } label: {
                                Text("RETRY SCAN")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
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
                .padding(.horizontal, OPSStyle.Layout.spacing3)
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
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
        }
    }

    // MARK: - Details Card

    private var detailsCard: some View {
        VStack(spacing: 0) {
            formField("MERCHANT", text: $merchantName, placeholder: "Business name")
            dividerLine
            currencyField("AMOUNT", text: $amount)
            dividerLine
            currencyField("TAX", text: $taxAmount)
            dividerLine
            datePickerRow
            dividerLine
            categoryPickerRow
            dividerLine
            paymentMethodRow
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private var dividerLine: some View {
        Divider().background(OPSStyle.Colors.cardBorder)
    }

    private func formField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 120, alignment: .leading)
            TextField(placeholder, text: text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
    }

    private func currencyField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 120, alignment: .leading)
            TextField("0.00", text: text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
    }

    private var datePickerRow: some View {
        HStack {
            Text("DATE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 120, alignment: .leading)
            Spacer()
            DatePicker("", selection: $expenseDate, displayedComponents: .date)
                .labelsHidden()
                .colorScheme(.dark)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
    }

    private var categoryPickerRow: some View {
        HStack {
            Text("CATEGORY")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 120, alignment: .leading)
            Spacer()
            Picker("", selection: $selectedCategoryId) {
                Text("None").tag(String?.none)
                ForEach(viewModel.categories) { cat in
                    HStack {
                        if let icon = cat.icon {
                            Image(systemName: icon)
                        }
                        Text(cat.name)
                    }
                    .tag(Optional(cat.id))
                }
            }
            .pickerStyle(.menu)
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .accentColor(OPSStyle.Colors.primaryAccent)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
    }

    private var paymentMethodRow: some View {
        HStack {
            Text("PAYMENT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 120, alignment: .leading)
            Spacer()
            Picker("", selection: $paymentMethod) {
                ForEach(ExpensePaymentMethod.allCases, id: \.self) { method in
                    Text(method.displayName).tag(method)
                }
            }
            .pickerStyle(.menu)
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .accentColor(OPSStyle.Colors.primaryAccent)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
    }

    // MARK: - Project Allocation Card

    private var allocationCard: some View {
        VStack(spacing: 0) {
            ForEach(projectAllocations.indices, id: \.self) { index in
                VStack(spacing: 0) {
                    allocationRow(index: index)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)

                    // Suggestions dropdown when this row is active
                    if activeSearchIndex == index {
                        let searchText = projectSearchTexts[index] ?? ""
                        let results = filteredProjects(for: searchText)
                        if !results.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { i, project in
                                    Button {
                                        projectAllocations[index].projectId = project.id
                                        projectSearchTexts[index] = project.title
                                        activeSearchIndex = nil
                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(project.title)
                                                    .font(OPSStyle.Typography.bodyBold)
                                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                                if !project.effectiveClientName.isEmpty {
                                                    Text(project.effectiveClientName)
                                                        .font(OPSStyle.Typography.caption)
                                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                                }
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                                        .padding(.vertical, 12)
                                        .background(OPSStyle.Colors.cardBackgroundDark)
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    if i < results.count - 1 {
                                        Divider().background(OPSStyle.Colors.cardBorder)
                                    }
                                }
                            }
                            .background(OPSStyle.Colors.cardBackgroundDark)
                        }
                    }
                }

                if index < projectAllocations.count - 1 {
                    Divider().background(OPSStyle.Colors.cardBorder)
                }
            }

            if !isViewMode {
                if !projectAllocations.isEmpty {
                    Divider().background(OPSStyle.Colors.cardBorder)
                }

                Button {
                    projectAllocations.append((projectId: "", percentage: "100"))
                } label: {
                    HStack {
                        Image(systemName: OPSStyle.Icons.plus)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        Text("ADD PROJECT")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        Spacer()
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    @ViewBuilder
    private func allocationRow(index: Int) -> some View {
        let hasProject = !projectAllocations[index].projectId.isEmpty
        let isEditing = activeSearchIndex == index

        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: OPSStyle.Icons.folderFill)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if hasProject && !isEditing {
                // Show selected project name
                let project = allProjects.first(where: { $0.id == projectAllocations[index].projectId })
                VStack(alignment: .leading, spacing: 2) {
                    Text(project?.title ?? projectAllocations[index].projectId)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    if let clientName = project?.effectiveClientName, !clientName.isEmpty {
                        Text(clientName)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .onTapGesture {
                    projectSearchTexts[index] = ""
                    activeSearchIndex = index
                }
            } else {
                // Show search field
                TextField("Search project", text: Binding(
                    get: { projectSearchTexts[index] ?? "" },
                    set: { projectSearchTexts[index] = $0 }
                ), onEditingChanged: { editing in
                    if editing {
                        activeSearchIndex = index
                    }
                })
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.words)
            }

            Spacer()

            TextField("100", text: allocationPercentBinding(index: index))
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
                .frame(width: 50)
            Text("%")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            if !isViewMode {
                Button {
                    projectAllocations.remove(at: index)
                    // Rekey search texts so indices stay in sync with projectAllocations
                    var rekeyed: [Int: String] = [:]
                    for (key, value) in projectSearchTexts {
                        if key < index { rekeyed[key] = value }
                        else if key > index { rekeyed[key - 1] = value }
                    }
                    projectSearchTexts = rekeyed
                    if activeSearchIndex == index { activeSearchIndex = nil }
                    else if let active = activeSearchIndex, active > index { activeSearchIndex = active - 1 }
                } label: {
                    Image(systemName: OPSStyle.Icons.xmark)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
        }
    }

    private func allocationPercentBinding(index: Int) -> Binding<String> {
        Binding(
            get: { projectAllocations[index].percentage },
            set: { projectAllocations[index].percentage = $0 }
        )
    }

    // MARK: - Notes Card

    private var notesCard: some View {
        TextEditor(text: $notes)
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 100)
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
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
                    // NEW expense — same as before
                    if hasMoreReceipts {
                        Button("SAVE & NEXT (\(remainingReceiptCount) LEFT)") {
                            Task { await saveAndAdvance() }
                        }
                        .opsPrimaryButtonStyle()
                    } else {
                        Button("SAVE DRAFT") {
                            Task { await save(submit: false) }
                        }
                        .opsSecondaryButtonStyle()

                        Button("SUBMIT EXPENSE") {
                            Task { await save(submit: true) }
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
                    Button("EDIT") {
                        withAnimation(.easeInOut(duration: 0.2)) { isViewMode = false }
                    }
                    .opsSecondaryButtonStyle()

                    if expenseStatus == .draft {
                        Button("SUBMIT") {
                            Task { await save(submit: true) }
                        }
                        .opsPrimaryButtonStyle()
                    } else if expenseStatus == .rejected {
                        Button("RESUBMIT") {
                            Task { await save(submit: true) }
                        }
                        .opsPrimaryButtonStyle()
                    }
                } else {
                    // Edit mode for draft/submitted/rejected
                    if expenseStatus == .rejected {
                        Button("SAVE") {
                            Task { await save(submit: false) }
                        }
                        .opsSecondaryButtonStyle()
                        Button("RESUBMIT") {
                            Task { await save(submit: true) }
                        }
                        .opsPrimaryButtonStyle()
                    } else if expenseStatus == .submitted {
                        // Submitted — save edits, keep submitted status
                        Button("SAVE") {
                            Task { await save(submit: false) }
                        }
                        .opsPrimaryButtonStyle()
                    } else {
                        // Draft — save as draft or submit
                        Button("SAVE DRAFT") {
                            Task { await save(submit: false) }
                        }
                        .opsSecondaryButtonStyle()
                        Button("SUBMIT") {
                            Task { await save(submit: true) }
                        }
                        .opsPrimaryButtonStyle()
                    }
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.background)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
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
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
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
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    // MARK: - OCR

    private func runOCR() async {
        guard !receiptQueue.isEmpty, queueIndex < receiptQueue.count else { return }
        let image = receiptQueue[queueIndex]
        isScanning = true
        defer { isScanning = false }
        if let result = await viewModel.scanReceipt(image: image) {
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

        if expenseDate > Date() {
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
        let descriptionValue = notes.isEmpty ? nil : notes

        let ocrData: [String: String]? = nil
        let ocrConfidence: Double? = nil

        if let exp = editing {
            let fields = UpdateExpenseDTO(
                categoryId: selectedCategoryId,
                merchantName: merchantName.isEmpty ? nil : merchantName,
                description: descriptionValue,
                amount: amountValue,
                taxAmount: taxValue,
                expenseDate: dateString,
                paymentMethod: paymentMethod.rawValue
            )
            await viewModel.updateExpense(exp.id, fields: fields)

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
        merchantName = ""
        amount = ""
        taxAmount = ""
        expenseDate = Date()
        selectedCategoryId = nil
        notes = ""
        ocrUsed = false
        validationErrors = []

        if prefilledProjectId == nil {
            projectAllocations = []
            projectSearchTexts = [:]
            activeSearchIndex = nil
        }

        // Run OCR on next receipt
        Task { await runOCR() }
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
