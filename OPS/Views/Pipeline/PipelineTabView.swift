//
//  PipelineTabView.swift
//  OPS
//
//  Container for the Pipeline tab — segmented nav between Pipeline, Estimates, Invoices, Accounting.
//

import SwiftUI

enum PipelineSection: String, CaseIterable {
    case pipeline   = "PIPELINE"
    case estimates  = "ESTIMATES"
    case invoices   = "INVOICES"
    case accounting = "ACCOUNTING"
}

struct PipelineTabView: View {
    @State private var selectedSection: PipelineSection = .pipeline

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control header
                HStack(spacing: 0) {
                    ForEach(PipelineSection.allCases, id: \.self) { section in
                        Button(action: { selectedSection = section }) {
                            VStack(spacing: 4) {
                                Text(section.rawValue)
                                    .font(OPSStyle.Typography.smallCaption)
                                    .fontWeight(selectedSection == section ? .semibold : .regular)
                                    .foregroundColor(
                                        selectedSection == section
                                        ? OPSStyle.Colors.primaryText
                                        : OPSStyle.Colors.tertiaryText
                                    )
                                Rectangle()
                                    .frame(height: 2)
                                    .foregroundColor(
                                        selectedSection == section
                                        ? OPSStyle.Colors.primaryAccent
                                        : Color.clear
                                    )
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetStandard)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .background(OPSStyle.Colors.background)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(OPSStyle.Colors.separator),
                    alignment: .bottom
                )

                // Content
                Group {
                    switch selectedSection {
                    case .pipeline:
                        PipelineView()
                    case .estimates:
                        EstimatesListView()
                    case .invoices:
                        InvoicesListView()
                    case .accounting:
                        AccountingDashboard()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(OPSStyle.Animation.fast, value: selectedSection)
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
        }
    }
}
