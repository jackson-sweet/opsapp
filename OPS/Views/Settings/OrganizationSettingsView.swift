//
//  OrganizationSettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import Foundation
import SwiftData
import SwiftUI

struct OrganizationSettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var organization: Company?
    @State private var isLoading = true

    // Navigation states
    @State private var showOrganizationDetails = false
    @State private var showManageTeam = false
    @State private var showManageSubscription = false

    private var isCompanyAdmin: Bool {
        dataController.currentUser?.isCompanyAdmin == true || dataController.currentUser?.role == .admin
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Organization",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 24)

                if isLoading {
                    loadingView
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Company contact card preview
                            if let company = organization {
                                CompanyContactCard(company: company, showTeamCount: true)
                                    .padding(.horizontal, 20)
                            }

                            // Navigation sections using SettingsRowCard
                            VStack(spacing: 16) {
                                // Organization Details
                                Button {
                                    showOrganizationDetails = true
                                } label: {
                                    SettingsRowCard(
                                        title: "Organization Details",
                                        description: "Company info, contact details, logo",
                                        iconName: "building.2.fill"
                                    )
                                }

                                // Manage Team
                                Button {
                                    showManageTeam = true
                                } label: {
                                    SettingsRowCard(
                                        title: "Manage Team",
                                        description: "Edit roles, permissions, invite members",
                                        iconName: "person.3.fill"
                                    )
                                }

                                // Manage Subscription (admin only)
                                if isCompanyAdmin {
                                    Button {
                                        showManageSubscription = true
                                    } label: {
                                        SettingsRowCard(
                                            title: "Subscription",
                                            description: subscriptionSummary,
                                            iconName: "creditcard.fill"
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.vertical, 16)
                        .tabBarPadding()
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadOrganizationData()
        }
        .fullScreenCover(isPresented: $showOrganizationDetails) {
            NavigationStack {
                OrganizationDetailsView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showManageTeam) {
            NavigationStack {
                ManageTeamView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showManageSubscription) {
            NavigationStack {
                ManageSubscriptionView()
                    .environmentObject(dataController)
                    .environmentObject(subscriptionManager)
            }
        }
    }

    // MARK: - Computed Properties

    private var subscriptionSummary: String {
        guard let company = organization else {
            return "View plan and seats"
        }

        var parts: [String] = []

        if let plan = company.subscriptionPlan,
           let planEnum = SubscriptionPlan(rawValue: plan) {
            parts.append(planEnum.displayName)
        }

        let seatedCount = company.seatedEmployeeIds
            .split(separator: ",")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count

        parts.append("\(seatedCount)/\(company.maxSeats) seats")

        return parts.joined(separator: " • ")
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                .scaleEffect(1.2)

            Text("Loading organization...")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadOrganizationData() {
        guard let companyID = dataController.currentUser?.companyId else {
            isLoading = false
            return
        }

        Task {
            // Try to refresh from API if connected
            if dataController.isConnected {
                do {
                    try await dataController.forceRefreshCompany(id: companyID)

                    if let company = dataController.getCompany(id: companyID) {
                        await dataController.syncManager?.syncCompanyTeamMembers(company)
                    }
                } catch {
                    print("[ORG_SETTINGS] Error refreshing: \(error)")
                }
            }

            // Load from local database
            let company = dataController.getCompany(id: companyID)

            await MainActor.run {
                self.organization = company
                self.isLoading = false
            }
        }
    }
}

#Preview {
    OrganizationSettingsView()
        .environmentObject(DataController())
        .environmentObject(SubscriptionManager.shared)
        .preferredColorScheme(.dark)
}
