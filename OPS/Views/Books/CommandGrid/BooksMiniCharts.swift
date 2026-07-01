//
//  BooksMiniCharts.swift
//  OPS
//
//  Money & Leads redesign (2026-06-30) — the small, static data-viz primitives
//  that live inside the KPI command-grid tiles. Each takes already-computed
//  values off `MoneyDashboardViewModel` / `CashflowForecastViewModel` and draws
//  a single glanceable shape. No axes, no labels — the tile copy carries the
//  numbers; these carry the shape (DESIGN.md: visuals over numbers).
//
//  All monochrome + earth-tone semantic only; no accent on data (accent is
//  CTA/focus only). Drawn with plain Shapes so they stay crisp in sunlight.
//

import SwiftUI

// MARK: - Trend sparkline (NET PROFIT hero)

/// A single normalized polyline across the available box. Used for the weekly
/// net-cash trend beside the profit hero.
struct BooksSparkline: View {
    let values: [Double]
    var color: Color = OPSStyle.Colors.olive
    var lineWidth: CGFloat = 1.8

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            if pts.count >= 2 {
                Path { path in
                    path.move(to: pts[0])
                    for p in pts.dropFirst() { path.addLine(to: p) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let span = max(hi - lo, 0.0001)
        let stepX = size.width / CGFloat(values.count - 1)
        let inset: CGFloat = lineWidth
        let usableH = max(size.height - inset * 2, 1)
        return values.enumerated().map { idx, v in
            let x = CGFloat(idx) * stepX
            let norm = CGFloat((v - lo) / span)
            let y = inset + (1 - norm) * usableH
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Weekly in/out bars (CASH FLOW)

/// Per-week paired bars — money in (olive) beside money out (cost). Heights
/// normalized to the largest single value across all weeks.
struct BooksWeeklyBars: View {
    /// Trailing weeks, oldest → newest. Each is `(inflow, outflow)`.
    let weeks: [(inflow: Double, outflow: Double)]
    var height: CGFloat = 28

    private var maxValue: Double {
        max(weeks.flatMap { [$0.inflow, $0.outflow] }.max() ?? 1, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(alignment: .bottom, spacing: 2) {
                    bar(week.inflow, color: OPSStyle.Colors.olive)
                    bar(week.outflow, color: OPSStyle.Colors.rose.opacity(0.55))
                }
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func bar(_ value: Double, color: Color) -> some View {
        let fraction = CGFloat(max(value, 0) / maxValue)
        return RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color)
            .frame(width: 5, height: max(height * fraction, 2), alignment: .bottom)
    }
}

// MARK: - Runway projected-balance line (RUNWAY)

/// Projected weekly balance as a line, with a tone dot marking the low-water
/// week. Tone tracks `ForecastState` (healthy/lowWater/danger) at the call site.
struct BooksRunwayLine: View {
    let balances: [Double]
    let lowIndex: Int
    var tone: Color = OPSStyle.Colors.tan
    var height: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack(alignment: .topLeading) {
                if pts.count >= 2 {
                    Path { path in
                        path.move(to: pts[0])
                        for p in pts.dropFirst() { path.addLine(to: p) }
                    }
                    .stroke(OPSStyle.Colors.text2, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
                if pts.indices.contains(lowIndex) {
                    Circle()
                        .fill(tone)
                        .frame(width: 5, height: 5)
                        .position(pts[lowIndex])
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard balances.count >= 2 else { return [] }
        let lo = balances.min() ?? 0
        let hi = balances.max() ?? 1
        let span = max(hi - lo, 0.0001)
        let stepX = size.width / CGFloat(balances.count - 1)
        let inset: CGFloat = 3
        let usableH = max(size.height - inset * 2, 1)
        return balances.enumerated().map { idx, v in
            let x = CGFloat(idx) * stepX
            let norm = CGFloat((v - lo) / span)
            let y = inset + (1 - norm) * usableH
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Aging ramp (RECEIVABLES)

/// Four weighted segments — current → 30 → 60 → 90+ — sharing the canonical A/R
/// aging ramp colors (DESIGN.md §3: olive → tan → receivables → overdue). Each
/// segment's width is proportional to its dollar share of total outstanding.
struct BooksAgingRamp: View {
    let current: Double
    let d30: Double
    let d60: Double
    let d90: Double
    var height: CGFloat = 4

    // Canonical A/R aging ramp — matches the A/R lens buckets exactly
    // (0–30 olive · 31–60 receivables · 61–90 warning · 90+ overdue).
    private var segments: [(value: Double, color: Color)] {
        [
            (current, OPSStyle.Colors.olive),
            (d30,     OPSStyle.Colors.accountingReceivables),
            (d60,     OPSStyle.Colors.warningStatus),
            (d90,     OPSStyle.Colors.accountingOverdue),
        ]
    }

    var body: some View {
        let total = max(segments.map(\.value).reduce(0, +), 0.0001)
        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    if seg.value > 0 {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(seg.color)
                            .frame(width: max(geo.size.width * CGFloat(seg.value / total) - 2, 1))
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Per-job margin bars (JOB PROFITABILITY)

/// A row of thin bars, one per top project, heights normalized to the largest
/// absolute net. Olive when the job nets positive, rose when it nets a loss.
struct BooksMarginBars: View {
    let nets: [Double]
    var height: CGFloat = 30

    private var maxAbs: Double { max(nets.map { abs($0) }.max() ?? 1, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(nets.enumerated()), id: \.offset) { _, net in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(net >= 0 ? OPSStyle.Colors.olive : OPSStyle.Colors.rose)
                    .frame(width: 9, height: max(height * CGFloat(abs(net) / maxAbs), 4), alignment: .bottom)
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
