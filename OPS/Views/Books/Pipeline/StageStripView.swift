//
//  StageStripView.swift
//  OPS
//
//  Horizontal pinned strip of pipeline stages. Active stage highlighted with
//  underline accent + bold label. Vertical divider separates active from
//  terminal stages (Won/Lost). Tap a pill to focus that stage.
//

import SwiftUI

struct StageStripView: View {
    @Binding var selectedStage: PipelineStage
    let countProvider: (PipelineStage) -> Int

    private let activeStages: [PipelineStage] = [
        .newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation
    ]
    private let terminalStages: [PipelineStage] = [.won, .lost]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(activeStages) { stage in
                    pill(for: stage)
                }
                divider
                ForEach(terminalStages) { stage in
                    pill(for: stage, terminal: true)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .frame(minHeight: 48)
        .background(OPSStyle.Colors.background)
    }

    @ViewBuilder
    private func pill(for stage: PipelineStage, terminal: Bool = false) -> some View {
        let isSelected = selectedStage == stage
        let count = countProvider(stage)

        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(OPSStyle.Animation.standard) {
                selectedStage = stage
            }
        }) {
            VStack(spacing: OPSStyle.Layout.spacing1) {
                HStack(spacing: 6) {
                    Text(stage.displayName)
                        .font(isSelected ? OPSStyle.Typography.captionBold : OPSStyle.Typography.caption)
                        .foregroundColor(
                            isSelected
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.secondaryText
                        )
                    if count > 0 {
                        Text("\(count)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(
                                isSelected
                                    ? OPSStyle.Colors.primaryAccent
                                    : OPSStyle.Colors.tertiaryText
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
    }

    private var divider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorder)
            .frame(width: OPSStyle.Layout.Border.standard, height: 24)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
    }
}
