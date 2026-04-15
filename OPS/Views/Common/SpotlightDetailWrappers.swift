//
//  SpotlightDetailWrappers.swift
//  OPS
//
//  Thin wrappers around InvoiceDetailView / EstimateDetailView that create and
//  initialize their view models before presenting. Used by the deep-link sheet
//  presentations in MainTabView (Spotlight taps, universal links, push notifications).
//

import SwiftUI
import SwiftData

struct InvoiceDetailViewDeepLinkWrapper: View {
    let invoice: Invoice
    let companyId: String

    @StateObject private var viewModel = InvoiceViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        InvoiceDetailView(invoice: invoice, viewModel: viewModel)
            .onAppear {
                viewModel.setup(companyId: companyId, modelContext: modelContext)
            }
    }
}

struct EstimateDetailViewDeepLinkWrapper: View {
    let estimate: Estimate
    let companyId: String

    @StateObject private var viewModel = EstimateViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        EstimateDetailView(estimate: estimate, viewModel: viewModel)
            .onAppear {
                viewModel.setup(companyId: companyId, modelContext: modelContext)
            }
    }
}
