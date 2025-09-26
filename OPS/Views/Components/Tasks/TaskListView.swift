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
            }
            .padding(.horizontal)
            
            // Task content
            if project.tasks.isEmpty {
                // Empty state matching ProjectDetailsView style
                VStack(spacing: 12) {
                    Image(systemName: "hammer.circle")
                        .font(.system(size: 36))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text("No tasks assigned")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text("Create tasks in the web app")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
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
    }
}

// Individual task row (matching ProjectDetailsView info row style)
struct TaskRow: View {
    let task: ProjectTask
    let isFirst: Bool
    let isLast: Bool
    let onTap: () -> Void
    @EnvironmentObject private var dataController: DataController
    
    var body: some View {
        Button(action: onTap) {
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
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            logTaskRowTeamMemberData()
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