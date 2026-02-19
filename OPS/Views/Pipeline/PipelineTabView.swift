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
                        .foregroundColor(Color.white.opacity(0.15)),
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
                        sectionPlaceholder(title: "INVOICES", icon: OPSStyle.Icons.invoiceReceipt)
                    case .accounting:
                        sectionPlaceholder(title: "ACCOUNTING", icon: OPSStyle.Icons.accountingChart)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.2), value: selectedSection)
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
        }
    }

    private func sectionPlaceholder(title: String, icon: String) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(title)
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text("Coming in Sprint 3+")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.background)
    }
}
