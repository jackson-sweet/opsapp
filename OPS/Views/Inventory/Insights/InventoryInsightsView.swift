//
//  InventoryInsightsView.swift
//  OPS
//
//  Full-screen inventory analytics dashboard.
//  Presented as a sheet from the inventory app header.
//

import SwiftUI
import SwiftData

struct InventoryInsightsView: View {
    @EnvironmentObject private var dataController: DataController
    @StateObject private var viewModel: InventoryInsightsViewModel
    @Environment(\.dismiss) private var dismiss
    @Query private var inventoryItems: [InventoryItem]

    @State private var showThresholdSetup = false

    init(companyId: String) {
        self._viewModel = StateObject(wrappedValue: InventoryInsightsViewModel(companyId: companyId))
    }

    /// True if no items have any thresholds set
    private var noThresholdsConfigured: Bool {
        activeItems.allSatisfy { $0.warningThreshold == nil && $0.criticalThreshold == nil }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    // Loading state
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                            .scaleEffect(1.2)
                        Text("Analyzing inventory...")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                                // 1. Health Summary
                                healthSummaryRow(proxy: proxy)

                                // 2. Consumption Trends
                                ConsumptionChart(viewModel: viewModel)
                                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                                // 3. Depletion Forecast
                                DepletionForecastChart(
                                    forecasts: viewModel.depletionForecasts,
                                    onItemTap: { _ in
                                        dismiss()
                                    }
                                )
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                                // 4. Top Movers
                                TopMoversSection(
                                    movers: viewModel.topMovers,
                                    onItemTap: { _ in
                                        dismiss()
                                    }
                                )
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                                // 5. Stock Alerts (or setup CTA if no thresholds)
                                if noThresholdsConfigured && !activeItems.isEmpty {
                                    thresholdSetupCTA
                                        .id("stockAlerts")
                                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                } else {
                                    StockAlertsSection(
                                        criticalAlerts: viewModel.criticalAlerts,
                                        warningAlerts: viewModel.warningAlerts,
                                        onUpdateThreshold: { itemId, warning, critical in
                                            Task {
                                                await viewModel.updateThreshold(
                                                    itemId: itemId,
                                                    warning: warning,
                                                    critical: critical
                                                )
                                            }
                                        },
                                        onItemTap: { _ in
                                            dismiss()
                                        }
                                    )
                                    .id("stockAlerts")
                                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                }

                                Spacer().frame(height: 40)
                            }
                            .padding(.vertical, OPSStyle.Layout.spacing3)
                        }
                        .refreshable {
                            await viewModel.loadData(items: activeItems)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .top) {
                // Header
                SettingsHeader(
                    title: "Inventory Insights",
                    onBackTapped: { dismiss() }
                )
                .background(OPSStyle.Colors.background)
            }
        }
        .onAppear {
            Task {
                await viewModel.loadData(items: activeItems)
            }
        }
        .sheet(isPresented: $showThresholdSetup) {
            NavigationStack {
                InventoryThresholdSetupView(
                    items: activeItems,
                    onApply: {
                        showThresholdSetup = false
                        Task { await viewModel.loadData(items: activeItems) }
                    },
                    onSkip: {
                        showThresholdSetup = false
                    }
                )
                .environmentObject(dataController)
            }
        }
    }

    private var activeItems: [InventoryItem] {
        inventoryItems.filter { $0.deletedAt == nil }
    }

    // MARK: - Threshold Setup CTA

    private var thresholdSetupCTA: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text("STOCK ALERTS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            VStack(spacing: OPSStyle.Layout.spacing3) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 28))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                Text("Set up stock alerts")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("Get notified when materials run low. We'll suggest thresholds based on your current quantities.")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)

                Button {
                    showThresholdSetup = true
                } label: {
                    Text("AUTO-SUGGEST THRESHOLDS")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.invertedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Set manually")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .underline()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(OPSStyle.Layout.spacing3_5)
            .glassSurface()
        }
    }

    private func healthSummaryRow(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            HealthSummaryCard(
                icon: "shippingbox",
                value: viewModel.healthSummary.totalItems,
                label: "ITEMS TRACKED",
                valueColor: OPSStyle.Colors.primaryText,
                iconColor: OPSStyle.Colors.secondaryText
            )

            HealthSummaryCard(
                icon: "exclamationmark.triangle",
                value: viewModel.healthSummary.lowStockCount,
                label: "LOW STOCK",
                valueColor: viewModel.healthSummary.lowStockCount > 0
                    ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.secondaryText,
                iconColor: OPSStyle.Colors.warningStatus
            )
            .onTapGesture {
                withAnimation { proxy.scrollTo("stockAlerts", anchor: .top) }
            }

            HealthSummaryCard(
                icon: "xmark.octagon",
                value: viewModel.healthSummary.criticalCount,
                label: "CRITICAL",
                valueColor: viewModel.healthSummary.criticalCount > 0
                    ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.secondaryText,
                iconColor: OPSStyle.Colors.errorStatus
            )
            .onTapGesture {
                withAnimation { proxy.scrollTo("stockAlerts", anchor: .top) }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, 60) // Clear the header
    }
}
