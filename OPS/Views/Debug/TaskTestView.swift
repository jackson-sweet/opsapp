//
//  TaskTestView.swift
//  OPS
//
//  Debug view for testing task-based scheduling models
//

import SwiftUI
import SwiftData

struct TaskTestView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    @State private var testProject: Project?
    @State private var testTasks: [ProjectTask] = []
    @State private var testTaskTypes: [TaskType] = []
    @State private var statusMessage = "Ready to test"
    @State private var isSyncing = false

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Test Status")
                .font(.headline)
            Text(statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private var testActionsSection: some View {
        VStack(spacing: 12) {
            Button(action: createTestData) {
                Label("Create Test Data", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: testTaskStatusPropagation) {
                Label("Test Status Propagation", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(testProject == nil)

            Button(action: testTaskDateAssignment) {
                Label("Assign Task Dates", systemImage: "calendar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(testTasks.isEmpty)

            Button(action: cleanupTestData) {
                Label("Cleanup Test Data", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
            .disabled(testProject == nil)

            Divider()
                .padding(.vertical, 8)

            // API Sync Testing
            Text("API Sync Testing")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
           
            Button(action: testTaskTypeSync) {
                Label("Test TaskType Sync", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSyncing)

            Button(action: testTaskSync) {
                Label("Test Task Sync", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isSyncing || testProject == nil)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var testDataSection: some View {
        if let project = testProject {
            projectDataSection(project)
        }

        if !testTaskTypes.isEmpty {
            taskTypesDataSection
        }

        if !testTasks.isEmpty {
            tasksDataSection
        }
    }

    private func projectDataSection(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test Project")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Title: \(project.title)")
                Text("Status: \(project.status.displayName)")
                Text("Computed Status: \(project.computedStatus.displayName)")
                Text("Has Tasks: \(project.hasTasks ? "Yes" : "No")")
                Text("Task Count: \(project.tasks.count)")
            }
            .font(.caption)
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.horizontal)
    }

    private var taskTypesDataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Task Types")
                .font(.headline)

            ForEach(testTaskTypes, id: \.id) { taskType in
                HStack {
                    if let icon = taskType.icon {
                        Image(systemName: icon)
                            .foregroundColor(Color(hex: taskType.color))
                    }
                    Text(taskType.display)
                    Spacer()
                    Circle()
                        .fill(Color(hex: taskType.color) ?? .gray)
                        .frame(width: 20, height: 20)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(.horizontal)
    }

    private var tasksDataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tasks")
                .font(.headline)

            ForEach(testTasks, id: \.id) { task in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.displayTitle)
                            .font(.caption)
                            .bold()
                        Spacer()
                        Text(task.status.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(statusColor(for: task.status))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    Text("Color: \(task.effectiveColor)")
                        .font(.caption2)
                    Text("Order: \(task.displayOrder)")
                        .font(.caption2)
                    Text("Dates: \(formatDate(task.startDate)) - \(formatDate(task.endDate))")
                        .font(.caption2)
                    Text("Duration: \(task.duration) days")
                        .font(.caption2)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(.horizontal)
    }


    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusSection
                    testActionsSection
                    testDataSection
                    Spacer(minLength: 50)
                }
                .padding(.vertical)
            }
            .navigationTitle("Task Model Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Test Functions
    
    private func createTestData() {
        statusMessage = "Creating test data..."
        
        // Create test company (if needed)
        let companyId = "test-company-001"
        
        // Create test project
        let project = Project(
            id: "test-project-001",
            title: "Test Renovation Project",
            status: .accepted
        )
        project.companyId = companyId
        // Client name will be set via Client relationship
        project.address = "123 Test Street"
        project.startDate = Date()
        project.endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())
        
        modelContext.insert(project)
        testProject = project
        
        // Create task types
        let taskTypes = [
            TaskType(
                id: "test-type-001",
                display: "Site Estimate",
                color: "#A5B368",
                companyId: companyId,
                isDefault: true,
                icon: "clipboard.fill"
            ),
            TaskType(
                id: "test-type-002",
                display: "Installation",
                color: "#931A32",
                companyId: companyId,
                isDefault: true,
                icon: "hammer.fill"
            ),
            TaskType(
                id: "test-type-003",
                display: "Inspection",
                color: "#7B68A6",
                companyId: companyId,
                isDefault: true,
                icon: "magnifyingglass"
            )
        ]
        
        taskTypes.forEach { modelContext.insert($0) }
        testTaskTypes = taskTypes
        
        // Create tasks
        let tasks = [
            ProjectTask(
                id: "test-task-001",
                projectId: project.id,
                taskTypeId: taskTypes[0].id,
                companyId: companyId,
                status: .completed,
                taskColor: taskTypes[0].color
            ),
            ProjectTask(
                id: "test-task-002",
                projectId: project.id,
                taskTypeId: taskTypes[1].id,
                companyId: companyId,
                status: .active,
                taskColor: taskTypes[1].color
            ),
            ProjectTask(
                id: "test-task-003",
                projectId: project.id,
                taskTypeId: taskTypes[2].id,
                companyId: companyId,
                status: .active,
                taskColor: taskTypes[2].color
            )
        ]
        
        // Set display order and relationships
        for (index, task) in tasks.enumerated() {
            task.displayOrder = index
            task.project = project
            task.taskType = taskTypes[index]
            task.taskNotes = "Test notes for \(taskTypes[index].display)"
            modelContext.insert(task)
            project.tasks.append(task)
        }
        
        testTasks = tasks
        
        do {
            try modelContext.save()
            statusMessage = "✅ Test data created successfully"
        } catch {
            statusMessage = "❌ Error creating test data: \(error.localizedDescription)"
        }
    }
    
    private func testTaskStatusPropagation() {
        guard let project = testProject else { return }
        
        statusMessage = "Testing status propagation..."
        
        // Test 1: Mark all tasks as completed
        for task in testTasks {
            task.status = .completed
        }
        
        let allCompleteStatus = project.computedStatus
        statusMessage = "All tasks completed -> Project status: \(allCompleteStatus.displayName)"
        
        // Test 2: Mark one task as active
        if let firstTask = testTasks.first {
            firstTask.status = .active
            let activeStatus = project.computedStatus
            statusMessage += "\nOne task active -> Project status: \(activeStatus.displayName)"
        }
        
        // Test 3: Cancel all tasks
        for task in testTasks {
            task.status = .cancelled
        }
        let allCancelledStatus = project.computedStatus
        statusMessage += "\nAll tasks cancelled -> Project status: \(allCancelledStatus.displayName)"
        
        do {
            try modelContext.save()
        } catch {
            statusMessage = "❌ Error updating statuses: \(error.localizedDescription)"
        }
    }
    
    private func testTaskDateAssignment() {
        guard testProject != nil else { return }

        statusMessage = "Assigning dates to tasks..."

        let calendar = Calendar.current
        var currentDate = Date()

        // Assign dates directly to tasks
        for task in testTasks {
            let startDate = currentDate
            let endDate = calendar.date(byAdding: .day, value: 2, to: startDate) ?? startDate

            task.startDate = startDate
            task.endDate = endDate
            let daysDiff = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            task.duration = daysDiff + 1
            task.needsSync = true

            // Move to next date
            currentDate = calendar.date(byAdding: .day, value: 3, to: currentDate) ?? currentDate
        }

        do {
            try modelContext.save()
            statusMessage = "Assigned dates to \(testTasks.count) tasks"

            // Display date ranges
            let dateInfo = testTasks.map { task in
                "\(task.displayTitle): \(task.spannedDates.count) days"
            }.joined(separator: "\n")
            statusMessage += "\n\(dateInfo)"

        } catch {
            statusMessage = "Error assigning task dates: \(error.localizedDescription)"
        }
    }
    
    private func cleanupTestData() {
        statusMessage = "Cleaning up test data..."

        // Delete tasks
        for task in testTasks {
            modelContext.delete(task)
        }
        testTasks.removeAll()
        
        // Delete task types
        for taskType in testTaskTypes {
            modelContext.delete(taskType)
        }
        testTaskTypes.removeAll()
        
        // Delete project
        if let project = testProject {
            modelContext.delete(project)
            testProject = nil
        }
        
        do {
            try modelContext.save()
            statusMessage = "✅ Test data cleaned up"
        } catch {
            statusMessage = "❌ Error cleaning up: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Helper Functions
    
    private func statusColor(for status: TaskStatus) -> Color {
        switch status {
        case .active:
            return .blue
        case .completed:
            return .green
        case .cancelled:
            return .gray
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "nil" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - API Sync Test Functions
    
    private func testTaskTypeSync() {
        guard let syncManager = dataController.syncManager else {
            statusMessage = "❌ SyncManager not available"
            return
        }
        
        isSyncing = true
        statusMessage = "Testing TaskType sync..."
        
        Task {
            do {
                // Get current user's company ID
                guard let currentUser = dataController.currentUser else {
                    await MainActor.run {
                        statusMessage = "❌ No current user found"
                        isSyncing = false
                    }
                    return
                }
                
                guard let companyId = currentUser.companyId, !companyId.isEmpty else {
                    await MainActor.run {
                        statusMessage = "❌ No company ID found"
                        isSyncing = false
                    }
                    return
                }
                
                // Sync task types
                try await syncManager.syncCompanyTaskTypes(companyId: companyId)
                
                // Fetch and display synced task types
                let descriptor = FetchDescriptor<TaskType>(
                    predicate: #Predicate<TaskType> { $0.companyId == companyId }
                )
                let syncedTypes = try modelContext.fetch(descriptor)
                
                await MainActor.run {
                    testTaskTypes = syncedTypes
                    statusMessage = "✅ Synced \(syncedTypes.count) task types"
                    isSyncing = false
                }
                
            } catch {
                await MainActor.run {
                    statusMessage = "❌ Sync failed: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
    
    private func testTaskSync() {
        guard let syncManager = dataController.syncManager,
              let project = testProject else {
            statusMessage = "❌ SyncManager or project not available"
            return
        }
        
        isSyncing = true
        statusMessage = "Testing Task sync for project..."
        
        Task {
            do {
                let projectId = project.id
                
                // Sync tasks for the test project
                try await syncManager.syncProjectTasks(projectId: projectId)
                
                // Fetch and display synced tasks
                let descriptor = FetchDescriptor<ProjectTask>(
                    predicate: #Predicate<ProjectTask> { $0.projectId == projectId }
                )
                let syncedTasks = try modelContext.fetch(descriptor)
                
                await MainActor.run {
                    testTasks = syncedTasks
                    statusMessage = "✅ Synced \(syncedTasks.count) tasks for project"
                    isSyncing = false
                }
                
            } catch {
                await MainActor.run {
                    statusMessage = "❌ Task sync failed: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
}

// Preview
struct TaskTestView_Previews: PreviewProvider {
    static var previews: some View {
        TaskTestView()
    }
}
