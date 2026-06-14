//
//  PipelineFooter.swift
//  OPS
//
//  Secondary drill-down at the bottom of the triage screen. For the operator
//  who wants to browse by pipeline stage rather than urgency. Renders as a
//  single L1 glass panel with one row per pipeline stage:
//
//    // BY STAGE                           OPEN STAGE BOARD →
//    ┌───────────────────────────────────────────────────────┐
//    │ NEW LEAD                                03 · 10%   →  │
//    │ QUALIFYING                              07 · 20%   →  │
//    │ QUOTING                                 04 · 40%   →  │
//    │ QUOTED                                  02 · 60%   →  │
//    │ FOLLOW-UP                               05 · 50%   →  │
//    │ NEGOTIATION                             01 · 75%   →  │
//    ├───────────────────────────────────────────────────────┤ ← heavier divider
//    │ WON                                          12    →  │ ← closed stages,
//    │ LOST                                         04    →  │   60% opacity
//    └───────────────────────────────────────────────────────┘
//
//  Tapping a row navigates to a filtered single-stage list
//  (`PipelineStageListView`, per plan §2.1 Q2 = (b)). Won/Lost are surfaced
//  below a heavier divider at 60% opacity — design-intent §15 / §23 #5: the
//  footer carries the won/lost drill since the stage-strip CLOSED reveal was
//  removed. Win-probability is omitted on closed rows (count only). Chevrons
//  are textMute — never accent (per spec).
//

import SwiftUI

struct PipelineFooter: View {
    /// Count of leads per stage, keyed by PipelineStage. Populated for every
    /// stage including `.won` / `.lost`.
    let counts: [PipelineStage: Int]
    /// Tap on a stage row — wired to push the per-stage filtered list.
    var onStageTap: (PipelineStage) -> Void = { _ in }
    /// Tap on the trailing `OPEN STAGE BOARD →` link. Routes to whichever
    /// first open-stage list has leads (fallback NEW LEAD).
    var onBoardTap: () -> Void = {}

    /// Open (non-terminal) stages — the active pipeline.
    private let openStages: [PipelineStage] = [
        .newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation
    ]
    /// Closed (terminal) stages — surfaced below the divider, dimmed.
    private let closedStages: [PipelineStage] = [.won, .lost]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSectionHeader(
                label: "BY STAGE",
                hint: "OPEN STAGE BOARD →",
                onHintTap: onBoardTap
            )

            VStack(spacing: 0) {
                ForEach(Array(openStages.enumerated()), id: \.element) { idx, stage in
                    stageButton(for: stage)
                    if idx < openStages.count - 1 { interRowHairline }
                }

                // Heavier full-bleed divider — separates the active pipeline
                // from the dimmed closed stages.
                Rectangle()
                    .fill(OPSStyle.Colors.line)
                    .frame(height: 1)

                ForEach(Array(closedStages.enumerated()), id: \.element) { idx, stage in
                    stageButton(for: stage)
                        .opacity(0.6)   // design-intent §15 closed-stage treatment
                    if idx < closedStages.count - 1 { interRowHairline }
                }
            }
            .glassSurface()
        }
    }

    // MARK: - Rows

    private func stageButton(for stage: PipelineStage) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onStageTap(stage)
        }) {
            row(for: stage)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(for: stage))
    }

    /// Inset hairline between peer rows within a section.
    private var interRowHairline: some View {
        Rectangle()
            .fill(OPSStyle.Colors.fillNeutralDim)
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func row(for stage: PipelineStage) -> some View {
        HStack(spacing: 10) {
            Text(stage.displayName)
                .font(.custom("JetBrainsMono-Regular", size: 11.5))
                .fontWeight(.medium)
                .foregroundColor(OPSStyle.Colors.text2)
                .kerning(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%02d", counts[stage] ?? 0))
                .font(.custom("JetBrainsMono-Regular", size: 10))
                .foregroundColor(OPSStyle.Colors.text3)
                .monospacedDigit()

            // Win probability is meaningless for terminal stages — count only.
            if !stage.isTerminal {
                Text("·")
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .font(.custom("JetBrainsMono-Regular", size: 10))

                Text("\(stage.winProbability)%")
                    .font(.custom("JetBrainsMono-Regular", size: 10))
                    .foregroundColor(OPSStyle.Colors.text3)
                    .monospacedDigit()
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(OPSStyle.Colors.textMute)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)        // 44pt tap target, gloves-on
    }

    private func accessibilityText(for stage: PipelineStage) -> String {
        let count = counts[stage] ?? 0
        if stage.isTerminal {
            return "\(stage.displayName), \(count) leads"
        }
        return "\(stage.displayName), \(count) leads, \(stage.winProbability) percent win probability"
    }
}

#if DEBUG
#Preview("PipelineFooter / mixed counts") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        VStack {
            Spacer()
            PipelineFooter(counts: [
                .newLead: 3,
                .qualifying: 7,
                .quoting: 4,
                .quoted: 2,
                .followUp: 5,
                .negotiation: 1,
                .won: 12,
                .lost: 4
            ])
            .padding(OPSStyle.Layout.spacing3_5)
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("PipelineFooter / empty pipeline") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        VStack {
            Spacer()
            PipelineFooter(counts: [:])
                .padding(OPSStyle.Layout.spacing3_5)
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}
#endif
