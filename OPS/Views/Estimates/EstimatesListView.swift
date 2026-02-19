//
//  EstimatesListView.swift
//  OPS
//
//  List of all company estimates — filter by status, swipe actions, FAB for new estimate.
//

import SwiftUI

struct EstimatesListView: View {
    @StateObject private var viewModel = EstimateViewModel()
    @EnvironmentObject private var dataController: DataController
    @State private var showNewEstimateSheet = false
    @State private var selectedEstimate: Estimate? = nil
    @State private var showConvertConfirm = false
    @State private var estimateToConvert: Estimate? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Search + filter
                searchAndFilter
                    .padding(.top, OPSStyle.Layout.spacing2)

                Divider().background(Color.white.opacity(0.15))

                // Content
                if viewModel.isLoading && viewModel.estimates.isEmpty {
                    Spacer()
                    TacticalLoadingBarAnimated()
                    Spacer()
                } else if viewModel.filteredEstimates.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(viewModel.filteredEstimates) { est in
                                EstimateCard(
                                    estimate: est,
                                    onTap: { selectedEstimate = est },
                                    onSwipeRight: {
                                        if est.status == .draft {
                                            Task { await viewModel.sendEstimate(est) }
                                        } else if est.status == .approved {
                                            estimateToConvert = est
                                            showConvertConfirm = true
                                        }
                                    },
                                    onSwipeLeft: {
                                        // Void not yet implemented
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .padding(.bottom, 80)
                    }
                    .refreshable {
                        await viewModel.loadEstimates()
                    }
                }
            }

            // FAB
            estimatesFAB
        }
        .navigationDestination(item: $selectedEstimate) { est in
            EstimateDetailView(estimate: est, viewModel: viewModel)
        }
        .sheet(isPresented: $showNewEstimateSheet) {
            EstimateFormSheet(viewModel: viewModel)
        }
        .confirmationDialog("Convert to Invoice?", isPresented: $showConvertConfirm) {
            Button("Convert to Invoice") {
                if let est = estimateToConvert {
                    Task { await viewModel.convertToInvoice(est) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will create an invoice from this estimate. This action cannot be undone.")
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
        .task {
            if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                viewModel.setup(companyId: companyId)
                await viewModel.loadEstimates()
            }
        }
    }

    // MARK: - Search & Filter

    private var searchAndFilter: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(EstimateViewModel.EstimateFilter.allCases, id: \.self) { filter in
                        Button(action: { viewModel.selectedFilter = filter }) {
                            Text(filter.rawValue)
                                .font(OPSStyle.Typography.smallCaption)
                                .fontWeight(viewModel.selectedFilter == filter ? .semibold : .regular)
                                .foregroundColor(
                                    viewModel.selectedFilter == filter
                                    ? OPSStyle.Colors.primaryText
                                    : OPSStyle.Colors.tertiaryText
                                )
                                .padding(.horizontal, OPSStyle.Layout.spacing2 + 2)
                                .padding(.vertical, OPSStyle.Layout.spacing1 + 2)
                                .background(
                                    viewModel.selectedFilter == filter
                                    ? OPSStyle.Colors.primaryAccent.opacity(0.2)
                                    : OPSStyle.Colors.cardBackgroundDark.opacity(0.6)
                                )
                                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .stroke(
                                            viewModel.selectedFilter == filter
                                            ? OPSStyle.Colors.primaryAccent
                                            : Color.white.opacity(0.1),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: OPSStyle.Icons.estimateDoc)
                .font(.system(size: 44))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(viewModel.estimates.isEmpty ? "NO ESTIMATES YET" : "NO ESTIMATES MATCH FILTER")
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            if viewModel.estimates.isEmpty {
                Text("Create your first estimate to get started.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                Button("NEW ESTIMATE") { showNewEstimateSheet = true }
                    .opsPrimaryButtonStyle()
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
            }
            Spacer()
        }
    }

    // MARK: - FAB

    private var estimatesFAB: some View {
        Button {
            showNewEstimateSheet = true
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
        .accessibilityLabel("New Estimate")
    }
}
