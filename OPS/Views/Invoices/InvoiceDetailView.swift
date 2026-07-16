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
    @State private var showWriteOffConfirm = false
    @State private var showBreakdown: Bool

    /// `initialShowBreakdown` seeds the bundle-breakdown toggle — the default
    /// (bundled) is production behavior; the snapshot harness passes `true`
    /// to capture the expanded state.
    init(invoice: Invoice, viewModel: InvoiceViewModel, initialShowBreakdown: Bool = false) {
        self.invoice = invoice
        self.viewModel = viewModel
        _showBreakdown = State(initialValue: initialShowBreakdown)
    }

    private var lineItems: [InvoiceLineItem] {
        viewModel.lineItems(for: invoice.id)
    }

    // Bundle-aware grouping — estimates converted to invoices carry their
    // parent/child line items across (convert_estimate_to_invoice copies
    // children with remapped parent ids). Parents hold the money; children
    // are the material breakdown. Rendering them as flat peers would double-
    // count every bundle on screen, so the invoice mirrors the estimate
    // detail: bundled by default, BREAKDOWN on demand.
    private var parentItems: [InvoiceLineItem] {
        lineItems.filter { $0.parentLineItemId == nil }
    }

    private func childItems(for parentId: String) -> [InvoiceLineItem] {
        lineItems.filter { $0.parentLineItemId == parentId }
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
        .trackScreen("InvoiceDetail")
        .navigationBarTitleDisplayMode(.inline)
        .hidesGlobalTabBar()
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
                        if invoice.status.needsPayment {
                            Button("Bad Debt", role: .destructive) {
                                showWriteOffConfirm = true
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
        .confirmationDialog("Write Off as Bad Debt?", isPresented: $showWriteOffConfirm, titleVisibility: .visible) {
            Button("Write Off", role: .destructive) {
                Task {
                    await viewModel.writeOffInvoice(invoice)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will write off \(invoice.invoiceNumber) (\(LineItemDisplay.money(invoice.balanceDue))) as bad debt. This action cannot be undone.")
        }
        .sheet(isPresented: $showPaymentSheet) {
            PaymentRecordSheet(invoice: invoice, viewModel: viewModel)
        }
        .errorToast($viewModel.error, label: Feedback.Err.operationFailed)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack {
                Text(invoice.invoiceNumber.isEmpty ? "NEW INVOICE" : invoice.invoiceNumber)
                    .font(OPSStyle.Typography.screenTitle(for: invoice.invoiceNumber.isEmpty ? "NEW INVOICE" : invoice.invoiceNumber))
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text)
                Spacer()
            }

            if let title = invoice.title, !title.isEmpty {
                Text(title)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(LineItemDisplay.money(invoice.total))
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
        return HStack(spacing: OPSStyle.Layout.spacing1) {
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
            HStack {
                Text("LINE ITEMS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                if lineItems.contains(where: { $0.parentLineItemId != nil }) {
                    Button {
                        withAnimation(OPSStyle.Animation.spring) { showBreakdown.toggle() }
                    } label: {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Text(showBreakdown ? "BUNDLED" : "BREAKDOWN")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            Image(systemName: showBreakdown ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            if lineItems.isEmpty {
                Text("No line items")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(parentItems.enumerated()), id: \.element.id) { index, item in
                        parentLineItemRow(item)

                        if showBreakdown {
                            let children = childItems(for: item.id)
                            ForEach(children) { child in
                                childLineItemRow(child)
                            }
                        }

                        if index < parentItems.count - 1 {
                            Divider().background(OPSStyle.Colors.separator)
                        }
                    }
                }
                .glassSurface()
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
        }
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    private func parentLineItemRow(_ item: InvoiceLineItem) -> some View {
        let children = childItems(for: item.id)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(item.name)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Spacer()
                Text(LineItemDisplay.money(item.lineTotal))
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text(item.type.rawValue.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                // Standalone items carry their own math; bundle parents are a
                // sum of their children, so they show the item count instead.
                if children.isEmpty {
                    Text("· \(LineItemDisplay.quantityPriceMeta(quantity: item.quantity, unit: item.unit, unitPrice: item.unitPrice, resolvedUnitPrice: item.resolvedUnitPrice))")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                if let label = item.resolvedOptionsLabel, !label.isEmpty {
                    Text("· \(label)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }
                if !children.isEmpty {
                    Text("[\(children.count) items]")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    private func childLineItemRow(_ item: InvoiceLineItem) -> some View {
        HStack {
            Rectangle()
                .fill(OPSStyle.Colors.tertiaryText.opacity(0.2))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
                Text(childMetaLine(item))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
            Text(LineItemDisplay.money(item.lineTotal))
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(.leading, OPSStyle.Layout.spacing3 + 14)
        .padding(.trailing, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing1)
        .background(OPSStyle.Colors.surfaceHover)
    }

    /// Child-row metadata: "qty unit × unit price · [chosen option]". Configured
    /// children display their resolved snapshot price — the price their line
    /// total was actually computed from.
    private func childMetaLine(_ item: InvoiceLineItem) -> String {
        let meta = LineItemDisplay.quantityPriceMeta(
            quantity: item.quantity,
            unit: item.unit,
            unitPrice: item.unitPrice,
            resolvedUnitPrice: item.resolvedUnitPrice
        )
        if let label = item.resolvedOptionsLabel, !label.isEmpty {
            return "\(meta) · \(label)"
        }
        return meta
    }

    // MARK: - Totals

    private var totalsSection: some View {
        VStack(spacing: 0) {
            Divider().background(OPSStyle.Colors.separator)

            VStack(spacing: OPSStyle.Layout.spacing1) {
                HStack {
                    Text("SUBTOTAL")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Text(LineItemDisplay.money(invoice.subtotal))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                // Discount is derived from the stored totals so the card's
                // arithmetic always closes on screen — without this row a
                // discounted invoice reads subtotal + tax ≠ total.
                if let discount = LineItemDisplay.discountAmount(
                    subtotal: invoice.subtotal,
                    taxAmount: invoice.taxAmount,
                    total: invoice.total
                ) {
                    HStack {
                        Text("DISCOUNT")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Spacer()
                        Text("−\(LineItemDisplay.money(discount))")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }

                if invoice.taxRate > 0 {
                    HStack {
                        Text("TAX (\(LineItemDisplay.taxRateString(invoice.taxRate))%)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Spacer()
                        Text(LineItemDisplay.money(invoice.taxAmount))
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
                    Text(LineItemDisplay.money(invoice.total))
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
                        Text(LineItemDisplay.money(invoice.amountPaid))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.successStatus)
                    }

                    HStack {
                        Text("BALANCE DUE")
                            .font(OPSStyle.Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(invoice.isOverdue ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryText)
                        Spacer()
                        Text(LineItemDisplay.money(invoice.balanceDue))
                            .font(OPSStyle.Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(invoice.isOverdue ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryText)
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .glassSurface()
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
                        Divider().background(OPSStyle.Colors.separator)
                    }
                }
            }
            .glassSurface()
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
            Text(LineItemDisplay.money(payment.amount))
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
        OPSFloatingButtonBar(horizontalPadding: OPSStyle.Layout.spacing3, verticalPadding: OPSStyle.Layout.spacing2) {
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
                        Text(LineItemDisplay.money(invoice.balanceDue))
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

                case .writtenOff:
                    Text("WRITTEN OFF")
                        .font(OPSStyle.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Spacer()
                }
            }
        }
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
        case .writtenOff:      return OPSStyle.Colors.tertiaryText
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
