//
//  PipelineStageStrip.swift
//  OPS
//
//  Horizontal scrollable filter chips for pipeline stage filtering.
//

import SwiftUI

struct PipelineStageStrip: View {
    let stages: [(stage: PipelineStage, count: Int)]
    @Binding var selectedStage: PipelineStage?

    private var totalActiveCount: Int {
        stages
            .filter { !$0.stage.isTerminal }
            .reduce(0) { $0 + $1.count }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    // ALL chip
                    filterChip(
                        id: "all",
                        label: "ALL",
                        count: totalActiveCount,
                        isSelected: selectedStage == nil,
                        stageColor: nil
                    )
                    .id("all")
                    .onTapGesture {
                        withAnimation(OPSStyle.Animation.fast) {
                            selectedStage = nil
                        }
                    }

                    // Per-stage chips
                    ForEach(stages, id: \.stage) { item in
                        filterChip(
                            id: item.stage.rawValue,
                            label: item.stage.displayName,
                            count: item.count,
                            isSelected: selectedStage == item.stage,
                            stageColor: OPSStyle.Colors.pipelineStageColor(for: item.stage)
                        )
                        .id(item.stage.rawValue)
                        .onTapGesture {
                            withAnimation(OPSStyle.Animation.fast) {
                                selectedStage = item.stage
                                proxy.scrollTo(item.stage.rawValue, anchor: .center)
                            }
                        }
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)
            }
        }
        .animation(OPSStyle.Animation.fast, value: selectedStage)
    }

    // MARK: - Filter Chip

    private func filterChip(
        id: String,
        label: String,
        count: Int,
        isSelected: Bool,
        stageColor: Color?
    ) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            if let color = stageColor {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }

            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .fontWeight(.medium)

            if count > 0 {
                Text("\(count)")
                    .font(OPSStyle.Typography.smallCaption)
                    .opacity(isSelected ? 0.7 : 0.5)
            }
        }
        .foregroundColor(isSelected ? OPSStyle.Colors.invertedText : OPSStyle.Colors.secondaryText)
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        .background(
            isSelected
            ? OPSStyle.Colors.primaryText
            : OPSStyle.Colors.cardBackgroundDark
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(
                    isSelected ? Color.clear : OPSStyle.Colors.cardBorder,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
    }
}
