//
//  LeadsSummary.swift
//  OPS
//
//  The LEADS command band (console redesign 2026-08-05, spec §3 / §4). One
//  band, three postures, chosen by `LeadsQueryEngine.bandState` — never by
//  conditionals scattered through the body:
//
//      WORKING   4 NEED ACTION                     ← rose overdue / tan due
//                2 OVERDUE · 1 DUE TODAY · 1 YOUR MOVE
//                PIPELINE $86K · OPEN 12 · WON AUG $22.4K
//                ▓▓▓▓▓▒▒▒▒░░░░░░░        BY STAGE ▸
//
//      QUIET     // ALL QUIET — NO FOLLOW-UPS DUE
//                PIPELINE $86K · OPEN 12 · WON AUG $22.4K
//                ▓▓▓▓▒▒▒░░░░░░░          BY STAGE ▸
//
//      EMPTY     PIPELINE — · OPEN 0
//
//  What went, and why: the three bordered KPI tiles collapsed into the one
//  metrics line (same numbers, a fifth of the vertical budget), and the 38pt
//  "0 NEED ACTION" zero-hero is gone — celebration chrome for "nothing to do"
//  bought nothing and pushed the queue down a hundred points. The empty band
//  says nothing about follow-ups at all: the queue's own `LeadsCaughtUp` block
//  owns that message, and stating it twice would be noise.
//
//  All values come straight off `PipelineViewModel`.
//

import SwiftUI

struct LeadsSummary: View {
    let viewModel: PipelineViewModel
    /// Opens the stage browser. Deliberately argument-free — the band shows the
    /// distribution, the console decides which stage to land on.
    var onByStage: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch bandState {
            case .working:
                needActionHero
                metricsLine.padding(.top, OPSStyle.Layout.spacing2)
                barRow.padding(.top, OPSStyle.Layout.spacing2)
            case .quiet:
                quietLine
                metricsLine.padding(.top, OPSStyle.Layout.spacing2)
                barRow.padding(.top, OPSStyle.Layout.spacing2)
            case .emptyPipeline:
                metricsLine
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    private var buckets: PipelineViewModel.TriageBuckets { viewModel.triageBuckets }

    private var bandState: LeadsBandState {
        LeadsQueryEngine.bandState(
            needAction: viewModel.needActionCount,
            openLeads: viewModel.openLeadCount
        )
    }

    // MARK: Need-action hero (working state)

    /// Numeral tone: rose while anything is overdue, tan while anything else
    /// needs action. The hero only renders when work is due, so there is no
    /// third case.
    private var heroTone: Color {
        buckets.overdue.count > 0 ? OPSStyle.Colors.roseTextM : OPSStyle.Colors.tanTextM
    }

    private var needActionHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                CountUpText(
                    target: Double(viewModel.needActionCount),
                    format: { "\(Int($0))" },
                    font: .custom("Mohave-Light", size: 34),
                    color: heroTone
                )
                Text("NEED ACTION")
                    .font(.custom("JetBrainsMono-Medium", size: 11))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundColor(heroTone)
            }

            breakdownLine
                .padding(.top, OPSStyle.Layout.spacing1 + 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(heroAccessibilityLabel)
    }

    /// `2 OVERDUE · 1 DUE TODAY · 1 YOUR MOVE` — each segment in its bucket tone.
    private var breakdownLine: some View {
        HStack(spacing: 6) {
            breakdownSegment(buckets.overdue.count, "OVERDUE", OPSStyle.Colors.roseTextM)
            breakdownSegment(buckets.dueToday.count, "DUE TODAY", OPSStyle.Colors.tanTextM,
                             leadingDot: buckets.overdue.count > 0)
            breakdownSegment(
                buckets.waitingOnYou.count, "YOUR MOVE", OPSStyle.Colors.opsAccent,
                leadingDot: buckets.overdue.count > 0 || buckets.dueToday.count > 0
            )
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
            .font(OPSStyle.Typography.miniLabel)
            .tracking(1.0)
            .textCase(.uppercase)
        }
    }

    private var heroAccessibilityLabel: String {
        var parts: [String] = ["\(viewModel.needActionCount) need action"]
        if buckets.overdue.count > 0 { parts.append("\(buckets.overdue.count) overdue") }
        if buckets.dueToday.count > 0 { parts.append("\(buckets.dueToday.count) due today") }
        if buckets.waitingOnYou.count > 0 { parts.append("\(buckets.waitingOnYou.count) your move") }
        return parts.joined(separator: ", ")
    }

