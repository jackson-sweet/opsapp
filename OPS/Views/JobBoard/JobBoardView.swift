//
//  JobBoardView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-09-26.
//

import SwiftUI
import SwiftData

struct JobBoardView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @State private var selectedSection: JobBoardSection = .dashboard
    @State private var searchText = ""
    @State private var showCreateMenu = false
    
    // Permission check
    private var hasAccess: Bool {
        guard let currentUser = dataController.currentUser else { return false }
        return currentUser.role == .admin || currentUser.role == .officeCrew
    }
    
    private var isAdmin: Bool {
        return dataController.currentUser?.role == .admin
    }
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.background
                .ignoresSafeArea()
            
            if hasAccess {
                VStack(spacing: 0) {
                    // Section selector
                    JobBoardSectionSelector(selectedSection: $selectedSection)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.top, 100) // Account for header
                        .padding(.bottom, OPSStyle.Layout.spacing2)
                    
                    // Main content
                    ScrollView {
                        VStack(spacing: OPSStyle.Layout.spacing3) {
                            switch selectedSection {
                            case .dashboard:
                                JobBoardDashboard()
                            case .clients:
                                JobBoardClientsView(searchText: $searchText)
                            case .projects:
                                JobBoardProjectsView(searchText: $searchText)
                            case .tasks:
                                JobBoardTasksView(searchText: $searchText)
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.bottom, 120) // Account for tab bar
                    }
                }
                
                // Floating action button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            showCreateMenu = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 56, height: 56)
                                .background(OPSStyle.Colors.primaryAccent)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.trailing, OPSStyle.Layout.spacing3)
                        .padding(.bottom, 140) // Position above tab bar
                    }
                }
                
            } else {
                // No access view
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 48))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    
                    Text("ACCESS RESTRICTED")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text("This feature is only available for Admin and Office Crew members")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, OPSStyle.Layout.spacing5)
                }
                .padding(.top, 200)
            }
        }
        .sheet(isPresented: $showCreateMenu) {
            JobBoardCreateMenu(selectedSection: selectedSection)
        }
    }
}

// MARK: - Section Types
enum JobBoardSection: String, CaseIterable {
    case dashboard = "Dashboard"
    case clients = "Clients"
    case projects = "Projects"
    case tasks = "Tasks"
    
    var icon: String {
        switch self {
        case .dashboard:
            return "chart.bar.fill"
        case .clients:
            return "person.2.fill"
        case .projects:
            return "folder.fill"
        case .tasks:
            return "checklist"
        }
    }
}

// MARK: - Section Selector
struct JobBoardSectionSelector: View {
    @Binding var selectedSection: JobBoardSection
    
    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(JobBoardSection.allCases, id: \.self) { section in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedSection = section
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: section.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(selectedSection == section ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                        
                        Text(section.rawValue)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(selectedSection == section ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(selectedSection == section ? OPSStyle.Colors.cardBackgroundDark : Color.clear)
                    )
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius + 4)
                .fill(OPSStyle.Colors.cardBackground)
        )
    }
}

// MARK: - Dashboard View (Placeholder)
struct JobBoardDashboard: View {
    @EnvironmentObject private var dataController: DataController
    
    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            // Stats cards
            HStack(spacing: OPSStyle.Layout.spacing2) {
                StatCard(title: "ACTIVE PROJECTS", value: "\(activeProjectCount)", icon: "folder.fill", color: OPSStyle.Colors.primaryAccent)
                StatCard(title: "TOTAL CLIENTS", value: "\(clientCount)", icon: "person.2.fill", color: .green)
            }
            
            HStack(spacing: OPSStyle.Layout.spacing2) {
                StatCard(title: "PENDING TASKS", value: "\(pendingTaskCount)", icon: "clock.fill", color: .orange)
                StatCard(title: "TEAM MEMBERS", value: "\(teamMemberCount)", icon: "person.3.fill", color: .blue)
            }
            
