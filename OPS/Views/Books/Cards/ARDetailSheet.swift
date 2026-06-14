//
//  ARDetailSheet.swift
//  OPS
//
//  Books P6 — UX overhaul. The merged A/R detail shown when the A/R condensed
//  card expands. One rich sheet (owner decision 2026-06-01): the full A/R card
//  (hero + aging ramp + bucket grid + top-chase) on top, the per-client
//  top-outstanding list below — folding in the unique content of the former
//  standalone AR aging detail so TOP CHASE scrolls in-place instead of stacking
//  a second sheet.
//
//  Spec: docs/superpowers/specs/2026-06-01-books-condensed-cards-ux-overhaul-design.md
//

import SwiftUI

struct ARDetailSheet: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    @EnvironmentObject private var dataController: DataController

    @State private var invoices: [Invoice] = []
    @State private var clientNames: [String: String] = [:]
    @State private var isLoadingClients = true

    private let chaseAnchor = "ar-top-outstanding"

    /// Per-client outstanding totals, top 5 — the genuinely-additive content the
    /// aging ramp/buckets don't surface.
    private var topOutstanding: [(name: String, amount: Double)] {
        var totals: [String: Double] = [:]
        for inv in invoices where inv.balanceDue > 0 && inv.status != .void {
            totals[inv.clientId ?? "Unknown", default: 0] += inv.balanceDue
        }
        return totals
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (name: clientNames[$0.key] ?? "Unknown", amount: $0.value) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                    // Full A/R card — TOP CHASE scrolls to the client list rather
                    // than presenting a second sheet.
                    ARCard(
                        viewModel: viewModel,
                        style: .full,
                        onTapTopChase: {
                            withAnimation(OPSStyle.Animation.page) {
                                proxy.scrollTo(chaseAnchor, anchor: .top)
                            }
                        }
                    )

                    topOutstandingSection
                        .id(chaseAnchor)
                }
                .padding(.vertical, OPSStyle.Layout.spacing3)
            }
        }
        .task { await loadClients() }
    }

    // MARK: - Top-outstanding client list

    private var topOutstandingSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text("//").foregroundColor(OPSStyle.Colors.textMute)
                Text("TOP OUTSTANDING").foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .font(.custom("JetBrainsMono-Medium", size: 10))
            .tracking(1.6)
            .textCase(.uppercase)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            if isLoadingClients {
                HStack {
                    Spacer()
                    ProgressView().tint(OPSStyle.Colors.tertiaryText)
                    Spacer()
                }
                .frame(height: 64)
            } else if topOutstanding.isEmpty {
                Text("// NO OUTSTANDING BALANCES")
                    .font(.custom("JetBrainsMono-Medium", size: 11))
                    .tracking(1.32)
                    .foregroundColor(OPSStyle.Colors.inactiveText)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(topOutstanding.enumerated()), id: \.offset) { idx, entry in
                        HStack {
                            Text(entry.name)
                                .font(.custom("Mohave-Medium", size: 15))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .lineLimit(1)
                            Spacer(minLength: OPSStyle.Layout.spacing3)
                            Text(entry.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                                .font(.custom("JetBrainsMono-Medium", size: 14))
                                .foregroundColor(OPSStyle.Colors.rose)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                        if idx < topOutstanding.count - 1 {
                            Rectangle()
                                .fill(OPSStyle.Colors.lineSoft)
                                .frame(height: 1)
                                .padding(.leading, OPSStyle.Layout.spacing3)
                        }
                    }
                }
                .background(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius)
                        .stroke(OPSStyle.Colors.glassBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius))
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }
        }
    }

    private func loadClients() async {
        guard let companyId = dataController.currentUser?.companyId else {
            isLoadingClients = false
            return
        }
        let repo = AccountingRepository(companyId: companyId)
        do {
            let dtos = try await repo.fetchAllInvoices()
            invoices = dtos.map { $0.toModel() }
            let clients = dataController.getAllClients(for: companyId)
            clientNames = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0.displayName) })
        } catch {
            // Non-fatal — the card hero/ramp/buckets still render from the VM.
        }
        isLoadingClients = false
    }
}
