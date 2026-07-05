//
//  BooksLensSheets.swift
//  OPS
//
//  Money drill-down layer (2026-07-01) — the sheets the command-grid tiles
//  expand into, rebuilt in the grid's own language: tactical header (Cake Mono
//  title, no system nav chrome), Mohave-Light hero with a numeric transition,
//  the lens's signature chart scaled up for continuity with the tapped tile,
//  flat hairline statement rows (the ledger language), and the L2 drill tiles.
//
//  Every value is the SAME number its lens already computes — derivations are
//  carried over verbatim from the Mission-Deck cards (PLCard / CashFlowCard /
//  ARCard / ForecastCard / JobsCard), as are the skeleton / card-error / empty
//  state forks and the composed VoiceOver summaries.
//

import SwiftUI

// MARK: - Shared sheet chrome

/// Sheet title band — `// LENS` in the uppercase display voice + an optional
/// trailing period/scope tag. Replaces the system navigation title (SF Pro)
/// that made every drill-down read stock-iOS.
struct BooksSheetHeader: View {
    let title: String
    var tag: String? = nil
    var tagColor: Color = OPSStyle.Colors.text3

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                Text("//")
                    .font(.custom("JetBrainsMono-Regular", size: 13))
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text(title)
                    .font(.custom("CakeMono-Light", size: 18))
                    .tracking(1.44)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text)
            }
            Spacer(minLength: 0)
            if let tag {
                Text(tag)
                    .font(.custom("JetBrainsMono-Medium", size: 9.5))
                    .tracking(1.43)
                    .textCase(.uppercase)
                    .foregroundColor(tagColor)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(OPSStyle.Colors.lineSoft, lineWidth: 1)
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// `// SECTION` eyebrow between sheet zones.
struct BooksSheetSection: View {
    let label: String

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Text("//").foregroundColor(OPSStyle.Colors.textMute)
            Text(label).foregroundColor(OPSStyle.Colors.text3)
            Spacer(minLength: 0)
        }
        .font(.custom("JetBrainsMono-Medium", size: 10))
        .tracking(1.6)
        .textCase(.uppercase)
        .monospacedDigit()
    }
}

/// Lens hero — label eyebrow + Mohave-Light 40 number + a keyed sub-line.
/// Same voice as the grid's NET CASH hero, one size down for the sheet.
struct BooksSheetHero: View {
    let label: String
    let value: String
    var valueColor: Color = OPSStyle.Colors.text
    var sub: String? = nil
    var subColor: Color = OPSStyle.Colors.text3

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1 + 2) {
            Text(label)
                .font(.custom("JetBrainsMono-Medium", size: 10))
                .tracking(2.0)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text3)
            Text(value)
                .font(.custom("Mohave-Light", size: 40))
                .foregroundColor(valueColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .contentTransition(.numericText())
            if let sub {
                Text(sub)
                    .font(.custom("JetBrainsMono-Medium", size: 10.5))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundColor(subColor)
                    .monospacedDigit()
            }
        }
    }
}

/// Flat statement row — the ledger's hairline language inside a sheet.
struct BooksStatementRow: View {
    let label: String
    let value: String
    var valueColor: Color = OPSStyle.Colors.text
    var trailingSub: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
            Text(label)
                .font(.custom("JetBrainsMono-Regular", size: 10.5))
                .tracking(1.05)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text3)
                .lineLimit(1)
            Spacer(minLength: OPSStyle.Layout.spacing2)
            if let trailingSub {
                Text(trailingSub)
                    .font(.custom("JetBrainsMono-Regular", size: 9.5))
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .monospacedDigit()
            }
            Text(value)
                .font(.custom("JetBrainsMono-Medium", size: 14))
                .foregroundColor(valueColor)
                .monospacedDigit()
        }
        .frame(minHeight: 38)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OPSStyle.Colors.lineSoft).frame(height: 1)
        }
    }
}

// MARK: - P&L sheet

