//
//  ProjectHistorySettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import SwiftUI
import Combine
import UIKit

// Use standardized components directly (internal modules don't need import)

struct ProjectHistorySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    @State private var selectedTab = 0
    @State private var projectHistory: [Project] = []
    @State private var filteredProjects: [Project] = []
    @State private var expenses: [Expense] = []
    @State private var isLoading = true
    @State private var dateFilter: DateFilter = .all
    @State private var statusFilter: StatusFilter = .all
    @State private var searchText: String = ""
    // State for modal presentation - using optional Project as the item
    @State private var selectedProject: Project? = nil
    @State private var isRefreshing = false
    @State private var selectedTeamMemberId: String? = nil
    @State private var availableTeamMembers: [TeamMember] = []
    
    // Placeholder model - part of shelved expense functionality, kept for future reference
    struct Expense: Identifiable {
        let id: String
        let projectId: String?
        let projectTitle: String?
        let amount: Double
        let description: String
        let date: Date
        let status: ExpenseStatus
        let category: String
        let receiptURL: String?
        
        enum ExpenseStatus: String {
            case pending = "Pending"
            case approved = "Approved"
            case rejected = "Rejected"
        }
        
        var statusColor: Color {
            switch status {
            case .pending:
                return Color.orange
            case .approved:
                return Color.green
            case .rejected:
                return Color.red
            }
        }
    }
    
    enum DateFilter: String, CaseIterable, Identifiable {
        case all = "All Time"
        case thisMonth = "This Month"
        case lastMonth = "Last Month"
        case thisQuarter = "This Quarter"
        
        var id: String { self.rawValue }
    }
    
    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All Statuses"
        case completed = "Completed"
        case inProgress = "In Progress"
        
        var id: String { self.rawValue }
    }
    
    // Check if current user should see team member filter
    private var shouldShowTeamMemberFilter: Bool {
        guard let user = dataController.currentUser else { return false }
        return user.role == .admin || user.role == .officeCrew
    }
    
    // Get the display text for team member filter
    private var teamMemberFilterText: String {
        if let memberId = selectedTeamMemberId,
           let member = availableTeamMembers.first(where: { $0.id == memberId }) {
            return member.fullName
        }
        return "All Team Members"
    }
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header using standardized component
                SettingsHeader(
                    title: "Project History",
                    onBackTapped: {
                        dismiss()
                    }
                )
                
                // Search bar using standardized component
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        TextField("Search projects...", text: $searchText)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(.white)
                            // onEditingChanged for iOS 14 compatibility
                            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification)) { _ in
                                applyFilters()
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                applyFilters()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(10)
                }
                // SearchBar parameters removed - they were accidentally left in despite direct implementation
                
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                // Filter row
                HStack {
                    // Date filter
                    Menu {
                        ForEach(DateFilter.allCases) { filter in
                            Button(action: {
                                dateFilter = filter
                                applyFilters()
                            }) {
                                Text(filter.rawValue)
                            }
                        }
                    } label: {
                        HStack {
                            Text(dateFilter.rawValue)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            
                            Image(systemName: "chevron.down")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(OPSStyle.Colors.cardBackground)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    
                    // Status filter
                    Menu {
                        ForEach(StatusFilter.allCases) { filter in
                            Button(action: {
                                statusFilter = filter
                                applyFilters()
                            }) {
                                Text(filter.rawValue)
                            }
                        }
                    } label: {
                        HStack {
                            Text(statusFilter.rawValue)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            
                            Image(systemName: "chevron.down")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(OPSStyle.Colors.cardBackground)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    
                    // Team member filter (only for admin/office crew)
                    if shouldShowTeamMemberFilter {
                        Menu {
                            Button(action: {
                                selectedTeamMemberId = nil
                                applyFilters()
                            }) {
                                Text("All Team Members")
                            }
                            
                            Divider()
                            
                            ForEach(availableTeamMembers, id: \.id) { member in
                                Button(action: {
                                    selectedTeamMemberId = member.id
                                    applyFilters()
                                }) {
                                    Text(member.fullName)
                                }
                            }
                        } label: {
                            HStack {
                                Text(teamMemberFilterText)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .lineLimit(1)
                                
                                Image(systemName: "chevron.down")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(OPSStyle.Colors.cardBackground)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                    }
                    
                    Spacer()
                    
                    // Refresh button
                    Button(action: {
                        refreshProjects()
                    }) {
                        Image(systemName: isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    }
                    .disabled(isRefreshing)
                }
                .padding()
                
                if isLoading {
                    loadingView
                } else {
                    // Content based on selected tab - only showing projects tab
                    // We're keeping just the projects tab and not using TabView since expenses are disabled
                    projectsTab
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Reset filters to default values when view appears
            dateFilter = .all
            statusFilter = .all
            selectedTeamMemberId = nil
            // Load initial data
            loadHistoryData()
            
            // Also trigger a sync if we're connected
            if dataController.isConnected, let syncManager = dataController.syncManager {
                Task {
                    await syncManager.triggerBackgroundSync()
                }
            }
        }
        // Show project details in modal - using item instead of isPresented for better lifecycle management
        .sheet(item: $selectedProject, onDismiss: {
            // Reload data when returning from details
            loadHistoryData()
        }) { project in
            // Using a NavigationStack to provide navigation functionality within the modal
            NavigationStack {
                ProjectDetailsView(project: project)
                    .environmentObject(dataController)
            }
        }
    }
    
    private func tabButton(title: String, index: Int) -> some View {
        Button(action: {
            withAnimation {
                selectedTab = index
            }
        }) {
            Text(title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(selectedTab == index ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    selectedTab == index ?
                        OPSStyle.Colors.cardBackground :
                        Color.clear
                )
        }
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                .scaleEffect(1.5)
            
            Text("Loading data...")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var projectsTab: some View {
        ScrollView {
            VStack(spacing: OPSStyle.Layout.spacing3) {
                if filteredProjects.isEmpty {
                    // Empty state with context about the filters
                    let (title, message) = emptyStateMessageForFilters()
                    emptyStateView(
                        icon: "folder.fill",
                        title: title,
                        message: message
                    )
                } else {
                    // Project history cards
                    ForEach(filteredProjects) { project in
                        projectHistoryCard(project: project)
                    }
                    
                    // Total count
                    Text("\(filteredProjects.count) projects match your criteria")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }
            }
            .padding()
            .tabBarPadding() // Add padding for tab bar
        }
    }
    
    // Expenses tab - commented out as part of shelving expense functionality
    // We're keeping this code for future reference when the feature is implemented
    /*
    private var expensesTab: some View {
        ScrollView {
            VStack(spacing: OPSStyle.Layout.spacing3) {
                if expenses.isEmpty {
                    // Coming soon banner for expenses feature
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        // Empty state with coming soon message
                        emptyStateView(
                            icon: "dollarsign.circle.fill",
                            title: "Expense tracking coming soon",
                            message: "In the next update, you'll be able to submit and track expenses directly from the app"
                        )
                        
                        // Feature highlight
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("UPCOMING FEATURES")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.bottom, 2)
                            
                            featureRow(icon: "receipt.fill", text: "Submit expense receipts with photos")
                            featureRow(icon: "chart.bar.fill", text: "Track expense approvals and payments")
                            featureRow(icon: "folder.badge.plus", text: "Organize expenses by projects and categories")
                            featureRow(icon: "icloud.and.arrow.up", text: "Automatic syncing with office accounting")
                        }
                        .padding()
                        .background(OPSStyle.Colors.cardBackground)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                } else {
                    // Expense cards - this section will be used when the feature is implemented
                    ForEach(expenses) { expense in
                        expenseCard(expense: expense)
                    }
                    
                    // Add expense button
                    Button(action: {
                        // Action to add expense
                    }) {
                        HStack {
                            Image(systemName: "plus")
                                .font(OPSStyle.Typography.body)
                            
                            Text("Add New Expense")
                                .font(OPSStyle.Typography.bodyBold)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                        )
                    }
                    .padding(.top, OPSStyle.Layout.spacing3)
                }
            }
            .padding()
        }
    }
    */
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: 24, height: 24)
            
            Text(text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Spacer()
                Image(systemName: icon)
                    .font(OPSStyle.Typography.largeTitle)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.bottom, 8)
                Spacer()
            }
            
            Text(title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(message)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .background(OPSStyle.Colors.cardBackground.opacity(0.3))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    private func projectHistoryCard(project: Project) -> some View {
        Button(action: {
            // Just set the selected project, the sheet binding will handle the presentation
            selectedProject = project
        }) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                // Header with project title and status
                HStack {
                    Text(project.title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Spacer()
                    
                    // Status badge - implement directly instead of using component
                    Text(project.status.rawValue.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .background(OPSStyle.Colors.statusColor(for: project.status))
                        .cornerRadius(OPSStyle.Layout.cornerRadius / 2)
                }
                
                // Client and address
                Text(project.clientName)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(project.address ?? "No address")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Divider()
                    .background(OPSStyle.Colors.cardBackgroundDark)
                
                // Dates
                HStack {
                    if let startDate = project.startDate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start Date")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            Text(formatDate(startDate))
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                    }
                    
                    Spacer()
                    
                    if let endDate = project.endDate {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("End Date")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            Text(formatDate(endDate))
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                    }
                }
                
                // View details button
                HStack {
                    Spacer()
                    
                    HStack {
                        Text("View Details")
                            .font(OPSStyle.Typography.captionBold)
                        
                        Image(systemName: "arrow.right")
                            .font(OPSStyle.Typography.smallCaption)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.top, 6)
                }
            }
            .padding()
            .background(OPSStyle.Colors.cardBackground.opacity(0.3))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle()) // Prevent default button styling
    }
    
    // Expense card - commented out as part of shelving expense functionality
    // We're keeping this code for future reference when the feature is implemented
    /*
    private func expenseCard(expense: Expense) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Header with amount and status
            HStack {
                Text("$\(String(format: "%.2f", expense.amount))")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Spacer()
                
                // Status badge
                Text(expense.status.rawValue)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(expense.statusColor)
                    .cornerRadius(12)
            }
            
            // Description
            Text(expense.description)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            // Category and project (if available)
            HStack {
                Text("Category: \(expense.category)")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
                
                if let projectTitle = expense.projectTitle {
                    Text("Project: \(projectTitle)")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            
            Divider()
                .background(OPSStyle.Colors.secondaryText.opacity(0.3))
            
            // Date
            HStack {
                Text("Date Submitted:")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(formatDate(expense.date))
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Spacer()
            }
            
            // View receipt button if available
            if expense.receiptURL != nil {
                Button(action: {
                    // Action to view receipt
                }) {
                    HStack {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 14))
                        
                        Text("View Receipt")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackground.opacity(0.3))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    */
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func loadHistoryData() {
        isLoading = true
        
        Task {
            // Load all projects assigned to current user
            let userId = dataController.currentUser?.id ?? ""
            let userRole = dataController.currentUser?.role.displayName ?? "unknown"
            let companyId = dataController.currentUser?.companyId ?? "none"
            
            
            let allProjects = dataController.getProjectHistory(for: userId)
            
            
            // Load team members if user is admin/office crew
            if shouldShowTeamMemberFilter {
                if let company = dataController.getCompany(id: companyId) {
                    availableTeamMembers = company.teamMembers.sorted { $0.fullName < $1.fullName }
                }
            }
            
            // Apply initial filters
            let filtered = allProjects.filter { project in
                let matchesStatus = filterProjectByStatus(project, filter: statusFilter)
                let matchesDate = filterProjectByDate(project, filter: dateFilter)
                let matchesSearch = searchText.isEmpty || matchesSearchCriteria(project)
                let matchesTeamMember = filterProjectByTeamMember(project, memberId: selectedTeamMemberId)
                return matchesStatus && matchesDate && matchesSearch && matchesTeamMember
            }
            
            // Sort projects by date (most recent first)
            let sortedProjects = filtered.sorted { 
                guard let date1 = $0.startDate, let date2 = $1.startDate else {
                    return false
                }
                return date1 > date2
            }
            
            
            // In a real app, you would load expenses from the data controller
            // For now, using sample data
            
            await MainActor.run {
                self.projectHistory = allProjects  // Store all projects for filtering
                self.filteredProjects = sortedProjects  // Store filtered projects for display
                
                // Uncomment to enable expenses feature
                self.expenses = []  // Empty for now to show empty state
                
                // Expense feature shelved
                // Create sample expense data if needed (only for UI testing)
                /*
                if !sortedProjects.isEmpty && AppConfiguration.Debug.useSampleData {
                    self.expenses = generateSampleExpenses(for: sortedProjects.first!)
                }
                */
                
                self.isLoading = false
            }
        }
    }
    
    // Search project based on search criteria
    private func matchesSearchCriteria(_ project: Project) -> Bool {
        let searchLower = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If search text is empty, return true
        if searchLower.isEmpty {
            return true
        }
        
        // Search in multiple fields
        return project.title.lowercased().contains(searchLower) ||
               project.clientName.lowercased().contains(searchLower) ||
               (project.address?.lowercased().contains(searchLower) ?? false) ||
               project.status.rawValue.lowercased().contains(searchLower)
    }
    
    // Generate sample expenses for UI testing - commented out as part of shelving expense functionality
    /*
    private func generateSampleExpenses(for project: Project) -> [Expense] {
        return [
            Expense(
                id: "1",
                projectId: project.id,
                projectTitle: project.title,
                amount: 126.50,
                description: "Construction materials",
                date: Date().addingTimeInterval(-7*24*60*60),
                status: .approved,
                category: "Materials",
                receiptURL: "https://example.com/receipt1.pdf"
            ),
            Expense(
                id: "2",
                projectId: project.id,
                projectTitle: project.title,
                amount: 45.75,
                description: "Lunch for team",
                date: Date().addingTimeInterval(-3*24*60*60),
                status: .pending,
                category: "Meals",
                receiptURL: nil
            )
        ]
    }
    */
    
    // Generate appropriate empty state messages based on applied filters
    private func emptyStateMessageForFilters() -> (String, String) {
        // Check if we have restrictive filters applied
        let hasDateFilter = dateFilter != .all
        let hasStatusFilter = statusFilter != .all
        let hasSearchText = !searchText.isEmpty
        
        // Generate appropriate empty state message
        if hasSearchText {
            if hasDateFilter || hasStatusFilter {
                return (
                    "No projects match your search",
                    "Try adjusting your search terms or filters to see more projects"
                )
            } else {
                return (
                    "No projects match '\(searchText)'",
                    "Try a different search term or clear the search"
                )
            }
        } else if hasDateFilter && hasStatusFilter {
            // Both date and status filters are applied
            return (
                "No projects match your filters",
                "Try adjusting your date or status filters to see more projects"
            )
        } else if hasDateFilter {
            // Only date filter is applied
            return (
                "No projects found for \(dateFilter.rawValue.lowercased())",
                "Try selecting a different date range to see your projects"
            )
        } else if hasStatusFilter {
            // Only status filter is applied
            let statusType = statusFilter == .completed ? "completed" : "in progress"
            return (
                "No \(statusType) projects found",
                "Projects with \(statusType) status will appear here"
            )
        } else {
            // No filters applied - check user role for appropriate message
            if let user = dataController.currentUser {
                if user.role == .fieldCrew {
                    return (
                        "No projects found",
                        "Projects you've been assigned to will appear here. Try refreshing to load the latest data."
                    )
                } else {
                    return (
                        "No projects found",
                        "All company projects will appear here. Try refreshing to load the latest data."
                    )
                }
            } else {
                return (
                    "No projects found",
                    "Projects will appear here once loaded"
                )
            }
        }
    }
    
    private func applyFilters() {
        isLoading = true
        
        Task {
            // Use the existing projectHistory array (all projects)
            // and apply filters without reloading from data controller
            let filtered = projectHistory.filter { project in
                let matchesStatus = filterProjectByStatus(project, filter: statusFilter)
                let matchesDate = filterProjectByDate(project, filter: dateFilter)
                let matchesSearch = searchText.isEmpty || matchesSearchCriteria(project)
                let matchesTeamMember = filterProjectByTeamMember(project, memberId: selectedTeamMemberId)
                return matchesStatus && matchesDate && matchesSearch && matchesTeamMember
            }
            
            // Sort projects by date (most recent first)
            let sortedProjects = filtered.sorted { 
                guard let date1 = $0.startDate, let date2 = $1.startDate else {
                    return false
                }
                return date1 > date2
            }
            
            // Update UI on main thread
            await MainActor.run {
                self.filteredProjects = sortedProjects
                self.isLoading = false
            }
        }
    }
    
    // Filter project by status
    private func filterProjectByStatus(_ project: Project, filter: StatusFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .completed:
            return project.status == .completed || project.status == .closed
        case .inProgress:
            return project.status == .inProgress || project.status == .accepted
        }
    }
    
    // Filter project by date
    private func filterProjectByDate(_ project: Project, filter: DateFilter) -> Bool {
        guard let startDate = project.startDate else {
            // If no start date, only include in "all" filter
            return filter == .all
        }
        
        let calendar = Calendar.current
        let now = Date()
        
        switch filter {
        case .all:
            return true
            
        case .thisMonth:
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)
            let projectMonth = calendar.component(.month, from: startDate)
            let projectYear = calendar.component(.year, from: startDate)
            
            return currentMonth == projectMonth && currentYear == projectYear
            
        case .lastMonth:
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!
            let lastMonthComponent = calendar.component(.month, from: lastMonth)
            let lastMonthYear = calendar.component(.year, from: lastMonth)
            let projectMonth = calendar.component(.month, from: startDate)
            let projectYear = calendar.component(.year, from: startDate)
            
            return lastMonthComponent == projectMonth && lastMonthYear == projectYear
            
        case .thisQuarter:
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)
            let projectMonth = calendar.component(.month, from: startDate)
            let projectYear = calendar.component(.year, from: startDate)
            
            // Determine current quarter
            let currentQuarter = (currentMonth - 1) / 3 + 1
            let projectQuarter = (projectMonth - 1) / 3 + 1
            
            return currentQuarter == projectQuarter && currentYear == projectYear
        }
    }
    
    // Filter project by team member
    private func filterProjectByTeamMember(_ project: Project, memberId: String?) -> Bool {
        // If no team member selected, show all projects
        guard let memberId = memberId else {
            return true
        }
        
        // Check if the selected team member is assigned to this project
        return project.getTeamMemberIds().contains(memberId) ||
               project.teamMembers.contains(where: { $0.id == memberId })
    }
    
    private func refreshProjects() {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        
        Task {
            // Force sync projects from the server
            
            if let syncManager = dataController.syncManager {
                // Force project sync
                await syncManager.forceSyncProjects()
                
                // Wait a moment for the sync to complete
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
            
            // Reload the project history
            loadHistoryData()
            
            await MainActor.run {
                isRefreshing = false
            }
        }
    }
}

#Preview {
    ProjectHistorySettingsView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
