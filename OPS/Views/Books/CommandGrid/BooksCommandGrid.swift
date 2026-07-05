//
//  BooksCommandGrid.swift
//  OPS
//
//  Money & Leads redesign (2026-06-30) — the Money tab's at-a-glance KPI grid
//  (design direction "1b · COMMAND GRID"). Replaces the swipeable hero carousel
//  with a single scannable grid: a full-width NET CASH hero, a 2×2 of CASH FLOW
//  · RUNWAY · RECEIVABLES · FORECAST, and a full-width JOB PROFITABILITY strip.
//
//  Every number is the SAME value its lens already computes — the tiles drill
//  into the existing expand sheets (`ExpandedCardSheet`) / RUNWAY full screen,
//  so no detail is lost. Pure view layer; reads published metrics off
//  `MoneyDashboardViewModel` + `CashflowForecastViewModel`. Permission-gated
//  exactly like the lenses (finances.view / pipeline.view); hidden tiles reflow.
//

import SwiftUI

struct BooksCommandGrid: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    @ObservedObject var cashflowVM: CashflowForecastViewModel
    let canFinances: Bool
    let canPipeline: Bool
    var onExpand: (HeroCarousel.CardID) -> Void = { _ in }
    var onOpenRunway: () -> Void = {}

    private let columns = [
        GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2),
        GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2),
    ]

    var body: some View {
        Group {
            // Skeleton only during the very first load — once any data (even
            // zeros) is in hand, show the real grid rather than a placeholder.
            if viewModel.isLoading && !viewModel.hasEverLoaded {
                skeleton
            } else {
                grid
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    // MARK: Loaded grid

    private var grid: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            if canFinances {
                ProfitHeroCard(
                    netCash: viewModel.netCash,
                    marginPct: marginPct,
                    weeklyNets: weeklyNets,
                    periodShort: viewModel.selectedPeriod.shortLabel,
                    hasActivity: viewModel.totalPayments != 0 || viewModel.totalExpenses != 0,
                    onTap: { onExpand(.pl) }
                )
                .booksCardIn(index: 0)
            }

            LazyVGrid(columns: columns, spacing: OPSStyle.Layout.spacing2) {
                if canFinances {
                    CashFlowTile(weeks: weeklyFlows, netPerWeek: avgWeeklyNet, onTap: { onExpand(.cashFlow) })
                        .booksCardIn(index: 1)
                    RunwayTile(result: cashflowVM.result, onTap: onOpenRunway)
                        .booksCardIn(index: 2)
                    ReceivablesTile(
                        total: receivablesTotal,
                        overdue: viewModel.overdueInvoicesValue,
                        buckets: agingBuckets,
                        onTap: { onExpand(.ar) }
                    )
                    .booksCardIn(index: 3)
                }
                if canPipeline {
                    ForecastTile(
                        value: viewModel.weightedForecastValue,
                        openCount: viewModel.activeLeadCount,
                        onTap: { onExpand(.forecast) }
                    )
                    .booksCardIn(index: 4)
                }
            }

            if canFinances {
                JobsTile(
                    marginPct: Int((viewModel.avgProjectMargin * 100).rounded()),
                    nets: viewModel.topProjectsByNet.map(\.net),
                    profitable: viewModel.profitableProjectCount,
                    losers: viewModel.losersProjectCount,
                    onTap: { onExpand(.jobs) }
                )
                .booksCardIn(index: 5)
            }
        }
    }

    // MARK: Derived metrics (mirror the lens math exactly)

    /// Net-cash margin — identical to the P&L lens: `netCash / totalPayments`.
    private var marginPct: Int {
        guard viewModel.totalPayments > 0 else { return 0 }
        return Int((viewModel.netCash / viewModel.totalPayments * 100).rounded())
    }

    /// Per-week net cash (inflow − outflow), aligned by index.
    private var weeklyNets: [Double] {
        let count = min(viewModel.paymentsByWeek.count, viewModel.expensesByWeek.count)
        guard count > 0 else { return [] }
        return (0..<count).map { viewModel.paymentsByWeek[$0].amount - viewModel.expensesByWeek[$0].amount }
    }

    private var weeklyFlows: [(inflow: Double, outflow: Double)] {
        let count = min(viewModel.paymentsByWeek.count, viewModel.expensesByWeek.count)
        guard count > 0 else { return [] }
        return (0..<count).map { (inflow: viewModel.paymentsByWeek[$0].amount, outflow: viewModel.expensesByWeek[$0].amount) }
    }

    private var avgWeeklyNet: Double {
        let nets = weeklyNets
        guard !nets.isEmpty else { return 0 }
        return nets.reduce(0, +) / Double(nets.count)
    }

    private var receivablesTotal: Double {
        viewModel.outstandingInvoiceBreakdown.reduce(0) { $0 + $1.amount }
    }

    /// Aging buckets split at 31/61/91 days off each outstanding item's date.
    /// Single source of truth — the drill-down sheet reads the SAME split, so
    /// the tile hero and the sheet it opens always reconcile.
    private var agingBuckets: (current: Double, d30: Double, d60: Double, d90: Double) {
        let b = MoneyDashboardViewModel.agingBuckets(from: viewModel.outstandingInvoiceBreakdown)
        return (b.current, b.d30, b.d60, b.d90)
    }

    // MARK: Skeleton (cold launch, no cached metrics yet)

    private var skeleton: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            BooksSkeleton.bar(width: nil, height: 92)
            LazyVGrid(columns: columns, spacing: OPSStyle.Layout.spacing2) {
                ForEach(0..<4, id: \.self) { _ in BooksSkeleton.bar(width: nil, height: 96) }
            }
            BooksSkeleton.bar(width: nil, height: 64)
        }
    }
}

