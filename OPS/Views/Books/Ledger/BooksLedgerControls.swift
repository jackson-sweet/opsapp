//
//  BooksLedgerControls.swift
//  OPS
//
//  Money & Leads redesign (2026-06-30) — the Money tab's sticky ledger control
//  band: the 3-segment ledger switch (INVOICES · ESTIMATES · EXPENSES) and the
//  per-ledger filter model that drives the tone-tinted chip row.
//
//  Books owns the filter state (not the embedded VMs) so the design's filter
//  SETS can differ from each list's standalone filter — e.g. estimates filter
//  ALL · OUT · WON here, but the standalone EstimatesListView keeps its own
//  ALL · DRAFT · SENT · APPROVED. The underlying data is still the shared VM's.
//

import SwiftUI

// MARK: - Invoice filter (ALL · UNPAID · OVERDUE · PAID)

enum BooksInvoiceFilter: String, CaseIterable, Identifiable {
    case all, unpaid, overdue, paid
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "ALL"
        case .unpaid: return "UNPAID"
        case .overdue: return "OVERDUE"
        case .paid: return "PAID"
        }
    }

    var tone: Color? {
        switch self {
        case .overdue: return OPSStyle.Colors.rose
        case .paid: return OPSStyle.Colors.olive
        default: return nil
        }
    }

    func matches(_ invoice: Invoice) -> Bool {
        switch self {
        case .all: return true
        case .unpaid: return invoice.status.needsPayment
        case .overdue: return invoice.isOverdue
        case .paid: return invoice.status.isPaid
        }
    }

    static func chips(from invoices: [Invoice]) -> [TacticalChip] {
        allCases.map { f in
            TacticalChip(id: f.rawValue, label: f.label, count: invoices.filter(f.matches).count, tone: f.tone)
        }
    }
}

// MARK: - Estimate filter (ALL · OUT · WON)

enum BooksEstimateFilter: String, CaseIterable, Identifiable {
    case all, out, won
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "ALL"
        case .out: return "OUT"
        case .won: return "WON"
        }
    }

    var tone: Color? {
        switch self {
        case .out: return OPSStyle.Colors.opsAccent
        case .won: return OPSStyle.Colors.olive
        default: return nil
        }
    }

    func matches(_ estimate: Estimate) -> Bool {
        switch self {
        case .all: return true
        case .out: return [.sent, .viewed, .approved].contains(estimate.status)
        case .won: return estimate.status == .converted
        }
    }

    static func chips(from estimates: [Estimate]) -> [TacticalChip] {
        allCases.map { f in
            TacticalChip(id: f.rawValue, label: f.label, count: estimates.filter(f.matches).count, tone: f.tone)
        }
    }
}

// MARK: - Expense filter (ALL · NO RECEIPT · NEEDS OK)

enum BooksExpenseFilter: String, CaseIterable, Identifiable {
    case all, noReceipt, needsOk
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "ALL"
        case .noReceipt: return "NO RECEIPT"
        case .needsOk: return "NEEDS OK"
        }
    }

    var tone: Color? {
        switch self {
        case .noReceipt: return OPSStyle.Colors.rose
        case .needsOk: return OPSStyle.Colors.tan
        default: return nil
        }
    }

    func matches(_ expense: ExpenseDTO) -> Bool {
        switch self {
        case .all: return true
        case .noReceipt: return (expense.receiptImageUrl?.isEmpty ?? true)
        case .needsOk: return ExpenseStatus(rawValue: expense.status) == .submitted
        }
    }

    static func chips(from expenses: [ExpenseDTO]) -> [TacticalChip] {
        allCases.map { f in
            TacticalChip(id: f.rawValue, label: f.label, count: expenses.filter(f.matches).count, tone: f.tone)
        }
    }
}

// MARK: - Ledger segment control

/// The inset-pill 3-segment switch (INVOICES · ESTIMATES · EXPENSES). Neutral
/// active fill — no accent on toggles (DESIGN.md §9). Same visual the Books
/// hero-carousel build shipped; lifted into a reusable component.
struct BooksLedgerSegments: View {
    let segments: [BooksSection]
    @Binding var selected: BooksSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                let isActive = selected == segment
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) { selected = segment }
                } label: {
                    Text(segment.rawValue)
                        .font(.custom("JetBrainsMono-Medium", size: 10.5))
                        .tracking(1.68)
                        .textCase(.uppercase)
                        .foregroundColor(isActive ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(activeBackground(isActive))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(segment.rawValue) ledger\(isActive ? ", selected" : "")")
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .strokeBorder(OPSStyle.Colors.lineSoft, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func activeBackground(_ isActive: Bool) -> some View {
        if isActive {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 3).fill(OPSStyle.Colors.line)
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 1)
                    .padding(.horizontal, 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
        } else {
            Color.clear
        }
    }
}
