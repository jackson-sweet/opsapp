//
//  AppHeader.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import SwiftUI

struct AppHeader: View {
    enum HeaderType {
        case home
        case settings
        case schedule
    }
    
    // Tab selection for settings screen
    enum SettingsTab {
        case settings
        case data
    }
    
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var selectedTab: SettingsTab = .settings
    var headerType: HeaderType
    var onSearchTapped: (() -> Void)? = nil
    var onRefreshTapped: (() -> Void)? = nil
    var onFilterTapped: (() -> Void)? = nil
    var hasActiveFilters: Bool = false
    var filterCount: Int = 0
    
    private var title: String {
        switch headerType {
        case .home:
            let greeting = getGreeting().uppercased()
            return "\(greeting), \(dataController.currentUser?.firstName.uppercased() ?? "USER")"
        case .settings:
            return "SETTINGS"
        case .schedule:
            return "SCHEDULE"
        }
    }
    
    var body: some View {
        
        if headerType == .home {
            
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    HStack(spacing: 8) {
                        if let company = dataController.getCurrentUserCompany() {
                            Text(company.name.uppercased())
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            // Show subscription badge if relevant
                            if let status = company.subscriptionStatus,
                               let statusEnum = SubscriptionStatus(rawValue: status) {
                                Text("•")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(statusColor(for: statusEnum))
                                        .frame(width: 6, height: 6)
                                    
                                    Text(statusText(for: statusEnum))
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(statusColor(for: statusEnum))
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                // User profile image - use unified UserAvatar component
                if let user = dataController.currentUser {
                    UserAvatar(user: user, size: 44)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .shadow(radius: 2)
                } else {
                    // Fallback if no user
                    UserAvatar(
                        firstName: "U",
                        lastName: "",
                        size: 44,
                        backgroundColor: OPSStyle.Colors.primaryAccent
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(radius: 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
        } else {
            
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    // Show date subtitle for schedule view
                    if headerType == .schedule {
                        HStack(spacing: 8) {
                            Text("TODAY")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            Text("|")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            Text(todayDateString)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                }
                
                Spacer()
                
                // Search, filter and refresh buttons for schedule view
                if headerType == .schedule {
                    HStack(spacing: 8) {
                        // Filter button
                        if let onFilterTapped = onFilterTapped {
                            Button(action: onFilterTapped) {
                                ZStack {
                                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(hasActiveFilters ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryText)
                                        .frame(width: 44, height: 44)
                                        .background(OPSStyle.Colors.cardBackground)
                                        .clipShape(Circle())
                                    
                                    // Show filter count badge if filters are active
                                    if hasActiveFilters && filterCount > 0 {
                                        Text("\(filterCount)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(4)
                                            .background(OPSStyle.Colors.primaryAccent)
                                            .clipShape(Circle())
                                            .offset(x: 14, y: -14)
                                    }
                                }
                            }
                        }
                        
                        // Refresh button
                        if let onRefreshTapped = onRefreshTapped {
                            Button(action: onRefreshTapped) {
                                Image(systemName: "arrow.clockwise")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .frame(width: 44, height: 44)
                                    .background(OPSStyle.Colors.cardBackground)
                                    .clipShape(Circle())
                            }
                        }
                        
                        // Search button
                        if let onSearchTapped = onSearchTapped {
                            Button(action: onSearchTapped) {
                                Image(systemName: "magnifyingglass")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .frame(width: 44, height: 44)
                                    .background(OPSStyle.Colors.cardBackground)
                                    .clipShape(Circle())
                            }
                        }
                    }
                }
                
                // User information if available
                if headerType == .settings {
                    if let user = dataController.currentUser {
                        VStack(alignment: .trailing, spacing: 2) {
                            // Name and role
                            HStack(spacing: 8) {
                                Text("\(user.firstName) \(user.lastName)")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(.white)
                                Text("|")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                Text("\(user.role.displayName)")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            
                            // Email
                            if let email = user.email, !email.isEmpty {
                                Text(email)
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        }
                    }
                }
                
                

            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
        }
    }
    
    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: Date())
    }
    
    private func getGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        
        switch hour {
        case 0..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        default:
            return "Good Evening"
        }
    }
    
    private func statusColor(for status: SubscriptionStatus) -> Color {
        switch status {
        case .trial:
            return OPSStyle.Colors.primaryAccent
        case .active:
            return OPSStyle.Colors.successStatus
        case .grace:
            return OPSStyle.Colors.warningStatus
        case .expired, .cancelled:
            return OPSStyle.Colors.errorStatus
        }
    }
    
    private func statusText(for status: SubscriptionStatus) -> String {
        switch status {
        case .trial:
            if let company = dataController.getCurrentUserCompany(),
               let trialEnd = company.trialEndDate {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0
                if days > 0 {
                    return "TRIAL • \(days) DAYS LEFT"
                } else {
                    return "TRIAL ENDING"
                }
            }
            return "TRIAL"
        case .active:
            if let company = dataController.getCurrentUserCompany(),
               let plan = company.subscriptionPlan,
               let planEnum = SubscriptionPlan(rawValue: plan) {
                return planEnum.displayName.uppercased()
            }
            return "ACTIVE"
        case .grace:
            if let company = dataController.getCurrentUserCompany(),
               let days = company.daysRemainingInGracePeriod {
                if days > 0 {
                    return "GRACE • \(days) DAYS"
                } else {
                    return "GRACE ENDING"
                }
            }
            return "GRACE PERIOD"
        case .expired:
            return "EXPIRED"
        case .cancelled:
            return "CANCELLED"
        }
    }
    
    // MARK: - Settings Components
    
    // Settings tab selector component
    private struct SettingsTabSelector: View {
        @Binding var selectedTab: SettingsTab
        
        var body: some View {
            SegmentedControl(
                selection: $selectedTab,
                options: [
                    (SettingsTab.settings, "Settings"),
                    (SettingsTab.data, "Data")
                ]
            )
            .padding(.horizontal, 20)
        }
    }
    
    // Settings content view
    private var settingsContentView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Settings categories - using the same ones from SettingsView
                ForEach(SettingsCategory.allCases) { category in
                    NavigationLink(destination: destinationFor(category)) {
                        CategoryCard(
                            title: category.rawValue,
                            description: category.description,
                            iconName: category.iconName
                        )
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
    
    // Data content view
    private var dataContentView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Data categories - using the same ones from SettingsView
                // Team Members - active
                NavigationLink(destination: TeamMembersView()) {
                    CategoryCard(
                        title: "Team Members",
                        description: "Manage team members and access",
                        iconName: "person.3"
                    )
                }
                
                // Project History - active
                NavigationLink(destination: ProjectHistorySettingsView()) {
                    CategoryCard(
                        title: "Project History",
                        description: "View past and completed projects",
                        iconName: "clock.arrow.circlepath"
                    )
                }
                
                // Expenses - coming soon, grayed out
                NavigationLink(destination: EmptyView()) {
                    CategoryCard(
                        title: "Expense History",
                        description: "Track expenses and materials costs",
                        iconName: "dollarsign.circle",
                        isDisabled: true,
                        comingSoon: true
                    )
                }
                .disabled(true) // Disable navigation
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
    
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
                return "gear"
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
    
    // Return appropriate destination view based on selected category
    @ViewBuilder
    private func destinationFor(_ category: SettingsCategory) -> some View {
        switch category {
        case .profile:
            ProfileSettingsView()
        case .organization:
            OrganizationSettingsView()
        case .appSettings:
            AppSettingsView()
        }
    }
    
    // Version and actions view at the bottom
    private var versionAndActionsView: some View {
        VStack(spacing: 16) {
            Divider()
                .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                .padding(.horizontal, 20)
            
            // Feature request and logout buttons in HStack
            HStack(spacing: 16) {
                // Feature request button (1/3 width)
                NavigationLink(destination: FeatureRequestView()) {
                    HStack {
                        Image(systemName: "lightbulb")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        
                        Text("REQUEST FEATURE")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(12)
                }
                .frame(height: 44)
                
                // Logout button (2/3 width)
                Button(action: {
                    dataController.logout()
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
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            
            // App version and logo
            HStack {
                Image("LogoWhite") // Placeholder for actual logo
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                
                Text("OPS APP")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
                
                Text(AppConfiguration.AppInfo.displayVersion)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}
