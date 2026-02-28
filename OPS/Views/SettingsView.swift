//
//  SettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//

import SwiftUI
import UIKit
import Foundation

struct SettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @State private var showLogoutConfirmation = false
    @State private var showingSearchSheet = false
    @State private var isRestartingTutorial = false

    // Developer mode state
    @State private var developerModeEnabled: Bool = false
    @State private var developerModeExplicitlyDisabled: Bool = false

    // Navigation destinations (fullScreenCover)
    @State private var showProfileSettings = false
    @State private var showOrganizationSettings = false
    @State private var showSubscriptionSettings = false
    @State private var showNotificationSettings = false
    @State private var showMapSettings = false
    @State private var showDataSettings = false
    @State private var showSecuritySettings = false
    @State private var showProductsServices = false
    @State private var showIntegrations = false
    @State private var showProjectSettings = false
    @State private var showWhatsNew = false
    @State private var showReportIssue = false
    @State private var showDeveloperDashboard = false

    // Role checks
    private var isAdmin: Bool {
        dataController.currentUser?.role == .admin
    }

    private var isAdminOrOffice: Bool {
        let role = dataController.currentUser?.role
        return role == .admin || role == .officeCrew
    }

    private var hasPipelineAccess: Bool {
        dataController.currentUser?.specialPermissions.contains("pipeline") ?? false
    }

    private var shouldShowDeveloperOptions: Bool {
        if developerModeExplicitlyDisabled { return false }
        #if DEBUG
        return true
        #else
        return developerModeEnabled
        #endif
    }

    // All searchable settings
    private var allSearchableSettings: [SearchableSettingItem] {
        var items: [SearchableSettingItem] = []

        // Account items
        items.append(contentsOf: [
            SearchableSettingItem(
                title: "Profile Information",
                categoryTitle: "Account",
                categoryIcon: OPSStyle.Icons.person,
                keywords: ["name", "contact", "personal", "information", "profile", "phone", "email", "address"],
                destination: AnyView(ProfileSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Organization",
                categoryTitle: "Account",
                categoryIcon: "building.2",
                keywords: ["company", "business", "organization", "team", "members"],
                destination: AnyView(OrganizationSettingsView().environmentObject(dataController))
            )
        ])

        if isAdmin {
            items.append(
                SearchableSettingItem(
                    title: "Subscription",
                    categoryTitle: "Account",
                    categoryIcon: "creditcard",
                    keywords: ["subscription", "plan", "billing", "seats", "payment"],
                    destination: AnyView(OrganizationSettingsView().environmentObject(dataController))
                )
            )
        }

        // App items
        items.append(contentsOf: [
            SearchableSettingItem(
                title: "Notifications",
                categoryTitle: "App",
                categoryIcon: OPSStyle.Icons.bellFill,
                keywords: ["notifications", "alerts", "reminders", "quiet", "mute"],
                destination: AnyView(NotificationSettingsView().environmentObject(dataController).environmentObject(NotificationManager.shared))
            ),
            SearchableSettingItem(
                title: "Map Settings",
                categoryTitle: "App",
                categoryIcon: OPSStyle.Icons.map,
                keywords: ["map", "navigation", "display", "zoom", "location"],
                destination: AnyView(MapSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Data & Storage",
                categoryTitle: "App",
                categoryIcon: "externaldrive",
                keywords: ["data", "sync", "storage", "cache"],
                destination: AnyView(DataStorageSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Security & Privacy",
                categoryTitle: "App",
                categoryIcon: "lock",
                keywords: ["security", "privacy", "pin", "biometric", "protection"],
                destination: AnyView(SecuritySettingsView().environmentObject(dataController))
            )
        ])

        // Business items (pipeline permission-gated)
        if hasPipelineAccess {
            items.append(contentsOf: [
                SearchableSettingItem(
                    title: "Products & Services",
                    categoryTitle: "Business",
                    categoryIcon: OPSStyle.Icons.productTag,
                    keywords: ["products", "services", "catalog", "pricing", "labor", "material"],
                    destination: AnyView(ProductsListView())
                ),
                SearchableSettingItem(
                    title: "Integrations",
                    categoryTitle: "Business",
                    categoryIcon: OPSStyle.Icons.accountingChart,
                    keywords: ["integrations", "quickbooks", "sage", "accounting", "sync"],
                    destination: AnyView(IntegrationsSettingsView())
                )
            ])
        }

        if isAdminOrOffice {
            items.append(
                SearchableSettingItem(
                    title: "Project Settings",
                    categoryTitle: "Business",
                    categoryIcon: "hammer.circle",
                    keywords: ["task", "types", "project", "defaults", "scheduling"],
                    destination: AnyView(ProjectSettingsView().environmentObject(dataController))
                )
            )
        }

        // Support items
        items.append(contentsOf: [
            SearchableSettingItem(
                title: "What's New",
                categoryTitle: "Support",
                categoryIcon: "sparkles",
                keywords: ["new", "updates", "features", "changelog", "release"],
                destination: AnyView(WhatsNewView())
            ),
            SearchableSettingItem(
                title: "Report Issue",
                categoryTitle: "Support",
                categoryIcon: OPSStyle.Icons.alert,
                keywords: ["report", "issue", "bug", "problem", "help"],
                destination: AnyView(ReportIssueView())
            )
        ])

        return items
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)

                VStack(alignment: .leading, spacing: 0) {
                    AppHeader(headerType: .settings)

                    ScrollView {
                        VStack(spacing: OPSStyle.Layout.spacing4) {
                            // Search bar
                            searchButton
                                .padding(.horizontal, 20)
                                .padding(.top, 16)

                            // Profile card
                            profileCard
                                .padding(.horizontal, 20)

                            // Account section
                            settingsSection(title: "ACCOUNT") {
                                settingsRow(
                                    icon: "building.2",
                                    title: "Organization",
                                    action: { showOrganizationSettings = true }
                                )

                                if isAdmin {
                                    sectionDivider

                                    settingsRow(
                                        icon: "creditcard",
                                        title: "Subscription",
                                        action: { showSubscriptionSettings = true }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)

                            // App section
                            settingsSection(title: "APP") {
                                settingsRow(
                                    icon: OPSStyle.Icons.bellFill,
                                    title: "Notifications",
                                    action: { showNotificationSettings = true }
                                )

                                sectionDivider

                                settingsRow(
                                    icon: OPSStyle.Icons.map,
                                    title: "Map Settings",
                                    action: { showMapSettings = true }
                                )

                                sectionDivider

                                settingsRow(
                                    icon: "externaldrive",
                                    title: "Data & Storage",
                                    action: { showDataSettings = true }
                                )

                                sectionDivider

                                settingsRow(
                                    icon: "lock",
                                    title: "Security & Privacy",
                                    action: { showSecuritySettings = true }
                                )
                            }
                            .padding(.horizontal, 20)

                            // Business section (admin/office crew, or pipeline permission holders)
                            if isAdminOrOffice || hasPipelineAccess {
                                settingsSection(title: "BUSINESS") {
                                    if hasPipelineAccess {
                                        settingsRow(
                                            icon: OPSStyle.Icons.productTag,
                                            title: "Products & Services",
                                            action: { showProductsServices = true }
                                        )

                                        sectionDivider

                                        settingsRow(
                                            icon: OPSStyle.Icons.accountingChart,
                                            title: "Integrations",
                                            action: { showIntegrations = true }
                                        )

                                        if isAdminOrOffice {
                                            sectionDivider
                                        }
                                    }

                                    if isAdminOrOffice {
                                        settingsRow(
                                            icon: "hammer.circle",
                                            title: "Project Settings",
                                            action: { showProjectSettings = true }
                                        )
                                    }
                                }
                                .padding(.horizontal, 20)
                            }

                            // Support section
                            settingsSection(title: "SUPPORT") {
                                settingsRow(
                                    icon: "sparkles",
                                    title: "What's New",
                                    action: { showWhatsNew = true }
                                )

                                sectionDivider

                                settingsRow(
                                    icon: OPSStyle.Icons.alert,
                                    title: "Report Issue",
                                    action: { showReportIssue = true }
                                )

                                sectionDivider

                                settingsRow(
                                    icon: "graduationcap",
                                    title: "Restart Tutorial",
                                    action: { restartTutorial() }
                                )
                            }
                            .padding(.horizontal, 20)

                            // Developer section (conditional)
                            if shouldShowDeveloperOptions {
                                settingsSection(title: "DEVELOPER") {
                                    settingsRow(
                                        icon: "hammer.circle.fill",
                                        title: "Developer Tools",
                                        action: { showDeveloperDashboard = true }
                                    )
                                }
                                .padding(.horizontal, 20)
                            }

                            // Log out button
                            logOutButton
                                .padding(.horizontal, 20)
                                .padding(.top, 8)

                            // App version footer
                            appVersionFooter
                                .padding(.top, 8)
                                .padding(.bottom, 24)
                        }
                        .padding(.bottom, 90) // Tab bar padding
                    }
                }
            }
        }
        .onAppear {
            AnalyticsManager.shared.trackScreenView(screenName: .settings, screenClass: "SettingsView")
            developerModeEnabled = UserDefaults.standard.bool(forKey: "developerModeEnabled")
            #if DEBUG
            if !developerModeEnabled && UserDefaults.standard.object(forKey: "developerModeEnabled") != nil {
                developerModeExplicitlyDisabled = true
            }
            #endif
        }
        .sheet(isPresented: $showingSearchSheet) {
            SettingsSearchSheet(allSearchableSettings: allSearchableSettings)
                .environmentObject(dataController)
        }
        .alert("Log Out", isPresented: $showLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                dataController.logout()
            }
        } message: {
            Text("Are you sure you want to log out of your account?")
        }
        // MARK: - Navigation Covers
        .fullScreenCover(isPresented: $showProfileSettings) {
            NavigationStack {
                ProfileSettingsView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showOrganizationSettings) {
            NavigationStack {
                OrganizationSettingsView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showSubscriptionSettings) {
            NavigationStack {
                OrganizationSettingsView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showNotificationSettings) {
            NavigationStack {
                NotificationSettingsView()
                    .environmentObject(dataController)
                    .environmentObject(NotificationManager.shared)
            }
        }
        .fullScreenCover(isPresented: $showMapSettings) {
            NavigationStack {
                MapSettingsView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showDataSettings) {
            NavigationStack {
                DataStorageSettingsView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showSecuritySettings) {
            NavigationStack {
                SecuritySettingsView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showProductsServices) {
            NavigationStack {
                ProductsListView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showIntegrations) {
            NavigationStack {
                IntegrationsSettingsView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showProjectSettings) {
            NavigationStack {
                ProjectSettingsView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showWhatsNew) {
            NavigationStack {
                WhatsNewView()
            }
        }
        .fullScreenCover(isPresented: $showReportIssue) {
            NavigationStack {
                ReportIssueView()
            }
        }
        .fullScreenCover(isPresented: $showDeveloperDashboard) {
            NavigationStack {
                DeveloperDashboard()
                    .environmentObject(dataController)
            }
        }
        .onChange(of: showDeveloperDashboard) { _, isShowing in
            if !isShowing {
                developerModeEnabled = UserDefaults.standard.bool(forKey: "developerModeEnabled")
                #if DEBUG
                if !developerModeEnabled && UserDefaults.standard.object(forKey: "developerModeEnabled") != nil {
                    developerModeExplicitlyDisabled = true
                }
                #endif
            }
        }
    }

    // MARK: - Search Button

    private var searchButton: some View {
        Button(action: { showingSearchSheet = true }) {
            HStack(spacing: 12) {
                Image(systemName: OPSStyle.Icons.search)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Text("Search settings...")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        Button(action: { showProfileSettings = true }) {
            HStack(spacing: 14) {
                // Avatar
                profileAvatar

                // Name and subtitle
                VStack(alignment: .leading, spacing: 4) {
                    Text((dataController.currentUser?.fullName ?? "User").uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if let role = dataController.currentUser?.role {
                            Text(role.displayName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }

                        if let email = dataController.currentUser?.email, !email.isEmpty {
                            Text("·")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text(email)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Profile Avatar

    @ViewBuilder
    private var profileAvatar: some View {
        if let user = dataController.currentUser {
            if let imageData = user.profileImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(hex: user.userColor ?? "#59779F") ?? OPSStyle.Colors.primaryAccent)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text("\(user.firstName.prefix(1))\(user.lastName.prefix(1))")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    )
            }
        } else {
            Circle()
                .fill(OPSStyle.Colors.primaryAccent)
                .frame(width: 48, height: 48)
                .overlay(
                    Text("U")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                )
        }
    }

    // MARK: - Grouped Section Builder

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Grouped card
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

                Image(systemName: OPSStyle.Icons.chevronRight)
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
            .padding(.leading, 58) // Inset past icon area
    }

    // MARK: - Log Out

    private var logOutButton: some View {
        Button(action: { showLogoutConfirmation = true }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.errorStatus)

                Text("LOG OUT")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.errorStatus, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - App Version Footer

    private var appVersionFooter: some View {
        HStack(spacing: 12) {
            Image("LogoWhite")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            Text("OPS v\(AppConfiguration.AppInfo.version)")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("·")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("© 2025 OPS")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tutorial Restart

    private func restartTutorial() {
        guard dataController.currentUser != nil else { return }
        isRestartingTutorial = true
        isRestartingTutorial = false
        appState.shouldRestartTutorial = true
    }
}

#Preview {
    SettingsView()
        .environmentObject(DataController())
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
