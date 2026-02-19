//
//  InvoiceDetailView.swift
//  OPS
//
//  Full detail for one invoice — line items, payments, totals, and context-dependent action footer.
//

import SwiftUI

struct InvoiceDetailView: View {
    var invoice: Invoice
    @ObservedObject var viewModel: InvoiceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showPaymentSheet = false
    @State private var showVoidConfirm = false

    private var lineItems: [InvoiceLineItem] {
        viewModel.lineItems(for: invoice.id)
    }

    private var payments: [Payment] {
        viewModel.payments(for: invoice.id)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    lineItemsSection
                    totalsSection
                    if !payments.isEmpty {
                        paymentsSection
                    }
                }
                .padding(.bottom, 100) // footer clearance
            }

            // Sticky footer
            stickyFooter
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if invoice.status != .void && invoice.status != .paid {
                    Menu {
                        if invoice.status.needsPayment {
                            Button("Record Payment") { showPaymentSheet = true }
                        }
                        if invoice.status == .draft {
                            Button("Send Invoice") {
                                Task { await viewModel.sendInvoice(invoice) }
                            }
                        }
                        if invoice.status != .void && invoice.status != .paid {
                            Button("Void Invoice", role: .destructive) {
                                showVoidConfirm = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
            }
        }
        .confirmationDialog("Void Invoice?", isPresented: $showVoidConfirm) {
            Button("Void Invoice", role: .destructive) {
                Task {
                    await viewModel.voidInvoice(invoice)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will void the invoice. This action cannot be undone.")
        }
        .sheet(isPresented: $showPaymentSheet) {
            PaymentRecordSheet(invoice: invoice, viewModel: viewModel)
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack {
                Text(invoice.invoiceNumber.isEmpty ? "NEW INVOICE" : invoice.invoiceNumber)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
            }

            if let title = invoice.title, !title.isEmpty {
                Text(title)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(invoice.total, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                statusBadge

                if let due = invoice.dueDate {
                    if invoice.isOverdue {
                        Text("[overdue \(due.timeAgoDetail)]")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                    } else {
                        Text("[due \(due.dueInDetail)]")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                } else {
                    Text("[created \(invoice.createdAt.timeAgoDetail)]")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing2)
    }

    private var statusBadge: some View {
        let color = invoice.status.detailBadgeColor(isOverdue: invoice.isOverdue)
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(invoice.isOverdue ? "OVERDUE" : invoice.status.displayName)
                .font(OPSStyle.Typography.smallCaption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }

    // MARK: - Line Items

    private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("LINE ITEMS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            if lineItems.isEmpty {
                Text("No line items")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing4)
            } else {
                VStack(spacing: 0) {
                    ForEach(lineItems) { item in
                        lineItemRow(item)
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
        }
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    private func lineItemRow(_ item: InvoiceLineItem) -> some View {
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
                let qty = formatQuantity(item.quantity)
                Text("[\(qty)\(item.unit ?? "") · \(item.unitPrice, format: .currency(code: "USD"))/\(item.unit ?? "ea")]")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    private func formatQuantity(_ qty: Double) -> String {
        qty.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(qty)) : String(format: "%.1f", qty)
    }

    // MARK: - Totals

    private var totalsSection: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.1))

            VStack(spacing: OPSStyle.Layout.spacing1) {
                HStack {
                    Text("SUBTOTAL")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Text(invoice.subtotal, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                if invoice.taxRate > 0 {
                    HStack {
                        Text("TAX (\(String(format: "%.0f", invoice.taxRate))%)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Spacer()
                        Text(invoice.taxAmount, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }

                HStack {
                    Text("TOTAL")
                        .font(OPSStyle.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Spacer()
                    Text(invoice.total, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                if invoice.amountPaid > 0 {
                    HStack {
                        Text("PAID")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.successStatus)
                        Spacer()
                        Text(invoice.amountPaid, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.successStatus)
                    }

                    HStack {
                        Text("BALANCE DUE")
                            .font(OPSStyle.Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(invoice.isOverdue ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryText)
                        Spacer()
                        Text(invoice.balanceDue, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(OPSStyle.Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(invoice.isOverdue ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryText)
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Payments

    private var paymentsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("PAYMENTS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            VStack(spacing: 0) {
                ForEach(payments) { payment in
                    paymentRow(payment)
                    if payment.id != payments.last?.id {
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
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    private func paymentRow(_ payment: Payment) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.method.displayName)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text(payment.paidAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
            Text(payment.amount, format: .currency(code: "USD").precision(.fractionLength(2)))
                .font(OPSStyle.Typography.body)
                .foregroundColor(payment.isVoided ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.successStatus)
            if payment.isVoided {
                Text("[VOID]")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    // MARK: - Sticky Footer

    private var stickyFooter: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            switch invoice.status {
            case .draft:
                Button("SEND INVOICE") {
                    Task { await viewModel.sendInvoice(invoice) }
                }
                .opsPrimaryButtonStyle()

            case .awaitingPayment, .partiallyPaid, .sent, .pastDue:
                VStack(alignment: .leading, spacing: 2) {
                    Text("BALANCE DUE")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text(invoice.balanceDue, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(invoice.isOverdue ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryText)
                }
                Spacer()
                Button("RECORD PAYMENT") { showPaymentSheet = true }
                    .opsPrimaryButtonStyle()

            case .paid:
                Text("PAID IN FULL")
                    .font(OPSStyle.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(OPSStyle.Colors.successStatus)
                Spacer()

            case .void:
                Text("VOIDED")
                    .font(OPSStyle.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(
            OPSStyle.Colors.background
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: -2)
        )
    }
}

// MARK: - Helpers

private extension InvoiceStatus {
    func detailBadgeColor(isOverdue: Bool) -> Color {
        if isOverdue { return OPSStyle.Colors.errorStatus }
        switch self {
        case .draft:           return OPSStyle.Colors.tertiaryText
        case .sent:            return OPSStyle.Colors.primaryAccent
        case .awaitingPayment: return OPSStyle.Colors.warningStatus
        case .partiallyPaid:   return OPSStyle.Colors.warningStatus
        case .paid:            return OPSStyle.Colors.successStatus
        case .pastDue:         return OPSStyle.Colors.errorStatus
        case .void:            return OPSStyle.Colors.tertiaryText
        }
    }
}

private extension Date {
    var timeAgoDetail: String {
        let interval = Date().timeIntervalSince(self)
        let days = Int(interval / 86400)
        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        return "\(days) days ago"
    }

    var dueInDetail: String {
        let interval = self.timeIntervalSince(Date())
        let days = Int(interval / 86400)
        if days == 0 { return "today" }
        if days == 1 { return "tomorrow" }
        if days > 0 { return "in \(days) days" }
        return timeAgoDetail
    }
}
