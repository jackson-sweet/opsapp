//
//  LineItemEditSheet.swift
//  OPS
//
//  Bottom sheet for editing or creating a line item on an estimate.
//

import SwiftUI

struct LineItemEditSheet: View {
    let estimateId: String
    @ObservedObject var viewModel: EstimateViewModel
    var editing: EstimateLineItem? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var type: LineItemType = .labor
    @State private var quantity = "1"
    @State private var unit = ""
    @State private var unitPrice = ""
    @State private var isOptional = false
    @State private var isTaxable = true
    @State private var isSaving = false
    @State private var productId: String? = nil

    private var lineTotal: Double {
        let qty = Double(quantity) ?? 0
        let price = Double(unitPrice) ?? 0
        return qty * price
    }

    private var isValid: Bool {
        !description.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Double(quantity) ?? 0) > 0 &&
        (Double(unitPrice) ?? 0) >= 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    // Description
                    sectionHeader("DESCRIPTION")
                    TextField("Line item name", text: $description)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // Type picker
                    sectionHeader("TYPE")
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(LineItemType.allCases, id: \.self) { t in
                            Button(action: { type = t }) {
                                Text(t.rawValue.uppercased())
                                    .font(OPSStyle.Typography.smallCaption)
                                    .fontWeight(.medium)
                                    .foregroundColor(
                                        type == t ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText
                                    )
                                    .padding(.horizontal, OPSStyle.Layout.spacing2 + 2)
                                    .padding(.vertical, OPSStyle.Layout.spacing1 + 2)
                                    .background(
                                        type == t
                                        ? OPSStyle.Colors.primaryAccent.opacity(0.2)
                                        : OPSStyle.Colors.cardBackgroundDark.opacity(0.6)
                                    )
                                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                            .stroke(
                                                type == t ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.1),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // Quantity + Unit Price side by side
                    sectionHeader("QUANTITY & PRICE")
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("QTY")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            TextField("1", text: $quantity)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .keyboardType(.decimalPad)
                                .padding(OPSStyle.Layout.spacing2)
                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("UNIT")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            TextField("hr", text: $unit)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding(OPSStyle.Layout.spacing2)
                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                        .frame(width: 80)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("UNIT PRICE")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            TextField("$0", text: $unitPrice)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .keyboardType(.decimalPad)
                                .padding(OPSStyle.Layout.spacing2)
                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // Toggles
                    VStack(spacing: 0) {
                        toggleRow("Optional?", isOn: $isOptional)
                        Divider().background(Color.white.opacity(0.1))
                        toggleRow("Taxable?", isOn: $isTaxable)
                    }
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // Line Total (read-only)
                    HStack {
                        Text("LINE TOTAL")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Spacer()
                        Text(lineTotal, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(OPSStyle.Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)

                    // Save button
                    Button(editing != nil ? "SAVE CHANGES" : "ADD LINE ITEM") { save() }
                        .opsPrimaryButtonStyle()
                        .disabled(!isValid || isSaving)
                        .opacity(isValid ? 1 : 0.5)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // Delete button (edit mode only)
                    if editing != nil {
                        Button("DELETE LINE ITEM") { deleteItem() }
                            .opsDestructiveButtonStyle()
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                    }
                }
                .padding(.top, OPSStyle.Layout.spacing3)
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationTitle(editing != nil ? "EDIT LINE ITEM" : "NEW LINE ITEM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .onAppear {
                if let item = editing {
                    description = item.name
                    type = item.type
                    quantity = item.quantity.truncatingRemainder(dividingBy: 1) == 0
                        ? String(Int(item.quantity))
                        : String(format: "%.1f", item.quantity)
                    unit = item.unit ?? ""
                    unitPrice = String(format: "%.2f", item.unitPrice)
                    isOptional = item.optional
                    isTaxable = item.taxable
                    productId = item.productId
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(OPSStyle.Layout.largeCornerRadius)
        .presentationDragIndicator(.visible)
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

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .tint(OPSStyle.Colors.primaryAccent)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
    }

    // MARK: - Actions

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            if let item = editing {
                await viewModel.updateLineItem(
                    id: item.id,
                    estimateId: estimateId,
                    description: description,
                    quantity: Double(quantity),
                    unitPrice: Double(unitPrice),
                    isOptional: isOptional
                )
            } else {
                await viewModel.addLineItem(
                    estimateId: estimateId,
                    description: description,
                    type: type,
                    quantity: Double(quantity) ?? 1,
                    unitPrice: Double(unitPrice) ?? 0,
                    isOptional: isOptional,
                    productId: productId
                )
            }
            if viewModel.error == nil { dismiss() }
        }
    }

    private func deleteItem() {
        guard let item = editing else { return }
        Task {
            await viewModel.deleteLineItem(id: item.id, estimateId: estimateId)
            if viewModel.error == nil { dismiss() }
        }
    }
}