// MARK: - Tile eyebrow

/// The `// LABEL` tile eyebrow, with an optional trailing status badge.
private struct TileEyebrow: View {
    let label: String
    var badge: (text: String, color: Color)? = nil

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 0) {
                Text("// ").foregroundColor(OPSStyle.Colors.textMute)
                Text(label).foregroundColor(OPSStyle.Colors.text3)
            }
            .font(.custom("JetBrainsMono-Medium", size: 9.5))
            .tracking(1.4)
            .textCase(.uppercase)

            if let badge {
                Spacer(minLength: 0)
                Text(badge.text)
                    .font(.custom("JetBrainsMono-Medium", size: 8))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundColor(badge.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(badge.color.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(badge.color.opacity(0.40), lineWidth: 1)
                    )
            }
        }
    }
}

// MARK: - NET CASH hero

private struct ProfitHeroCard: View {
    let netCash: Double
    let marginPct: Int
    let weeklyNets: [Double]
    let periodShort: String
    let hasActivity: Bool
    var onTap: () -> Void

    private var marginColor: Color {
        if !hasActivity { return OPSStyle.Colors.inactiveText }
        if marginPct > 0 { return OPSStyle.Colors.olive }
        if marginPct < 0 { return OPSStyle.Colors.rose }
        return OPSStyle.Colors.text3
    }

    var body: some View {
        Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); onTap() }) {
            HStack(alignment: .bottom, spacing: OPSStyle.Layout.spacing3) {
                VStack(alignment: .leading, spacing: 0) {
                    TileEyebrow(label: "NET CASH · \(periodShort)")
                    CountUpText(
                        target: netCash,
                        font: .custom("Mohave-Light", size: 42),
                        color: netCash >= 0 ? OPSStyle.Colors.text : OPSStyle.Colors.rose
                    )
                    .padding(.top, OPSStyle.Layout.spacing1 + 2)
                    Text(hasActivity ? "\(marginPct)% MARGIN" : "NO ACTIVITY")
                        .font(.custom("JetBrainsMono-Regular", size: 10.5))
                        .tracking(0.4)
                        .foregroundColor(marginColor)
                        .padding(.top, OPSStyle.Layout.spacing1)
                }
                Spacer(minLength: 0)
                BooksSparkline(values: weeklyNets, color: marginPct >= 0 ? OPSStyle.Colors.olive : OPSStyle.Colors.rose)
                    .frame(width: 76, height: 42)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .commandCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Net cash \(BooksFormat.currency(netCash)), \(marginPct) percent margin")
        .accessibilityHint("Opens the profit and loss detail")
    }
}

// MARK: - 2×2 tiles

/// A small KPI tile on the canonical L2 surface (`booksL2Surface`). Optional
/// `tone` tints it for the attention surfaces (RUNWAY).
private struct BooksTileShell<Content: View>: View {
    var tone: Color? = nil
    var onTap: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); onTap() }) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(OPSStyle.Layout.spacing2_5)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .modifier(BooksTileBackground(tone: tone))
        }
        .buttonStyle(.plain)
    }
}

/// Tile background — L2 nested surface, or a tone-tinted command card.
private struct BooksTileBackground: ViewModifier {
    var tone: Color?
    func body(content: Content) -> some View {
        if let tone {
            content.commandCard(tone: tone, cornerRadius: OPSStyle.Layout.cardRadius)
        } else {
            content.booksL2Surface()
        }
    }
}

private struct CashFlowTile: View {
    let weeks: [(inflow: Double, outflow: Double)]
    let netPerWeek: Double
    var onTap: () -> Void

    var body: some View {
        BooksTileShell(onTap: onTap) {
            TileEyebrow(label: "CASH FLOW")
            BooksWeeklyBars(weeks: weeks)
                .padding(.top, OPSStyle.Layout.spacing2)
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text(BooksFormat.compact(netPerWeek))
                    .font(.custom("JetBrainsMono-Medium", size: 11))
                    .foregroundColor(netPerWeek >= 0 ? OPSStyle.Colors.olive : OPSStyle.Colors.rose)
                Text("NET / WK")
                    .font(.custom("JetBrainsMono-Regular", size: 9))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .monospacedDigit()
            .padding(.top, OPSStyle.Layout.spacing1 + 3)
        }
    }
}

private struct RunwayTile: View {
    let result: ForecastResult?
    var onTap: () -> Void

