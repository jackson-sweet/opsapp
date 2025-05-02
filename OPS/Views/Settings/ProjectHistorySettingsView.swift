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
            loadHistoryData()
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
                    // Empty state
                    emptyStateView(
                        icon: "folder.fill",
                        title: "No projects found",
                        message: "Projects you've worked on will appear here"
                    )
                } else {
                    // Project history cards
                    ForEach(projectHistory) { project in
                        projectHistoryCard(project: project)
                    }
                }
            }
            .padding()
        }
    }
    
    private var expensesTab: some View {
        ScrollView {
            VStack(spacing: OPSStyle.Layout.spacing3) {
                if expenses.isEmpty {
                    // Empty state
                    emptyStateView(
                        icon: "dollarsign.circle.fill",
                        title: "No expenses found",
                        message: "Expenses you've submitted will appear here"
                    )
                } else {
                    // Expense cards
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
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Header with project title and status
            HStack {
                Text(project.title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Spacer()
                
                // Status badge
                Text(project.status.description)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(project.statusColor)
                    .cornerRadius(12)
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
            Button(action: {
                // Action to view project details
            }) {
                HStack {
                    Text("View Details")
                        .font(OPSStyle.Typography.captionBold)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .padding(.top, 4)
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackground.opacity(0.3))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
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
        // This would normally load from your data controller
        isLoading = true
        
        Task {
            // Load projects assigned to current user
            let history = dataController.getProjectHistory(
                for: dataController.currentUser?.id ?? ""
            )
            
            // In a real app, you would load expenses from the data controller
            // For now, using sample data
            
            await MainActor.run {
                self.projectHistory = history
                self.expenses = []  // Empty for now to show empty state
                
                // Sample data - uncomment to see populated UI:
                /*
                self.expenses = [
                    Expense(
                        id: "1",
                        projectId: history.first?.id,
                        projectTitle: history.first?.title,
                        amount: 126.50,
                        description: "Construction materials",
                        date: Date().addingTimeInterval(-7*24*60*60),
                        status: .approved,
                        category: "Materials",
                        receiptURL: "https://example.com/receipt1.pdf"
                    ),
                    Expense(
                        id: "2",
                        projectId: history.first?.id,
                        projectTitle: history.first?.title,
                        amount: 45.75,
                        description: "Lunch for team",
                        date: Date().addingTimeInterval(-3*24*60*60),
                        status: .pending,
                        category: "Meals",
                        receiptURL: nil
                    )
                ]
                */
                
                self.isLoading = false
            }
        }
    }
    
    private func applyFilters() {
        // Apply date and status filters to the data
        // In a real implementation, this would requery the filtered data
        loadHistoryData()
    }
}

#Preview {
    ProjectHistorySettingsView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}