struct BooksPLSheet: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapOutstanding: () -> Void = {}
    var onTapForecast: () -> Void = {}

    // Derivations carried over verbatim from PLCard.
    private var marginPctSigned: Int {
        guard viewModel.totalPayments > 0 else { return 0 }
        return Int((viewModel.netCash / viewModel.totalPayments * 100).rounded())
    }
    private var meterFraction: Double {
        guard viewModel.totalPayments > 0 else { return 0 }
        return max(0, min(1, viewModel.netCash / viewModel.totalPayments))
    }
    private var marginColor: Color {
        if marginPctSigned > 0 { return OPSStyle.Colors.olive }
        if marginPctSigned < 0 { return OPSStyle.Colors.rose }
        return OPSStyle.Colors.text3
    }
    private var weeklyFlows: [(inflow: Double, outflow: Double)] {
        let count = min(viewModel.paymentsByWeek.count, viewModel.expensesByWeek.count)
        guard count > 0 else { return [] }
        return (0..<count).suffix(8).map {
            (inflow: viewModel.paymentsByWeek[$0].amount, outflow: viewModel.expensesByWeek[$0].amount)
        }
    }
    private var isEmpty: Bool { viewModel.totalPayments == 0 && viewModel.totalExpenses == 0 }
    private var isSkeleton: Bool { !viewModel.hasEverLoaded && viewModel.isLoading }

    var body: some View {
        if isSkeleton {
            BooksSheetSkeleton()
        } else if viewModel.cardError(.pl) {
            BooksCardError(onRetry: { Task { await viewModel.retry(.pl) } })
        } else {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    BooksSheetHero(
                        label: "NET CASH · \(viewModel.selectedPeriod.shortLabel)",
                        value: BooksFormat.currency(viewModel.netCash),
                        valueColor: isEmpty
                            ? OPSStyle.Colors.text3
                            : (viewModel.netCash >= 0 ? OPSStyle.Colors.text : OPSStyle.Colors.rose),
                        sub: isEmpty ? "// NO ACTIVITY THIS PERIOD" : "\(marginPctSigned)% MARGIN",
                        subColor: isEmpty ? OPSStyle.Colors.textMute : marginColor
                    )

                    // Margin meter — olive fill on the neutral track.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                                .fill(OPSStyle.Colors.fillNeutralDim)
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                                .fill(OPSStyle.Colors.olive)
                                .frame(width: geo.size.width * meterFraction)
                        }
                    }
                    .frame(height: 6)
                    .padding(.top, OPSStyle.Layout.spacing2_5)
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("P and L. Net cash \(BooksFormat.currency(viewModel.netCash)), \(viewModel.selectedPeriod.pillLabel). \(marginPctSigned)% margin.")

                BooksSheetSection(label: "STATEMENT")
                    .padding(.top, OPSStyle.Layout.spacing4)
                BooksStatementRow(
                    label: "REVENUE IN",
                    value: "+\(BooksFormat.currency(viewModel.totalPayments))",
                    valueColor: OPSStyle.Colors.olive
                )
                .padding(.top, OPSStyle.Layout.spacing1)
                BooksStatementRow(
                    label: "COSTS OUT",
                    value: "\u{2212}\(BooksFormat.currency(viewModel.totalExpenses))",
                    valueColor: OPSStyle.Colors.rose
                )

                if !weeklyFlows.isEmpty {
                    BooksSheetSection(label: "WEEKLY FLOW · TRAILING \(weeklyFlows.count)W")
                        .padding(.top, OPSStyle.Layout.spacing4)
                    BooksWeeklyBars(weeks: weeklyFlows, height: 56)
                        .padding(.top, OPSStyle.Layout.spacing2_5)
                        .accessibilityHidden(true)
                }

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    BooksDrillTile(
                        label: "OUTSTANDING",
                        value: BooksFormat.currency(viewModel.overdueInvoicesValue),
                        sub: "\(viewModel.overdueInvoicesCount) \(viewModel.overdueInvoicesCount == 1 ? "ITEM" : "ITEMS")",
                        valueColor: isEmpty ? OPSStyle.Colors.text3 : OPSStyle.Colors.rose,
                        onTap: onTapOutstanding,
                        accessibilityHint: "Double-tap to view overdue invoices"
                    )
                    BooksDrillTile(
                        label: "FORECAST",
                        value: BooksFormat.currency(viewModel.pendingEstimatesValue),
                        sub: "\(viewModel.pendingEstimatesCount) \(viewModel.pendingEstimatesCount == 1 ? "ITEM" : "ITEMS")",
                        valueColor: isEmpty ? OPSStyle.Colors.text3 : OPSStyle.Colors.text,
                        onTap: onTapForecast,
                        accessibilityHint: "Double-tap to view sent estimates"
                    )
                }
                .padding(.top, OPSStyle.Layout.spacing4)
            }
        }
    }
}

