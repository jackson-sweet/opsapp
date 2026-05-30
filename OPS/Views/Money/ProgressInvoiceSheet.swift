//
//  ProgressInvoiceSheet.swift
//  OPS
//
//  Sheet for partial estimate-to-invoice conversion.
//  Users select line items and set percentages to invoice.
//

import SwiftUI

// MARK: - Line Item Selection Model

private struct LineItemSelection {
    var isSelected: Bool = false
    var percentage: Double = 100.0
}

// MARK: - ProgressInvoiceSheet

struct ProgressInvoiceSheet: View {

    let estimate: Estimate
    let lineItems: [EstimateLineItem]
    let onCreateInvoice: ([(lineItemId: String, percentage: Double)]) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var selections: [String: LineItemSelection] = [:]
    @State private var isCreating: Bool = false

    // MARK: - Computed

    /// Preview total — matches RPC math: pro-rate from lineTotal when available,
    /// otherwise pro-rate quantity then multiply by unitPrice with discount.
    private var invoiceSubtotal: Double {
        lineItems.reduce(0.0) { total, item in
            guard let sel = selections[item.id], sel.isSelected, sel.percentage > 0 else { return total }
            let pct = sel.percentage / 100.0
            if item.lineTotal != 0 {
                // Pro-rate the stored line total (includes discount)
                return total + (item.lineTotal * pct).rounded(toPlaces: 2)
            } else {
                let proQty = (item.quantity * pct).rounded(toPlaces: 4)
                return total + (proQty * item.unitPrice).rounded(toPlaces: 2)
            }
        }
    }

    private var estimatedTax: Double {
        (invoiceSubtotal * estimate.taxRate / 100.0).rounded(toPlaces: 2)
    }

    private var invoiceTotal: Double {
        invoiceSubtotal + estimatedTax
    }

