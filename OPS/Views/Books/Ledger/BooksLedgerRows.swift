//
//  BooksLedgerRows.swift
//  OPS
//
//  Money & Leads redesign (2026-06-30) — the flat ledger rows for the Money
//  tab. Hairline-separated rows (not glass cards) that scan fast: who + what's
//  owed up top, the metadata + status pill below. One row family per ledger.
//  Pure presentation — the orchestrator resolves client/crew names and hands
//  each row a ready model; a tap opens the existing detail screen.
//

import SwiftUI

// MARK: - Status pill

struct BooksPill {
    let text: String
    let color: Color
    var solid: Bool = false
}

struct BooksPillView: View {
    let pill: BooksPill

    var body: some View {
        Text(pill.text)
            .font(.custom("JetBrainsMono-Medium", size: 8.5))
            .tracking(0.85)
            .textCase(.uppercase)
            .foregroundColor(pill.solid ? OPSStyle.Colors.invertedText : pill.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(pill.solid ? pill.color : pill.color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(pill.color.opacity(pill.solid ? 0 : 0.30), lineWidth: 1)
            )
            .fixedSize()
    }
}

// MARK: - Row hairline

private struct LedgerRowChrome: ViewModifier {
    var onTap: () -> Void
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTap()
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(OPSStyle.Colors.lineSoft)
                    .frame(height: 1)
            }
    }
}

private extension View {
    func ledgerRow(onTap: @escaping () -> Void) -> some View { modifier(LedgerRowChrome(onTap: onTap)) }
}

// MARK: - Invoice row

struct BooksInvoiceRow: View {
    let invoice: Invoice
    let clientName: String?
    var onTap: () -> Void

    private var primary: String {
        if let clientName, !clientName.isEmpty { return clientName }
        if let title = invoice.title, !title.isEmpty { return title }
        return invoice.invoiceNumber
    }
    private var owed: Double { invoice.status.isPaid ? invoice.total : invoice.balanceDue }
    private var amountColor: Color {
        if invoice.isOverdue { return OPSStyle.Colors.rose }
        if invoice.status.isPaid { return OPSStyle.Colors.olive }
        return OPSStyle.Colors.text
    }
    private var amountSub: String? {
        (invoice.balanceDue > 0 && invoice.balanceDue < invoice.total)
            ? "OF \(BooksFormat.currency(invoice.total))" : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2_5) {
                Text(primary)
                    .font(.custom("Mohave-Medium", size: 15))
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(BooksFormat.currency(owed))
                    .font(.custom("JetBrainsMono-Medium", size: 15))
                    .foregroundColor(amountColor)
                    .monospacedDigit()
            }
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(invoice.invoiceNumber)
                    .font(.custom("JetBrainsMono-Regular", size: 9.5))
                    .foregroundColor(OPSStyle.Colors.text3)
                BooksPillView(pill: BooksLedgerStatus.invoice(invoice))
                let due = BooksLedgerStatus.invoiceDue(invoice)
                if !due.text.isEmpty {
                    Text(due.text)
                        .font(.custom("JetBrainsMono-Regular", size: 9.5))
                        .foregroundColor(due.color)
                }
                Spacer(minLength: 0)
                if let amountSub {
                    Text(amountSub)
                        .font(.custom("JetBrainsMono-Regular", size: 9))
                        .foregroundColor(OPSStyle.Colors.textMute)
                }
            }
            .monospacedDigit()
        }
        .ledgerRow(onTap: onTap)
    }
}

// MARK: - Estimate row

struct BooksEstimateRow: View {
    let estimate: Estimate
    let clientName: String?
    var onTap: () -> Void

    private var primary: String {
        if let clientName, !clientName.isEmpty { return clientName }
        if let title = estimate.title, !title.isEmpty { return title }
        return estimate.estimateNumber
    }
    private var amountColor: Color {
        switch estimate.status {
        case .converted: return OPSStyle.Colors.olive
        case .declined:  return OPSStyle.Colors.text3
        default:         return OPSStyle.Colors.text
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2_5) {
                Text(primary)
                    .font(.custom("Mohave-Medium", size: 15))
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(BooksFormat.currency(estimate.total))
                    .font(.custom("JetBrainsMono-Medium", size: 15))
                    .foregroundColor(amountColor)
                    .monospacedDigit()
                    .strikethrough(estimate.status == .declined, color: OPSStyle.Colors.text3)
            }
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(estimate.estimateNumber)
                    .font(.custom("JetBrainsMono-Regular", size: 9.5))
                    .foregroundColor(OPSStyle.Colors.text3)
                BooksPillView(pill: BooksLedgerStatus.estimate(estimate))
                Spacer(minLength: 0)
                let date = BooksLedgerStatus.estimateDate(estimate)
                Text(date.text)
                    .font(.custom("JetBrainsMono-Regular", size: 9.5))
                    .foregroundColor(date.color)
            }
            .monospacedDigit()
        }
        .ledgerRow(onTap: onTap)
    }
}