// MARK: - Cash-flow sheet

struct BooksCashFlowSheet: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel

    private struct WeekPoint: Identifiable {
        var id: Date { weekStart }
        let weekStart: Date
        let inflow: Double
        let outflow: Double
        var net: Double { inflow - outflow }
    }

    // Union-by-week derivation carried over from CashFlowCard.
    private var weeks: [WeekPoint] {
        let inDict = Dictionary(uniqueKeysWithValues: viewModel.paymentsByWeek.map { ($0.weekStart, $0.amount) })
        let outDict = Dictionary(uniqueKeysWithValues: viewModel.expensesByWeek.map { ($0.weekStart, $0.amount) })
        let allWeeks = Set(inDict.keys).union(outDict.keys).sorted()
        return allWeeks.map { ws in
            WeekPoint(weekStart: ws, inflow: inDict[ws] ?? 0, outflow: outDict[ws] ?? 0)
        }
    }
    private var trailing: [WeekPoint] { Array(weeks.suffix(8)) }
    private var avgPerWeek: Double {
        let withInflow = viewModel.paymentsByWeek.filter { $0.amount > 0 }
        guard !withInflow.isEmpty else { return 0 }
        return withInflow.map { $0.amount }.reduce(0, +) / Double(withInflow.count)
    }
    private var isEmpty: Bool { viewModel.paymentsByWeek.isEmpty && viewModel.expensesByWeek.isEmpty }
    private var isSkeleton: Bool { !viewModel.hasEverLoaded && viewModel.isLoading }

    var body: some View {
        if isSkeleton {
            BooksSheetSkeleton()
        } else if viewModel.cardError(.cashFlow) {
            BooksCardError(onRetry: { Task { await viewModel.retry(.cashFlow) } })
        } else if isEmpty {
            BooksSheetEmpty(hero: "$0", label: "NO PAYMENTS THIS PERIOD",
                            hint: "CASH FLOW BUILDS AS PAYMENTS LAND")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    BooksSheetHero(
                        label: "NET CASH · \(weeks.count)W TRAILING",
                        value: BooksFormat.currency(viewModel.netCash),
                        valueColor: viewModel.netCash >= 0 ? OPSStyle.Colors.text : OPSStyle.Colors.rose,
                        sub: "\(BooksFormat.compact(avgPerWeek))/WK AVG INFLOW",
                        subColor: OPSStyle.Colors.olive
                    )

                    BooksWeeklyBars(weeks: trailing.map { (inflow: $0.inflow, outflow: $0.outflow) }, height: 72)
                        .padding(.top, OPSStyle.Layout.spacing3_5)

                    HStack(spacing: OPSStyle.Layout.spacing3) {
                        legendDot(color: OPSStyle.Colors.olive, label: "IN")
                        legendDot(color: OPSStyle.Colors.rose, label: "OUT")
                        Spacer(minLength: 0)
                    }
                    .padding(.top, OPSStyle.Layout.spacing2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Cash flow. Net cash \(BooksFormat.currency(viewModel.netCash)) over \(weeks.count) weeks. \(BooksFormat.compact(avgPerWeek)) per week average.")

                BooksSheetSection(label: "WEEK BY WEEK · LAST \(trailing.count)")
                    .padding(.top, OPSStyle.Layout.spacing4)
                    .padding(.bottom, OPSStyle.Layout.spacing1)
                ForEach(trailing.reversed()) { week in
                    weekRow(week)
                }

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    BooksDrillTile(label: "SALES", value: BooksFormat.compact(viewModel.totalSales), sub: "TRAILING")
                    BooksDrillTile(label: "AVG/WK", value: BooksFormat.compact(avgPerWeek), sub: "INFLOW",
                                   valueColor: OPSStyle.Colors.olive)
                    BooksDrillTile(label: "DAYS", value: String(format: "%.1f", viewModel.avgDaysToPayment), sub: "TO PAY")
                }
                .padding(.top, OPSStyle.Layout.spacing4)
            }
        }
    }

    private func weekRow(_ week: WeekPoint) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
            Text("WK \(monthDay(week.weekStart))")
                .font(.custom("JetBrainsMono-Regular", size: 10.5))
                .tracking(1.05)
                .foregroundColor(OPSStyle.Colors.text3)
                .monospacedDigit()
            Spacer(minLength: OPSStyle.Layout.spacing2)
            Text("+\(BooksFormat.compact(week.inflow))")
                .font(.custom("JetBrainsMono-Regular", size: 11.5))
                .foregroundColor(week.inflow > 0 ? OPSStyle.Colors.olive : OPSStyle.Colors.textMute)
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
            Text("\u{2212}\(BooksFormat.compact(week.outflow))")
                .font(.custom("JetBrainsMono-Regular", size: 11.5))
                .foregroundColor(week.outflow > 0 ? OPSStyle.Colors.rose : OPSStyle.Colors.textMute)
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
            Text(BooksFormat.compact(week.net))
                .font(.custom("JetBrainsMono-Medium", size: 12.5))
                .foregroundColor(week.net >= 0 ? OPSStyle.Colors.text : OPSStyle.Colors.rose)
                .monospacedDigit()
                .frame(width: 66, alignment: .trailing)
        }
        .frame(minHeight: 34)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OPSStyle.Colors.lineSoft).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.custom("JetBrainsMono-Regular", size: 9))
                .tracking(1.35)
                .foregroundColor(OPSStyle.Colors.text3)
        }
    }

    private func monthDay(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date).uppercased()
    }
}

