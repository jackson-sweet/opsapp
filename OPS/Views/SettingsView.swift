//
//  SettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @State private var showLogoutConfirmation = false
    @State private var selectedSection: SettingsSection?
    
    @AppStorage("syncOnLaunch") private var syncOnLaunch = true
    @AppStorage("backgroundSyncEnabled") private var backgroundSyncEnabled = true
    
    enum SettingsSection: String, Identifiable {
        case profile = "Profile Settings"
        case organization = "Organization Settings"
        case projectHistory = "Project & Expense History"
        
        var id: String { self.rawValue }
        
        var iconName: String {
            switch self {
            case .profile: return "person.fill"
            case .organization: return "building.2.fill"
            case .projectHistory: return "clock.arrow.circlepath"
            }
        }
        
        var description: String {
            switch self {
            case .profile: return "Personal information, contact details"
            case .organization: return "Company information, team members"
            case .projectHistory: return "Past projects, expense records"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header without gradient
                        AppHeader(headerType: .settings)
                            .padding(.horizontal, 4)
                        
                        // User profile summary
                        if let user = dataController.currentUser {
                            UserProfileCard(user: user)
                        }
                        
                        // Section title
                        Text("SETTINGS")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        
                        // Settings menu options
                        settingsContent
                        
                        // Sync settings section
                        Text("DATA SYNCHRONIZATION")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        
                        syncSettingsContent
                        
                        // Footer with logout and version
                        VStack(spacing: 24) {
                            // Logout button
                            Button(action: {
                                showLogoutConfirmation = true
                            }) {
                                HStack {
                                    Spacer()
                                    
                                    Text("Log Out")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(OPSStyle.Colors.errorStatus)
                                    
                                    Image(systemName: "arrow.right.square")
                                        .font(.system(size: 16))
                                        .foregroundColor(OPSStyle.Colors.errorStatus)
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 16)
                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                .cornerRadius(12)
                                .padding(.horizontal, 20)
                            }
                            
                            // App version and logo
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
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)
                        }
                        .padding(.top, 16)
                    }
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
            ForEach(SettingsSection.allCases, id: \.id) { section in
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
                    .padding(16)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var syncSettingsContent: some View {
        VStack(spacing: 16) {
            // Sync toggle row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync on App Launch")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("Automatically sync data when app starts")
                        .font(.system(size: 13))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                Spacer()
                
                Toggle("", isOn: $syncOnLaunch)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.primaryAccent))
            }
            .padding(16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(12)
            
            // Background sync toggle row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Background Sync")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("Sync data when app is in the background")
                        .font(.system(size: 13))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                Spacer()
                
                Toggle("", isOn: $backgroundSyncEnabled)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.primaryAccent))
            }
            .padding(16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(12)
        }
        .padding(.horizontal, 20)
    }
    
    private func logout() {
        // Simple, direct logout function
        dataController.logout()
    }
}

// MARK: - Extensions
extension SettingsView.SettingsSection: CaseIterable {}

