//
//  PipelineFooter.swift
//  OPS
//
//  Secondary drill-down at the bottom of the triage screen. For the operator
//  who wants to browse by pipeline stage rather than urgency. Renders as a
//  single L1 glass panel containing one row per active stage:
//
//    // BY STAGE                           OPEN STAGE BOARD →
//    ┌───────────────────────────────────────────────────────┐
//    │ NEW LEAD                                03 · 10%   →  │
//    │ QUALIFYING                              07 · 20%   →  │
//    │ QUOTING                                 04 · 40%   →  │
//    │ QUOTED                                  02 · 60%   →  │
//    │ FOLLOW-UP                               05 · 50%   →  │
//    │ NEGOTIATION                             01 · 75%   →  │
//    └───────────────────────────────────────────────────────┘
//
//  Tapping a row navigates to a filtered single-stage list (per plan §2.1
//  Q2 = (b)). Chevrons are textMute — never accent (per spec).
//

import SwiftUI

struct PipelineFooter: View {
    /// Count of open leads per stage, keyed by PipelineStage.
    let counts: [PipelineStage: Int]
    /// Tap on a stage row. Engineering wires this to push the per-stage
    /// filtered list.
    var onStageTap: (PipelineStage) -> Void = { _ in }
    /// Tap on the trailing `OPEN STAGE BOARD →` link. Phase 6 may build a
    /// dedicated board view; v1 routes to whichever first-active-stage list.
    var onBoardTap: () -> Void = {}

    private let stages: [PipelineStage] = [
        .newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSectionHeader(
                label: "BY STAGE",
                hint: "OPEN STAGE BOARD →",
                onHintTap: onBoardTap
            )

            VStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.element) { idx, stage in
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onStageTap(stage)
                    }) {
                        row(for: stage)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(stage.displayName), \(counts[stage] ?? 0) leads, \(stage.winProbability) percent win probability")

                    if idx < stages.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 1)
                            .padding(.horizontal, 14)
                    }
                }
            }
            .glassSurface()
        }
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

            Text("·")
                .foregroundColor(OPSStyle.Colors.textMute)
                .font(.custom("JetBrainsMono-Regular", size: 10))

            Text("\(stage.winProbability)%")
                .font(.custom("JetBrainsMono-Regular", size: 10))
                .foregroundColor(OPSStyle.Colors.text3)
                .monospacedDigit()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(OPSStyle.Colors.textMute)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)        // 44pt tap target, gloves-on
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
                .negotiation: 1
            ])
            .padding(20)
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
                .padding(20)
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}
#endif
