//
//  AppSettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-13.
//

import SwiftUI

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissionStore: PermissionStore
    @State private var showMapSettings = false
    @State private var showDataSettings = false
    @State private var showSecuritySettings = false
    @State private var showProjectSettings = false
    @State private var showInventorySettings = false
    @State private var showDeveloperDashboard = false
    @State private var developerModeEnabled: Bool = false
    @State private var developerModeExplicitlyDisabled: Bool = false
    @State private var isRestartingTutorial = false

    private var shouldShowDeveloperOptions: Bool {
        // If explicitly disabled, hide even in DEBUG builds
        if developerModeExplicitlyDisabled {
            return false
        }

        #if DEBUG
        return true
        #else
        return developerModeEnabled
        #endif
    }

    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Fixed Header
                SettingsHeader(
                    title: "App Settings",
                    onBackTapped: { dismiss() }
                )

                // Scrollable Settings list
                ScrollView {
                    VStack(spacing: 24) {
                        // APP CONFIGURATION section
                        settingsSection(title: "APP CONFIGURATION") {
                            settingsRow(icon: OPSStyle.Icons.map, title: "Map Settings") {
                                showMapSettings = true
                            }
                            sectionDivider
                            settingsRow(icon: "externaldrive", title: "Data & Storage") {
                                showDataSettings = true
                            }
                            sectionDivider
                            settingsRow(icon: "lock", title: "Security") {
                                showSecuritySettings = true
                            }
                        }

                        // MANAGEMENT section (admin/office only)
                        if permissionStore.can("team.manage") || permissionStore.can("settings.company") {
                            settingsSection(title: "MANAGEMENT") {
                                settingsRow(icon: "hammer.circle", title: "Project Settings") {
                                    showProjectSettings = true
                                }

                                if permissionStore.can("inventory.view") {
                                    sectionDivider
                                    settingsRow(icon: "shippingbox", title: "Inventory Settings") {
                                        showInventorySettings = true
                                    }
                                }
                            }
                        } else if permissionStore.can("inventory.view") {
                            // Field crew with inventory access
                            settingsSection(title: "MANAGEMENT") {
                                settingsRow(icon: "shippingbox", title: "Inventory Settings") {
                                    showInventorySettings = true
                                }
                            }
                        }

                        // OTHER section
                        settingsSection(title: "OTHER") {
                            settingsRow(icon: "graduationcap", title: "Restart Tutorial") {
                                restartTutorial()
                            }

                            if shouldShowDeveloperOptions {
                                sectionDivider
                                settingsRow(icon: "hammer.circle.fill", title: "Developer Tools") {
                                    showDeveloperDashboard = true
                                }
                            }
                        }

                        // App info footer
                        AppInfoCard()
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Load developer mode state
            developerModeEnabled = UserDefaults.standard.bool(forKey: "developerModeEnabled")

            // Check if developer mode was explicitly disabled (even in DEBUG builds)
            #if DEBUG
            // In DEBUG builds, check if it was explicitly disabled
            if !developerModeEnabled && UserDefaults.standard.object(forKey: "developerModeEnabled") != nil {
                developerModeExplicitlyDisabled = true
            }
            #endif
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
        .fullScreenCover(isPresented: $showProjectSettings) {
            NavigationStack {
                ProjectSettingsView()
                    .environmentObject(dataController)
                    .environmentObject(permissionStore)
            }
        }
        .fullScreenCover(isPresented: $showInventorySettings) {
            NavigationStack {
                InventorySettingsView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showDeveloperDashboard) {
            NavigationStack {
                DeveloperDashboard()
                    .environmentObject(dataController)
            }
        }
        // Re-check developer mode state when dashboard dismisses (in case user tapped "Exit Dev Mode")
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

    // MARK: - Gold Standard Helpers

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

    private var sectionDivider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorder)
            .frame(height: 1)
            .padding(.leading, 58)
    }

    // MARK: - Tutorial Restart

    private func restartTutorial() {
        guard dataController.currentUser != nil else {
            print("[SETTINGS] No current user found")
            return
        }

        isRestartingTutorial = true
        print("[SETTINGS] Restarting tutorial (keeping hasCompletedAppTutorial = true)")

        // Trigger tutorial restart and dismiss settings
        // Note: We do NOT reset hasCompletedAppTutorial so SKIP TUTORIAL button remains available
        isRestartingTutorial = false
        appState.shouldRestartTutorial = true
        dismiss()
    }
}

// App info card
struct AppInfoCard: View {
    var body: some View {
        HStack(spacing: 20) {
            // Logo and name
            HStack(spacing: 12) {
                Image("LogoWhite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)

                Text("OPS APP")
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }

            Spacer()

            // Version info
            VStack(alignment: .trailing, spacing: 2) {
                Text("[ VERSION \(AppConfiguration.AppInfo.version.uppercased()) ]")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Text("© 2025 OPS")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
    }
}

#Preview {
    AppSettingsView()
        .preferredColorScheme(.dark)
        .environmentObject(DataController())
        .environmentObject(AppState())
}