// MARK: - Receivables sheet (absorbs ARDetailSheet)

struct BooksARSheet: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    @EnvironmentObject private var dataController: DataController

    @State private var invoices: [Invoice] = []
    @State private var clientNames: [String: String] = [:]
    @State private var isLoadingClients = true

    private let chaseAnchor = "ar-top-outstanding"

    private struct Bucket: Identifiable {
        let id: Int
        let label: String
        let amount: Double
        let color: Color
    }

    // 31/61/91 thresholds + canonical ramp colors. The split comes from the ONE
    // shared reducer (MoneyDashboardViewModel.agingBuckets) that the command-grid
    // tile also uses — not-yet-due and undated invoices land in the youngest
    // bucket, so these four columns always sum to `totalOutstanding` (the hero)
    // and this drill-down reconciles to the card it was opened from.
    private var buckets: [Bucket] {
        let b = MoneyDashboardViewModel.agingBuckets(from: viewModel.outstandingInvoiceBreakdown)
        return [
            Bucket(id: 0, label: "0–30D",  amount: b.current, color: OPSStyle.Colors.olive),
            Bucket(id: 1, label: "31–60D", amount: b.d30,     color: OPSStyle.Colors.accountingReceivables),
            Bucket(id: 2, label: "61–90D", amount: b.d60,     color: OPSStyle.Colors.warningStatus),
            Bucket(id: 3, label: "90D+",   amount: b.d90,     color: OPSStyle.Colors.accountingOverdue),
        ]
    }
    private var totalOutstanding: Double {
        viewModel.outstandingInvoiceBreakdown.reduce(0) { $0 + $1.amount }
    }
    private var topChase: MoneyDashboardViewModel.BreakdownItem? {
        var best: MoneyDashboardViewModel.BreakdownItem?
        var bestDate: Date = .distantFuture
        for item in viewModel.outstandingInvoiceBreakdown {
            guard let d = item.date else { continue }
            if d < bestDate { bestDate = d; best = item }
        }
        return best
    }
    private func daysLate(_ item: MoneyDashboardViewModel.BreakdownItem) -> Int {
        guard let d = item.date else { return 0 }
        return max(Int(Date().timeIntervalSince(d) / 86400), 0)
    }
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
    private var isEmpty: Bool { viewModel.outstandingInvoiceBreakdown.isEmpty }
    private var isSkeleton: Bool { !viewModel.hasEverLoaded && viewModel.isLoading }

    var body: some View {
        if isSkeleton {
            BooksSheetSkeleton()
        } else if viewModel.cardError(.ar) {
            BooksCardError(onRetry: { Task { await viewModel.retry(.ar) } })
        } else if isEmpty {
            BooksSheetEmpty(hero: "$0", label: "NO OPEN INVOICES",
                            hint: "EVERYTHING BILLED IS PAID")
        } else {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        BooksSheetHero(
                            label: "TOTAL OUTSTANDING",
                            value: BooksFormat.currency(totalOutstanding),
                            valueColor: OPSStyle.Colors.rose,
                            sub: "\(viewModel.outstandingInvoiceBreakdown.count) OPEN · \(viewModel.overdueInvoicesCount) OVERDUE",
                            subColor: viewModel.overdueInvoicesCount > 0 ? OPSStyle.Colors.rose : OPSStyle.Colors.text3
                        )
                        BooksAgingRamp(
                            current: buckets[0].amount, d30: buckets[1].amount,
                            d60: buckets[2].amount, d90: buckets[3].amount,
                            height: 8
                        )
                        .padding(.top, OPSStyle.Layout.spacing3_5)

                        // Bucket read-out — four flat columns under the ramp.
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(buckets) { bucket in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(bucket.label)
                                        .font(.custom("JetBrainsMono-Regular", size: 9))
                                        .tracking(0.9)
                                        .foregroundColor(OPSStyle.Colors.text3)
                                    Text(BooksFormat.compact(bucket.amount))
                                        .font(.custom("JetBrainsMono-Medium", size: 12.5))
                                        .foregroundColor(bucket.amount > 0 ? bucket.color : OPSStyle.Colors.textMute)
                                        .monospacedDigit()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, OPSStyle.Layout.spacing2_5)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Receivables. \(BooksFormat.currency(totalOutstanding)) outstanding across \(viewModel.outstandingInvoiceBreakdown.count) invoices, \(viewModel.overdueInvoicesCount) overdue.")

                    if let chase = topChase {
                        BooksSheetSection(label: "TOP CHASE")
                            .padding(.top, OPSStyle.Layout.spacing4)
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(OPSStyle.Animation.page) {
                                proxy.scrollTo(chaseAnchor, anchor: .top)
                            }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                                Text(chase.label)
                                    .font(.custom("Mohave-Medium", size: 15))
                                    .foregroundColor(OPSStyle.Colors.text)
                                    .lineLimit(1)
                                Spacer(minLength: OPSStyle.Layout.spacing2)
                                Text("\(daysLate(chase))D LATE")
                                    .font(.custom("JetBrainsMono-Regular", size: 9.5))
                                    .foregroundColor(OPSStyle.Colors.rose)
                                    .monospacedDigit()
                                Text(BooksFormat.currency(chase.amount))
                                    .font(.custom("JetBrainsMono-Medium", size: 14))
                                    .foregroundColor(OPSStyle.Colors.rose)
                                    .monospacedDigit()
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(OPSStyle.Colors.lineSoft).frame(height: 1)
                        }
                        .accessibilityHint("Scrolls to the outstanding balances list")
                    }

                    BooksSheetSection(label: "TOP OUTSTANDING")
                        .padding(.top, OPSStyle.Layout.spacing4)
                        .id(chaseAnchor)
                    if isLoadingClients {
                        HStack {
                            Spacer()
                            ProgressView().tint(OPSStyle.Colors.text3)
                            Spacer()
                        }
                        .frame(height: 64)
                    } else if topOutstanding.isEmpty {
                        Text("// NO OUTSTANDING BALANCES")
                            .font(.custom("JetBrainsMono-Regular", size: 10.5))
                            .tracking(1.26)
                            .foregroundColor(OPSStyle.Colors.textMute)
                            .padding(.vertical, OPSStyle.Layout.spacing3)
                    } else {
                        ForEach(Array(topOutstanding.enumerated()), id: \.offset) { _, entry in
                            BooksStatementRow(
                                label: entry.name,
                                value: BooksFormat.currency(entry.amount),
                                valueColor: OPSStyle.Colors.rose
                            )
                        }
                    }
                }
                .task { await loadClients() }
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
            // Non-fatal — the hero/ramp/buckets still render from the VM.
        }
        isLoadingClients = false
    }
}

