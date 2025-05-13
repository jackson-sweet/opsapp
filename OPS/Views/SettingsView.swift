//
//  SettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @State private var showLogoutConfirmation = false
    @State private var selectedSection: SettingsSection?
    
    @AppStorage("syncOnLaunch") private var syncOnLaunch = true
    @AppStorage("backgroundSyncEnabled") private var backgroundSyncEnabled = true
    @AppStorage("mapSettings") private var showMapSettings = false
    
    enum SettingsSection: String, Identifiable, CaseIterable {
        case profile = "Profile Settings"
        case organization = "Organization Settings"
        case projectHistory = "Project & Expense History"
        case notifications = "Notification Settings"
        case mapSettings = "Map Settings"
        
        var id: String { self.rawValue }
        
        var iconName: String {
            switch self {
            case .profile:
                return "person.fill"
            case .organization:
                return "building.2.fill"
            case .projectHistory:
                return "clock.arrow.circlepath"
            case .notifications:
                return "bell.fill"
            case .mapSettings:
                return "map.fill"
            }
        }
        
        var description: String {
            switch self {
            case .profile:
                return "Personal information, contact details"
            case .organization:
                return "Company information, team members"
            case .projectHistory:
                return "Past projects, expense records"
            case .notifications:
                return "Manage notifications and reminders"
            case .mapSettings:
                return "Customize map display and behavior"
            }
        }
    }
    
    // Main sections for List to break up the large expression
    private var settingsSection: some View {
        Section(header: Text("SETTINGS")
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(OPSStyle.Colors.secondaryText)) {
            ForEach(SettingsSection.allCases.filter { $0 != .mapSettings }, id: \.self) { section in
                NavigationLink(value: section) {
                    SettingsSectionRow(section: section)
                }
                .listRowBackground(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            }
        }
    }
    
    private var appSettingsSection: some View {
        Section(header: Text("APP SETTINGS")
            .font(OPSStyle.Typography.cardTitle)
            .foregroundColor(OPSStyle.Colors.secondaryText)) {
            
            // Map settings link
            NavigationLink(value: SettingsSection.mapSettings) {
                SettingsSectionRow(section: SettingsSection.mapSettings)
            }
            .listRowBackground(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            
            // Sync toggles
            VStack(spacing: 16) {
                SettingsToggle(
                    title: "Sync on App Launch",
                    description: "Automatically sync data when app starts",
                    isOn: $syncOnLaunch
                )
                
                SettingsToggle(
                    title: "Background Sync",
                    description: "Sync data when app is in the background",
                    isOn: $backgroundSyncEnabled
                )
            }
            .padding(.vertical, 8)
            .listRowBackground(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        }
    }
    
    private var accountActionsSection: some View {
        Section {
            Button(action: {
                showLogoutConfirmation = true
            }) {
                HStack {
                    Image(systemName: "arrow.right.square")
                        .font(.system(size: 16))
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                    
                    Text("Log Out")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            }
            .listRowBackground(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        }
    }
    
    private var appVersionSection: some View {
        Section {
            HStack {
                Image("AppIcon") // Placeholder for actual logo
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                
                Text("OPS APP")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
                
                Text("v1.0.0")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .listRowBackground(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        }
    }
    
    // Helper view to simplify section rows
    private struct SettingsSectionRow: View {
        let section: SettingsSection
        
        var body: some View {
            HStack(spacing: 16) {
                // Icon in colored circle
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: section.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(section.description)
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
    }
    
    var body: some View {
        // Navigation stack for drilling down view
        NavigationStack {
            ZStack {
                // Background gradient
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)
                
                // Main content - removed outer ScrollView to minimize scroll views
                VStack(alignment: .leading, spacing: 0) {
                    // Header without gradient
                    AppHeader(headerType: .settings)
                        .padding(.horizontal, 4)
                    
                    // User profile summary
                    if let user = dataController.currentUser {
                        UserProfileCard(user: user)
                            .padding(.bottom, 16)
                    }
                    
                    // Use List for settings to match design inspiration
                    List {
                        settingsSection
                        appSettingsSection
                        accountActionsSection
                        appVersionSection
                    }
                    .listStyle(PlainListStyle())
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationDestination(for: SettingsSection.self) { section in
                switch section {
                case .profile:
                    ProfileSettingsView()
                case .organization:
                    OrganizationSettingsView()
                case .projectHistory:
                    ProjectHistorySettingsView()
                case .notifications:
                    NotificationSettingsView()
                case .mapSettings:
                    MapSettingsView()
                }
            }
        }
        .alert("Log Out", isPresented: $showLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                logout()
            }
        } message: {
            Text("Are you sure you want to log out of your account?")
        }
    }
    
    private var settingsContent: some View {
        VStack(spacing: 12) {
            ForEach(SettingsSection.allCases) { section in
                NavigationLink(value: section) {
                    HStack(spacing: 16) {
                        // Icon in colored circle
                        ZStack {
                            Circle()
                                .fill(OPSStyle.Colors.primaryAccent.opacity(0.2))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: section.iconName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.rawValue)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text(section.description)
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .contentShape(Rectangle())
                    .padding(16)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func logout() {
        // Simple, direct logout function
        dataController.logout()
    }
}
