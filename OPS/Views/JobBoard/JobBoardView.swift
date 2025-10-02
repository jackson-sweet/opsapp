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
    @State private var previousSection: JobBoardSection = .dashboard
    @State private var searchText = ""
    @State private var showingFilters = false
    @State private var showCreateMenu = false
    @State private var showingCreateProject = false
    @State private var showingCreateClient = false
    @State private var showingCreateTaskType = false
    @State private var showingCreateTask = false
    @State private var showingProjectFilterSheet = false
    @State private var showingTaskFilterSheet = false

    // Permission check
    private var hasAccess: Bool {
        guard let currentUser = dataController.currentUser else { return false }
        return currentUser.role == .admin || currentUser.role == .officeCrew
    }

    private var isAdmin: Bool {
        return dataController.currentUser?.role == .admin
    }

    private var slideTransition: AnyTransition {
        let currentIndex = JobBoardSection.allCases.firstIndex(of: selectedSection) ?? 0
        let previousIndex = JobBoardSection.allCases.firstIndex(of: previousSection) ?? 0

        if currentIndex > previousIndex {
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        } else {
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        }
    }

    var body: some View {
        
            ZStack (alignment: .top) {
                // Background
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                AppHeader(headerType: .jobBoard)

                VStack(spacing: 0) {

                    // Section selector
                    JobBoardSectionSelector(selectedSection: $selectedSection)
                        .padding(.top, 70) // Account for header
                        .onChange(of: selectedSection) { oldValue, newValue in
                            previousSection = oldValue
                        }

                    // Universal search bar
                    if selectedSection != .dashboard {
                        UniversalSearchBar(
                            section: selectedSection,
                            searchText: $searchText,
                            showingFilters: $showingFilters,
                            onFilterTap: {
                                switch selectedSection {
                                case .projects:
                                    showingProjectFilterSheet = true
                                case .tasks:
                                    showingTaskFilterSheet = true
                                default:
                                    break
                                }
                            }
                        )
                        .padding(.top, 12)
                    }

                    // Main content
                    Group {
                        switch selectedSection {
                        case .dashboard:
                            JobBoardDashboard()
                        case .clients:
                            ClientListView(searchText: searchText)
                                .padding(.horizontal, 4)
                        case .projects:
                            JobBoardProjectListView(
                                searchText: searchText,
                                showingFilters: $showingFilters,
                                showingFilterSheet: $showingProjectFilterSheet
                            )
                            .padding(.horizontal, 4)
                        case .tasks:
                            JobBoardTasksView(
                                searchText: searchText,
                                showingFilters: $showingFilters,
                                showingFilterSheet: $showingTaskFilterSheet
                            )
                            .padding(.horizontal, 4)
                        }
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: selectedSection)
                    
                }
            
                // Floating action button and menu
                ZStack {
                    // Dimmed background when menu is shown
                    if showCreateMenu {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showCreateMenu = false
                                }
                            }
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()

                            VStack(alignment: .trailing, spacing: 16) {
                                // Floating menu items (shown when expanded)
                                VStack(alignment: .trailing, spacing: 16){
                                if showCreateMenu {
                                    FloatingActionItem(
                                        icon: "checklist",
                                        label: "New Task Type",
                                        action: {
                                            showCreateMenu = false
                                            showingCreateTaskType = true
                                        }
                                    )
                                    .transition(.scale.combined(with: .opacity))
                                    
                                    FloatingActionItem(
                                        icon: "checkmark.square.fill",
                                        label: "Create Task",
                                        action: {
                                            showCreateMenu = false
                                            showingCreateTask = true
                                        }
                                    )
                                    .transition(.scale.combined(with: .opacity))
                                    
                                    FloatingActionItem(
                                        icon: "folder.badge.plus",
                                        label: "Create Project",
                                        action: {
                                            showCreateMenu = false
                                            showingCreateProject = true
                                        }
                                    )
                                    .transition(.scale.combined(with: .opacity))
                                    
                                    FloatingActionItem(
                                        icon: "person.badge.plus",
                                        label: "Create Client",
                                        action: {
                                            showCreateMenu = false
                                            showingCreateClient = true
                                        }
                                    )
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                                .padding(.trailing, 8)
                                // Main plus button
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        showCreateMenu.toggle()
                                    }
                                }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 30))
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                        .rotationEffect(.degrees(showCreateMenu ? 225 : 0))
                                        .frame(width: 64, height: 64)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                        .shadow(color: OPSStyle.Colors.background.opacity(0.4), radius: 8, x: 0, y: 4)
                                }
                            }
                            .padding(.trailing, 36)
                            .padding(.bottom, 140) // Position above tab bar
                        }
                    }
                }
                
            
            }
            .sheet(isPresented: $showingCreateClient) {
                ClientFormSheet(mode: .create) { _ in }
            }
            .sheet(isPresented: $showingCreateProject) {
                ProjectFormSheet(mode: .create) { _ in }
            }
            .sheet(isPresented: $showingCreateTaskType) {
                TaskTypeFormSheet { _ in }
            }
            .sheet(isPresented: $showingCreateTask) {
                TaskFormSheet(mode: .create) { _ in }
            }
        }
    
}

