//
//  SettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//

import SwiftUI
import UIKit
import Foundation

// Use standardized components directly (internal modules don't need import)

struct SettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @State private var showLogoutConfirmation = false
    @State private var showingSearchSheet = false

    // Settings categories
    enum SettingsCategory: String, Identifiable, CaseIterable {
        case profile = "Profile Settings"
        case organization = "Organization Settings"
        case appSettings = "App Settings"

        var id: String { self.rawValue }

        var iconName: String {
            switch self {
            case .profile:
                return "person"
            case .organization:
                return "building.2"
            case .appSettings:
                return "gearshape"
            }
        }

        var description: String {
            switch self {
            case .profile:
                return "Personal information, contact details"
            case .organization:
                return "Company information, team members"
            case .appSettings:
                return "Map, notifications, data, security"
            }
        }
    }


    // All searchable settings
    private var allSearchableSettings: [SearchableSettingItem] {
        var items: [SearchableSettingItem] = []

        // Profile Settings items
        items.append(contentsOf: [
            SearchableSettingItem(
                title: "Profile Information",
                categoryTitle: "Profile Settings",
                categoryIcon: "person",
                keywords: ["name", "contact", "personal", "information"],
                destination: AnyView(ProfileSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Contact Details",
                categoryTitle: "Profile Settings",
                categoryIcon: "person",
                keywords: ["phone", "email", "address", "contact"],
                destination: AnyView(ProfileSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Reset Password",
                categoryTitle: "Profile Settings",
                categoryIcon: "person",
                keywords: ["password", "credentials", "security", "reset"],
                destination: AnyView(ProfileSettingsView().environmentObject(dataController))
            )
        ])

        // Organization Settings items
        items.append(contentsOf: [
            SearchableSettingItem(
                title: "Company Information",
                categoryTitle: "Organization Settings",
                categoryIcon: "building.2",
                keywords: ["company", "business", "organization", "info"],
                destination: AnyView(OrganizationSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Subscription",
                categoryTitle: "Organization Settings",
                categoryIcon: "building.2",
                keywords: ["subscription", "plan", "billing", "seats"],
                destination: AnyView(OrganizationSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Team Management",
                categoryTitle: "Organization Settings",
                categoryIcon: "building.2",
                keywords: ["team", "members", "users", "roles"],
                destination: AnyView(OrganizationSettingsView().environmentObject(dataController))
            )
        ])

        // App Settings items
        items.append(contentsOf: [
            SearchableSettingItem(
                title: "Map Settings",
                categoryTitle: "App Settings",
                categoryIcon: "gearshape",
                keywords: ["map", "navigation", "display"],
                destination: AnyView(MapSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Notifications",
                categoryTitle: "App Settings",
                categoryIcon: "gearshape",
                keywords: ["notifications", "alerts", "reminders"],
                destination: AnyView(NotificationSettingsView().environmentObject(dataController).environmentObject(NotificationManager.shared))
            ),
            SearchableSettingItem(
                title: "Data & Sync",
                categoryTitle: "App Settings",
                categoryIcon: "gearshape",
                keywords: ["data", "sync", "storage", "cache"],
                destination: AnyView(DataStorageSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Security & Privacy",
                categoryTitle: "App Settings",
                categoryIcon: "gearshape",
                keywords: ["security", "privacy", "protection"],
                destination: AnyView(SecuritySettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "App Version & Info",
                categoryTitle: "App Settings",
                categoryIcon: "gearshape",
                keywords: ["version", "info", "about", "app"],
                destination: AnyView(AppSettingsView().environmentObject(dataController))
            )
        ])


        // Project Settings (conditional based on user role)
        if let user = dataController.currentUser, (user.role == .admin || user.role == .officeCrew) {
            items.append(contentsOf: [
                SearchableSettingItem(
                    title: "Task Types",
                    categoryTitle: "Project Settings",
                    categoryIcon: "hammer.circle",
                    keywords: ["task", "types", "project", "templates"],
                    destination: AnyView(TaskSettingsView().environmentObject(dataController))
                ),
                SearchableSettingItem(
                    title: "Scheduling Type",
                    categoryTitle: "Project Settings",
                    categoryIcon: "hammer.circle",
                    keywords: ["scheduling", "calendar", "project"],
                    destination: AnyView(SchedulingTypeExplanationView().environmentObject(dataController))
                )
            ])
        }

        return items
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)

                VStack(alignment: .leading, spacing: 0) {
                    // App Header - only use it for the title/user info section
                    AppHeader(headerType: .settings)

                    // Search button
                    searchButton
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                    // Settings content
                    settingsContent

                    // App version and actions at bottom
                    versionAndActions
                }
                .padding(.bottom, 90) // Add padding for tab bar
            }
        }
        .sheet(isPresented: $showingSearchSheet) {
            SettingsSearchSheet(allSearchableSettings: allSearchableSettings)
                .environmentObject(dataController)
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

    // MARK: - Content Views

    // Settings tab content
    private var settingsContent: some View {
        // Use GeometryReader to determine if content needs scrolling
        GeometryReader { geometry in

                VStack(spacing: 20) {
                    // Settings categories
                    ForEach(SettingsCategory.allCases) { category in
                        NavigationLink(destination: destinationFor(category)) {
                            categoryCard(for: category)
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                //.frame(minHeight: geometry.size.height) // Ensure content fills scroll view

        }
    }
    
    // Action buttons only - app info moved to AppSettingsView
    private var versionAndActions: some View {
        VStack(spacing: 16) {
            Divider()
                .background(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, 20)
            
            // What we're working on - compact card
            NavigationLink(destination: WhatsNewView()) {
                HStack {
                    Text("What We're Working On")
                        .font(.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            
            // Feature request, report issue, and logout buttons
            HStack(spacing: 12) {
                // First row: Feature request and Report issue buttons
                VStack(spacing: 12) {
                    
                    // Report issue button
                    NavigationLink(destination: ReportIssueView()) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                            
                            Text("REPORT ISSUE")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.warningStatus, lineWidth: 1)
                        )
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .frame(height: 44)
                }
                
                // Second row: Logout button (full width)
                Button(action: {
                    showLogoutConfirmation = true
                }) {
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
                            .stroke(OPSStyle.Colors.errorStatus, lineWidth: 1)
                    )
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .frame(height: 44)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            
        }
    }
    
    // MARK: - Helper Views and Functions
    
    // Convenience function for SettingsCategory
    private func categoryCard(for category: SettingsCategory) -> some View {
        CategoryCard(
            title: category.rawValue,
            description: category.description,
            iconName: category.iconName
        )
    }
    
    // Return appropriate destination view based on selected category
    @ViewBuilder
    private func destinationFor(_ category: SettingsCategory) -> some View {
        switch category {
        case .profile:
            ProfileSettingsView()
                .environmentObject(dataController)
        case .organization:
            OrganizationSettingsView()
                .environmentObject(dataController)
        case .appSettings:
            AppSettingsView()
                .environmentObject(dataController)
        }
    }
    

    // Search button
    private var searchButton: some View {
        Button(action: {
            showingSearchSheet = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Text("Search settings...")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private func logout() {
        // Simple, direct logout function
        dataController.logout()
    }
}

#Preview {
    SettingsView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
