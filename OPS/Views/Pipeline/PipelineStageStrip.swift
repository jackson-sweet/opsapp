//
//  PipelineStageStrip.swift
//  OPS
//
//  Horizontal scrolling stage selector for the Pipeline Kanban.
//

import SwiftUI

struct PipelineStageStrip: View {
    let stages: [(stage: PipelineStage, count: Int)]
    @Binding var selectedStage: PipelineStage

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(stages, id: \.stage) { item in
                    Button(action: { selectedStage = item.stage }) {
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Text(item.stage.displayName)
                                    .font(OPSStyle.Typography.smallCaption)
                                    .fontWeight(.medium)
                                if item.count > 0 {
                                    Text("·\(item.count)")
                                        .font(OPSStyle.Typography.smallCaption)
                                }
                            }
                            .foregroundColor(
                                selectedStage == item.stage
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.tertiaryText
                            )

                            Rectangle()
                                .frame(height: 2)
                                .foregroundColor(
                                    selectedStage == item.stage
                                    ? OPSStyle.Colors.primaryAccent
                                    : Color.clear
                                )
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .frame(minWidth: OPSStyle.Layout.touchTargetStandard)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.4))
        .animation(.easeInOut(duration: 0.2), value: selectedStage)
    }
}