    private var hasSelections: Bool {
        selections.values.contains { $0.isSelected && $0.percentage > 0 }
    }

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f
    }()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {

                // Scrollable content
                ScrollView {
                    VStack(spacing: 0) {
                        instructionBanner
                        lineItemsList
                        // Bottom padding so footer doesn't cover last row
                        Color.clear.frame(height: 140)
                    }
                }

                // Sticky footer
                stickyFooter
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PROGRESS INVOICE")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .disabled(isCreating)
                }
            }
            .allowsHitTesting(!isCreating)
        }
        .onAppear {
            initializeSelections()
        }
    }

    // MARK: - Instruction Banner

    private var instructionBanner: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("SELECT LINE ITEMS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("Choose which line items to include and set the percentage of each to invoice now. The remainder can be invoiced at completion.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing2_5)
    }

    // MARK: - Line Items List

    private var lineItemsList: some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            ForEach(lineItems.sorted { $0.displayOrder < $1.displayOrder }) { item in
                lineItemRow(item)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Line Item Row

    @ViewBuilder
    private func lineItemRow(_ item: EstimateLineItem) -> some View {
        let isSelected = selections[item.id]?.isSelected ?? false

        VStack(spacing: 0) {
            // Main row: checkbox + info
            Button {
                toggleSelection(for: item.id)
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    // Checkbox
                    Image(systemName: isSelected
                          ? OPSStyle.Icons.checkmarkSquareFill
                          : OPSStyle.Icons.square)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(isSelected
                                         ? OPSStyle.Colors.primaryAccent
                                         : OPSStyle.Colors.tertiaryText)

                    // Name + description
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)

                        if let desc = item.itemDescription, !desc.isEmpty {
                            Text(desc)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Line total
                    Text(formatted(item.lineTotal))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .monospacedDigit()
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2_5)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            // Percentage input — shown only when selected
            if isSelected {
                percentageRow(for: item)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(
                    isSelected ? OPSStyle.Colors.primaryAccent.opacity(0.4) : OPSStyle.Colors.inputFieldBorder,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
        .animation(OPSStyle.Animation.fast, value: isSelected)
    }

    // MARK: - Percentage Row

    @ViewBuilder
    private func percentageRow(for item: EstimateLineItem) -> some View {
        let binding = Binding<Double>(
            get: { selections[item.id]?.percentage ?? 100.0 },
            set: { newValue in
                selections[item.id]?.percentage = newValue
            }
        )

        VStack(spacing: OPSStyle.Layout.spacing2) {
            Divider()
                .background(OPSStyle.Colors.inputFieldBorder)

            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Text("INVOICE %")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                // Percentage stepper buttons
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    // Decrease by 10 (min 10%)
                    Button {
                        let current = selections[item.id]?.percentage ?? 100.0
                        selections[item.id]?.percentage = max(10, current - 10)
                    } label: {
                        Image(systemName: OPSStyle.Icons.minus)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(width: 32, height: 32)
                            .background(OPSStyle.Colors.cardBackground)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Percentage display
                    HStack(spacing: 2) {
                        Text(percentageString(binding.wrappedValue))
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .monospacedDigit()
                            .frame(minWidth: 40, alignment: .trailing)

                        Text("%")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }

                    // Increase by 10
                    Button {
                        let current = selections[item.id]?.percentage ?? 100.0
                        selections[item.id]?.percentage = min(100, current + 10)
                    } label: {
                        Image(OPSStyle.Icons.plus)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(width: 32, height: 32)
                            .background(OPSStyle.Colors.cardBackground)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Invoiced sub-amount
                Text(formatted(item.lineTotal * binding.wrappedValue / 100.0))
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.accountingRevenue)
                    .monospacedDigit()
                    .frame(minWidth: 72, alignment: .trailing)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.bottom, OPSStyle.Layout.spacing2_5)
        }
    }

    // MARK: - Sticky Footer

    private var stickyFooter: some View {
        OPSFloatingButtonBar(horizontalPadding: OPSStyle.Layout.spacing3, verticalPadding: OPSStyle.Layout.spacing2_5) {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                // Subtotal row
                HStack {
                    Text("SUBTOTAL")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Text(formatted(invoiceSubtotal))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .monospacedDigit()
                }

                // Tax row (only show if tax rate > 0)
                if estimate.taxRate > 0 {
                    HStack {
                        Text("TAX (\(percentageString(estimate.taxRate))%)")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Spacer()
                        Text(formatted(estimatedTax))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .monospacedDigit()
                    }
                }

                // Total row
                HStack {
                    Text("INVOICE TOTAL")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Spacer()

                    Text(formatted(invoiceTotal))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(
                            invoiceTotal > 0
                                ? OPSStyle.Colors.accountingRevenue
                                : OPSStyle.Colors.tertiaryText
                        )
                        .monospacedDigit()
                }

                // Create Invoice button
                Button {
                    createInvoice()
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        if isCreating {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isCreating ? "CREATING..." : "CREATE INVOICE")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(hasSelections ? .white : OPSStyle.Colors.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(
                        hasSelections && !isCreating
                            ? OPSStyle.Colors.primaryAccent
                            : OPSStyle.Colors.cardBackgroundDark
                    )
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(
                                hasSelections && !isCreating
                                    ? Color.clear
                                    : OPSStyle.Colors.inputFieldBorder,
                                lineWidth: OPSStyle.Layout.Border.standard
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!hasSelections || isCreating)
            }
        }
    }

    // MARK: - Helpers

    private func initializeSelections() {
        for item in lineItems {
            if selections[item.id] == nil {
                selections[item.id] = LineItemSelection()
            }
        }
    }

    private func toggleSelection(for id: String) {
        withAnimation(OPSStyle.Animation.fast) {
            if selections[id] == nil {
                selections[id] = LineItemSelection(isSelected: true, percentage: 100.0)
            } else {
                selections[id]?.isSelected.toggle()
            }
        }
    }

    private func createInvoice() {
        isCreating = true
        let result = lineItems.compactMap { item -> (lineItemId: String, percentage: Double)? in
            guard let sel = selections[item.id], sel.isSelected, sel.percentage > 0 else {
                return nil
            }
            return (lineItemId: item.id, percentage: sel.percentage)
        }
        Task {
            let success = await onCreateInvoice(result)
            if !success {
                isCreating = false
            }
            // On success, parent dismisses the sheet.
        }
    }

    private func formatted(_ value: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private func percentageString(_ value: Double) -> String {
        let int = Int(value.rounded())
        return "\(int)"
    }
}

// MARK: - Double Rounding Helper

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}
