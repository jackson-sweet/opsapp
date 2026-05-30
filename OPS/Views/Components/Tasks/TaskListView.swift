//
//  TaskListView.swift
//  OPS
//
//  Task list component for displaying project tasks
//

import SwiftUI
import SwiftData
import Supabase
import UserNotifications

struct TaskListView: View {
    let project: Project
    var onSwitchToProjectBased: (() -> Void)? = nil
    var onTaskSelected: ((ProjectTask) -> Void)? = nil  // Callback for task selection
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissionStore: PermissionStore
    @State private var showingTaskForm = false
    @State private var showingSchedulingModeAlert = false

    private var canModify: Bool {
        permissionStore.can("tasks.edit")
    }

    /// Active (non-deleted) tasks sorted by display order.
    private var activeTasks: [ProjectTask] {
        project.tasks
            .filter { $0.deletedAt == nil }
            .sorted { $0.displayOrder < $1.displayOrder }
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
            if activeTasks.isEmpty {
                // Empty state with create button
                Button(action: {
                    showingTaskForm = true
                }) {
                    VStack(spacing: 12) {
                        Image(OPSStyle.Icons.task)
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
                    ForEach(activeTasks) { task in
                        TaskRow(
                            task: task,
                            isFirst: task.id == activeTasks.first?.id,
                            isLast: task.id == activeTasks.last?.id,
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
    @EnvironmentObject private var permissionStore: PermissionStore
    @Query private var users: [User]
    @State private var showingActions = false
    @State private var showingStatusPicker = false
    @State private var showingTeamPicker = false
    @State private var showingScheduler = false
    @State private var showingDeleteConfirmation = false

    private var canModify: Bool {
        permissionStore.can("tasks.edit")
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
                            try? await dataController.updateProjectDates(
                                project: project,
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

        guard let modelContext = dataController.modelContext else { return }

        // STEP 1: Record the SyncOperation FIRST so the server learns about this deletion
        // even if the app is killed or goes offline after the local delete.
        dataController.syncEngine.recordOperation(
            entityType: .projectTask,
            entityId: taskId,
            operationType: "delete",
            changedFields: ["_deleted": true]
        )
        print("[DELETE_TASK] ✅ SyncOperation recorded for task: \(taskId)")

        // STEP 2: Soft-delete locally and update UI
        task.deletedAt = Date()
        task.needsSync = true
        try? modelContext.save()
        print("[DELETE_TASK] ✅ Task soft-deleted locally (UI updated)")

        // STEP 3: Update project dates in background
        Task {
            do {
                if let project = project {
                    print("[DELETE_TASK] 📅 Updating project dates after deletion...")
                    print("[DELETE_TASK] Project: \(project.title)")
                    print("[DELETE_TASK] Remaining tasks: \(project.tasks.count)")

                    try await dataController.updateProjectDates(
                        project: project,
                        startDate: project.computedStartDate,
                        endDate: project.computedEndDate
                    )
                    print("[DELETE_TASK] ✅ Project dates update complete")
                } else {
                    print("[DELETE_TASK] ⚠️ No project found - skipping date update")
                }

                await MainActor.run {
                    scheduleDeletionNotification(itemType: "TASK", itemName: taskName)
                }
            } catch {
                print("[DELETE_TASK] ❌ Error updating project dates after deletion: \(error)")
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
