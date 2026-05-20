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
//      OVERDUE      DUE TODAY    OPEN
//      04           03           17
//      NEEDS NOW    FOLLOW UP    03 WAITING
//
//  Per ops-design-system mobile/MOBILE.md § 5 (Hero carousel) — but rendered
//  as a single card here, not a carousel. The carousel pattern (5 KPI tiles)
//  was the prototype that we replaced in this rebuild.
//
//  The forecast-delta line is hidden until the data pipeline is wired up
//  (plan §2.1 decision Q1 = option a).
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

    /// Tap target — opens a future ForecastBreakdownSheet. nil disables the tap.
    var onForecastTap: (() -> Void)? = nil

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onForecastTap?()
        } label: {
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
                    .padding(.top, 12)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()
        }
        .buttonStyle(PlainButtonStyle())
        .allowsHitTesting(onForecastTap != nil)
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
        HStack(spacing: 4) {
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
        VStack(spacing: 20) {
            HeroWidget(
                forecastValue: 184_240,
                forecastDeltaPct: nil,        // delta line hidden per plan Q1 = (a)
                overdueCount: 4,
                dueTodayCount: 3,
                openLeadCount: 17,
                waitingCount: 3,
                onForecastTap: {}
            )
            HeroWidget(
                forecastValue: 0,
                forecastDeltaPct: nil,
                overdueCount: 0,
                dueTodayCount: 0,
                openLeadCount: 0,
                waitingCount: 0
            )
        }
        .padding(.horizontal, 20)
    }
    .preferredColorScheme(.dark)
}
#endif
