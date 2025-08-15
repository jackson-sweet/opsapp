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
    @State private var expandedTaskId: String? = nil
    
    // Group tasks by status
    private var tasksByStatus: [TaskStatus: [ProjectTask]] {
        Dictionary(grouping: project.tasks, by: { $0.status })
    }
    
    private var sortedStatuses: [TaskStatus] {
        [.scheduled, .inProgress, .completed, .cancelled].filter { status in
            tasksByStatus[status] != nil
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with add button
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "hammer.circle")
                        .font(.system(size: 20))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Text("TASKS")
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Task count badge
                Text("\(project.tasks.count)")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(OPSStyle.Colors.cardBackgroundDark)
                    )
                
            }
            .padding(.horizontal)
            
            if project.tasks.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "hammer.circle")
                        .font(.system(size: 48))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    
                    Text("No tasks assigned")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text("Create tasks in the web app")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    
                    Text("Defaulting to project-based scheduling")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .padding(.horizontal)
            } else {
                // Task list grouped by status
                VStack(spacing: 16) {
                    ForEach(sortedStatuses, id: \.self) { status in
                        if let tasks = tasksByStatus[status] {
                            TaskStatusGroup(
                                status: status,
                                tasks: tasks,
                                expandedTaskId: $expandedTaskId,
                                onTaskTap: handleTaskTap,
                                onStatusChange: handleStatusChange
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func canEditTasks() -> Bool {
        // Check user permissions
        guard let currentUser = dataController.currentUser else { return false }
        return currentUser.role != .fieldCrew
    }
    
    private func handleTaskTap(_ task: ProjectTask) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if expandedTaskId == task.id {
                expandedTaskId = nil
            } else {
                expandedTaskId = task.id
            }
        }
    }
    
    private func handleStatusChange(_ task: ProjectTask, newStatus: TaskStatus) {
        // Update task status
        task.status = newStatus
        
        // Mark for sync
        task.needsSync = true
        project.needsSync = true
        
        // Save changes
        try? dataController.modelContext?.save()
    }
}

// Task status group component
struct TaskStatusGroup: View {
    let status: TaskStatus
    let tasks: [ProjectTask]
    @Binding var expandedTaskId: String?
    let onTaskTap: (ProjectTask) -> Void
    let onStatusChange: (ProjectTask, TaskStatus) -> Void
    @EnvironmentObject private var dataController: DataController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status header
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                Text(status.displayName.uppercased())
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text("(\(tasks.count))")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            
            // Task cards
            VStack(spacing: 8) {
                ForEach(tasks.sorted { $0.displayOrder < $1.displayOrder }) { task in
                    TaskCard(
                        task: task,
                        isExpanded: expandedTaskId == task.id,
                        onTap: { onTaskTap(task) },
                        onStatusChange: { newStatus in
                            onStatusChange(task, newStatus)
                        }
                    )
                    .environmentObject(dataController)
                }
            }
        }
    }
    
    private var statusColor: Color {
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
}

// Individual task card
struct TaskCard: View {
    let task: ProjectTask
    let isExpanded: Bool
    let onTap: () -> Void
    let onStatusChange: (TaskStatus) -> Void
    @State private var editingNotes = false
    @State private var editedNotes: String = ""
    @EnvironmentObject private var dataController: DataController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main card content (always visible)
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Task type icon with color
                    ZStack {
                        Circle()
                            .fill(Color(hex: task.taskColor) ?? OPSStyle.Colors.primaryAccent)
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: task.taskType?.icon ?? "hammer.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                    
                    // Task info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.taskType?.display ?? "Task")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(.white)
                        
                        if let calendarEvent = task.calendarEvent {
                            HStack(spacing: 8) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 12))
                                Text(formatDateRange(calendarEvent.startDate, calendarEvent.endDate))
                                    .font(OPSStyle.Typography.caption)
                            }
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                    
                    Spacer()
                    
                    // Progress indicator
                    TaskProgressIndicator(status: task.status)
                    
                    // Expand chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackground)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .background(OPSStyle.Colors.tertiaryText.opacity(0.3))
                    
                    // Team members
                    if !task.teamMembers.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TEAM MEMBERS")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(task.teamMembers) { member in
                                        TeamMemberPill(member: member)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Task notes (editable)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("NOTES")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            Spacer()
                            
                            Button(action: {
                                editedNotes = task.taskNotes ?? ""
                                editingNotes.toggle()
                            }) {
                                Image(systemName: editingNotes ? "checkmark.circle" : "pencil")
                                    .font(.system(size: 16))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                        }
                        
                        if editingNotes {
                            TextEditor(text: $editedNotes)
                                .frame(minHeight: 80)
                                .padding(8)
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(8)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            
                            HStack {
                                Spacer()
                                
                                Button("Cancel") {
                                    editingNotes = false
                                    editedNotes = task.taskNotes ?? ""
                                }
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                Button("Save") {
                                    saveTaskNotes()
                                }
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            .font(OPSStyle.Typography.bodyBold)
                        } else {
                            Text(task.taskNotes?.isEmpty == false ? task.taskNotes! : "No notes added")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(task.taskNotes?.isEmpty == false ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                        }
                    }
                    
                    // Quick actions
                    HStack(spacing: 12) {
                        if task.status == .scheduled {
                            Button {
                                onStatusChange(.inProgress)
                            } label: {
                                Label("Start", systemImage: "play.fill")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.warningStatus)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(OPSStyle.Colors.warningStatus, lineWidth: 1)
                            )
                        }
                        
                        if task.status == .inProgress {
                            Button {
                                onStatusChange(.completed)
                            } label: {
                                Label("Complete", systemImage: "checkmark.circle.fill")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.successStatus)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(OPSStyle.Colors.successStatus, lineWidth: 1)
                            )
                        }
                        
                        Spacer()
                    }
                }
                .padding()
                .background(OPSStyle.Colors.cardBackground)
            }
        }
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }
    
    private func saveTaskNotes() {
        // Update the task notes
        task.taskNotes = editedNotes
        task.needsSync = true
        
        // Save locally
        do {
            try dataController.modelContext?.save()
            editingNotes = false
            
            // Sync to backend
            Task {
                if let syncManager = dataController.syncManager {
                    // If we add a specific method for task notes, use it here
                    // For now, mark for sync and it will sync on next sync cycle
                    print("Task notes updated and marked for sync")
                }
            }
        } catch {
            print("Error saving task notes: \(error)")
        }
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

// Task progress indicator
struct TaskProgressIndicator: View {
    let status: TaskStatus
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(OPSStyle.Colors.tertiaryText.opacity(0.3), lineWidth: 2)
                .frame(width: 24, height: 24)
            
            if status == .inProgress {
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(OPSStyle.Colors.warningStatus, lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(-90))
            } else if status == .completed {
                Circle()
                    .fill(OPSStyle.Colors.successStatus)
                    .frame(width: 24, height: 24)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}

// Team member pill
struct TeamMemberPill: View {
    let member: User
    
    var body: some View {
        HStack(spacing: 6) {
            // Use UserAvatar component
            UserAvatar(user: member, size: 20)
            
            Text(member.firstName)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(12)
    }
}

#Preview {
    TaskListView(project: Project(
        id: "1",
        title: "Sample Project",
        status: .inProgress
    ))
    .environmentObject(DataController())
    .preferredColorScheme(.dark)
}