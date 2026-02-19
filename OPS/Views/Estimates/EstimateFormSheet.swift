//
//  EstimateFormSheet.swift
//  OPS
//
//  Create or edit an estimate — collapsible sections, line items, sticky total footer.
//

import SwiftUI

struct EstimateFormSheet: View {
    @ObservedObject var viewModel: EstimateViewModel
    var editing: Estimate? = nil

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var isSaving = false
    @State private var createdEstimate: Estimate? = nil
    @State private var showLineItemSheet = false
    @State private var showProductPicker = false
    @State private var editingLineItem: EstimateLineItem? = nil
    @State private var clientSectionExpanded = true
    @State private var paymentSectionExpanded = false
    @State private var notesSectionExpanded = false

    private var estimate: Estimate? {
        editing ?? createdEstimate
    }

    private var lineItems: [EstimateLineItem] {
        guard let est = estimate else { return [] }
        return viewModel.lineItems(for: est.id)
    }

    private var subtotal: Double {
        lineItems.reduce(0) { $0 + $1.lineTotal }
    }

    private var taxAmount: Double {
        let rate = estimate?.taxRate ?? 0
        return subtotal * rate / 100
    }

    private var total: Double {
        subtotal + taxAmount
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        // CLIENT & PROJECT section
                        collapsibleSection(
                            title: "CLIENT & PROJECT",
                            isExpanded: $clientSectionExpanded
                        ) {
                            VStack(spacing: 0) {
                                formField("Title", text: $title, placeholder: "Estimate title")
                            }
                            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                        }

                        // LINE ITEMS section (always expanded)
                        sectionHeader("LINE ITEMS")
                        lineItemsContent

                        // PAYMENT & TERMS section
                        collapsibleSection(
                            title: "PAYMENT & TERMS",
                            isExpanded: $paymentSectionExpanded
                        ) {
                            Text("Payment terms configuration coming soon.")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                        }

                        // NOTES section
                        collapsibleSection(
                            title: "NOTES & ATTACHMENTS",
                            isExpanded: $notesSectionExpanded
                        ) {
                            Text("Notes and attachments coming soon.")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                        }
                    }
                    .padding(.top, OPSStyle.Layout.spacing3)
                    .padding(.bottom, 120) // footer clearance
                }

                // Sticky footer with totals
                stickyFooter
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationTitle(editing != nil ? "EDIT ESTIMATE" : "NEW ESTIMATE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                            .tint(OPSStyle.Colors.primaryAccent)
                    } else {
                        Button("SAVE") { saveDraft() }
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
            .sheet(isPresented: $showLineItemSheet) {
                if let est = estimate {
                    LineItemEditSheet(
                        estimateId: est.id,
                        viewModel: viewModel,
                        editing: editingLineItem
                    )
                }
            }
            .sheet(isPresented: $showProductPicker) {
                if let est = estimate {
                    ProductPickerSheet(
                        estimateId: est.id,
                        viewModel: viewModel
                    )
                }
            }
            .onAppear {
                if let est = editing {
                    title = est.title ?? ""
                }
            }
            .task {
                // Auto-create estimate on first open (create mode)
                if editing == nil && createdEstimate == nil {
                    let companyId = dataController.currentUser?.companyId ?? ""
                    createdEstimate = await viewModel.createEstimate(
                        title: title.isEmpty ? "New Estimate" : title,
                        companyId: companyId
                    )
                }
            }
        }
    }

    // MARK: - Line Items Content

    private var lineItemsContent: some View {
        VStack(spacing: 0) {
            if lineItems.isEmpty {
                Text("ADD LINE ITEMS ABOVE")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing4)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
            } else {
                VStack(spacing: 0) {
                    ForEach(lineItems) { item in
                        Button {
                            editingLineItem = item
                            showLineItemSheet = true
                        } label: {
                            lineItemRow(item)
                        }
                        .buttonStyle(PlainButtonStyle())

                        if item.id != lineItems.last?.id {
                            Divider().background(Color.white.opacity(0.1))
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }

            // Add buttons
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Button("[+ ADD FROM CATALOG]") {
                    showProductPicker = true
                }
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

                Button("[+ CUSTOM LINE ITEM]") {
                    editingLineItem = nil
                    showLineItemSheet = true
                }
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing2)
        }
    }

    private func lineItemRow(_ item: EstimateLineItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(item.name)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Spacer()
                Text(item.lineTotal, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            HStack(spacing: 4) {
                Text(item.type.rawValue.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                let qty = item.quantity.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(item.quantity))
                    : String(format: "%.1f", item.quantity)
                Text("[\(qty)\(item.unit ?? "") · \(item.unitPrice, format: .currency(code: "USD"))/\(item.unit ?? "ea")]")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    // MARK: - Sticky Footer

    private var stickyFooter: some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            HStack {
                Text("Subtotal \(subtotal, format: .currency(code: "USD").precision(.fractionLength(0)))")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                if (estimate?.taxRate ?? 0) > 0 {
                    Text("Tax \(taxAmount, format: .currency(code: "USD").precision(.fractionLength(0)))")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            HStack {
                Text("TOTAL")
                    .font(OPSStyle.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text(total, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                if let est = estimate, est.status == .draft, !lineItems.isEmpty {
                    Button("SEND EST") {
                        Task {
                            await viewModel.sendEstimate(est)
                            if viewModel.error == nil { dismiss() }
                        }
                    }
                    .opsPrimaryButtonStyle()
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(
            OPSStyle.Colors.background
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: -2)
        )
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func collapsibleSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.wrappedValue.toggle() } }) {
                HStack {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text(title)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded.wrappedValue {
                content()
            }
        }
    }

    private func formField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.body)
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

    // MARK: - Actions

    private func saveDraft() {
        isSaving = true
        Task {
            // Title update would be a repository call — for now just dismiss
            isSaving = false
            dismiss()
        }
    }
}
