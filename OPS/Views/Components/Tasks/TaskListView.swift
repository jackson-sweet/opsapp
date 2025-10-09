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
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @State private var selectedTask: ProjectTask? = nil
    @State private var showingTaskForm = false
    @State private var showingSchedulingModeAlert = false
    
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

                // ADD button
                Button(action: {
                    if !project.usesTaskBasedScheduling {
                        showingSchedulingModeAlert = true
                    } else {
                        showingTaskForm = true
                    }
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
            .padding(.horizontal)
            
            // Task content - always show
            if project.tasks.isEmpty {
                // Empty state with create button
                Button(action: {
                    if !project.usesTaskBasedScheduling {
                        showingSchedulingModeAlert = true
                    } else {
                        showingTaskForm = true
                    }
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
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
                    }
                }
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
    @State private var showingActions = false
    @State private var showingStatusPicker = false
    @State private var showingTeamPicker = false
    @State private var showingScheduler = false
    @State private var showingDeleteConfirmation = false
    @State private var isLongPressing = false
    @State private var hasTriggeredHaptic = false

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
                    if let calendarEvent = task.calendarEvent {
                        Text(formatDateRange(calendarEvent.startDate, calendarEvent.endDate))
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
                if !task.teamMembers.isEmpty {
                    HStack(spacing: -8) {
                        ForEach(task.teamMembers.prefix(3)) { member in
                            UserAvatar(user: member, size: 24)
                                .overlay(
                                    Circle()
                                        .stroke(OPSStyle.Colors.cardBackgroundDark, lineWidth: 2)
                                )
                        }
                        
                        if task.teamMembers.count > 3 {
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.cardBackground)
                                    .frame(width: 24, height: 24)
                                
                                Text("+\(task.teamMembers.count - 3)")
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
            Button("Change Team") {
                showingTeamPicker = true
            }
            Button("Reschedule") {
                showingScheduler = true
            }
            Button("Delete", role: .destructive) {
                showingDeleteConfirmation = true
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
                    if let calendarEvent = task.calendarEvent {
                        calendarEvent.startDate = startDate
                        calendarEvent.endDate = endDate
                        calendarEvent.needsSync = true
                    }
                    try? dataController.modelContext?.save()
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
        Task {
            do {
                try await dataController.apiService.deleteTask(id: task.id)
                await MainActor.run {
                    guard let modelContext = dataController.modelContext else { return }
                    modelContext.delete(task)
                    try? modelContext.save()
                }
            } catch {
                print("[DELETE_TASK] ❌ Error deleting task: \(error)")
            }
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
        case .scheduled:
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