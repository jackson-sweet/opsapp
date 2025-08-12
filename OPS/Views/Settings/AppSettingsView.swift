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
    @State private var showTaskTest = false
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "App Settings",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 24)
                
                // Settings list - using buttons with sheets instead of NavigationLink
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
                    
                    #if DEBUG
                    // Debug section - only visible in debug builds
                    Divider()
                        .background(OPSStyle.Colors.tertiaryText)
                        .padding(.vertical, 8)
                    
                    Text("DEBUG OPTIONS")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Task Test View
                    Button {
                        showTaskTest = true
                    } label: {
                        SettingsRowCard(
                            title: "Task Model Test",
                            description: "Test task-based scheduling models",
                            iconName: "hammer.circle"
                        )
                    }
                    #endif
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // App info
                AppInfoCard()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .padding(.bottom, 90) // Tab bar padding
        }
        .navigationBarBackButtonHidden(true)
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
        .fullScreenCover(isPresented: $showTaskTest) {
            NavigationStack {
                TaskTestView()
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
