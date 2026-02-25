//
//  PipelinePlaceholderView.swift
//  OPS
//
//  Placeholder for the Pipeline CRM tab — will be replaced by PipelineKanbanView in Sprint 2.
//

import SwiftUI

struct PipelinePlaceholderView: View {
    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            Image(systemName: OPSStyle.Icons.pipelineChart)
                .font(OPSStyle.Typography.largeTitle)
                .foregroundColor(OPSStyle.Colors.primaryAccent)

            Text("PIPELINE")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("Coming soon")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.background)
    }
}