// MARK: - Forecast sheet

struct BooksForecastSheet: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel

    private var maxStageValue: Double {
        max(viewModel.weightedForecastByStage.map { $0.value }.max() ?? 0, 1)
    }
    private var isEmpty: Bool { viewModel.weightedForecastByStage.isEmpty }
    private var isSkeleton: Bool { !viewModel.hasEverLoaded && viewModel.isLoading }

    var body: some View {
        if isSkeleton {
            BooksSheetSkeleton()
        } else if viewModel.cardError(.forecast) {
            BooksCardError(onRetry: { Task { await viewModel.retry(.forecast) } })
        } else if isEmpty {
            BooksSheetEmpty(hero: "$0", label: "NO ACTIVE OPPORTUNITIES",
                            hint: "THE FORECAST BUILDS FROM OPEN LEADS")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    // Neutral hero — weighted pipeline is data, not a CTA;
                    // the old accent-blue hero broke the accent-is-CTA-only rule.
                    BooksSheetHero(
                        label: "WEIGHTED FORECAST",
                        value: BooksFormat.currency(viewModel.weightedForecastValue),
                        valueColor: OPSStyle.Colors.text,
                        sub: "\(viewModel.activeLeadCount) ACTIVE OPPORTUNITIES",
                        subColor: OPSStyle.Colors.text3
                    )
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Forecast. \(BooksFormat.currency(viewModel.weightedForecastValue)) weighted across \(viewModel.activeLeadCount) opportunities.")

                BooksSheetSection(label: "BY STAGE")
                    .padding(.top, OPSStyle.Layout.spacing4)
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                    ForEach(viewModel.weightedForecastByStage) { row in
                        stageRow(row)
                    }
                }
                .padding(.top, OPSStyle.Layout.spacing2_5)

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    BooksDrillTile(
                        label: "CLOSE RATE",
                        value: "\(Int(viewModel.closeRate.rounded()))%",
                        sub: "LAST 90D",
                        valueColor: OPSStyle.Colors.olive
                    )
                    BooksDrillTile(
                        label: "STALE",
                        value: "\(viewModel.staleLeadsCount)",
                        sub: "NO MOVEMENT",
                        valueColor: viewModel.staleLeadsCount > 0 ? OPSStyle.Colors.tan : OPSStyle.Colors.text3
                    )
                }
                .padding(.top, OPSStyle.Layout.spacing4)
            }
        }
    }

    private func stageRow(_ row: MoneyDashboardViewModel.StageForecast) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.stage.displayName)
                    .font(.custom("JetBrainsMono-Medium", size: 10))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("×\(Int(row.avgProbability.rounded()))%")
                    .font(.custom("JetBrainsMono-Regular", size: 9))
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .monospacedDigit()
                Text(BooksFormat.currency(row.value))
                    .font(.custom("JetBrainsMono-Medium", size: 13))
                    .foregroundColor(OPSStyle.Colors.text)
                    .monospacedDigit()
            }
            // Neutral magnitude bar (fill-neutral on dim track) — monochrome
            // data discipline; the dollar figure carries the read.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                        .fill(OPSStyle.Colors.fillNeutralDim)
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                        .fill(OPSStyle.Colors.fillNeutral)
                        .frame(width: geo.size.width * CGFloat(row.value / maxStageValue), height: 5)
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Jobs sheet

