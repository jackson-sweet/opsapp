//
//  TaskListDebugView.swift
//  OPS
//
//  Debug view for displaying all tasks with full field details
//

import SwiftUI
import SwiftData

struct TaskListDebugView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    @State private var tasks: [ProjectTask] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTask: ProjectTask?
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    
                    Spacer()
                    
                    Text("Task List Debug")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: fetchTasks) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                
                if isLoading {
                    Spacer()
                    ProgressView("Loading tasks...")
                        .foregroundColor(.white)
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                        Text("Error")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                        Text(error)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer()
                } else if tasks.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 50))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("No Tasks Found")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                        Text("No tasks in the local database")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(tasks, id: \.id) { task in
                                TaskDetailCard(task: task)
                                    .onTapGesture {
                                        selectedTask = task
                                    }
                            }
                        }
                        .padding()
                    }
                }
                
                // Summary bar
                HStack {
                    Text("Total: \(tasks.count) tasks")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Spacer()
                    
                    Button("Sync from API") {
                        syncTasksFromAPI()
                    }
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
            }
        }
        .onAppear {
            fetchTasks()
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(task: task)
        }
    }
    
    private func fetchTasks() {
        isLoading = true
        errorMessage = nil
        
        do {
            let descriptor = FetchDescriptor<ProjectTask>(
                sortBy: [SortDescriptor(\.displayOrder)]
            )
            tasks = try modelContext.fetch(descriptor)
            isLoading = false
        } catch {
            errorMessage = "Failed to fetch tasks: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func syncTasksFromAPI() {
        guard let companyId = dataController.currentUser?.companyId else {
            errorMessage = "Unable to sync: No company ID"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Fetch from API
                let apiTasks = try await dataController.apiService.fetchCompanyTasks(companyId: companyId)
                
                await MainActor.run {
                    // First, ensure we have task types for all unique type IDs
                    var taskTypeMap: [String: TaskType] = [:]
                    
                    // Fetch existing task types
                    let existingTypes = try? modelContext.fetch(FetchDescriptor<TaskType>())
                    for type in existingTypes ?? [] {
                        taskTypeMap[type.id] = type
                    }
                    
                    // Create missing task types from task data
                    let uniqueTypeIds = Set(apiTasks.compactMap { $0.type })
                    for typeId in uniqueTypeIds {
                        if taskTypeMap[typeId] == nil {
                            // Create a basic task type for this ID
                            let taskType = TaskType(
                                id: typeId,
                                display: "Task Type \(typeId.prefix(8))", // Use first 8 chars of ID as display
                                color: "#59779F",
                                companyId: companyId,
                                isDefault: false,
                                icon: "hammer.fill"
                            )
                            modelContext.insert(taskType)
                            taskTypeMap[typeId] = taskType
                        }
                    }
                    
                    // Convert and save tasks
                    var syncedCount = 0
                    let defaultColor = "#59779F"
                    
                    for dto in apiTasks {
                        // Check if exists
                        let existing = tasks.first { $0.id == dto.id }
                        if existing == nil {
                            let task = dto.toModel(defaultColor: defaultColor)
                            
                            // Link to task type if available
                            if let typeId = dto.type, let taskType = taskTypeMap[typeId] {
                                task.taskType = taskType
                            }
                            
                            modelContext.insert(task)
                            syncedCount += 1
                        }
                    }
                    
                    do {
                        try modelContext.save()
                        errorMessage = "Synced \(syncedCount) new tasks from API"
                    } catch {
                        errorMessage = "Failed to save tasks: \(error.localizedDescription)"
                    }
                    
                    fetchTasks()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "API sync failed: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

// Task detail card showing all fields
struct TaskDetailCard: View {
    let task: ProjectTask
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                if let icon = task.taskType?.icon {
                    Image(systemName: icon)
                        .foregroundColor(Color(hex: task.effectiveColor))
                }
                
                Text(task.displayTitle)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(task.status.displayName)
                    .font(OPSStyle.Typography.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor(for: task.status))
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }
            
            Divider()
                .background(OPSStyle.Colors.tertiaryText)
            
            // Fields grid
            VStack(alignment: .leading, spacing: 4) {
                FieldRow(label: "ID", value: task.id)
                FieldRow(label: "Project ID", value: task.projectId)
                FieldRow(label: "Company ID", value: task.companyId)
                FieldRow(label: "Task Type ID", value: task.taskTypeId)
                FieldRow(label: "Calendar Event ID", value: task.calendarEventId ?? "nil")
                FieldRow(label: "Display Order", value: "\(task.displayOrder)")
                FieldRow(label: "Task Color", value: task.taskColor)
                FieldRow(label: "Effective Color", value: task.effectiveColor)
                FieldRow(label: "Team Members", value: task.getTeamMemberIds().joined(separator: ", ").isEmpty ? "none" : task.getTeamMemberIds().joined(separator: ", "))
                FieldRow(label: "Needs Sync", value: task.needsSync ? "Yes" : "No")
                FieldRow(label: "Last Synced", value: task.lastSyncedAt?.formatted() ?? "Never")
                
                if let notes = task.taskNotes, !notes.isEmpty {
                    FieldRow(label: "Notes", value: notes)
                }
            }
            .font(OPSStyle.Typography.smallCaption)
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    private func statusColor(for status: TaskStatus) -> Color {
        switch status {
        case .scheduled: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        case .cancelled: return .gray
        }
    }
}

// Field row helper
struct FieldRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text("\(label):")
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: 120, alignment: .leading)
            
            Text(value)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// Detailed sheet for a single task
struct TaskDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: ProjectTask
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Task Type Info
                        if let taskType = task.taskType {
                            Section("Task Type") {
                                VStack(alignment: .leading, spacing: 8) {
                                    FieldRow(label: "Display", value: taskType.display)
                                    FieldRow(label: "Color", value: taskType.color)
                                    FieldRow(label: "Icon", value: taskType.icon ?? "none")
                                    FieldRow(label: "Is Default", value: taskType.isDefault ? "Yes" : "No")
                                }
                                .padding()
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(8)
                            }
                        }
                        
                        // Project Info
                        if let project = task.project {
                            Section("Project") {
                                VStack(alignment: .leading, spacing: 8) {
                                    FieldRow(label: "Title", value: project.title)
                                    FieldRow(label: "Status", value: project.status.displayName)
                                    FieldRow(label: "Client", value: project.effectiveClientName)
                                    FieldRow(label: "Address", value: project.address)
                                }
                                .padding()
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(8)
                            }
                        }
                        
                        // Team Members
                        if !task.teamMembers.isEmpty {
                            Section("Team Members") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(task.teamMembers, id: \.id) { member in
                                        HStack {
                                            Text(member.fullName)
                                                .foregroundColor(.white)
                                            Spacer()
                                            Text(member.role.displayName)
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        }
                                    }
                                }
                                .padding()
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Section header helper
private struct Section<Content: View>: View {
    let title: String
    let content: Content
    
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            
            content
        }
    }
}