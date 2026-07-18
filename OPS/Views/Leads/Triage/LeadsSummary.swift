//
//  LeadsSummary.swift
//  OPS
//
//  Leads redesign (2026-07-17, spec §7 / mockup leads-top A) — the tab
//  summary is WORK-FIRST: the hero is the number of leads that need a move
//  right now, not a forecast. Weighted probability is retired.
//
//      N NEED ACTION                       ← rose when overdue, tan when >0
//      2 OVERDUE · 1 DUE TODAY · 1 YOUR MOVE
//      [PIPELINE $86K] [OPEN 12] [WON · JUL $22.4K]
//      [stage distribution bar]
//
//  Zero state: 0 NEED ACTION + // ALL QUIET (consistent with LeadsCaughtUp).
//  All values come straight off `PipelineViewModel`.
//

import SwiftUI

struct LeadsSummary: View {
    let viewModel: PipelineViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            needActionHero
            tileRow.padding(.top, OPSStyle.Layout.spacing3)
            stageBar.padding(.top, OPSStyle.Layout.spacing3)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    // MARK: Need-action hero

    private var buckets: PipelineViewModel.TriageBuckets { viewModel.triageBuckets }

    /// Numeral tone: rose while anything is overdue, tan while anything needs
    /// action, primary text at zero (all quiet).
    private var heroTone: Color {
        if buckets.overdue.count > 0 { return OPSStyle.Colors.roseTextM }
        if viewModel.needActionCount > 0 { return OPSStyle.Colors.tanTextM }
        return OPSStyle.Colors.text
    }

    private var needActionHero: some View {
        let count = viewModel.needActionCount
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                CountUpText(
                    target: Double(count),
                    format: { "\(Int($0))" },
                    font: .custom("Mohave-Light", size: 38),
                    color: heroTone
                )
                Text("NEED ACTION")
                    .font(.custom("JetBrainsMono-Medium", size: 11))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundColor(count > 0 ? heroTone : OPSStyle.Colors.text3)
            }

            breakdownLine
                .padding(.top, OPSStyle.Layout.spacing1 + 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(heroAccessibilityLabel)
    }

    /// `2 OVERDUE · 1 DUE TODAY · 1 YOUR MOVE` — each segment in its bucket
    /// tone; zero state reads `// ALL QUIET`.
    @ViewBuilder
    private var breakdownLine: some View {
        if viewModel.needActionCount == 0 {
            HStack(spacing: 0) {
                Text("// ").foregroundColor(OPSStyle.Colors.textMute)
                Text("ALL QUIET").foregroundColor(OPSStyle.Colors.text3)
            }
            .font(.custom("JetBrainsMono-Regular", size: 10))
            .tracking(1.4)
            .textCase(.uppercase)
        } else {
            HStack(spacing: 6) {
                breakdownSegment(buckets.overdue.count, "OVERDUE", OPSStyle.Colors.roseTextM)
                breakdownSegment(buckets.dueToday.count, "DUE TODAY", OPSStyle.Colors.tanTextM, leadingDot: buckets.overdue.count > 0)
                breakdownSegment(
                    buckets.waitingOnYou.count, "YOUR MOVE", OPSStyle.Colors.opsAccent,
                    leadingDot: buckets.overdue.count > 0 || buckets.dueToday.count > 0
                )
            }
        }
    }

    @ViewBuilder
    private func breakdownSegment(_ count: Int, _ label: String, _ tone: Color, leadingDot: Bool = false) -> some View {
        if count > 0 {
            HStack(spacing: 6) {
                if leadingDot {
                    Text("·")
                        .foregroundColor(OPSStyle.Colors.textMute)
                }
                Text("\(count) \(label)")
                    .foregroundColor(tone)
                    .monospacedDigit()
            }
            .font(.custom("JetBrainsMono-Regular", size: 10))
            .tracking(1.0)
            .textCase(.uppercase)
        }
    }

    private var heroAccessibilityLabel: String {
        let count = viewModel.needActionCount
        guard count > 0 else { return "0 need action. All quiet." }
        var parts: [String] = ["\(count) need action"]
        if buckets.overdue.count > 0 { parts.append("\(buckets.overdue.count) overdue") }
        if buckets.dueToday.count > 0 { parts.append("\(buckets.dueToday.count) due today") }
        if buckets.waitingOnYou.count > 0 { parts.append("\(buckets.waitingOnYou.count) your move") }
        return parts.joined(separator: ", ")
    }

    // MARK: Tile row — real dollars, no weighting

    private var tileRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            tile(label: "PIPELINE", value: BooksFormat.compact(viewModel.openPipelineValue), tone: nil)
            tile(label: "OPEN", value: "\(viewModel.openLeadCount)", tone: nil)
            tile(label: "WON · \(monthLabel)", value: BooksFormat.compact(viewModel.wonThisMonthValue),
                 tone: viewModel.wonThisMonthValue > 0 ? OPSStyle.Colors.oliveTextM : nil)
        }
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f.string(from: Date()).uppercased()
    }

    private func tile(label: String, value: String, tone: Color?) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(.custom("JetBrainsMono-Medium", size: 8.5))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text3)
                .lineLimit(1)
            Text(value)
                .font(.custom("JetBrainsMono-Medium", size: 16))
                .foregroundColor(tone ?? OPSStyle.Colors.text)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    // MARK: Stage distribution bar (kept as-is)

    private static let openStages = PipelineStage.openStages

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
}
