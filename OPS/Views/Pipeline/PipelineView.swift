//
//  PipelineView.swift
//  OPS
//
//  Pipeline Kanban — stage-filtered opportunity cards with swipe gestures and FAB.
//

import SwiftUI

struct PipelineView: View {
    @StateObject private var viewModel = PipelineViewModel()
    @EnvironmentObject private var dataController: DataController
    @State private var showNewOpportunitySheet = false
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
        ZStack(alignment: .bottomTrailing) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header metrics
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PIPELINE")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text("\(currencyFormatter.string(from: NSNumber(value: viewModel.weightedPipelineValue)) ?? "$0") WEIGHTED · \(viewModel.activeDealsCount) DEALS")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    Spacer()
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing2)

                // Stage strip
                PipelineStageStrip(
                    stages: viewModel.stagesWithCounts,
                    selectedStage: $viewModel.selectedStage
                )

                Divider()
                    .background(Color.white.opacity(0.15))

                // Cards list
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
                        .padding(.bottom, 80) // FAB clearance
                    }
                    .refreshable {
                        await viewModel.loadOpportunities()
                    }
                }
            }

            // FAB
            pipelineFAB
        }
        .navigationDestination(item: $selectedOpportunity) { opp in
            OpportunityDetailView(opportunity: opp, viewModel: viewModel)
        }
        .sheet(isPresented: $showNewOpportunitySheet) {
            OpportunityFormSheet(viewModel: viewModel)
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
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: viewModel.opportunities.isEmpty
                  ? OPSStyle.Icons.pipelineChart
                  : "line.3.horizontal.decrease.circle")
                .font(.system(size: 44))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(viewModel.opportunities.isEmpty ? "NO LEADS YET" : "NO DEALS IN THIS STAGE")
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            if viewModel.opportunities.isEmpty {
                Text("Create your first lead to get started.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                Button("NEW LEAD") { showNewOpportunitySheet = true }
                    .opsPrimaryButtonStyle()
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
            }
            Spacer()
        }
    }

    // MARK: - Pipeline FAB

    private var pipelineFAB: some View {
        Button {
            showNewOpportunitySheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.white)
                .frame(width: OPSStyle.Layout.touchTargetLarge, height: OPSStyle.Layout.touchTargetLarge)
                .background(OPSStyle.Colors.primaryAccent)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .padding(OPSStyle.Layout.spacing3)
        .accessibilityLabel("New Lead")
    }
}
