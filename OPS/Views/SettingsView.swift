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
    @State private var selectedTab: SettingsTabSelector.Tab = .settings
    
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
    
    // Data categories
    enum DataCategory: String, Identifiable, CaseIterable {
        case teamMembers = "Team Members"
        case projectHistory = "Project History"
        case expenseHistory = "Expense History"
        
        var id: String { self.rawValue }
        
        var iconName: String {
            switch self {
            case .teamMembers:
                return "person.2"
            case .projectHistory:
                return "clock.arrow.circlepath"
            case .expenseHistory:
                return "dollarsign.circle"
            }
        }
        
        var description: String {
            switch self {
            case .teamMembers:
                return "Manage team members and access"
            case .projectHistory:
                return "View past and completed projects"
            case .expenseHistory:
                return "Track expenses and materials costs"
            }
        }
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
                        .padding(.bottom, 8)
                    
                    // Tab selector
                    SettingsTabSelector(selectedTab: $selectedTab)
                    
                    // Tab content - shows either settings or data content
                    if selectedTab == .settings {
                        settingsContent
                    } else {
                        dataContent
                    }
                    
                    // App version and actions at bottom
                    versionAndActions
                        
                }
                .padding(.top, 16)
                .padding(.bottom, 90) // Add padding for tab bar
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
    
    // Data tab content
    private var dataContent: some View {
        // Use GeometryReader to determine if content needs scrolling
        GeometryReader { geometry in

                VStack(spacing: 20) {
                    // Team Members - active
                    NavigationLink(destination: destinationFor(.teamMembers)) {
                        categoryCard(for: .teamMembers)
                    }
                    
                    // Project History - active
                    NavigationLink(destination: destinationFor(.projectHistory)) {
                        categoryCard(for: .projectHistory)
                    }
                    
                    // Expenses - coming soon
                    NavigationLink(destination: destinationFor(.expenseHistory)) {
                        categoryCard(for: .expenseHistory)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(minHeight: geometry.size.height) // Ensure content fills scroll view
            
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
    
    // Convenience function for DataCategory
    private func categoryCard(for category: DataCategory) -> some View {
        CategoryCard(
            title: category.rawValue,
            description: category.description,
            iconName: category.iconName,
            isDisabled: category == .expenseHistory,
            comingSoon: category == .expenseHistory
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
    
    // Return appropriate destination view based on selected data category
    @ViewBuilder
    private func destinationFor(_ category: DataCategory) -> some View {
        switch category {
        case .teamMembers:
            TeamMembersView()
                .environmentObject(dataController)
        case .projectHistory:
            ProjectHistorySettingsView()
                .environmentObject(dataController)
        case .expenseHistory:
            ExpenseHistoryView()
                .environmentObject(dataController)
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
