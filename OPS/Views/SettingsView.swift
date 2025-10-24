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
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

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

    // Searchable setting item
    struct SearchableSettingItem: Identifiable {
        let id = UUID()
        let title: String
        let categoryTitle: String
        let categoryIcon: String
        let keywords: [String]
        let destination: AnyView

        func matches(query: String) -> Bool {
            let lowercasedQuery = query.lowercased()
            return title.lowercased().contains(lowercasedQuery) ||
                   categoryTitle.lowercased().contains(lowercasedQuery) ||
                   keywords.contains { $0.lowercased().contains(lowercasedQuery) }
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
                destination: AnyView(AppSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Notifications",
                categoryTitle: "App Settings",
                categoryIcon: "gearshape",
                keywords: ["notifications", "alerts", "reminders"],
                destination: AnyView(AppSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Data & Sync",
                categoryTitle: "App Settings",
                categoryIcon: "gearshape",
                keywords: ["data", "sync", "storage", "cache"],
                destination: AnyView(AppSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Security & Privacy",
                categoryTitle: "App Settings",
                categoryIcon: "gearshape",
                keywords: ["security", "privacy", "protection"],
                destination: AnyView(AppSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "App Version & Info",
                categoryTitle: "App Settings",
                categoryIcon: "gearshape",
                keywords: ["version", "info", "about", "app"],
                destination: AnyView(AppSettingsView().environmentObject(dataController))
            )
        ])

        // Data tab items
        items.append(contentsOf: [
            SearchableSettingItem(
                title: "Team Members",
                categoryTitle: "Data",
                categoryIcon: "person.2",
                keywords: ["team", "members", "users", "crew"],
                destination: AnyView(TeamMembersView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Project History",
                categoryTitle: "Data",
                categoryIcon: "clock.arrow.circlepath",
                keywords: ["projects", "history", "past", "completed"],
                destination: AnyView(ProjectHistorySettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Expense History",
                categoryTitle: "Data",
                categoryIcon: "dollarsign.circle",
                keywords: ["expenses", "costs", "materials", "history"],
                destination: AnyView(ExpenseHistoryView().environmentObject(dataController))
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
                    destination: AnyView(AppSettingsView().environmentObject(dataController))
                ),
                SearchableSettingItem(
                    title: "Scheduling Type",
                    categoryTitle: "Project Settings",
                    categoryIcon: "hammer.circle",
                    keywords: ["scheduling", "calendar", "project"],
                    destination: AnyView(AppSettingsView().environmentObject(dataController))
                )
            ])
        }

        return items
    }

    // Filtered search results
    private var searchResults: [SearchableSettingItem] {
        guard !searchText.isEmpty else { return [] }
        return allSearchableSettings.filter { $0.matches(query: searchText) }
    }

    // Whether to show search results
    private var isSearchActive: Bool {
        !searchText.isEmpty
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

                    // Search bar
                    searchBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    // Tab selector - hide when searching
                    if !isSearchActive {
                        SettingsTabSelector(selectedTab: $selectedTab)
                    }

                    // Content - either search results or tab content
                    if isSearchActive {
                        searchResultsContent
                    } else {
                        // Tab content - shows either settings or data content
                        if selectedTab == .settings {
                            settingsContent
                        } else {
                            dataContent
                        }

                        // App version and actions at bottom
                        versionAndActions
                    }
                }
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
    
    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            // Magnifying glass icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Search text field
            TextField("Search settings...", text: $searchText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .focused($isSearchFocused)
                .autocapitalization(.none)
                .autocorrectionDisabled(true)

            // Clear button - only show when there's text
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(isSearchFocused ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Search Results

    private var searchResultsContent: some View {
        GeometryReader { geometry in
            ScrollView {
                if searchResults.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .padding(.top, 60)

                        Text("No Results Found")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("Try a different search term")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                } else {
                    VStack(spacing: 12) {
                        // Results header
                        HStack {
                            Text("\(searchResults.count) RESULT\(searchResults.count == 1 ? "" : "S")")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                        // Search results
                        ForEach(searchResults) { item in
                            NavigationLink(destination: item.destination) {
                                searchResultRow(for: item)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func searchResultRow(for item: SearchableSettingItem) -> some View {
        HStack(spacing: 16) {
            // Category icon
            Image(systemName: item.categoryIcon)
                .font(.system(size: 20))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(item.categoryTitle)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 20)
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
