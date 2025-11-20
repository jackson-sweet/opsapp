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
        VStack(alignment: .leading, spacing: 12) {
            // Section heading outside the card (matching ProjectDetailsView style)
            HStack {
                Image(systemName: "hammer.circle")
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("TASKS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                // Task count badge
                if !project.tasks.isEmpty {
                    Text("\(project.tasks.count)")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.black)
                        )
                }

                // Project-Based button (for switching back)
                if canModify, let onSwitch = onSwitchToProjectBased {
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

                // ADD button
                if canModify {
                    Button(action: {
                        // Task-only scheduling migration: All projects use task-based scheduling now
                        showingTaskForm = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(OPSStyle.Typography.smallCaption)
                            Text("Add")
                                .font(OPSStyle.Typography.smallCaption)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal)
            
            // Task content - always show
            if project.tasks.isEmpty {
                // Empty state with create button
                Button(action: {
                    // Task-only scheduling migration: All projects use task-based scheduling now
                    showingTaskForm = true
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: "hammer.circle")
                            .font(.system(size: 36))
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Text("NO TASKS - CREATE ONE")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                )
                .padding(.horizontal)
            } else {
                // Task cards in single container (matching ProjectDetailsView card style)
                VStack(spacing: 1) {
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
                // Animation removed - was causing parent sheet to dismiss when tasks were deleted
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                )
                .padding(.horizontal)
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

// Individual task row (matching ProjectDetailsView info row style)
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
    @State private var isLongPressing = false
    @State private var hasTriggeredHaptic = false

    private var canModify: Bool {
        guard let user = dataController.currentUser else { return false }
        return user.role == .admin || user.role == .officeCrew
    }

    private var displayTeamMembers: [User] {
        if !task.teamMembers.isEmpty {
            return Array(task.teamMembers)
        }

        let teamMemberIds = task.getTeamMemberIds()
        guard !teamMemberIds.isEmpty else { return [] }

        return teamMemberIds.compactMap { id in
            users.first(where: { $0.id == id })
        }
    }

    var body: some View {
        HStack(spacing: 12) {
                // Task type icon with color
                ZStack {
                    Circle()
                        .fill(Color(hex: task.taskColor) ?? OPSStyle.Colors.primaryAccent)
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: task.taskType?.icon ?? "hammer.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                .frame(width: 24)
                
                // Task info
                VStack(alignment: .leading, spacing: 4) {
                    Text((task.taskType?.display ?? "Task").uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    HStack(spacing: 6) {
                        // Status indicator
                        Circle()
                            .fill(statusColor(for: task.status))
                            .frame(width: 6, height: 6)
                        
                        Text(task.status.displayName)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    
                    // Date if available
                    if let calendarEvent = task.calendarEvent, let start = calendarEvent.startDate, let end = calendarEvent.endDate {
                        Text(formatDateRange(start, end))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    } else if let scheduledDate = task.scheduledDate {
                        Text(formatDate(scheduledDate))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                
                Spacer()

                // Team member avatars (if any)
                if !displayTeamMembers.isEmpty {
                    HStack(spacing: -8) {
                        ForEach(displayTeamMembers.prefix(3)) { member in
                            UserAvatar(user: member, size: 24)
                                .overlay(
                                    Circle()
                                        .stroke(OPSStyle.Colors.cardBackgroundDark, lineWidth: 2)
                                )
                        }

                        if displayTeamMembers.count > 3 {
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.cardBackground)
                                    .frame(width: 24, height: 24)

                                Text("+\(displayTeamMembers.count - 3)")
                                    .font(.system(size: 10))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .overlay(
                                Circle()
                                    .stroke(OPSStyle.Colors.cardBackgroundDark, lineWidth: 2)
                            )
                        }
                    }
                }
                
                // Navigation chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark)
            .contentShape(Rectangle())
            .scaleEffect(isLongPressing ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isLongPressing)
            .onTapGesture {
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.3) {
            showingActions = true
        } onPressingChanged: { pressing in
            if pressing {
                isLongPressing = true
                hasTriggeredHaptic = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if isLongPressing && !hasTriggeredHaptic {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        hasTriggeredHaptic = true
                    }
                }
            } else {
                isLongPressing = false
                hasTriggeredHaptic = false
            }
        }
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
        .alert("Delete Task?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteTask()
            }
        } message: {
            Text("This will permanently delete this task. This action cannot be undone.")
        }
        .onAppear {
            logTaskRowTeamMemberData()
        }
    }

    private func deleteTask() {
        let taskName = task.displayTitle

        Task {
            do {
                // Store IDs and project before deleting
                let taskId = task.id
                let calendarEventId = task.calendarEvent?.id
                let project = task.project

                await MainActor.run {
                    guard let modelContext = dataController.modelContext else { return }

                    // Delete task from local database (cascade will handle calendar event)
                    // Wrap in transaction with animations disabled to prevent parent sheet from dismissing
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        modelContext.delete(task)
                        try? modelContext.save()
                    }
                }

                // Delete calendar event from Bubble if it exists
                if let eventId = calendarEventId {
                    print("[DELETE_TASK] 🗑️ Deleting calendar event: \(eventId)")
                    try await dataController.apiService.deleteCalendarEvent(id: eventId)
                    print("[DELETE_TASK] ✅ Calendar event deleted from Bubble")
                }

                // Then delete the task from Bubble
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
                print("[DELETE_TASK] ❌ Error deleting task: \(error)")
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
    
    // MARK: - Debug Logging
    
    private func logTaskRowTeamMemberData() {
        
        // Log team member data for this row
        let teamMemberIds = task.getTeamMemberIds()
        
        // Log what's being displayed in the UI
        if !task.teamMembers.isEmpty {
            for (index, member) in task.teamMembers.prefix(3).enumerated() {
            }
            if task.teamMembers.count > 3 {
            }
        } else {
        }
        
    }
    
    private func statusColor(for status: TaskStatus) -> Color {
        switch status {
        case .booked:
            return OPSStyle.Colors.tertiaryText
        case .inProgress:
            return OPSStyle.Colors.warningStatus
        case .completed:
            return OPSStyle.Colors.successStatus
        case .cancelled:
            return OPSStyle.Colors.errorStatus
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func formatDateRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return formatter.string(from: start)
        } else {
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        }
    }
}
