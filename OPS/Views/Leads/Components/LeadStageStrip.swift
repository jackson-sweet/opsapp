//
//  LeadStageStrip.swift
//  OPS
//
//  Horizontal pinned strip of pipeline stages for the LEADS tab.
//  Each chip: stage-color pip + name (Mohave) + count (JetBrains Mono).
//  Active stage gets underline indicator. Vertical hairline separates
//  active stages from terminal (Won/Lost), which are revealed by tapping
//  a CLOSED chip and rendered at 0.6 opacity.
//
//  NOTE: temporarily named `LeadStageStrip` (file: LeadStageStrip.swift) to
//  coexist with the legacy `StageStripView` in OPS/Views/Books/Pipeline/.
//  Chunk P1-2 deletes the legacy file (plan Task 14); rename back to
//  `StageStripView` (file: StageStripView.swift) after that.
//

import SwiftUI

struct LeadStageStrip: View {
    @Binding var selectedStage: PipelineStage
    @Binding var showClosed: Bool
    let countProvider: (PipelineStage) -> Int

    private let activeStages: [PipelineStage] = [
        .newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation
    ]
    private let terminalStages: [PipelineStage] = [.won, .lost]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(activeStages) { stage in
                    pill(for: stage, terminal: false)
                }
                divider
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(OPSStyle.Animation.standard) {
                        showClosed.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("CLOSED")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Image(systemName: showClosed ? "chevron.left" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                }
                .buttonStyle(PlainButtonStyle())
                if showClosed {
                    ForEach(terminalStages) { stage in
                        pill(for: stage, terminal: true)
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .frame(minHeight: 48)
        .background(OPSStyle.Colors.background)
    }

    @ViewBuilder
    private func pill(for stage: PipelineStage, terminal: Bool) -> some View {
        let isSelected = selectedStage == stage
        let count = countProvider(stage)

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(OPSStyle.Animation.standard) {
                selectedStage = stage
            }
        } label: {
            VStack(spacing: OPSStyle.Layout.spacing1) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(stage.color)
                        .frame(width: 6, height: 6)
                    Text(stage.displayName)
                        .font(isSelected ? OPSStyle.Typography.captionBold : OPSStyle.Typography.caption)
                        .foregroundColor(
                            isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText
                        )
                    if count > 0 {
                        Text("\(count)")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(
                                isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText
                            )
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)

                Rectangle()
                    .fill(isSelected ? OPSStyle.Colors.primaryAccent : Color.clear)
                    .frame(height: OPSStyle.Layout.Border.thick)
            }
            .opacity(terminal ? 0.6 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("\(stage.displayName), \(count) leads")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var divider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorder)
            .frame(width: OPSStyle.Layout.Border.standard, height: 24)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
    }
}

#if DEBUG
private struct LeadStageStripPreviewHost: View {
    @State private var stage: PipelineStage = .qualifying
    @State private var showClosed = false
    private let counts: [PipelineStage: Int] = [
        .newLead: 4, .qualifying: 7, .quoting: 3, .quoted: 2,
        .followUp: 5, .negotiation: 1, .won: 12, .lost: 6
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected: \(stage.displayName)")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal)
            LeadStageStrip(
                selectedStage: $stage,
                showClosed: $showClosed,
                countProvider: { counts[$0] ?? 0 }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 40)
        .background(OPSStyle.Colors.background)
    }
}

#Preview("LeadStageStrip") {
    LeadStageStripPreviewHost()
        .preferredColorScheme(.dark)
}
#endif
