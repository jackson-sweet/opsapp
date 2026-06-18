//
//  HeroWidget.swift
//  OPS
//
//  The "WEIGHTED FORECAST + 3 SUB-METRIC" hero card at the top of the LEADS
//  triage screen. One L1 glass surface containing:
//
//      // WEIGHTED FORECAST · 30D                     ↑ 12% VS PRIOR
//      $184,240                                       ← Mohave Light 38pt
//      ─────────────────────────────────────────────
//      OVERDUE      DUE TODAY    OPEN         VELOCITY
//      04           03           17           18D
//      NEEDS NOW    FOLLOW UP    03 WAITING   90D AVG
//
//  Per ops-design-system mobile/MOBILE.md § 5 (Hero carousel) — but rendered
//  as a single card here, not a carousel. The carousel pattern (5 KPI tiles)
//  was the prototype that we replaced in this rebuild.
//
//  The forecast-delta line surfaces when the VM passes a non-nil
//  `forecastDeltaPct` (LEADS polish P1-3 — was hidden behind the plan §2.1
//  Q1 deferred decision). The VELOCITY column surfaces only when there are
//  ≥5 wins in the trailing 90D — same nil-on-low-N idiom as `closeRate`.
//

import SwiftUI

struct HeroWidget: View {
    let forecastValue: Double
    /// Optional positive/negative percent delta vs prior period. nil hides the line.
    let forecastDeltaPct: Double?

    let overdueCount: Int
    let dueTodayCount: Int
    let openLeadCount: Int
    let waitingCount: Int

    /// Average days new → won across the last 90D. nil hides the 4th column.
    /// Gating is the caller's responsibility (per `PipelineViewModel.avgVelocityDays`
    /// — nil when fewer than 5 qualifying wins).
    var avgVelocityDays: Int? = nil

    /// Tap target — opens a future breakdown drill-in (deferred). nil disables the tap.
    var onForecastTap: (() -> Void)? = nil

    var body: some View {
        if let onForecastTap {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onForecastTap()
            } label: { cardContent }
            .buttonStyle(PlainButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Opens the forecast breakdown")
        } else {
            // No tap handler in the shipped LEADS tab — render as a plain
            // container, not a no-op Button, so VoiceOver doesn't announce a
            // dead "button" and reads the hero as one stat line. (review W-1)
            cardContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text(forecastDisplay)
                .font(.custom("Mohave-Light", size: 38))
                .foregroundColor(OPSStyle.Colors.text)
                .monospacedDigit()
                .padding(.top, 6)

            hairline
                .padding(.top, 14)

            metaRow
                .padding(.top, OPSStyle.Layout.spacing2_5)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }

    /// Composed VoiceOver label so the hero reads as one coherent stat line
    /// rather than ~8 disjoint fragments (forecast, delta, each sub-metric
    /// label/value/hint read separately). (review W-1)
    private var accessibilityLabel: String {
        var parts: [String] = ["Weighted forecast, 30 days, \(forecastDisplay)"]
        if let delta = forecastDeltaPct {
            let pct = Int(delta.rounded())
            if pct > 0      { parts.append("up \(pct) percent versus prior") }
            else if pct < 0 { parts.append("down \(abs(pct)) percent versus prior") }
            else            { parts.append("flat versus prior") }
        }
        parts.append("\(overdueCount) overdue")
        parts.append("\(dueTodayCount) due today")
        parts.append("\(openLeadCount) open, \(waitingCount) waiting")
        if let velocity = avgVelocityDays { parts.append("velocity \(velocity) days") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Pieces

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("WEIGHTED FORECAST · 30D")
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .font(OPSStyle.Typography.metadata)
            .kerning(1.6)
            .textCase(.uppercase)

            Spacer()

            if let delta = forecastDeltaPct {
                deltaChip(delta: delta)
            }
        }
    }

    @ViewBuilder
    private func deltaChip(delta: Double) -> some View {
        let pct = Int(delta.rounded())
        let isUp = pct > 0
        let isFlat = pct == 0
        let color: Color = isFlat
            ? OPSStyle.Colors.text3
            : (isUp ? OPSStyle.Colors.oliveTextM : OPSStyle.Colors.roseTextM)
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Image(systemName: isFlat ? "minus" : (isUp ? "arrow.up" : "arrow.down"))
                .font(.system(size: 9, weight: .semibold))
            Text("\(abs(pct))% VS PRIOR")
                .font(OPSStyle.Typography.metadata)
                .fontWeight(.semibold)
                .kerning(1.0)
                .textCase(.uppercase)
        }
        .foregroundColor(color)
    }

    private var hairline: some View {
        Rectangle()
            .fill(OPSStyle.Colors.line)
            .frame(height: 1)
    }

    private var metaRow: some View {
        HStack(alignment: .top, spacing: 14) {
            SubMetric(
                label: "OVERDUE",
                value: String(format: "%02d", overdueCount),
                hint: overdueCount > 0 ? "NEEDS NOW" : "—",
                tone: overdueCount > 0 ? .rose : .neutral
            )
            SubMetric(
                label: "DUE TODAY",
                value: String(format: "%02d", dueTodayCount),
                hint: "FOLLOW UP",
                tone: dueTodayCount > 0 ? .tan : .neutral
            )
            SubMetric(
                label: "OPEN",
                value: String(format: "%02d", openLeadCount),
                hint: "\(String(format: "%02d", waitingCount)) WAITING",
                tone: .neutral
            )
            if let velocity = avgVelocityDays {
                SubMetric(
                    label: "VELOCITY",
                    value: "\(velocity)D",
                    hint: "90D AVG",
                    tone: .neutral
                )
            }
        }
    }

    // MARK: - Formatting

    private var forecastDisplay: String {
        if forecastValue == 0 { return "$0" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: forecastValue)) ?? "$0"
    }
}

#if DEBUG
#Preview("HeroWidget / loaded") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        VStack(spacing: OPSStyle.Layout.spacing3_5) {
            // Full data: delta + 4th velocity column.
            HeroWidget(
                forecastValue: 184_240,
                forecastDeltaPct: 12,
                overdueCount: 4,
                dueTodayCount: 3,
                openLeadCount: 17,
                waitingCount: 3,
                avgVelocityDays: 18,
                onForecastTap: {}
            )
            // Down delta, no velocity (not enough wins yet).
            HeroWidget(
                forecastValue: 92_500,
                forecastDeltaPct: -7,
                overdueCount: 1,
                dueTodayCount: 2,
                openLeadCount: 9,
                waitingCount: 2,
                avgVelocityDays: nil,
                onForecastTap: {}
            )
            // Empty pipeline.
            HeroWidget(
                forecastValue: 0,
                forecastDeltaPct: nil,
                overdueCount: 0,
                dueTodayCount: 0,
                openLeadCount: 0,
                waitingCount: 0,
                avgVelocityDays: nil
            )
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }
    .preferredColorScheme(.dark)
}
#endif