// MARK: - Expense row

struct BooksExpenseRow: View {
    let expense: ExpenseDTO
    /// Pre-resolved crew name (uppercased) or nil.
    let who: String?
    var onTap: () -> Void

    private var hasReceipt: Bool { !(expense.receiptImageUrl?.isEmpty ?? true) }

    private var meta: String {
        var parts: [String] = []
        if let cat = expense.category?.name, !cat.isEmpty { parts.append(cat.uppercased()) }
        let date = BooksLedgerStatus.shortDate(expense.expenseDate)
        if !date.isEmpty { parts.append(date) }
        if let who, !who.isEmpty { parts.append(who) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            receiptThumb
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.merchantName ?? "UNKNOWN MERCHANT")
                    .font(.custom("Mohave-Medium", size: 15))
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1).truncationMode(.tail)
                Text(meta)
                    .font(.custom("JetBrainsMono-Regular", size: 9.5))
                    .foregroundColor(OPSStyle.Colors.text3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                Text(BooksFormat.exact(expense.amount, code: expense.currency ?? "USD"))
                    .font(.custom("JetBrainsMono-Regular", size: 14))
                    .foregroundColor(OPSStyle.Colors.text)
                    .monospacedDigit()
                BooksPillView(pill: BooksLedgerStatus.expense(expense))
            }
        }
        .ledgerRow(onTap: onTap)
    }

    @ViewBuilder
    private var receiptThumb: some View {
        if hasReceipt {
            // Real thumbnail — thumb URL first, full receipt as the fallback
            // (same resolution order as the batch-review hub). While loading —
            // and on a fetch failure — the abstract receipt block stands in:
            // it still reads "receipt attached", which is the truth the pill
            // logic keys off. Only a missing URL gets the rose no-receipt state.
            if let raw = expense.receiptThumbnailUrl ?? expense.receiptImageUrl,
               let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        receiptPlaceholder
                    }
                }
                .frame(width: 34, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            } else {
                receiptPlaceholder
            }
        } else {
            Image(systemName: "camera")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(OPSStyle.Colors.rose)
                .frame(width: 34, height: 42)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(OPSStyle.Colors.rose.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3]))
                )
        }
    }

    /// Abstract receipt block — the loading / failed stand-in for an attached
    /// receipt (never shown when the expense has no receipt at all).
    private var receiptPlaceholder: some View {
        VStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.white.opacity(i == 0 ? 0.32 : 0.22))
                    .frame(width: i == 1 ? 18 : (i == 3 ? 13 : 22), height: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 5).padding(.vertical, 6)
        .frame(width: 34, height: 42)
        .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

// MARK: - Status / formatting helpers

enum BooksLedgerStatus {
    // Invoice pill — overdue overrides status.
    static func invoice(_ inv: Invoice) -> BooksPill {
        if inv.isOverdue { return BooksPill(text: "OVERDUE", color: OPSStyle.Colors.rose) }
        switch inv.status {
        case .draft:           return BooksPill(text: "DRAFT", color: OPSStyle.Colors.textMute)
        case .sent:            return BooksPill(text: "SENT", color: OPSStyle.Colors.opsAccent)
        case .awaitingPayment: return BooksPill(text: "AWAITING", color: OPSStyle.Colors.opsAccent)
        case .partiallyPaid:   return BooksPill(text: "PART-PAID", color: OPSStyle.Colors.tan)
        case .paid:            return BooksPill(text: "PAID", color: OPSStyle.Colors.olive)
        case .pastDue:         return BooksPill(text: "OVERDUE", color: OPSStyle.Colors.rose)
        case .void:            return BooksPill(text: "VOID", color: OPSStyle.Colors.textMute)
        case .writtenOff:      return BooksPill(text: "WRITTEN OFF", color: OPSStyle.Colors.textMute)
        }
    }

