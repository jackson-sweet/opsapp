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
                AppHeader(headerType: .pipeline)

                SegmentedControl(selection: $selectedSection, options: [
                    (.pipeline, "PIPELINE"),
                    (.estimates, "ESTIMATES"),
                    (.invoices, "INVOICES"),
                    (.accounting, "ACCOUNTING")
                ])
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)

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