// MARK: - Floating Action Item
struct FloatingActionItem: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                
                Text(label.uppercased())
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 48, height: 48)
                    .background(.clear)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(OPSStyle.Colors.secondaryText.opacity(1), lineWidth: 1)
                    )
                    .shadow(color: OPSStyle.Colors.background.opacity(0.3), radius: 4, x: 0, y: 2)
                
            }
           
            
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
            return "chart.bar"
        case .clients:
            return "person.2"
        case .projects:
            return "folder"
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
                        //Image(systemName: section.icon)
                         //   .font(.system(size: 20, weight: .medium))
                         //   .foregroundColor(selectedSection == section ? OPSStyle.Colors.cardBackground : OPSStyle.Colors.primaryText)
                        
                        Text(section.rawValue.uppercased())
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(selectedSection == section ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(selectedSection == section ? OPSStyle.Colors.primaryText : .clear)
                    )
                }
            }
        }
        //.padding(4)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius + 4)
                .fill(OPSStyle.Colors.cardBackgroundDark)
)
    }
}

// MARK: - Dashboard View (Placeholder)
struct JobBoardDashboardOld: View {
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
        return projects.filter { $0.status == .inProgress || $0.status == .accepted }.count
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

// MARK: - Clients Preview
struct JobBoardClientsPreview: View {
    @EnvironmentObject private var dataController: DataController
    @State private var showingCreateClient = false

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            HStack {
                Text("CLIENT MANAGEMENT")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                Text("VIEW ALL")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }

            let clients = dataController.getAllClients(for: dataController.currentUser?.companyId ?? "")
            if clients.isEmpty {
                JobBoardEmptyState(
                    icon: "person.2.fill",
                    title: "No Clients Yet",
                    subtitle: "Add your first client to get started"
                )
            } else {
                // Show preview of first 3 clients
                ForEach(clients.prefix(3)) { client in
                    ClientRowView(client: client)
                }

                if clients.count > 3 {
                    Text("+ \(clients.count - 3) more clients")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.top, OPSStyle.Layout.spacing2)
                }
            }
        }
    }
}