struct BooksJobsSheet: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel

    private var maxAbsNet: Double {
        max(viewModel.topProjectsByNet.map { abs($0.net) }.max() ?? 1, 1)
    }
    private var marginPct: Int { Int((viewModel.avgProjectMargin * 100).rounded()) }
    private var isEmpty: Bool { viewModel.topProjectsByNet.isEmpty }
    private var isSkeleton: Bool { !viewModel.hasEverLoaded && viewModel.isLoading }

    var body: some View {
        if isSkeleton {
            BooksSheetSkeleton()
        } else if viewModel.cardError(.jobs) {
            BooksCardError(onRetry: { Task { await viewModel.retry(.jobs) } })
        } else if isEmpty {
            BooksSheetEmpty(hero: "—", label: "NO COMPLETE JOBS THIS PERIOD",
                            hint: "MARGINS APPEAR AS JOBS FINISH + GET PAID")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    BooksSheetHero(
                        label: "AVG MARGIN · \(viewModel.selectedPeriod.shortLabel)",
                        value: "\(marginPct)%",
                        valueColor: marginPct >= 0 ? OPSStyle.Colors.olive : OPSStyle.Colors.rose,
                        sub: "\(viewModel.profitableProjectCount) PROFITABLE · \(viewModel.losersProjectCount) LOSING",
                        subColor: OPSStyle.Colors.text3
                    )
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Jobs. \(marginPct) percent average margin. \(viewModel.profitableProjectCount) profitable, \(viewModel.losersProjectCount) losing.")

                BooksSheetSection(label: "BY JOB · TOP \(viewModel.topProjectsByNet.count) BY NET")
                    .padding(.top, OPSStyle.Layout.spacing4)
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    ForEach(viewModel.topProjectsByNet) { job in
                        jobRow(job)
                    }
                }
                .padding(.top, OPSStyle.Layout.spacing3)

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    BooksDrillTile(label: "PROFITABLE", value: "\(viewModel.profitableProjectCount)", sub: "JOBS",
                                   valueColor: OPSStyle.Colors.olive)
                    BooksDrillTile(label: "AVG MARGIN", value: "\(marginPct)%", sub: "MEAN")
                    BooksDrillTile(label: "LOSERS", value: "\(viewModel.losersProjectCount)", sub: "JOBS",
                                   valueColor: viewModel.losersProjectCount > 0 ? OPSStyle.Colors.rose : OPSStyle.Colors.text3)
                }
                .padding(.top, OPSStyle.Layout.spacing4)
            }
        }
    }

    private func jobRow(_ job: MoneyDashboardViewModel.JobNet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                Text(job.title)
                    .font(.custom("Mohave-Medium", size: 14))
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(marginString(job))
                    .font(.custom("JetBrainsMono-Regular", size: 9.5))
                    .foregroundColor(OPSStyle.Colors.text3)
                    .monospacedDigit()
                Text(netString(job.net))
                    .font(.custom("JetBrainsMono-Medium", size: 14))
                    .foregroundColor(job.net >= 0 ? OPSStyle.Colors.oliveMobile : OPSStyle.Colors.roseMobile)
                    .monospacedDigit()
            }
            divergingBar(job)
        }
        .accessibilityElement(children: .combine)
    }

    private func divergingBar(_ job: MoneyDashboardViewModel.JobNet) -> some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let center = totalWidth / 2
            let ratio = CGFloat(abs(job.net) / maxAbsNet)
            let barWidth = totalWidth * 0.5 * ratio
            let isPositive = job.net >= 0
            let barX = isPositive ? center : center - barWidth
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(OPSStyle.Colors.line)
                    .frame(width: 1, height: 5)
                    .offset(x: center - 0.5)
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .fill(isPositive ? OPSStyle.Colors.olive : OPSStyle.Colors.rose)
                    .frame(width: barWidth, height: 5)
                    .offset(x: barX)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private func marginString(_ job: MoneyDashboardViewModel.JobNet) -> String {
        guard job.revenue > 0 else { return "0%" }
        let pct = Int((job.net / job.revenue * 100).rounded())
        if pct > 0 { return "+\(pct)%" }
        return "\(pct)%"
    }

    private func netString(_ net: Double) -> String {
        let formatted = abs(net).formatted(.currency(code: "USD").precision(.fractionLength(0)))
        return (net >= 0 ? "+" : "\u{2212}") + formatted
    }
}

