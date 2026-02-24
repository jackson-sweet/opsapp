//
//  PaymentRecordSheet.swift
//  OPS
//
//  Bottom sheet to record a payment against an invoice.
//

import SwiftUI

struct PaymentRecordSheet: View {
    let invoice: Invoice
    @ObservedObject var viewModel: InvoiceViewModel
    @EnvironmentObject private var dataController: DataController

    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var method: PaymentMethod = .cash
    @State private var notes = ""
    @State private var isSaving = false

    private var isValid: Bool {
        guard let val = Double(amount), val > 0 else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    // Invoice context
                    HStack {
                        Text(invoice.invoiceNumber)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()
                        Text("Balance: \(invoice.balanceDue, format: .currency(code: "USD").precision(.fractionLength(2)))")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // Amount
                    sectionHeader("AMOUNT")
                    TextField("$0.00", text: $amount)
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .padding(OPSStyle.Layout.spacing3)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // Method picker
                    sectionHeader("METHOD")
                    VStack(spacing: 0) {
                        ForEach(PaymentMethod.allCases, id: \.self) { m in
                            Button(action: { method = m }) {
                                HStack {
                                    Text(m.displayName)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(
                                            method == m ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText
                                        )
                                    Spacer()
                                    if method == m {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                            .font(.system(size: 14))
                                    }
                                }
                                .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                            }
                            .buttonStyle(PlainButtonStyle())

                            if m != PaymentMethod.allCases.last {
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

                    // Notes
                    sectionHeader("NOTES")
                    TextField("Optional note...", text: $notes, axis: .vertical)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(3...6)
                        .padding(OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // Record button
                    Button(isSaving ? "RECORDING..." : "RECORD PAYMENT") { recordPayment() }
                        .opsPrimaryButtonStyle()
                        .disabled(!isValid || isSaving)
                        .opacity(isValid ? 1 : 0.5)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                }
                .padding(.top, OPSStyle.Layout.spacing3)
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationTitle("RECORD PAYMENT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .onAppear {
                // Pre-fill with balance due
                amount = String(format: "%.2f", invoice.balanceDue)
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

    // MARK: - Actions

    private func recordPayment() {
        guard let val = Double(amount), val > 0 else { return }
        isSaving = true
        Task {
            let companyId = dataController.currentUser?.companyId ?? ""
            await viewModel.recordPayment(
                invoiceId: invoice.id,
                companyId: companyId,
                amount: val,
                method: method,
                notes: notes.isEmpty ? nil : notes
            )
            isSaving = false
            if viewModel.error == nil { dismiss() }
        }
    }
}
