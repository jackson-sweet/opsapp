//
//  TaskListView.swift
//  OPS
//
//  Task list component for displaying project tasks
//

import SwiftUI
import SwiftData

struct TaskListView: View {
    let project: Project
    var onSwitchToProjectBased: (() -> Void)? = nil
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @State private var selectedTask: ProjectTask? = nil
    @State private var showingTaskForm = false
    @State private var showingSchedulingModeAlert = false

    private var canModify: Bool {
        guard let user = dataController.currentUser else { return false }
        return user.role == .admin || user.role == .officeCrew
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project-Based button (for switching back) - only shown when callback provided
            if canModify, let onSwitch = onSwitchToProjectBased {
                HStack {
                    Spacer()

                    Button(action: {
                        onSwitch()
                    }) {
                        Text("Project-Based")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()
                    .background(OPSStyle.Colors.cardBorder)
            }

            // Task content
            if project.tasks.isEmpty {
                // Empty state with create button
                Button(action: {
                    showingTaskForm = true
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: OPSStyle.Icons.task)
                            .font(.system(size: 36))
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Text("NO TASKS - CREATE ONE")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
                .padding(.horizontal, 16)
            } else {
                // Task cards in single container (matching ProjectDetailsView card style)
                VStack(spacing: 8) {
                    ForEach(project.tasks.sorted { $0.displayOrder < $1.displayOrder }) { task in
                        TaskRow(
                            task: task,
                            isFirst: task.id == project.tasks.sorted { $0.displayOrder < $1.displayOrder }.first?.id,
                            isLast: task.id == project.tasks.sorted { $0.displayOrder < $1.displayOrder }.last?.id,
                            onTap: {
                                selectedTask = task
                            }
                        )
                        .environmentObject(dataController)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                // Animation removed - was causing parent sheet to dismiss when tasks were deleted
            }
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailsView(task: task, project: project)
                .environmentObject(dataController)
                .environmentObject(appState)
                .environment(\.modelContext, dataController.modelContext!)
        }
        .sheet(isPresented: $showingTaskForm) {
            TaskFormSheet(mode: .create, preselectedProjectId: project.id) { _ in }
                .environmentObject(dataController)
        }
        .alert("Switch to Task-Based Scheduling?", isPresented: $showingSchedulingModeAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Continue") {
                showingTaskForm = true
            }
        } message: {
            Text("By adding tasks, this project will switch to task-based scheduling. Project dates will be determined by individual task schedules.")
        }
    }
}

// Individual task row using reusable TaskLineItem component
struct TaskRow: View {
    let task: ProjectTask
    let isFirst: Bool
    let isLast: Bool
    let onTap: () -> Void
    @EnvironmentObject private var dataController: DataController
    @Query private var users: [User]
    @State private var showingActions = false
    @State private var showingStatusPicker = false
    @State private var showingTeamPicker = false
    @State private var showingScheduler = false
    @State private var showingDeleteConfirmation = false

    private var canModify: Bool {
        guard let user = dataController.currentUser else { return false }
        return user.role == .admin || user.role == .officeCrew
    }

    private var teamMemberCount: Int {
        if !task.teamMembers.isEmpty {
            return task.teamMembers.count
        }
        return task.getTeamMemberIds().count
    }

    var body: some View {
        TaskLineItem(
            title: task.taskType?.display ?? "Task",
            color: Color(hex: task.taskColor) ?? OPSStyle.Colors.primaryAccent,
            status: task.status,
            startDate: task.calendarEvent?.startDate,
            teamMemberCount: teamMemberCount,
            onTap: onTap,
            onDelete: canModify ? { showingDeleteConfirmation = true } : nil,
            onLongPress: { showingActions = true }
        )
        .confirmationDialog("Task Actions", isPresented: $showingActions, titleVisibility: .hidden) {
            Button("Change Status") {
                showingStatusPicker = true
            }
            if canModify {
                Button("Change Team") {
                    showingTeamPicker = true
                }
                Button("Reschedule") {
                    showingScheduler = true
                }
                Button("Delete", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingStatusPicker) {
            TaskStatusChangeSheet(task: task)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingTeamPicker) {
            TaskTeamChangeSheet(task: task)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingScheduler) {
            CalendarSchedulerSheet(
                isPresented: $showingScheduler,
                itemType: .task(task),
                currentStartDate: task.calendarEvent?.startDate,
                currentEndDate: task.calendarEvent?.endDate,
                onScheduleUpdate: { startDate, endDate in
                    print("[RESCHEDULE_TASK] 📅 Task rescheduled")
                    print("[RESCHEDULE_TASK] Task: \(task.displayTitle)")
                    print("[RESCHEDULE_TASK] New dates: \(startDate) to \(endDate)")

                    if let calendarEvent = task.calendarEvent {
                        print("[RESCHEDULE_TASK] Updating existing calendar event: \(calendarEvent.id)")
                        calendarEvent.startDate = startDate
                        calendarEvent.endDate = endDate
                        calendarEvent.needsSync = true
                    } else {
                        print("[RESCHEDULE_TASK] Creating new calendar event for task")
                        Task {
                            await createCalendarEventForTask(task: task, startDate: startDate, endDate: endDate)
                        }
                    }
                    try? dataController.modelContext?.save()
                    print("[RESCHEDULE_TASK] ✅ Task saved to SwiftData")

                    // Update project dates (computed from tasks)
                    if let project = task.project {
                        print("[RESCHEDULE_TASK] 📅 Updating project dates after reschedule...")
                        print("[RESCHEDULE_TASK] Project: \(project.title)")

                        Task {
                            // Sync computed dates to Bubble
                            print("[RESCHEDULE_TASK] 🔄 Syncing updated project dates to Bubble...")
                            try? await dataController.apiService.updateProjectDates(
                                projectId: project.id,
                                startDate: project.computedStartDate,
                                endDate: project.computedEndDate
                            )
                            print("[RESCHEDULE_TASK] ✅ Project dates update complete")
                        }
                    } else {
                        print("[RESCHEDULE_TASK] ⚠️ No project found - skipping date update")
                    }
                }
            )
            .environmentObject(dataController)
        }
        .deleteConfirmation(
            isPresented: $showingDeleteConfirmation,
            itemName: "Task",
            message: "This will permanently delete this task. This action cannot be undone.",
            onConfirm: deleteTask
        )
    }

    private func deleteTask() {
        let taskName = task.displayTitle

        // Store IDs and project before deleting
        let taskId = task.id
        let calendarEventId = task.calendarEvent?.id
        let project = task.project

        // STEP 1: Delete from UI immediately (optimistic deletion)
        guard let modelContext = dataController.modelContext else { return }
        modelContext.delete(task)
        try? modelContext.save()
        print("[DELETE_TASK] ✅ Task deleted from local database (UI updated)")

        // STEP 2: Delete from Bubble in background
        Task {
            do {
                // Delete calendar event from Bubble if it exists
                if let eventId = calendarEventId {
                    print("[DELETE_TASK] 🗑️ Deleting calendar event from Bubble: \(eventId)")
                    try await dataController.apiService.deleteCalendarEvent(id: eventId)
                    print("[DELETE_TASK] ✅ Calendar event deleted from Bubble")
                }

                // Delete the task from Bubble
                print("[DELETE_TASK] 🗑️ Deleting task from Bubble: \(taskId)")
                try await dataController.apiService.deleteTask(id: taskId)
                print("[DELETE_TASK] ✅ Task deleted from Bubble")

                // Update project dates (computed from tasks)
                if let project = project {
                    print("[DELETE_TASK] 📅 Updating project dates after deletion...")
                    print("[DELETE_TASK] Project: \(project.title)")
                    print("[DELETE_TASK] Remaining tasks: \(project.tasks.count)")

                    // Sync computed dates to Bubble
                    print("[DELETE_TASK] 🔄 Syncing updated project dates to Bubble...")
                    try await dataController.apiService.updateProjectDates(
                        projectId: project.id,
                        startDate: project.computedStartDate,
                        endDate: project.computedEndDate
                    )
                    print("[DELETE_TASK] ✅ Project dates update complete")
                } else {
                    print("[DELETE_TASK] ⚠️ No project found - skipping date update")
                }

                // Schedule deletion notification
                await MainActor.run {
                    scheduleDeletionNotification(itemType: "TASK", itemName: taskName)
                }
            } catch {
                print("[DELETE_TASK] ❌ Error deleting task from Bubble: \(error)")
                // Task is already deleted from UI, but will reappear on next sync if Bubble deletion failed
                await MainActor.run {
                    let content = UNMutableNotificationContent()
                    content.title = "Delete Failed"
                    content.body = "Task deleted locally but failed to sync. It may reappear on next sync."
                    content.sound = .default

                    let request = UNNotificationRequest(
                        identifier: UUID().uuidString,
                        content: content,
                        trigger: nil
                    )

                    UNUserNotificationCenter.current().add(request)
                }
            }
        }
    }

    private func scheduleDeletionNotification(itemType: String, itemName: String) {
        let content = UNMutableNotificationContent()
        content.title = "OPS"
        content.body = "\(itemName) deleted"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NOTIFICATION] Error scheduling notification: \(error)")
            }
        }
    }

    private func createCalendarEventForTask(task: ProjectTask, startDate: Date, endDate: Date) async {
        print("[CREATE_CALENDAR_EVENT] Creating calendar event for task")

        guard let project = task.project else {
            print("[CREATE_CALENDAR_EVENT] ❌ No project associated with task")
            return
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let duration = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1

        let eventDTO = CalendarEventDTO(
            id: UUID().uuidString,
            color: task.taskColor,
            companyId: task.companyId,
            projectId: task.projectId,
            taskId: task.id,
            duration: Double(duration),
            endDate: dateFormatter.string(from: endDate),
            startDate: dateFormatter.string(from: startDate),
            teamMembers: task.getTeamMemberIds(),
            title: task.taskType?.display ?? "Task",
            createdDate: nil,
            modifiedDate: nil,
            deletedAt: nil
        )

        do {
            let createdEvent = try await dataController.apiService.createAndLinkCalendarEvent(eventDTO)

            await MainActor.run {
                if let calendarEvent = createdEvent.toModel() {
                    calendarEvent.needsSync = false
                    calendarEvent.lastSyncedAt = Date()
                    dataController.modelContext?.insert(calendarEvent)
                    task.calendarEvent = calendarEvent
                    try? dataController.modelContext?.save()
                    print("[CREATE_CALENDAR_EVENT] ✅ Calendar event created and linked")
                }
            }
        } catch {
            print("[CREATE_CALENDAR_EVENT] ❌ Failed to create calendar event: \(error)")
        }
    }
    
}