// MARK: - Projects Preview
struct JobBoardProjectsPreview: View {
    @EnvironmentObject private var dataController: DataController
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            HStack {
                Text("PROJECT MANAGEMENT")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                Text("VIEW ALL")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            
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
    let searchText: String
    @Binding var showingFilters: Bool
    @Binding var showingFilterSheet: Bool
    @EnvironmentObject private var dataController: DataController
    @State private var selectedStatuses: Set<TaskStatus> = []
    @State private var selectedTaskTypeIds: Set<String> = []
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var sortOption: TaskSortOption = .createdDateDescending
    @State private var selectedTaskType: TaskType?
    @State private var showingTaskTypeDetails = false
    @State private var isCancelledExpanded = false

    private var allTasks: [ProjectTask] {
        let projects = dataController.getAllProjects()
        return projects.flatMap { $0.tasks }
    }

    private var availableTaskTypes: [TaskType] {
        guard let companyId = dataController.currentUser?.companyId else { return [] }
        return dataController.getAllTaskTypes(for: companyId)
    }

    private var availableTeamMembers: [User] {
        guard let companyId = dataController.currentUser?.companyId else { return [] }
        return dataController.getTeamMembers(companyId: companyId)
    }

    private var filteredTasks: [ProjectTask] {
        var filtered = allTasks

        if !selectedStatuses.isEmpty {
            filtered = filtered.filter { selectedStatuses.contains($0.status) }
        }

        if !selectedTaskTypeIds.isEmpty {
            filtered = filtered.filter { selectedTaskTypeIds.contains($0.taskTypeId) }
        }

        if !selectedTeamMemberIds.isEmpty {
            filtered = filtered.filter { task in
                let taskTeamMemberIds = Set(task.getTeamMemberIds())
                return !taskTeamMemberIds.intersection(selectedTeamMemberIds).isEmpty
            }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { task in
                let taskType = dataController.getAllTaskTypes(for: task.companyId).first(where: { $0.id == task.taskTypeId })
                let taskTypeName = taskType?.display ?? ""
                let projectName = dataController.getAllProjects().first(where: { $0.id == task.projectId })?.title ?? ""

                return taskTypeName.localizedCaseInsensitiveContains(searchText) ||
                       projectName.localizedCaseInsensitiveContains(searchText) ||
                       (task.taskNotes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        switch sortOption {
        case .createdDateDescending:
            return filtered.sorted(by: { ($0.scheduledDate ?? Date.distantPast) > ($1.scheduledDate ?? Date.distantPast) })
        case .createdDateAscending:
            return filtered.sorted(by: { ($0.scheduledDate ?? Date.distantPast) < ($1.scheduledDate ?? Date.distantPast) })
        case .scheduledDateDescending:
            return filtered.sorted(by: { ($0.scheduledDate ?? Date.distantPast) > ($1.scheduledDate ?? Date.distantPast) })
        case .scheduledDateAscending:
            return filtered.sorted(by: { ($0.scheduledDate ?? Date.distantPast) < ($1.scheduledDate ?? Date.distantPast) })
        case .statusAscending:
            return filtered.sorted(by: { $0.status.sortOrder < $1.status.sortOrder })
        case .statusDescending:
            return filtered.sorted(by: { $0.status.sortOrder > $1.status.sortOrder })
        }
    }

    private var activeTasks: [ProjectTask] {
        filteredTasks.filter { $0.status != .cancelled }
    }

    private var cancelledTasks: [ProjectTask] {
        filteredTasks.filter { $0.status == .cancelled }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showingFilters && hasActiveFilters {
                activeFilterBadges
                    .padding(.top, 8)
            }

            if allTasks.isEmpty {
                JobBoardEmptyState(
                    icon: "checklist",
                    title: "No Tasks Yet",
                    subtitle: "Create tasks from projects to get started"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(activeTasks) { task in
                            UniversalJobBoardCard(cardType: .task(task))
                                .environmentObject(dataController)
                        }

                        if !cancelledTasks.isEmpty {
                            CollapsibleSection(
                                title: "CANCELLED",
                                count: cancelledTasks.count,
                                isExpanded: $isCancelledExpanded
                            ) {
                                ForEach(cancelledTasks) { task in
                                    UniversalJobBoardCard(cardType: .task(task))
                                        .environmentObject(dataController)
                                }
                            }
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
            }
        }
        .sheet(isPresented: $showingTaskTypeDetails) {
            if let taskType = selectedTaskType {
                TaskTypeDetailSheet(taskType: taskType)
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            TaskListFilterSheet(
                selectedStatuses: $selectedStatuses,
                selectedTaskTypeIds: $selectedTaskTypeIds,
                selectedTeamMemberIds: $selectedTeamMemberIds,
                sortOption: $sortOption,
                availableTaskTypes: availableTaskTypes,
                availableTeamMembers: availableTeamMembers
            )
            .environmentObject(dataController)
            .onDisappear {
                updateFilterVisibility()
            }
        }
        .onChange(of: selectedStatuses) { _, _ in
            updateFilterVisibility()
        }
        .onChange(of: selectedTaskTypeIds) { _, _ in
            updateFilterVisibility()
        }
        .onChange(of: selectedTeamMemberIds) { _, _ in
            updateFilterVisibility()
        }
    }

    private var filterButton: some View {
        Button(action: {
            showingFilterSheet = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 20))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                Text("FILTER & SORT")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                if hasActiveFilters {
                    let filterCount = selectedStatuses.count + selectedTaskTypeIds.count + selectedTeamMemberIds.count
                    Text("\(filterCount)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Circle()
                                .fill(OPSStyle.Colors.primaryAccent)
                        )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(hasActiveFilters ? OPSStyle.Colors.primaryAccent.opacity(0.3) : OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 20)
        .sheet(isPresented: $showingFilterSheet) {
            TaskListFilterSheet(
                selectedStatuses: $selectedStatuses,
                selectedTaskTypeIds: $selectedTaskTypeIds,
                selectedTeamMemberIds: $selectedTeamMemberIds,
                sortOption: $sortOption,
                availableTaskTypes: availableTaskTypes,
                availableTeamMembers: availableTeamMembers
            )
            .environmentObject(dataController)
        }
    }

    private var activeFilterBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedStatuses), id: \.self) { status in
                    TaskFilterBadge(
                        text: status.displayName,
                        color: statusColor(for: status),
                        onRemove: {
                            selectedStatuses.remove(status)
                        }
                    )
                }

                ForEach(Array(selectedTaskTypeIds), id: \.self) { taskTypeId in
                    if let taskType = availableTaskTypes.first(where: { $0.id == taskTypeId }) {
                        TaskFilterBadge(
                            text: taskType.display,
                            color: Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent,
                            onRemove: {
                                selectedTaskTypeIds.remove(taskTypeId)
                            }
                        )
                    }
                }

                ForEach(Array(selectedTeamMemberIds), id: \.self) { memberId in
                    if let member = availableTeamMembers.first(where: { $0.id == memberId }) {
                        TaskFilterBadge(
                            text: "\(member.firstName) \(member.lastName)",
                            color: OPSStyle.Colors.primaryAccent,
                            onRemove: {
                                selectedTeamMemberIds.remove(memberId)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var hasActiveFilters: Bool {
        !selectedStatuses.isEmpty || !selectedTaskTypeIds.isEmpty || !selectedTeamMemberIds.isEmpty
    }

    private func updateFilterVisibility() {
        if hasActiveFilters {
            showingFilters = true
        } else {
            showingFilters = false
        }
    }

    private func statusColor(for status: TaskStatus) -> Color {
        return status.color
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
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
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
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Create Menu
struct JobBoardCreateMenu: View {
    let selectedSection: JobBoardSection
    @Environment(\.dismiss) private var dismiss
    @State private var showingCreateClient = false
    @State private var showingCreateProject = false

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
                                showingCreateClient = true
                            }
                        )
                        
                        Divider()
                            .background(OPSStyle.Colors.secondaryText.opacity(0.2))
                        
                        CreateMenuItem(
                            icon: "folder.badge.plus",
                            title: "New Project",
                            action: {
                                showingCreateProject = true
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
        .sheet(isPresented: $showingCreateClient) {
            ClientFormSheet(mode: .create) { _ in
                dismiss()
            }
        }
        .sheet(isPresented: $showingCreateProject) {
            // TODO: Add ProjectFormSheet when implemented
            Text("Project creation coming soon")
                .navigationTitle("NEW PROJECT")
                .navigationBarTitleDisplayMode(.inline)
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

struct TaskFilterBadge: View {
    let text: String
    let color: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(text.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

#Preview {
    JobBoardView()
        .environmentObject(DataController())
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