    // MARK: Quiet line (quiet state)

    private var quietLine: some View {
        HStack(spacing: 0) {
            Text("// ").foregroundColor(OPSStyle.Colors.textMute)
            Text("ALL QUIET — NO FOLLOW-UPS DUE").foregroundColor(OPSStyle.Colors.text3)
        }
        .font(.custom("JetBrainsMono-Medium", size: 11))
        .tracking(1.4)
        .textCase(.uppercase)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("All quiet, no follow-ups due")
    }

    // MARK: Metrics line (replaces the KPI tiles)

    private var metricsLine: some View {
        HStack(spacing: 6) {
            metric("PIPELINE", pipelineValueText, tone: nil)
            metricSeparator
            metric("OPEN", "\(viewModel.openLeadCount)", tone: nil)
            // A month with no wins yet says nothing worth a slot; the segment
            // returns the moment one lands.
            if viewModel.wonThisMonthValue > 0 {
                metricSeparator
                metric("WON \(monthLabel)",
                       BooksFormat.compact(viewModel.wonThisMonthValue),
                       tone: OPSStyle.Colors.oliveTextM)
            }
        }
        .font(.custom("JetBrainsMono-Medium", size: 11))
        .tracking(1.0)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metricsAccessibilityLabel)
    }

    private func metric(_ label: String, _ value: String, tone: Color?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundColor(OPSStyle.Colors.text3)
            Text(value)
                .foregroundColor(tone ?? OPSStyle.Colors.text)
                .monospacedDigit()
        }
    }

    private var metricSeparator: some View {
        Text("·").foregroundColor(OPSStyle.Colors.textMute)
    }

    /// Zero dollars is an em dash, never `$0` — the formatting law for an empty
    /// number on every OPS surface.
    private var pipelineValueText: String {
        viewModel.openPipelineValue > 0 ? BooksFormat.compact(viewModel.openPipelineValue) : "—"
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f.string(from: Date()).uppercased()
    }

    private var metricsAccessibilityLabel: String {
        var parts = [
            "Pipeline \(viewModel.openPipelineValue > 0 ? BooksFormat.compact(viewModel.openPipelineValue) : "none")",
            "\(viewModel.openLeadCount) open"
        ]
        if viewModel.wonThisMonthValue > 0 {
            let f = DateFormatter()
            f.dateFormat = "MMMM"
            parts.append("won \(BooksFormat.compact(viewModel.wonThisMonthValue)) in \(f.string(from: Date()))")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Stage bar + BY STAGE affordance

    private static let openStages = PipelineStage.openStages

    /// The distribution bar and its label are ONE control: the bar is what the
    /// operator points at when they want the stage view, so the whole row is
    /// the door rather than a 9.5pt word beside a decoration.
    private var barRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onByStage()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                stageBar
                HStack(spacing: 4) {
                    Text("BY STAGE")
                        .foregroundColor(OPSStyle.Colors.text3)
                    Text("▸")
                        .foregroundColor(OPSStyle.Colors.textMute)
                }
                .font(.custom("JetBrainsMono-Medium", size: 9.5))
                .tracking(1.2)
                .textCase(.uppercase)
                .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pipeline by stage, browse")
    }

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

// MARK: - Previews

#if DEBUG
#Preview("LeadsSummary / band states") {
    ScrollView {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing5) {
            // WORKING — overdue + due today + your move
            LeadsSummary(viewModel: .previewLoaded())
            // QUIET — open leads, nothing due
            LeadsSummary(viewModel: .previewLoaded(opportunities: [
                .preview(title: "Smith deck addition", contactName: "Mike Smith",
                         stage: .newLead, estimatedValue: 8_500, daysInStage: 1),
                .preview(title: "Hilltop pool deck", contactName: "Anna Patel",
                         stage: .quoting, estimatedValue: 22_400, daysInStage: 2)
            ]))
            // EMPTY PIPELINE — metrics only
            LeadsSummary(viewModel: .previewLoaded(opportunities: []))
        }
        .padding(.vertical, OPSStyle.Layout.spacing4)
    }
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
