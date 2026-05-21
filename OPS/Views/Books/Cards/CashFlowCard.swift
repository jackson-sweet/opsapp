//
//  CashFlowCard.swift
//  OPS
//
//  Books Phase 3 (Mission Deck) — Card 2 of the hero carousel.
//  Sparkline of weekly net cash with bad-week markers (any week where out > in).
//  "What's my cash rhythm?"
//
//  Spec: docs/superpowers/specs/2026-05-19-books-tab-mission-deck-rebuild.md § 5.2
//

import SwiftUI

struct CashFlowCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapDays: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct WeekPoint: Identifiable {
        var id: Date { weekStart }
        let weekStart: Date
        let net: Double
        let isBad: Bool   // outAmount > inAmount — rose marker (Q1 expansion)
    }

    // MARK: - Derived

    private var weeks: [WeekPoint] {
        let inDict = Dictionary(uniqueKeysWithValues: viewModel.paymentsByWeek.map { ($0.weekStart, $0.amount) })
        let outDict = Dictionary(uniqueKeysWithValues: viewModel.expensesByWeek.map { ($0.weekStart, $0.amount) })
        let allWeeks = Set(inDict.keys).union(outDict.keys).sorted()
        return allWeeks.map { ws in
            let inAmt = inDict[ws] ?? 0
            let outAmt = outDict[ws] ?? 0
            return WeekPoint(weekStart: ws, net: inAmt - outAmt, isBad: outAmt > inAmt)
        }
    }

    /// Mean of in-flow across weeks with payments recorded. Matches the prior
    /// AVG/WK semantic ("average paying week").
    private var avgPerWeek: Double {
        let withInflow = viewModel.paymentsByWeek.filter { $0.amount > 0 }
        guard !withInflow.isEmpty else { return 0 }
        return withInflow.map { $0.amount }.reduce(0, +) / Double(withInflow.count)
    }

    private var isEmpty: Bool {
        viewModel.paymentsByWeek.isEmpty && viewModel.expensesByWeek.isEmpty
    }

    private var isSkeleton: Bool {
        !viewModel.hasEverLoaded && viewModel.isLoading
    }

    /// Composed VoiceOver summary for the whole card (spec § 8.1, Card 2).
    private var accessibilityCardLabel: String {
        "Cash flow. Net cash \(viewModel.netCash.formatted(.currency(code: "USD").precision(.fractionLength(0)))) over \(weeks.count) weeks. \(compactCurrency(avgPerWeek)) per week average."
    }

    // MARK: - Body

    var body: some View {
        if isSkeleton {
            skeletonView.padding(.horizontal, OPSStyle.Layout.spacing3_5)
        } else if viewModel.cardError(.cashFlow) {
            BooksCardError(onRetry: { Task { await viewModel.retry(.cashFlow) } })
        } else if isEmpty {
            emptyView.padding(.horizontal, OPSStyle.Layout.spacing3_5)
        } else {
            normalBody.padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
    }

    // MARK: - Normal body

    private var normalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Non-tile content folded into one VoiceOver element (the § 8.1
            // card summary). The drill tiles below stay individually navigable.
            VStack(alignment: .leading, spacing: 0) {
                heroBlock
                sparkline.padding(.top, 22)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityCardLabel)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                BooksDrillTile(
                    label: "SALES",
                    value: compactCurrency(viewModel.totalSales),
                    sub: "TRAILING"
                )
                BooksDrillTile(
                    label: "AVG/WK",
                    value: compactCurrency(avgPerWeek),
                    sub: "PER WEEK",
                    valueColor: OPSStyle.Colors.olive
                )
                BooksDrillTile(
                    label: "DAYS",
                    value: String(format: "%.1f", viewModel.avgDaysToPayment),
                    sub: "TO PAY",
                    onTap: onTapDays,
                    accessibilityHint: "Double-tap for cash flow detail",
                    accessibilityLabelOverride: "Days to pay, \(String(format: "%.1f", viewModel.avgDaysToPayment)) days mean"
                )
            }
            .padding(.top, OPSStyle.Layout.spacing4)
        }
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NET CASH · \(weeks.count)W TRAILING")
                .font(.custom("JetBrainsMono-Medium", size: 10))
                .tracking(2.0)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text(viewModel.netCash, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(OPSStyle.Typography.heroNumber)
                .tracking(-1.5)
                .foregroundColor(viewModel.netCash >= 0 ? OPSStyle.Colors.primaryText : OPSStyle.Colors.rose)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)  // § 8.4 — hero number clamp
                .contentTransition(.numericText())
        }
    }

    // MARK: - Sparkline

    private var sparkline: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { _ in
                sparklineCanvas
            }
            .frame(height: 84)

            HStack {
                if let first = weeks.first {
                    Text(weekLabel(first.weekStart))
                        .font(.custom("JetBrainsMono-Regular", size: 8.5))
                        .tracking(0.85)
                        .foregroundColor(OPSStyle.Colors.inactiveText)
                        .monospacedDigit()
                }
                Spacer()
                if let last = weeks.last, weeks.count > 1 {
                    Text(weekLabel(last.weekStart))
                        .font(.custom("JetBrainsMono-Regular", size: 8.5))
                        .tracking(0.85)
                        .foregroundColor(OPSStyle.Colors.inactiveText)
                        .monospacedDigit()
                }
            }
        }
    }

    private var sparklineCanvas: some View {
        Canvas { context, size in
            guard !weeks.isEmpty else { return }

            let nets = weeks.map { $0.net }
            let rangeMin = min(nets.min() ?? 0, 0)
            let rangeMax = max(nets.max() ?? 0, 0)
            let range = max(rangeMax - rangeMin, 1)
            let n = weeks.count

            let dx: CGFloat = n > 1 ? size.width / CGFloat(n - 1) : 0
            func x(_ i: Int) -> CGFloat { n > 1 ? dx * CGFloat(i) : size.width / 2 }
            func y(_ net: Double) -> CGFloat {
                let frac = (rangeMax - net) / range
                return size.height * CGFloat(frac)
            }

            let points: [CGPoint] = weeks.enumerated().map { i, w in
                CGPoint(x: x(i), y: y(w.net))
            }

            // 1. Zero-axis hairline at the y where net = 0.
            let zeroY = y(0)
            var axis = Path()
            axis.move(to: CGPoint(x: 0, y: zeroY))
            axis.addLine(to: CGPoint(x: size.width, y: zeroY))
            context.stroke(axis, with: .color(OPSStyle.Colors.lineSoft), lineWidth: 1)

            // 2. Area fill below the line down to the bottom of the chart frame.
            if let first = points.first, let last = points.last {
                var area = Path()
                area.move(to: first)
                for p in points.dropFirst() { area.addLine(to: p) }
                area.addLine(to: CGPoint(x: last.x, y: size.height))
                area.addLine(to: CGPoint(x: first.x, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .color(OPSStyle.Colors.oliveSoft))
            }

            // 3. Line stroke through every point.
            if let first = points.first {
                var line = Path()
                line.move(to: first)
                for p in points.dropFirst() { line.addLine(to: p) }
                context.stroke(
                    line,
                    with: .color(OPSStyle.Colors.olive),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }

            // 4. Per-point dots — rose 3pt fill on bad weeks, bg-fill + olive 1.2pt
            //    stroke 2.5pt on normal weeks. Rule expanded per Q1 to every week
            //    where out > in, not just the worst.
            for (i, w) in weeks.enumerated() {
                let p = points[i]
                if w.isBad {
                    let r: CGFloat = 3
                    let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
                    context.fill(Path(ellipseIn: rect), with: .color(OPSStyle.Colors.rose))
                } else {
                    let r: CGFloat = 2.5
                    let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
                    context.fill(Path(ellipseIn: rect), with: .color(OPSStyle.Colors.background))
                    context.stroke(Path(ellipseIn: rect), with: .color(OPSStyle.Colors.olive), lineWidth: 1.2)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func weekLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date).uppercased()
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NET CASH")
                    .font(.custom("JetBrainsMono-Medium", size: 10))
                    .tracking(2.0)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text("$0")
                    .font(OPSStyle.Typography.heroNumber)
                    .tracking(-1.5)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .monospacedDigit()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)  // § 8.4 — hero number clamp
                Text("// NO PAYMENTS THIS PERIOD")
                    .font(.custom("JetBrainsMono-Medium", size: 11))
                    .tracking(1.76)
                    .foregroundColor(OPSStyle.Colors.inactiveText)
            }
            HStack(spacing: OPSStyle.Layout.spacing2) {
                BooksDrillTile(label: "SALES",  value: "$0", sub: "TRAILING",  valueColor: OPSStyle.Colors.tertiaryText)
                BooksDrillTile(label: "AVG/WK", value: "$0", sub: "PER WEEK",  valueColor: OPSStyle.Colors.tertiaryText)
                BooksDrillTile(label: "DAYS",   value: "—",  sub: "TO PAY",    valueColor: OPSStyle.Colors.tertiaryText)
            }
            .padding(.top, OPSStyle.Layout.spacing4)
        }
    }

    // MARK: - Skeleton

    private var skeletonView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                BooksSkeleton.bar(width: 150, height: 10)
                BooksSkeleton.bar(width: 220, height: 60)
            }
            BooksSkeleton.bar(width: nil, height: 84).padding(.top, 22)
            HStack(spacing: OPSStyle.Layout.spacing2) {
                BooksSkeleton.tile()
                BooksSkeleton.tile()
                BooksSkeleton.tile()
            }
            .padding(.top, OPSStyle.Layout.spacing4)
        }
    }

    // MARK: - Format helpers

    private func compactCurrency(_ value: Double) -> String {
        let absV = Swift.abs(value)
        let sign = value < 0 ? "-$" : "$"
        if absV >= 1_000_000 {
            return "\(sign)\(String(format: "%.1f", absV / 1_000_000))M"
        } else if absV >= 1_000 {
            return "\(sign)\(String(format: "%.1f", absV / 1_000))K"
        } else {
            return "\(sign)\(Int(absV.rounded()))"
        }
    }
}

#if DEBUG
#Preview("CashFlowCard — seeded") {
    CashFlowCard(viewModel: .previewStub(), onTapDays: {})
        .padding(.vertical, 24)
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
}

#Preview("CashFlowCard — empty") {
    CashFlowCard(viewModel: .previewEmpty(), onTapDays: {})
        .padding(.vertical, 24)
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
}
#endif