// MARK: - Shared empty + skeleton (sheet scale)

/// Sheet-scale empty state — the ledger's zero-hero voice.
struct BooksSheetEmpty: View {
    let hero: String
    let label: String
    let hint: String

    var body: some View {
        VStack(spacing: 0) {
            Text(hero)
                .font(.custom("Mohave-Light", size: 40))
                .foregroundColor(OPSStyle.Colors.text3)
                .monospacedDigit()
            Text("// \(label)")
                .font(.custom("JetBrainsMono-Regular", size: 10))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.textMute)
                .padding(.top, OPSStyle.Layout.spacing2)
            Text("[ \(hint) ]")
                .font(.custom("JetBrainsMono-Regular", size: 10))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text3)
                .padding(.top, OPSStyle.Layout.spacing2_5)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

/// Generic sheet skeleton — hero + chart + three rows.
struct BooksSheetSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BooksSkeleton.bar(width: 120, height: 10)
            BooksSkeleton.bar(width: 200, height: 40).padding(.top, 8)
            BooksSkeleton.bar(width: 140, height: 10).padding(.top, 8)
            BooksSkeleton.bar(width: nil, height: 64).padding(.top, OPSStyle.Layout.spacing4)
            ForEach(0..<3, id: \.self) { _ in
                BooksSkeleton.bar(width: nil, height: 14).padding(.top, OPSStyle.Layout.spacing3)
            }
        }
    }
}
