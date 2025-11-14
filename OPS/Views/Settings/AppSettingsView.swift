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
    @State private var showMapSettings = false
    @State private var showNotificationSettings = false
    @State private var showDataSettings = false
    @State private var showSecuritySettings = false
    @State private var showProjectSettings = false
    @State private var showDeveloperDashboard = false
    @State private var developerModeEnabled: Bool = false
    @State private var developerModeExplicitlyDisabled: Bool = false
    
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
                .padding(.bottom, 24)

                // Scrollable Settings list
                ScrollView {
                    VStack(spacing: 16) {
                    // Map Settings
                    Button {
                        showMapSettings = true
                    } label: {
                        SettingsRowCard(
                            title: "Map Settings",
                            description: "Customize map display and behavior",
                            iconName: "map"
                        )
                    }

                    // Notifications
                    Button {
                        showNotificationSettings = true
                    } label: {
                        SettingsRowCard(
                            title: "Notification Settings",
                            description: "Manage notifications and reminders",
                            iconName: "bell"
                        )
                    }

                    // Data & Storage
                    Button {
                        showDataSettings = true
                    } label: {
                        SettingsRowCard(
                            title: "Data & Storage",
                            description: "Control synchronization and storage",
                            iconName: "externaldrive"
                        )
                    }

                    // Security
                    Button {
                        showSecuritySettings = true
                    } label: {
                        SettingsRowCard(
                            title: "Security",
                            description: "Manage app security preferences",
                            iconName: "lock"
                        )
                    }

                    // Project Settings - only for admin and office crew
                    if let user = dataController.currentUser,
                       (user.role == .admin || user.role == .officeCrew) {
                        Button {
                            showProjectSettings = true
                        } label: {
                            SettingsRowCard(
                                title: "Project Settings",
                                description: "Manage task types and project defaults",
                                iconName: "hammer.circle"
                            )
                        }
                    }

                    // Developer Tools section - visible in debug builds or when developer mode is enabled
                    if shouldShowDeveloperOptions {
                        Divider()
                            .background(OPSStyle.Colors.tertiaryText)
                            .padding(.vertical, 8)

                        // Developer Tools Card
                        Button {
                            showDeveloperDashboard = true
                        } label: {
                            SettingsRowCard(
                                title: "Developer Tools",
                                description: "Access debugging and testing tools",
                                iconName: "hammer.circle.fill"
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 80) // Extra padding for fixed footer
                }

                Spacer()

                // Fixed footer at bottom
                AppInfoCard()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .padding(.bottom, 90) // Tab bar padding
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
        .fullScreenCover(isPresented: $showNotificationSettings) {
            NavigationStack {
                NotificationSettingsView()
                    .environmentObject(dataController)
                    .environmentObject(NotificationManager.shared)
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
            }
        }
        .fullScreenCover(isPresented: $showDeveloperDashboard) {
            NavigationStack {
                DeveloperDashboard()
                    .environmentObject(dataController)
            }
        }
    }
}

// Simple settings row card
struct SettingsRowCard: View {
    let title: String
    let description: String
    let iconName: String
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: iconName)
                .font(.system(size: 24, weight: .light))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: 30)
            
            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(OPSStyle.Typography.cardBody)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(24)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
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
                    .foregroundColor(.white)
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
}