            // Recent activity placeholder
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("RECENT ACTIVITY")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                VStack(spacing: 0) {
                    ForEach(0..<3) { _ in
                        HStack {
                            Circle()
                                .fill(OPSStyle.Colors.primaryAccent.opacity(0.3))
                                .frame(width: 8, height: 8)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Project status updated")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                
                                Text("2 hours ago")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        
                        Divider()
                            .background(OPSStyle.Colors.secondaryText.opacity(0.2))
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }
    
    private var activeProjectCount: Int {
        let projects = dataController.getAllProjects()
        return projects.filter { $0.status == .inProgress || $0.status == .accepted || $0.status == .pending }.count
    }
    
    private var clientCount: Int {
        guard let companyId = dataController.currentUser?.companyId else { return 0 }
        return dataController.getAllClients(for: companyId).count
    }
    
    private var pendingTaskCount: Int {
        let projects = dataController.getAllProjects()
        let allTasks = projects.flatMap { $0.tasks }
        return allTasks.filter { task in
            task.status == .scheduled || task.status == .inProgress
        }.count
    }
    
    private var teamMemberCount: Int {
        guard let companyId = dataController.currentUser?.companyId else { return 0 }
        return dataController.getTeamMembers(companyId: companyId).count
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                
                Spacer()
            }
            
            Text(value)
                .font(OPSStyle.Typography.largeTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            Text(title)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

// MARK: - Placeholder Views (Will be implemented in subsequent phases)
struct JobBoardClientsView: View {
    @Binding var searchText: String
    @EnvironmentObject private var dataController: DataController
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            Text("CLIENT LIST")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            let clients = dataController.getAllClients(for: dataController.currentUser?.companyId ?? "")
            if clients.isEmpty {
                JobBoardEmptyState(
                    icon: "person.2.fill",
                    title: "No Clients Yet",
                    subtitle: "Add your first client to get started"
                )
            } else {
                ForEach(clients) { client in
                    ClientRowView(client: client)
                }
            }
        }
    }
}

struct JobBoardProjectsView: View {
    @Binding var searchText: String
    @EnvironmentObject private var dataController: DataController
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            Text("PROJECT LIST")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            let projects = dataController.getAllProjects()
            if projects.isEmpty {
                JobBoardEmptyState(
                    icon: "folder.fill",
                    title: "No Projects Yet",
                    subtitle: "Create your first project to get started"
                )
            } else {
                ForEach(projects.sorted(by: { $0.startDate ?? Date() > $1.startDate ?? Date() })) { project in
                    ProjectRowView(project: project)
                }
            }
        }
    }
}

struct JobBoardTasksView: View {
    @Binding var searchText: String
    @EnvironmentObject private var dataController: DataController
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            Text("TASK TEMPLATES")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            let taskTypes = dataController.getAllTaskTypes(for: dataController.currentUser?.companyId ?? "")
            if taskTypes.isEmpty {
                JobBoardEmptyState(
                    icon: "checklist",
                    title: "No Task Types Yet",
                    subtitle: "Create task types to use as templates"
                )
            } else {
                ForEach(taskTypes) { taskType in
                    TaskTypeRowView(taskType: taskType)
                }
            }
        }
    }
}

// MARK: - Job Board Empty State View
struct JobBoardEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            
            Text(title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            Text(subtitle)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing5)
    }
}

// MARK: - Row Views
struct ClientRowView: View {
    let client: Client
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(client.name)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                if let email = client.email {
                    Text(email)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

struct ProjectRowView: View {
    let project: Project
    
    var body: some View {
        HStack {
            Circle()
                .fill(project.status.color)
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(project.effectiveClientName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

struct TaskTypeRowView: View {
    let taskType: TaskType
    
    var body: some View {
        HStack {
            Image(systemName: taskType.icon ?? "checklist")
                .font(.system(size: 16))
                .foregroundColor(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(taskType.display)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(taskType.isDefault ? "Default" : "Custom")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

// MARK: - Create Menu
struct JobBoardCreateMenu: View {
    let selectedSection: JobBoardSection
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    Text("CREATE NEW")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                    
                    VStack(spacing: 0) {
                        CreateMenuItem(
                            icon: "person.badge.plus.fill",
                            title: "New Client",
                            action: {
                                // TODO: Navigate to create client
                                dismiss()
                            }
                        )
                        
                        Divider()
                            .background(OPSStyle.Colors.secondaryText.opacity(0.2))
                        
                        CreateMenuItem(
                            icon: "folder.badge.plus",
                            title: "New Project",
                            action: {
                                // TODO: Navigate to create project
                                dismiss()
                            }
                        )
                        
                        Divider()
                            .background(OPSStyle.Colors.secondaryText.opacity(0.2))
                        
                        CreateMenuItem(
                            icon: "checklist",
                            title: "New Task Type",
                            action: {
                                // TODO: Navigate to create task type
                                dismiss()
                            }
                        )
                    }
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    
                    Spacer()
                }
                .padding(.top, OPSStyle.Layout.spacing3)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }
}

struct CreateMenuItem: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: 28)
                
                Text(title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(OPSStyle.Layout.spacing3)
            .contentShape(Rectangle())
        }
    }
}

#Preview {
    JobBoardView()
        .environmentObject(DataController())
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}