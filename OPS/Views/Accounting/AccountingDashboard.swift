//
//  AccountingDashboard.swift
//  OPS
//
//  Read-only financial health overview — AR aging, invoice status, top outstanding clients.
//

import SwiftUI
import Charts

struct AccountingDashboard: View {
    @EnvironmentObject private var dataController: DataController

    @State private var invoices: [Invoice] = []
    @State private var isLoading = true

    private var agingBuckets: [ARAgingBucket] {
        computeAgingBuckets(from: invoices)
    }

    private var statusCounts: StatusCounts {
        computeStatusCounts(from: invoices)
    }

    private var topOutstanding: [(name: String, amount: Double)] {
        computeTopOutstanding(from: invoices)
    }

    var body: some View {
        if isLoading {
            VStack {
                Spacer()
                TacticalLoadingBarAnimated()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OPSStyle.Colors.background)
            .task { await loadData() }
        } else {
            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing4) {
                    agingSection
                    statusSection
                    outstandingSection
                }
                .padding(.top, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing4)
            }
            .background(OPSStyle.Colors.background)
            .refreshable { await loadData() }
        }
    }

    // MARK: - AR Aging

    private var agingSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("AR AGING")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            if agingBuckets.allSatisfy({ $0.amount == 0 }) {
                Text("No outstanding invoices")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
            } else {
                Chart(agingBuckets) { bucket in
                    BarMark(
                        x: .value("Amount", bucket.amount),
                        y: .value("Period", bucket.label)
                    )
                    .foregroundStyle(bucket.color)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(bucket.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundStyle(OPSStyle.Colors.secondaryText)
                    }
                }
                .frame(height: 160)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
        }
    }

    // MARK: - Status Tiles

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("INVOICE STATUS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: OPSStyle.Layout.spacing2) {
                statusTile(count: statusCounts.awaiting, label: "AWAITING", color: OPSStyle.Colors.warningStatus)
                statusTile(count: statusCounts.overdue, label: "OVERDUE", color: OPSStyle.Colors.errorStatus)
                statusTile(count: statusCounts.paid, label: "PAID", color: OPSStyle.Colors.successStatus)
                amountTile(amount: statusCounts.outstanding, label: "OUTSTAND.", color: OPSStyle.Colors.primaryAccent)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    private func statusTile(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(OPSStyle.Typography.title)
                .foregroundColor(color)
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func amountTile(amount: Double, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(OPSStyle.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Top Outstanding

    private var outstandingSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("TOP OUTSTANDING")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            if topOutstanding.isEmpty {
                Text("No outstanding balances")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(topOutstanding.enumerated()), id: \.offset) { idx, entry in
                        HStack {
                            Text(entry.name)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .lineLimit(1)
                            Spacer()
                            Text(entry.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)

                        if idx < topOutstanding.count - 1 {
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
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let companyId = dataController.currentUser?.companyId else {
            isLoading = false
            return
        }
        let repo = AccountingRepository(companyId: companyId)
        do {
            let dtos = try await repo.fetchAllInvoices()
            invoices = dtos.map { $0.toModel() }
        } catch {
            // Silently fail — dashboard shows empty state
        }
        isLoading = false
    }

    // MARK: - Computations

    struct ARAgingBucket: Identifiable {
        let id = UUID()
        let label: String
        let amount: Double
        let color: Color
    }

    struct StatusCounts {
        var awaiting: Int = 0
        var overdue: Int = 0
        var paid: Int = 0
        var outstanding: Double = 0
    }

    private func computeAgingBuckets(from invoices: [Invoice]) -> [ARAgingBucket] {
        let today = Date()
        var b0_30: Double = 0
        var b31_60: Double = 0
        var b61_90: Double = 0
        var b90plus: Double = 0

        for inv in invoices where inv.balanceDue > 0 && inv.status != .void {
            guard let due = inv.dueDate else { continue }
            let days = Int(today.timeIntervalSince(due) / 86400)
            if days < 0 { continue } // not yet due
            switch days {
            case 0...30:  b0_30 += inv.balanceDue
            case 31...60: b31_60 += inv.balanceDue
            case 61...90: b61_90 += inv.balanceDue
            default:      b90plus += inv.balanceDue
            }
        }

        return [
            ARAgingBucket(label: "0-30d", amount: b0_30, color: OPSStyle.Colors.primaryAccent),
            ARAgingBucket(label: "31-60d", amount: b31_60, color: OPSStyle.Colors.primaryAccent),
            ARAgingBucket(label: "61-90d", amount: b61_90, color: OPSStyle.Colors.warningStatus),
            ARAgingBucket(label: "90d+", amount: b90plus, color: OPSStyle.Colors.errorStatus),
        ]
    }

    private func computeStatusCounts(from invoices: [Invoice]) -> StatusCounts {
        var counts = StatusCounts()
        for inv in invoices where inv.status != .void {
            if inv.status == .paid { counts.paid += 1 }
            else if inv.isOverdue { counts.overdue += 1 }
            else if inv.status.needsPayment || inv.status == .sent { counts.awaiting += 1 }
            counts.outstanding += inv.balanceDue
        }
        return counts
    }

    private func computeTopOutstanding(from invoices: [Invoice]) -> [(name: String, amount: Double)] {
        var clientTotals: [String: Double] = [:]
        for inv in invoices where inv.balanceDue > 0 && inv.status != .void {
            let key = inv.clientId ?? "Unknown"
            clientTotals[key, default: 0] += inv.balanceDue
        }
        return clientTotals
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (name: $0.key, amount: $0.value) }
    }
}
