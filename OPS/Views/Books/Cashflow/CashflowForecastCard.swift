//
//  CashflowForecastCard.swift
//  OPS
//
//  Books — RUNWAY lens. The condensed cash-flow forecast face that rides in the
//  hero carousel (folded in 2026-06-29, replacing the standalone below-carousel
//  card so the carousel stays the single top-level KPI surface). Headline =
//  projected ending balance, signature viz = the runway sparkline, sub-stat =
//  the low-water point. Tap expands to the full CashflowForecastScreen.
//

import SwiftUI

struct CashForecastCard: View {
    @ObservedObject var viewModel: CashflowForecastViewModel
    @State private var presentFull = false

    private var state: ForecastState { viewModel.result?.state ?? .healthy }

    /// Hero number color tracks forecast health — white when on track, amber on
    /// a low-water watch, rose when a week dips below zero.
    private var heroColor: Color {
        switch state {
        case .healthy:  return OPSStyle.Colors.primaryText
        case .lowWater: return OPSStyle.Colors.tanMobile
        case .danger:   return OPSStyle.Colors.rose
        }
    }

    private var lineColor: Color {
        switch state {
        case .healthy:  return OPSStyle.Colors.primaryAccent
        case .lowWater: return OPSStyle.Colors.tanMobile
        case .danger:   return OPSStyle.Colors.rose
        }
    }

    var body: some View {
        CondensedHeroCard(
            caption: "RUNWAY",
            heroText: heroText,
            heroColor: heroColor,
            onExpand: { presentFull = true },
            viz: { vizContent },
            subStat: { subStatContent }
        )
        .fullScreenCover(isPresented: $presentFull) {
            CashflowForecastScreen(viewModel: viewModel)
        }
        .task { if viewModel.result == nil { await viewModel.load() } }
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var vizContent: some View {
        if let r = viewModel.result {
            CashflowSparkline(weeks: r.weeks, lineColor: lineColor, threshold: r.lowWaterThreshold)
        } else {
            Rectangle().fill(Color.clear)
        }
    }

    @ViewBuilder
    private var subStatContent: some View {
        if let r = viewModel.result {
            Text("LOW \(currency(r.lowestBalance)) · WK \(r.lowestWeekIndex + 1)")
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .tracking(0.44)
                .foregroundColor(state == .danger ? OPSStyle.Colors.rose : OPSStyle.Colors.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
        } else {
            Text("// TAP TO SET BALANCE")
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .tracking(1.76)
                .foregroundColor(OPSStyle.Colors.inactiveText)
                .lineLimit(1)
        }
    }

    private var heroText: String {
        guard let r = viewModel.result else { return "—" }
        return currency(r.endingBalance)
    }

    private var accessibilityLabel: String {
        guard let r = viewModel.result else {
            return "Cash runway. Tap to set current balance."
        }
        return "Cash runway. Projected balance \(currency(r.endingBalance)). Low point \(currency(r.lowestBalance)) in week \(r.lowestWeekIndex + 1)."
    }

    private func currency(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}

/// Compact sparkline (no markers, no axis labels). Visual cue only.
struct CashflowSparkline: View {
    let weeks: [WeeklyProjection]
    let lineColor: Color
    let threshold: Double

    var body: some View {
        GeometryReader { geo in
            let points = computePoints(in: geo.size)
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for p in points.dropFirst() { path.addLine(to: p) }
            }
            .stroke(lineColor, lineWidth: 1.5)
        }
    }

    private func computePoints(in size: CGSize) -> [CGPoint] {
        guard !weeks.isEmpty else { return [] }
        let yValues = weeks.map { $0.balance }
        let minY = min(0, yValues.min() ?? 0)
        let maxY = max(yValues.max() ?? 1, threshold)
        let range = (maxY - minY) == 0 ? 1 : (maxY - minY)
        let stepX = size.width / CGFloat(max(weeks.count - 1, 1))
        return weeks.enumerated().map { i, w in
            let xRaw = CGFloat(i) * stepX
            let yRatio = CGFloat((w.balance - minY) / range)
            return CGPoint(x: xRaw, y: size.height - (yRatio * size.height))
        }
    }
}

#if DEBUG
#Preview("CashForecastCard — RUNWAY lens") {
    CashForecastCard(viewModel: CashflowForecastViewModel())
        .padding(.vertical, OPSStyle.Layout.spacing4)
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
}
#endif