    private var badge: (text: String, color: Color) {
        switch result?.state {
        case .healthy:  return ("ON TRACK", OPSStyle.Colors.olive)
        case .lowWater: return ("WATCH", OPSStyle.Colors.tan)
        case .danger:   return ("DANGER", OPSStyle.Colors.rose)
        case nil:       return ("—", OPSStyle.Colors.text3)
        }
    }

    private var toneColor: Color {
        switch result?.state {
        case .danger:   return OPSStyle.Colors.rose
        case .lowWater: return OPSStyle.Colors.tan
        default:        return OPSStyle.Colors.olive
        }
    }

    var body: some View {
        BooksTileShell(tone: OPSStyle.Colors.tan, onTap: onTap) {
            TileEyebrow(
                label: result.map { "RUNWAY · \($0.weeks.count)W" } ?? "RUNWAY",
                badge: badge
            )
            if let result, result.weeks.count >= 2 {
                BooksRunwayLine(
                    balances: result.weeks.map(\.balance),
                    lowIndex: result.lowestWeekIndex,
                    tone: toneColor
                )
                .padding(.top, OPSStyle.Layout.spacing2)
                Text("LOW \(BooksFormat.compact(result.lowestBalance)) · WK \(result.lowestWeekIndex + 1)")
                    .font(.custom("JetBrainsMono-Regular", size: 9))
                    .foregroundColor(toneColor)
                    .monospacedDigit()
                    .padding(.top, OPSStyle.Layout.spacing1 + 3)
            } else {
                Spacer(minLength: 0)
                Text("// NO FORECAST")
                    .font(.custom("JetBrainsMono-Regular", size: 9))
                    .tracking(1.4)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .padding(.top, OPSStyle.Layout.spacing2)
            }
        }
    }
}

private struct ReceivablesTile: View {
    let total: Double
    let overdue: Double
    let buckets: (current: Double, d30: Double, d60: Double, d90: Double)
    var onTap: () -> Void

    var body: some View {
        BooksTileShell(onTap: onTap) {
            TileEyebrow(label: "RECEIVABLES")
            Text(BooksFormat.compact(total))
                .font(.custom("JetBrainsMono-Medium", size: 18))
                .foregroundColor(OPSStyle.Colors.text)
                .monospacedDigit()
                .padding(.top, OPSStyle.Layout.spacing1 + 2)
            Text(overdue > 0 ? "\(BooksFormat.compact(overdue)) OVERDUE" : "NONE OVERDUE")
                .font(.custom("JetBrainsMono-Regular", size: 9))
                .foregroundColor(overdue > 0 ? OPSStyle.Colors.rose : OPSStyle.Colors.text3)
                .monospacedDigit()
                .padding(.top, 2)
            BooksAgingRamp(current: buckets.current, d30: buckets.d30, d60: buckets.d60, d90: buckets.d90)
                .padding(.top, OPSStyle.Layout.spacing2)
        }
    }
}

private struct ForecastTile: View {
    let value: Double
    let openCount: Int
    var onTap: () -> Void

    var body: some View {
        BooksTileShell(onTap: onTap) {
            TileEyebrow(label: "FORECAST")
            Text(BooksFormat.compact(value))
                .font(.custom("JetBrainsMono-Medium", size: 18))
                .foregroundColor(OPSStyle.Colors.text)
                .monospacedDigit()
                .padding(.top, OPSStyle.Layout.spacing1 + 2)
            Text("WEIGHTED · \(openCount) OPEN")
                .font(.custom("JetBrainsMono-Regular", size: 9))
                .foregroundColor(OPSStyle.Colors.text3)
                .monospacedDigit()
                .padding(.top, 2)
            Spacer(minLength: 0)
        }
    }
}

private struct JobsTile: View {
    let marginPct: Int
    let nets: [Double]
    let profitable: Int
    let losers: Int
    var onTap: () -> Void

    private var marginColor: Color {
        if nets.isEmpty { return OPSStyle.Colors.text3 }
        return marginPct >= 0 ? OPSStyle.Colors.olive : OPSStyle.Colors.rose
    }

    var body: some View {
        Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); onTap() }) {
            HStack(alignment: .center, spacing: OPSStyle.Layout.spacing3) {
                VStack(alignment: .leading, spacing: 0) {
                    TileEyebrow(label: "JOB PROFITABILITY")
                    HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                        Text(nets.isEmpty ? "—" : "\(marginPct)%")
                            .font(.custom("Mohave-Light", size: 24))
                            .foregroundColor(marginColor)
                        Text("AVG MARGIN")
                            .font(.custom("JetBrainsMono-Regular", size: 10))
                            .foregroundColor(OPSStyle.Colors.text3)
                    }
                    .padding(.top, OPSStyle.Layout.spacing1 + 1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: OPSStyle.Layout.spacing1 + 1) {
                    BooksMarginBars(nets: Array(nets.prefix(8)))
                    Text("\(profitable) PROFIT · \(losers) LOSS")
                        .font(.custom("JetBrainsMono-Regular", size: 9))
                        .foregroundColor(OPSStyle.Colors.text3)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2_5 + 2)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .frame(maxWidth: .infinity)
            .commandCard()
        }
        .buttonStyle(.plain)
    }
}
