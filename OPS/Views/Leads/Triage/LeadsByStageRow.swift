//
//  LeadsByStageRow.swift
//  OPS
//
//  Money & Leads redesign (2026-06-30) — the by-stage glance for the Leads tab.
//  A horizontal strip of stage tiles (count + value per open stage); tapping a
//  tile opens that stage's list. Replaces the vertical "BY STAGE" footer.
//

import SwiftUI

struct LeadsByStageRow: View {
    let viewModel: PipelineViewModel
    var onStageTap: (PipelineStage) -> Void

    private static let openStages: [PipelineStage] = [.newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation]

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: 0) {
                Text("// ").foregroundColor(OPSStyle.Colors.textMute)
                Text("PIPELINE BY STAGE").foregroundColor(OPSStyle.Colors.text3)
            }
            .font(.custom("JetBrainsMono-Medium", size: 10))
            .tracking(1.4)
            .textCase(.uppercase)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(Self.openStages, id: \.self) { stage in
                        stageTile(stage)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }
        }
    }

    private func stageTile(_ stage: PipelineStage) -> some View {
        let leads = viewModel.opportunities(in: stage)
        let value = leads.reduce(0.0) { $0 + ($1.estimatedValue ?? 0) }
        return Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onStageTap(stage)
        }) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(stage.shortLabel)
                    .font(.custom("JetBrainsMono-Medium", size: 8))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.pipelineStageColor(for: stage))
                Text("\(leads.count)")
                    .font(.custom("JetBrainsMono-Medium", size: 15))
                    .foregroundColor(OPSStyle.Colors.text)
                    .monospacedDigit()
                Text(value > 0 ? BooksFormat.compact(value) : "—")
                    .font(.custom("JetBrainsMono-Regular", size: 9))
                    .foregroundColor(OPSStyle.Colors.text3)
                    .monospacedDigit()
            }
            .frame(minWidth: 78, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).fill(OPSStyle.Colors.surfaceInput))
            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).strokeBorder(OPSStyle.Colors.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.displayName), \(leads.count) leads")
    }
}
