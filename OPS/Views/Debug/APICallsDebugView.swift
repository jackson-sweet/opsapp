//
//  APICallsDebugView.swift
//  OPS
//
//  Debug view for testing API calls and viewing responses
//

import SwiftUI
import SwiftData

struct APICallsDebugView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    @State private var selectedCategory: APICategory = .projects
    @State private var isLoading = false
    @State private var responseText = "Select an API call to test"
    @State private var responseStatus = ""
    @State private var showRawResponse = false
    @State private var showClearDataConfirmation = false
    
    enum APICategory: String, CaseIterable {
        case projects = "Projects"
        case tasks = "Tasks"
        case taskTypes = "Task Types"
        case calendarEvents = "Calendar Events"
        case clients = "Clients"
        case users = "Users"
        case company = "Company"
        
        var icon: String {
            switch self {
            case .projects: return "folder"
            case .tasks: return "list.bullet"
            case .taskTypes: return "tag"
            case .calendarEvents: return "calendar"
            case .clients: return "person.2"
            case .users: return "person.circle"
            case .company: return "building.2"
            }
        }
    }
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: OPSStyle.Icons.close)
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    
                    Spacer()
                    
                    Text("API Calls Debug")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button(action: { showClearDataConfirmation = true }) {
                            Image(systemName: OPSStyle.Icons.delete)
                                .font(.system(size: 16))
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                        
                        Button(action: { showRawResponse.toggle() }) {
                            Text(showRawResponse ? "Formatted" : "Raw")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                
                // Category selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(APICategory.allCases, id: \.self) { category in
                            CategoryChip(
                                title: category.rawValue,
                                icon: category.icon,
                                isSelected: selectedCategory == category,
                                action: { selectedCategory = category }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
                
                // API calls for selected category
                ScrollView {
                    VStack(spacing: 12) {
                        apiCallsForCategory(selectedCategory)
                    }
                    .padding()
                }
                
                // Response section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Response")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        if !responseStatus.isEmpty {
                            Text(responseStatus)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(responseStatus.contains("200") ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                        }
                        
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    
                    ScrollView {
                        Text(responseText)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(OPSStyle.Colors.avatarOverlay)
                            .cornerRadius(8)
                    }
                    .frame(height: 200)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
            }
        }
        .alert("Clear Local Task Data", isPresented: $showClearDataConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                clearLocalTaskData()
            }
        } message: {
            Text("This will delete all local Tasks, Calendar Events, Task Types, and Task Status data. You can re-sync from the API afterwards.")
        }
    }
    
    @ViewBuilder
    private func apiCallsForCategory(_ category: APICategory) -> some View {
        switch category {
        case .projects:
            APICallButton(title: "Fetch All Projects", icon: "arrow.down.circle") {
                await fetchProjects()
            }
            APICallButton(title: "Fetch User Projects", icon: "person.crop.circle.badge.checkmark") {
                await fetchUserProjects()
            }
            APICallButton(title: "Fetch Company Projects", icon: "building.2.crop.circle") {
                await fetchCompanyProjects()
            }
            
        case .tasks:
            APICallButton(title: "Fetch Company Tasks", icon: "list.bullet.rectangle") {
                await fetchCompanyTasks()
            }
            APICallButton(title: "Fetch Project Tasks", icon: "folder.badge.questionmark") {
                await fetchProjectTasks()
            }
            APICallButton(title: "Fetch User Tasks", icon: "person.crop.circle.badge.questionmark") {
                await fetchUserTasks()
            }
            APICallButton(title: "Test Task Type Name", icon: "questionmark.circle") {
                await testTaskTypeName()
            }
            
        case .taskTypes:
            APICallButton(title: "Fetch Company Task Types", icon: "tag.circle") {
                await fetchCompanyTaskTypes()
            }
            APICallButton(title: "Create Default Task Types", icon: "plus.circle") {
                await createDefaultTaskTypes()
            }
            
        case .calendarEvents:
            APICallButton(title: "Fetch Company Calendar Events", icon: "calendar.circle") {
                await fetchCompanyCalendarEvents()
            }
            APICallButton(title: "Fetch Project Calendar Events", icon: "calendar.badge.plus") {
                await fetchProjectCalendarEvents()
            }
            
        case .clients:
            APICallButton(title: "Fetch Company Clients", icon: "person.2.circle") {
                await fetchCompanyClients()
            }
            APICallButton(title: "Fetch Single Client", icon: "person.circle") {
                await fetchSingleClient()
            }
            
        case .users:
            APICallButton(title: "Fetch Current User", icon: "person.circle.fill") {
                await fetchCurrentUser()
            }
            APICallButton(title: "Fetch Team Members", icon: "person.3") {
                await fetchTeamMembers()
            }
            
        case .company:
            APICallButton(title: "Fetch Company Info", icon: "building.2.fill") {
                await fetchCompanyInfo()
            }
        }
    }
    
    // MARK: - API Call Functions
    
    private func fetchProjects() async {
        isLoading = true
        responseText = "Fetching all projects..."
        
        do {
            let projects = try await dataController.apiService.fetchProjects()
            responseStatus = "200 OK"
            responseText = formatResponse(projects, count: projects.count, type: "Projects")
        } catch {
            responseStatus = "Error"
            responseText = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func fetchUserProjects() async {
        guard let userId = dataController.currentUser?.id else {
            responseText = "Error: No current user ID"
            return
        }
        
        isLoading = true
        responseText = "Fetching user projects..."
        
        do {
            let projects = try await dataController.apiService.fetchUserProjects(userId: userId)
            responseStatus = "200 OK"
            responseText = formatResponse(projects, count: projects.count, type: "User Projects")
        } catch {
            responseStatus = "Error"
            responseText = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func fetchCompanyProjects() async {
        guard let companyId = dataController.currentUser?.companyId else {
            responseText = "Error: No company ID"
            return
        }
        
        isLoading = true
        responseText = "Fetching company projects..."
        
        do {
            let projects = try await dataController.apiService.fetchCompanyProjects(companyId: companyId)
            responseStatus = "200 OK"
            responseText = formatResponse(projects, count: projects.count, type: "Company Projects")
        } catch {
            responseStatus = "Error"
            responseText = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func fetchCompanyTasks() async {
        guard let companyId = dataController.currentUser?.companyId else {
            responseText = "Error: No company ID"
            return
        }
        
        isLoading = true
        responseText = "Fetching company tasks..."
        
        do {
            let tasks = try await dataController.apiService.fetchCompanyTasks(companyId: companyId)
            responseStatus = "200 OK"
            responseText = formatResponse(tasks, count: tasks.count, type: "Tasks")
            
            // Print to console for debugging
            for (index, task) in tasks.enumerated() {
            }
        } catch {
            responseStatus = "Error"
            responseText = "Error: \(error.localizedDescription)\n\nThis likely means the Task type doesn't exist in Bubble yet."
        }
        
        isLoading = false
    }
    
    private func fetchProjectTasks() async {
        responseText = "Please select a project first (not implemented in debug view)"
    }
    
    private func fetchUserTasks() async {
        guard let userId = dataController.currentUser?.id else {
            responseText = "Error: No current user ID"
            return
        }
        
        isLoading = true
        responseText = "Fetching user tasks..."
        
        do {
            let tasks = try await dataController.apiService.fetchUserTasks(userId: userId)
            responseStatus = "200 OK"
            responseText = formatResponse(tasks, count: tasks.count, type: "User Tasks")
        } catch {
            responseStatus = "Error"
            responseText = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func testTaskTypeName() async {
        isLoading = true
        responseText = "Testing different task type names in Bubble..."
        
        // Try different possible names
        let possibleNames = ["Task", "task", "Tasks", "tasks", "ProjectTask", "project_task"]
        var results: [String] = []
        
        for name in possibleNames {
            results.append("Testing '\(name)'...")
            // We'll need to create a test endpoint for this
        }
        
        responseText = """
        Possible task type names to check in Bubble:
        - Task
        - Tasks
        - ProjectTask
        - project_task
        
        Check your Bubble data types to see what exists.
        The error "Type not found task" suggests it doesn't exist yet.
        """
        responseStatus = "Info"
        isLoading = false
    }
    
    private func fetchCompanyTaskTypes() async {
        guard let companyId = dataController.currentUser?.companyId else {
            responseText = "Error: No company ID"
            return
        }
        
        isLoading = true
        responseText = "Fetching company task types..."
        
        do {
            let taskTypes = try await dataController.apiService.fetchCompanyTaskTypes(companyId: companyId)
            responseStatus = "200 OK"
            responseText = formatResponse(taskTypes, count: taskTypes.count, type: "Task Types")
            
            // Print to console for debugging
            for (index, taskType) in taskTypes.enumerated() {
            }
        } catch {
            responseStatus = "Error"
            responseText = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func createDefaultTaskTypes() async {
        guard let companyId = dataController.currentUser?.companyId else {
            responseText = "Error: No company ID"
            return
        }
        
        isLoading = true
        responseText = "Creating default task types..."
        
        let defaultTypes = TaskType.createDefaults(companyId: companyId)
        var created = 0
        var errors: [String] = []
        
        for taskType in defaultTypes {
            do {
                let dto = TaskTypeDTO.from(taskType)
                _ = try await dataController.apiService.createTaskType(dto)
                created += 1
            } catch {
                errors.append("Failed to create \(taskType.display): \(error.localizedDescription)")
            }
        }
        
        responseStatus = created > 0 ? "200 OK" : "Error"
        responseText = """
        Created \(created) of \(defaultTypes.count) task types
        
        \(errors.joined(separator: "\n"))
        """
        
        isLoading = false
    }
    
    private func fetchCompanyCalendarEvents() async {
        guard let companyId = dataController.currentUser?.companyId else {
            responseText = "Error: No company ID"
            return
        }
        
        isLoading = true
        responseText = "Fetching company calendar events..."
        
        do {
            let events = try await dataController.apiService.fetchCompanyCalendarEvents(companyId: companyId)
            responseStatus = "200 OK"
            responseText = formatResponse(events, count: events.count, type: "Calendar Events")
            
            // Print to console for debugging
            for (index, event) in events.enumerated() {
            }
        } catch {
            responseStatus = "Error"
            responseText = "Error: \(error.localizedDescription)\n\nThis likely means the CalendarEvent type doesn't exist in Bubble yet."
        }
        
        isLoading = false
    }
    
    private func fetchProjectCalendarEvents() async {
        responseText = "Please select a project first (not implemented in debug view)"
    }
    
    private func fetchCompanyClients() async {
        guard let companyId = dataController.currentUser?.companyId else {
            responseText = "Error: No company ID"
            return
        }
        
        isLoading = true
        responseText = "Fetching company clients..."
        
        do {
            let clients = try await dataController.apiService.fetchCompanyClients(companyId: companyId)
            responseStatus = "200 OK"
            responseText = formatResponse(clients, count: clients.count, type: "Clients")
        } catch {
            responseStatus = "Error"
            responseText = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func fetchSingleClient() async {
        responseText = "Please enter a client ID (not implemented in debug view)"
    }
    
    private func fetchCurrentUser() async {
        guard let userId = dataController.currentUser?.id else {
            responseText = "Error: No current user ID"
            return
        }
        
        isLoading = true
        responseText = "Fetching current user..."
        
        do {
            let user = try await dataController.apiService.fetchUser(id: userId)
            responseStatus = "200 OK"
            responseText = formatResponse([user], count: 1, type: "User")
        } catch {
            responseStatus = "Error"
            responseText = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func fetchTeamMembers() async {
        guard let companyId = dataController.currentUser?.companyId else {
            responseText = "Error: No company ID"
            return
        }
        
        isLoading = true
        responseText = "Fetching team members..."
        
        do {
            let users = try await dataController.apiService.fetchCompanyUsers(companyId: companyId)
            responseStatus = "200 OK"
            responseText = formatResponse(users, count: users.count, type: "Team Members")
        } catch {
            responseStatus = "Error"
            responseText = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func fetchCompanyInfo() async {
        guard let companyId = dataController.currentUser?.companyId else {
            responseText = "Error: No company ID"
            return
        }
        
        isLoading = true
        responseText = "Fetching company info..."
        
        do {
            let company = try await dataController.apiService.fetchCompany(id: companyId)
            responseStatus = "200 OK"
            responseText = formatResponse([company], count: 1, type: "Company")
        } catch {
            responseStatus = "Error"
            responseText = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Helper Functions
    
    private func clearLocalTaskData() {
        
        guard let modelContext = dataController.modelContext else {
            responseText = "Error: No model context available"
            responseStatus = "Error"
            return
        }
        
        do {
            // Clear Tasks
            let tasks = try modelContext.fetch(FetchDescriptor<ProjectTask>())
            for task in tasks {
                modelContext.delete(task)
            }
            
            // Clear Calendar Events
            let events = try modelContext.fetch(FetchDescriptor<CalendarEvent>())
            for event in events {
                modelContext.delete(event)
            }
            
            // Clear Task Types
            let taskTypes = try modelContext.fetch(FetchDescriptor<TaskType>())
            for taskType in taskTypes {
                modelContext.delete(taskType)
            }
            
            // Save changes
            try modelContext.save()
            
            responseText = "Successfully cleared all local task data:\n- \(tasks.count) tasks\n- \(events.count) calendar events\n- \(taskTypes.count) task types"
            responseStatus = "Cleared"
            
        } catch {
            responseText = "Error clearing data: \(error.localizedDescription)"
            responseStatus = "Error"
        }
    }
    
    private func formatResponse<T: Encodable>(_ items: [T], count: Int, type: String) -> String {
        if showRawResponse {
            // Show raw JSON
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(items)
                return String(data: data, encoding: .utf8) ?? "Failed to encode"
            } catch {
                return "Failed to encode: \(error.localizedDescription)"
            }
        } else {
            // Show formatted summary
            var result = "\(type): \(count) items\n\n"
            
            if let first = items.first {
                result += "First item:\n"
                let mirror = Mirror(reflecting: first)
                for child in mirror.children {
                    if let label = child.label {
                        result += "  \(label): \(child.value)\n"
                    }
                }
            }
            
            return result
        }
    }
}

// API Call Button
struct APICallButton: View {
    let title: String
    let icon: String
    let action: () async -> Void
    
    var body: some View {
        Button(action: {
            Task {
                await action()
            }
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 24)
                
                Text(title)
                    .font(OPSStyle.Typography.body)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .foregroundColor(OPSStyle.Colors.primaryText)
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }
}

// Category Chip
struct CategoryChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(OPSStyle.Typography.caption)
            }
            .foregroundColor(isSelected ? .black : OPSStyle.Colors.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(16)
        }
    }
}