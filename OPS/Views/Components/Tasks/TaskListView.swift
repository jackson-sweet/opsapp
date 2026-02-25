//
//  TaskListView.swift
//  OPS
//
//  Task list component for displaying project tasks
//

import SwiftUI
import SwiftData
import Supabase

struct TaskListView: View {
    let project: Project
    var onSwitchToProjectBased: (() -> Void)? = nil
    var onTaskSelected: ((ProjectTask) -> Void)? = nil  // Callback for task selection
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
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
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.standard)
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
                            .font(.system(size: OPSStyle.Layout.IconSize.xxl))
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
                                // Use callback if provided, otherwise no action
                                onTaskSelected?(task)
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
            startDate: task.startDate,
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
                currentStartDate: task.startDate,
                currentEndDate: task.endDate,
                onScheduleUpdate: { startDate, endDate in
                    print("[RESCHEDULE_TASK] 📅 Task rescheduled")
                    print("[RESCHEDULE_TASK] Task: \(task.displayTitle)")
                    print("[RESCHEDULE_TASK] New dates: \(startDate) to \(endDate)")

                    // Set dates directly on task
                    task.startDate = startDate
                    task.endDate = endDate
                    let daysDiff = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
                    task.duration = daysDiff + 1
                    task.needsSync = true
                    try? dataController.modelContext?.save()
                    print("[RESCHEDULE_TASK] ✅ Task saved to SwiftData")

                    // Update project dates (computed from tasks)
                    if let project = task.project {
                        print("[RESCHEDULE_TASK] 📅 Updating project dates after reschedule...")
                        print("[RESCHEDULE_TASK] Project: \(project.title)")

                        Task {
                            // Sync computed dates to Supabase
                            print("[RESCHEDULE_TASK] 🔄 Syncing updated project dates to Supabase...")
                            try? await dataController.syncManager.updateProjectDates(
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
        let project = task.project

        // STEP 1: Delete from UI immediately (optimistic deletion)
        guard let modelContext = dataController.modelContext else { return }
        modelContext.delete(task)
        try? modelContext.save()
        print("[DELETE_TASK] ✅ Task deleted from local database (UI updated)")

        // STEP 2: Delete from Supabase in background
        Task {
            do {
                // Delete the task from Supabase
                print("[DELETE_TASK] 🗑️ Deleting task from Supabase: \(taskId)")
                try await dataController.syncManager.deleteTask(taskId: taskId)
                print("[DELETE_TASK] ✅ Task deleted from Supabase")

                // Update project dates (computed from tasks)
                if let project = project {
                    print("[DELETE_TASK] 📅 Updating project dates after deletion...")
                    print("[DELETE_TASK] Project: \(project.title)")
                    print("[DELETE_TASK] Remaining tasks: \(project.tasks.count)")

                    // Sync computed dates to Supabase
                    print("[DELETE_TASK] 🔄 Syncing updated project dates to Supabase...")
                    try await dataController.syncManager.updateProjectDates(
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
                print("[DELETE_TASK] ❌ Error deleting task from Supabase: \(error)")
                // Task is already deleted from UI, but will reappear on next sync if deletion failed
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

}
