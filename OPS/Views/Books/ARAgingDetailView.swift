//
//  ARAgingDetailView.swift
//  OPS
//
//  Drill-down from the SmartStatCarousel "OVERDUE" tap. Shows AR aging
//  buckets + top outstanding clients. Replaces the orphan AccountingDashboard.
//

import SwiftUI
import Charts

struct ARAgingDetailView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var invoices: [Invoice] = []
    @State private var clientNames: [String: String] = [:]
    @State private var isLoading = true
    @State private var loadError: String?

    private struct Bucket: Identifiable {
        let id = UUID()
        let label: String
        let amount: Double
        let color: Color
    }

    private var buckets: [Bucket] {
        let today = Date()
        var b0_30: Double = 0
        var b31_60: Double = 0
        var b61_90: Double = 0
        var b90: Double = 0
        for inv in invoices where inv.balanceDue > 0 && inv.status != .void {
            guard let due = inv.dueDate else { continue }
            let days = Int(today.timeIntervalSince(due) / 86400)
            if days < 0 { continue }
            switch days {
            case 0...30: b0_30 += inv.balanceDue
            case 31...60: b31_60 += inv.balanceDue
            case 61...90: b61_90 += inv.balanceDue
            default: b90 += inv.balanceDue
            }
        }
        return [
            Bucket(label: "0–30d", amount: b0_30, color: OPSStyle.Colors.accountingReceivables),
            Bucket(label: "31–60d", amount: b31_60, color: OPSStyle.Colors.accountingReceivables),
            Bucket(label: "61–90d", amount: b61_90, color: OPSStyle.Colors.warningStatus),
            Bucket(label: "90d+", amount: b90, color: OPSStyle.Colors.accountingOverdue)
        ]
    }

    private var topOutstanding: [(name: String, amount: Double)] {
        var totals: [String: Double] = [:]
        for inv in invoices where inv.balanceDue > 0 && inv.status != .void {
            let key = inv.clientId ?? "Unknown"
            totals[key, default: 0] += inv.balanceDue
        }
        return totals
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (name: clientNames[$0.key] ?? "Unknown", amount: $0.value) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                if isLoading {
                    TacticalLoadingBarAnimated()
                        .task { await load() }
                } else if let error = loadError {
                    errorView(error)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                            agingChartSection
                            topOutstandingSection
                        }
                        .padding(OPSStyle.Layout.spacing3)
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("AR AGING")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("DONE") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }

    private var agingChartSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("AGING BUCKETS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            if buckets.allSatisfy({ $0.amount == 0 }) {
                Text("No outstanding invoices")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                Chart(buckets) { b in
                    BarMark(
                        x: .value("Amount", b.amount),
                        y: .value("Period", b.label)
                    )
                    .foregroundStyle(b.color)
                    .annotation(position: .trailing) {
                        Text(b.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 180)
            }
        }
    }

    private var topOutstandingSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("TOP OUTSTANDING")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            if topOutstanding.isEmpty {
                Text("No outstanding balances")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
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
                            Divider().background(OPSStyle.Colors.cardBorder)
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
            }
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(OPSStyle.Icons.alert)
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.warningStatus)
            Text("COULD NOT LOAD AR DATA")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text(msg)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Button("RETRY") { Task { await load() } }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
        }
        .padding(OPSStyle.Layout.spacing4)
    }

    private func load() async {
        guard let companyId = dataController.currentUser?.companyId else {
            isLoading = false
            return
        }
        loadError = nil
        let repo = AccountingRepository(companyId: companyId)
        do {
            let dtos = try await repo.fetchAllInvoices()
            invoices = dtos.map { $0.toModel() }
            buildClientLookup()
        } catch {
            if !error.isCancellation { loadError = error.localizedDescription }
        }
        isLoading = false
    }

    private func buildClientLookup() {
        guard let companyId = dataController.currentUser?.companyId else { return }
        let clients = dataController.getAllClients(for: companyId)
        clientNames = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0.displayName) })
    }
}
