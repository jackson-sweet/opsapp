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
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wizardStateManager) private var wizardStateManager
    @Environment(\.wizardTriggerService) private var wizardTriggerService

    @State private var organization: Company?
    @State private var isLoading = true

    // Navigation states
    @State private var showOrganizationDetails = false
    @State private var showManageTeam = false
    @State private var showManageSubscription = false

    private var isCompanyAdmin: Bool {
        permissionStore.can("settings.billing")
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
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
                                CompanyContactCard(
                                    name: company.name,
                                    logoURL: company.logoURL,
                                    logoData: company.logoData,
                                    logoImage: nil,
                                    email: company.email ?? "",
                                    phone: company.phone ?? "",
                                    address: company.address ?? "",
                                    website: company.website ?? "",
                                    teamMemberCount: dataController.getTeamMembers(companyId: company.id).count,
                                    showTeamCount: true
                                )
                                .padding(.horizontal, 20)
                            }

                            // Grouped navigation section
                            settingsSection(title: "ORGANIZATION") {
                                settingsRow(
                                    icon: "building.2.fill",
                                    title: "Organization Details",
                                    action: { showOrganizationDetails = true }
                                )

                                sectionDivider

                                settingsRow(
                                    icon: "person.3.fill",
                                    title: "Manage Team",
                                    action: { showManageTeam = true }
                                )

                                if isCompanyAdmin {
                                    sectionDivider

                                    settingsRow(
                                        icon: "creditcard.fill",
                                        title: "Subscription",
                                        action: { showManageSubscription = true }
                                    )
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
        .trackScreen("Settings.Organization")
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
                    .environment(\.wizardStateManager, wizardStateManager)
                    .environment(\.wizardTriggerService, wizardTriggerService)
            }
            .wizardBannerIfAvailable(stateManager: wizardStateManager)
            .wizardOverlayIfAvailable(stateManager: wizardStateManager)
        }
        // Wizard deep navigation: open ManageTeam when forwarded from SettingsView
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardOpenManageTeamFromOrg"))) { _ in
            showManageTeam = true
        }
        .fullScreenCover(isPresented: $showManageSubscription) {
            NavigationStack {
                ManageSubscriptionView()
                    .environmentObject(dataController)
                    .environmentObject(subscriptionManager)
            }
        }
    }

    // MARK: - Grouped Section Builder

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 0) {
                content()
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    // MARK: - Row Component

    private func settingsRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 28, alignment: .center)

                Text(title)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                Image(OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Divider

    private var sectionDivider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorder)
            .frame(height: 1)
            .padding(.leading, 58)
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

        return parts.joined(separator: " \u{2022} ")
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
            if dataController.isConnected {
                do {
                    try await dataController.forceRefreshCompany(id: companyID)

                    await dataController.triggerTeamMembersSync(companyId: companyID)
                } catch {
                    print("[ORG_SETTINGS] Error refreshing: \(error)")
                }
            }

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
