//
//  LeadsSummary.swift
//  OPS
//
//  Money & Leads redesign (2026-06-30) — the Leads tab summary block above the
//  chase queue: a bare weighted-forecast hero, a stage-distribution bar, three
//  triage count tiles (overdue / due today / waiting), and a velocity readout.
//  All values come straight off `PipelineViewModel`.
//

import SwiftUI

struct LeadsSummary: View {
    let viewModel: PipelineViewModel

    private static let openStages: [PipelineStage] = [.newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            forecastHero
            stageBar.padding(.top, OPSStyle.Layout.spacing3)
            triageTiles.padding(.top, OPSStyle.Layout.spacing3)
            velocityLine.padding(.top, OPSStyle.Layout.spacing2_5)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    // MARK: Forecast hero

    private var forecastHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("// ").foregroundColor(OPSStyle.Colors.textMute)
                Text("WEIGHTED PIPELINE · 30D").foregroundColor(OPSStyle.Colors.text3)
            }
            .font(.custom("JetBrainsMono-Medium", size: 10))
            .tracking(1.4)
            .textCase(.uppercase)

            CountUpText(
                target: viewModel.weightedForecastValue,
                font: .custom("Mohave-Light", size: 52),
                color: OPSStyle.Colors.text
            )
            .padding(.top, OPSStyle.Layout.spacing1 + 2)

            if let delta = viewModel.forecastDeltaPct {
                deltaLine(delta)
                    .padding(.top, OPSStyle.Layout.spacing1 + 3)
            }
        }
    }

    @ViewBuilder
    private func deltaLine(_ pct: Double) -> some View {
        let up = pct >= 0
        let color = up ? OPSStyle.Colors.oliveTextM : OPSStyle.Colors.roseTextM
        // Derive the absolute change from the % so the line reads like the design.
        let prior = pct == -100 ? 0 : viewModel.weightedForecastValue / (1 + pct / 100)
        let change = viewModel.weightedForecastValue - prior
        HStack(spacing: 0) {
            Text("\(up ? "↑" : "↓") \(abs(Int(pct.rounded())))% · \(up ? "+" : "")\(BooksFormat.compact(change))")
                .foregroundColor(color)
            Text("  VS PRIOR")
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .font(.custom("JetBrainsMono-Regular", size: 11))
        .tracking(0.4)
        .monospacedDigit()
    }

    // MARK: Stage distribution bar

    private var stageBar: some View {
        let counts = Self.openStages.map { (stage: $0, count: viewModel.count(in: $0)) }
        let total = max(counts.reduce(0) { $0 + $1.count }, 1)
        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(counts.enumerated()), id: \.offset) { _, item in
                    let width = item.count > 0
                        ? max(geo.size.width * CGFloat(item.count) / CGFloat(total) - 2, 6)
                        : 0
                    if width > 0 {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(OPSStyle.Colors.pipelineStageColor(for: item.stage))
                            .frame(width: width)
                    }
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    // MARK: Triage tiles

    private var triageTiles: some View {
        let buckets = viewModel.triageBuckets
        return HStack(spacing: OPSStyle.Layout.spacing2) {
            triageTile(count: buckets.overdue.count, label: "OVERDUE", tone: OPSStyle.Colors.rose)
            triageTile(count: buckets.dueToday.count, label: "DUE TODAY", tone: OPSStyle.Colors.tan)
            triageTile(count: viewModel.waitingCount, label: "WAITING", tone: nil)
        }
    }

    private func triageTile(count: Int, label: String, tone: Color?) -> some View {
        let active = count > 0 && tone != nil
        let valueColor = active ? tone! : OPSStyle.Colors.text2
        return VStack(spacing: OPSStyle.Layout.spacing1) {
            Text("\(count)")
                .font(.custom("JetBrainsMono-Medium", size: 18))
                .foregroundColor(valueColor)
                .monospacedDigit()
            Text(label)
                .font(.custom("JetBrainsMono-Medium", size: 8.5))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundColor(active ? tone! : OPSStyle.Colors.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous)
            .fill(active ? tone!.opacity(0.10) : OPSStyle.Colors.surfaceInput))
        .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous)
            .strokeBorder(active ? tone!.opacity(0.32) : OPSStyle.Colors.line, lineWidth: 1))
    }

    // MARK: Velocity

    private var velocityLine: some View {
        var parts = ["\(viewModel.openLeadCount) OPEN"]
        if let v = viewModel.avgVelocityDays() { parts.append("AVG VELOCITY \(v)D / STAGE") }
        return Text(parts.joined(separator: " · "))
            .font(.custom("JetBrainsMono-Regular", size: 10))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundColor(OPSStyle.Colors.text3)
            .monospacedDigit()
    }
}