    static func invoiceDue(_ inv: Invoice) -> (text: String, color: Color) {
        if inv.status.isPaid { return ("", .clear) }
        guard let due = inv.dueDate else {
            return inv.status == .draft ? ("NOT SENT", OPSStyle.Colors.textMute) : ("", .clear)
        }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: due)).day ?? 0
        if inv.isOverdue { return ("\(abs(days))D LATE", OPSStyle.Colors.rose) }
        if days <= 0 { return ("DUE TODAY", OPSStyle.Colors.tan) }
        return ("DUE IN \(days)D", days <= 3 ? OPSStyle.Colors.tan : OPSStyle.Colors.text3)
    }

    // Estimate pill — `.converted` reads WON here (this surface's vocabulary).
    static func estimate(_ est: Estimate) -> BooksPill {
        switch est.status {
        case .draft:     return BooksPill(text: "DRAFT", color: OPSStyle.Colors.textMute)
        case .sent:      return BooksPill(text: "SENT", color: OPSStyle.Colors.opsAccent)
        case .viewed:    return BooksPill(text: "VIEWED", color: OPSStyle.Colors.opsAccent)
        case .approved:  return BooksPill(text: "APPROVED", color: OPSStyle.Colors.olive)
        case .converted: return BooksPill(text: "WON", color: OPSStyle.Colors.olive, solid: true)
        case .declined:  return BooksPill(text: "DECLINED", color: OPSStyle.Colors.rose)
        case .expired:   return BooksPill(text: "EXPIRED", color: OPSStyle.Colors.tan)
        }
    }

    static func estimateDate(_ est: Estimate) -> (text: String, color: Color) {
        switch est.status {
        case .converted: return ("WON \(monthDay(est.updatedAt))", OPSStyle.Colors.olive)
        case .declined:  return ("LOST \(monthDay(est.updatedAt))", OPSStyle.Colors.rose)
        case .draft:     return ("NOT SENT", OPSStyle.Colors.text3)
        default:         return ("SENT \(relativeDays(est.createdAt))", OPSStyle.Colors.text3)
        }
    }

    // Expense approval pill — missing receipt overrides status.
    static func expense(_ exp: ExpenseDTO) -> BooksPill {
        if exp.receiptImageUrl?.isEmpty ?? true {
            return BooksPill(text: "NO RECEIPT", color: OPSStyle.Colors.rose)
        }
        switch ExpenseStatus(rawValue: exp.status) {
        case .submitted:            return BooksPill(text: "NEEDS OK", color: OPSStyle.Colors.tan)
        case .approved, .reimbursed: return BooksPill(text: "APPROVED", color: OPSStyle.Colors.olive)
        case .rejected:             return BooksPill(text: "REJECTED", color: OPSStyle.Colors.rose)
        case .draft:                return BooksPill(text: "DRAFT", color: OPSStyle.Colors.textMute)
        case nil:                   return BooksPill(text: "PENDING", color: OPSStyle.Colors.textMute)
        }
    }

    static func shortDate(_ raw: String?) -> String {
        guard let raw else { return "" }
        // A `date` column parses to midnight UTC — format it in UTC too, or
        // everyone west of Greenwich reads yesterday's date. Full timestamps
        // are real moments and format in local time as usual.
        if let dateOnly = SupabaseDate.parseDateOnly(raw) {
            return monthDay(dateOnly, timeZone: TimeZone(identifier: "UTC"))
        }
        guard let date = SupabaseDate.parse(raw) else { return "" }
        return monthDay(date)
    }

    private static func monthDay(_ date: Date, timeZone: TimeZone? = nil) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        if let timeZone { f.timeZone = timeZone }
        return f.string(from: date).uppercased()
    }

    private static func relativeDays(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: Date())).day ?? 0
        if days <= 0 { return "TODAY" }
        if days == 1 { return "1D AGO" }
        return "\(days)D AGO"
    }
}

// MARK: - Empty state + end marker

struct BooksLedgerEmpty: View {
    let value: String
    let label: String
    let hint: String
    var ctaTitle: String? = nil
    var onCreate: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.custom("Mohave-Light", size: 40))
                .foregroundColor(OPSStyle.Colors.text3)
            Text("// \(label)")
                .font(.custom("JetBrainsMono-Regular", size: 10))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.textMute)
                .padding(.top, OPSStyle.Layout.spacing2)
            Text("[ \(hint) ]")
                .font(.custom("JetBrainsMono-Regular", size: 10))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text3)
                .padding(.top, OPSStyle.Layout.spacing2_5)
                .multilineTextAlignment(.center)
            if let ctaTitle, let onCreate {
                Button(action: { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); onCreate() }) {
                    Text(ctaTitle)
                        .font(OPSStyle.Typography.buttonLabel)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.opsAccent)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.vertical, 11)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                .strokeBorder(OPSStyle.Colors.opsAccent, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, OPSStyle.Layout.spacing3 + 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, OPSStyle.Layout.spacing4)
        .padding(.top, 44)
        .padding(.bottom, 30)
    }
}

struct BooksLedgerEndMarker: View {
    let text: String
    var body: some View {
        Text("// END · \(text)")
            .font(.custom("JetBrainsMono-Regular", size: 9))
            .tracking(1.8)
            .textCase(.uppercase)
            .foregroundColor(OPSStyle.Colors.textMute)
            .frame(maxWidth: .infinity)
            .padding(.vertical, OPSStyle.Layout.spacing3)
    }
}
