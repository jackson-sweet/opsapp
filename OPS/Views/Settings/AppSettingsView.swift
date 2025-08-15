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
    @State private var showTaskList = false
    @State private var showCalendarEvents = false
    @State private var showAPICallsDebug = false
    @State private var developerModeEnabled: Bool = false
    
    private var shouldShowDeveloperOptions: Bool {
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
                    
                    // Debug section - visible in debug builds or when developer mode is enabled
                    if shouldShowDeveloperOptions {
                        Divider()
                            .background(OPSStyle.Colors.tertiaryText)
                            .padding(.vertical, 8)
                        
                        Text("DEVELOPER OPTIONS")
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
                        
                        // Task List View
                        Button {
                            showTaskList = true
                        } label: {
                            SettingsRowCard(
                                title: "Task List Debug",
                                description: "View all tasks with full field details",
                                iconName: "list.bullet.rectangle"
                            )
                        }
                        
                        // Calendar Events View
                        Button {
                            showCalendarEvents = true
                        } label: {
                            SettingsRowCard(
                                title: "Calendar Events Debug",
                                description: "View all calendar events with details",
                                iconName: "calendar.badge.clock"
                            )
                        }
                        
                        // API Calls Debug View
                        Button {
                            showAPICallsDebug = true
                        } label: {
                            SettingsRowCard(
                                title: "API Calls Debug",
                                description: "Test API endpoints and view responses",
                                iconName: "network"
                            )
                        }
                        
                        // Exit developer mode button - always show at bottom
                        Divider()
                            .background(OPSStyle.Colors.tertiaryText)
                            .padding(.vertical, 8)
                        
                        Button {
                            UserDefaults.standard.set(false, forKey: "developerModeEnabled")
                            UserDefaults.standard.synchronize()
                            developerModeEnabled = false
                            print("🔧 Developer mode deactivated")
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                                Text("Exit Developer Mode")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(OPSStyle.Colors.errorStatus, lineWidth: 1)
                            )
                        }
                        .padding(.top, 8)
                    }
                    
                    // App info at the bottom of scroll content
                    AppInfoCard()
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 90) // Tab bar padding
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Load developer mode state
            #if !DEBUG
            developerModeEnabled = UserDefaults.standard.bool(forKey: "developerModeEnabled")
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
        .fullScreenCover(isPresented: $showTaskTest) {
            NavigationStack {
                TaskTestView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showTaskList) {
            NavigationStack {
                TaskListDebugView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showCalendarEvents) {
            NavigationStack {
                CalendarEventsDebugView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showAPICallsDebug) {
            NavigationStack {
                APICallsDebugView()
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
