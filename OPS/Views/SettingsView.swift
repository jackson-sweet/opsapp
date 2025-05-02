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
        case certifications = "Certifications & Training"
        case projectHistory = "Project & Expense History"
        
        var id: String { self.rawValue }
        
        var iconName: String {
            switch self {
            case .profile: return "person.fill"
            case .organization: return "building.2.fill"
            case .certifications: return "certificate.fill"
            case .projectHistory: return "clock.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
                
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                    // Header
                    Text("Settings")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.horizontal)
                    
                    if let user = dataController.currentUser {
                        HStack {
                            // User avatar
                            Circle()
                                .fill(OPSStyle.Colors.primaryAccent)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(String(user.fullName.prefix(1)))
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(.white)
                                )
                            
                            VStack(alignment: .leading) {
                                Text(user.fullName)
                                    .font(OPSStyle.Typography.subtitle)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                
                                Text(user.email ?? "")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Settings menu options
                    settingsContent
                    
                    Spacer()
                    
                    // Sync settings section
                    VStack(alignment: .leading) {
                        Text("DATA SYNC")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.top)
                            .padding(.horizontal)
                        
                        VStack(spacing: OPSStyle.Layout.spacing2) {
                            Toggle("Sync on app launch", isOn: $syncOnLaunch)
                                .tint(OPSStyle.Colors.secondaryAccent)
                            
                            Toggle("Background sync", isOn: $backgroundSyncEnabled)
                                .tint(OPSStyle.Colors.secondaryAccent)
                        }
                        .padding()
                        .background(OPSStyle.Colors.cardBackground.opacity(0.3))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .padding(.horizontal)
                    }
                    
                    // Footer with logout and version
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        // Logout button
                        Button(action: {
                            showLogoutConfirmation = true
                        }) {
                            HStack {
                                Text("Log Out")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(Color.red)
                                
                                Image(systemName: "arrow.right.square")
                                    .font(.system(size: 18))
                                    .foregroundColor(Color.red)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .background(OPSStyle.Colors.cardBackground.opacity(0.3))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .padding(.horizontal)
                        
                        // App version and logo
                        HStack {
                            Text("OPS APP")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            Text("v1.0.0")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            // App logo
                            Image(systemName: "building.2.fill") // Using a system icon as placeholder
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .font(.system(size: 18))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, OPSStyle.Layout.spacing4)
                    }
                }
                .padding(.top)
            }
            .navigationDestination(for: SettingsSection.self) { section in
                switch section {
                case .profile:
                    ProfileSettingsView()
                case .organization:
                    OrganizationSettingsView()
                case .certifications:
                    CertificationsSettingsView()
                case .projectHistory:
                    ProjectHistorySettingsView()
                }
            }
        }
        .alert(isPresented: $showLogoutConfirmation) {
            Alert(
                title: Text("Log Out"),
                message: Text("Are you sure you want to log out?"),
                primaryButton: .destructive(Text("Log Out")) {
                    logout()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private var settingsContent: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(SettingsSection.allCases, id: \.id) { section in
                NavigationLink(value: section) {
                    HStack {
                        Image(systemName: section.iconName)
                            .font(.system(size: 18))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(width: 30, height: 30)
                        
                        Text(section.rawValue)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding()
                    .background(OPSStyle.Colors.cardBackground.opacity(0.3))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private func logout() {
        // Simple, direct logout function
        dataController.logout()
    }
}

// MARK: - Extensions
extension SettingsView.SettingsSection: CaseIterable {}
