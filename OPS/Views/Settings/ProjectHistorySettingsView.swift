//
//  ProjectHistorySettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import SwiftUI

struct ProjectHistorySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    @State private var selectedTab = 0
    @State private var projectHistory: [Project] = []
    @State private var expenses: [Expense] = []
    @State private var isLoading = true
    @State private var dateFilter: DateFilter = .all
    @State private var statusFilter: StatusFilter = .all
    // State for modal presentation - using optional Project as the item
    @State private var selectedProject: Project? = nil
    
    // Placeholder model
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
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    
                    Text("Projects & Expenses")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Spacer()
                }
                .padding()
                
                // Tab selector
                HStack(spacing: 0) {
                    tabButton(title: "Projects", index: 0)
                    tabButton(title: "Expenses", index: 1)
                }
                .background(OPSStyle.Colors.cardBackground.opacity(0.3))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .padding(.horizontal)
                
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
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(OPSStyle.Colors.cardBackground.opacity(0.3))
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
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(OPSStyle.Colors.cardBackground.opacity(0.3))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    
                    Spacer()
                }
                .padding()
                
                if isLoading {
                    loadingView
                } else {
                    // Content based on selected tab
                    TabView(selection: $selectedTab) {
                        projectsTab.tag(0)
                        expensesTab.tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Reset filters to default values when view appears
            dateFilter = .all
            statusFilter = .all
            // Load initial data
            loadHistoryData()
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
                        OPSStyle.Colors.primaryAccent.opacity(0.2) :
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
                if projectHistory.isEmpty {
                    // Empty state with context about the filters
                    let (title, message) = emptyStateMessageForFilters()
                    emptyStateView(
                        icon: "folder.fill",
                        title: title,
                        message: message
                    )
                } else {
                    // Project history cards
                    ForEach(projectHistory) { project in
                        projectHistoryCard(project: project)
                    }
                    
                    // Total count
                    Text("\(projectHistory.count) projects match your filters")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }
            }
            .padding()
        }
    }
    
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
                        .background(OPSStyle.Colors.cardBackground.opacity(0.3))
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
                                .font(.system(size: 16))
                            
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
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
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
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                .padding(.bottom, 8)
            
            Text(title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            Text(message)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
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
                    
                    // Status badge - use the centralized StatusBadge component
                    StatusBadge(status: project.status)
                }
                
                // Client and address
                Text(project.clientName)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(project.address)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Divider()
                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                
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
                            .font(.system(size: 12))
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
            let allProjects = dataController.getProjectHistory(
                for: dataController.currentUser?.id ?? ""
            )
            
            // Apply initial filters
            let filteredProjects = allProjects.filter { project in
                let matchesStatus = filterProjectByStatus(project, filter: statusFilter)
                let matchesDate = filterProjectByDate(project, filter: dateFilter)
                return matchesStatus && matchesDate
            }
            
            // Sort projects by date (most recent first)
            let sortedProjects = filteredProjects.sorted { 
                guard let date1 = $0.startDate, let date2 = $1.startDate else {
                    return false
                }
                return date1 > date2
            }
            
            print("ProjectHistorySettingsView: Loaded \(allProjects.count) total projects, \(filteredProjects.count) after filtering")
            
            // In a real app, you would load expenses from the data controller
            // For now, using sample data
            
            await MainActor.run {
                self.projectHistory = sortedProjects
                
                // Uncomment to enable expenses feature
                self.expenses = []  // Empty for now to show empty state
                
                // Create sample expense data if needed (only for UI testing)
                if !sortedProjects.isEmpty && AppConfiguration.Debug.useSampleData {
                    self.expenses = generateSampleExpenses(for: sortedProjects.first!)
                }
                
                self.isLoading = false
            }
        }
    }
    
    // Generate sample expenses for UI testing
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
    
    // Generate appropriate empty state messages based on applied filters
    private func emptyStateMessageForFilters() -> (String, String) {
        // Check if we have restrictive filters applied
        let hasDateFilter = dateFilter != .all
        let hasStatusFilter = statusFilter != .all
        
        // Generate appropriate empty state message
        if hasDateFilter && hasStatusFilter {
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
            // No filters applied
            return (
                "No projects found",
                "Projects you've worked on will appear here"
            )
        }
    }
    
    private func applyFilters() {
        isLoading = true
        
        Task {
            // First get all projects for the user
            let allProjects = dataController.getProjectHistory(
                for: dataController.currentUser?.id ?? ""
            )
            
            // Then apply filters
            let filteredProjects = allProjects.filter { project in
                let matchesStatus = filterProjectByStatus(project, filter: statusFilter)
                let matchesDate = filterProjectByDate(project, filter: dateFilter)
                return matchesStatus && matchesDate
            }
            
            // Update UI on main thread
            await MainActor.run {
                self.projectHistory = filteredProjects
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
}

#Preview {
    ProjectHistorySettingsView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}