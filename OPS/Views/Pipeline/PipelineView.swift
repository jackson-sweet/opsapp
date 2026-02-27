//
//  PipelineView.swift
//  OPS
//
//  Pipeline CRM — stage-filtered opportunity cards with search and swipe gestures.
//

import SwiftUI

struct PipelineView: View {
    @StateObject private var viewModel = PipelineViewModel()
    @EnvironmentObject private var dataController: DataController
    @State private var selectedOpportunity: Opportunity? = nil
    @State private var showLostSheet = false
    @State private var opportunityToMarkLost: Opportunity? = nil

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // 1. Search bar
            SearchBar(searchText: $viewModel.searchText, placeholder: "Search deals...")
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)

            // 2. Metrics strip
            metricsStrip

            // 3. Stage filter strip
            PipelineStageStrip(
                stages: viewModel.stagesWithCounts,
                selectedStage: $viewModel.selectedStage
            )

            // 4. Content
            if viewModel.isLoading && viewModel.opportunities.isEmpty {
                Spacer()
                TacticalLoadingBarAnimated()
                Spacer()
            } else if viewModel.filteredOpportunities.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(viewModel.filteredOpportunities) { opp in
                            OpportunityCard(
                                opportunity: opp,
                                onTap: { selectedOpportunity = opp },
                                onAdvance: {
                                    Task { await viewModel.advanceStage(opportunity: opp) }
                                },
                                onLost: {
                                    opportunityToMarkLost = opp
                                    showLostSheet = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                }
                .refreshable {
                    await viewModel.loadOpportunities()
                }
            }
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .navigationDestination(item: $selectedOpportunity) { opp in
            OpportunityDetailView(opportunity: opp, viewModel: viewModel)
        }
        .sheet(isPresented: $showLostSheet) {
            if let opp = opportunityToMarkLost {
                MarkLostSheet(opportunity: opp) { reason in
                    Task { await viewModel.markLost(opportunity: opp, reason: reason) }
                }
            }
        }
        .task {
            if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                viewModel.setup(companyId: companyId)
                await viewModel.loadOpportunities()
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - Metrics Strip

    private var metricsStrip: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            metricPill(label: "DEALS", value: "\(viewModel.activeDealsCount)")
            metricPill(
                label: "WEIGHTED",
                value: currencyFormatter.string(from: NSNumber(value: viewModel.weightedPipelineValue)) ?? "$0"
            )
            metricPill(
                label: "TOTAL",
                value: currencyFormatter.string(from: NSNumber(value: viewModel.totalPipelineValue)) ?? "$0"
            )
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing2)
    }

    private func metricPill(label: String, value: String) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text(value)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: viewModel.opportunities.isEmpty
                  ? OPSStyle.Icons.pipelineChart
                  : OPSStyle.Icons.filter)
                .font(OPSStyle.Typography.largeTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(viewModel.opportunities.isEmpty ? "NO LEADS YET" : "NO DEALS IN THIS STAGE")
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            if viewModel.opportunities.isEmpty {
                Text("Use the + button to create your first lead.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
            }
            Spacer()
        }
    }
}
