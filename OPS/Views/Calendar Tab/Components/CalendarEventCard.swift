//
//  CalendarEventCard.swift
//  OPS
//
//  Card for displaying calendar events with proper task/project information
//

import SwiftUI

struct CalendarEventCard: View {
    let event: CalendarEvent
    let isFirst: Bool
    let isOngoing: Bool
    let onTap: () -> Void
    @EnvironmentObject private var dataController: DataController
    @State private var showingReschedule = false
    @State private var showingQuickActions = false
    @State private var showingStatusPicker = false

    private var canModify: Bool {
        guard let user = dataController.currentUser else { return false }
        return user.role == .admin || user.role == .officeCrew
    }

    init(event: CalendarEvent, isFirst: Bool, isOngoing: Bool = false, onTap: @escaping () -> Void) {
        self.event = event
        self.isFirst = isFirst
        self.isOngoing = isOngoing
        self.onTap = onTap
    }
    
    // Get the associated project for client and address info
    private var associatedProject: Project? {
        // For task events, get the task's project
        if event.type == .task, let task = event.task {
            return task.project
        }
        // For project events, use the direct project
        return event.project
    }
    
    // Get the color for the status bar and task type
    private var displayColor: Color {
        // For project events, use the company's defaultProjectColor
        if event.type == .project {
            if let project = associatedProject,
               let company = dataController.getCompany(id: project.companyId),
               let defaultColor = Color(hex: company.defaultProjectColor) {
                return defaultColor
            }
        }
        
        // For task events, use the task color or event color
        if event.type == .task {
            if let task = event.task,
               let color = Color(hex: task.effectiveColor) {
                return color
            }
        }
        
        // Fallback to event color
        return event.swiftUIColor
    }
    
    // Format the address to show only: street number, street name, municipality
    private var formattedAddress: String {
        guard let project = associatedProject else { return "" }

        guard let address = project.address else { return "No address" }
        // Split address by comma to get components
        let components = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        if components.count >= 2 {
            // Typically: "123 Main St, City, State ZIP"
            // We want: "123 Main St, City"
            return "\(components[0]), \(components[1])"
        } else if components.count == 1 {
            // If no comma, just return the first part
            return components[0]
        }

        return address
    }
    
    // Get the display text for task type or "PROJECT"
    private var typeDisplay: String {
        if event.type == .task, let task = event.task, let taskType = task.taskType {
            return taskType.display.uppercased()
        } else if event.type == .project {
            // Check if this is a task-based project
            if let project = associatedProject, project.usesTaskBasedScheduling {
                let taskCount = project.tasks.count
                return taskCount == 1 ? "1 TASK" : "\(taskCount) TASKS"
            }
            return "PROJECT"
        }
        return ""
    }

    // Get the badge color based on project type
    private var badgeColor: Color {
        if event.type == .project,
           let project = associatedProject,
           project.usesTaskBasedScheduling {
            // Use secondary accent for task-based projects
            return OPSStyle.Colors.secondaryAccent
        }
        // Use display color for regular projects and tasks
        return displayColor
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left status bar - color coded by task type or project status
            Rectangle()
                .fill(displayColor)
                .frame(width: 4)
            
            // Content area with badges overlaid
            ZStack(alignment: .topLeading) {
                // Main content - fills available space
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Show project name as the main title
                        if let project = associatedProject {
                            Text(project.title)
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .lineLimit(1)
                                .textCase(.uppercase)
                            
                            // Show client name as subtitle for both tasks and projects
                            Text(project.effectiveClientName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .lineLimit(1)
                            
                            // Formatted address (street number, street name, municipality)
                            Text(formattedAddress)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Invisible spacer to reserve space for badges
                    Color.clear
                        .frame(width: 80) // Reserve space for badges
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                
                // Task type or "PROJECT" badge in top right corner
                VStack {
                    HStack {
                        Spacer()
                        if !typeDisplay.isEmpty {
                            Text(typeDisplay)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(badgeColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(badgeColor.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(badgeColor.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.trailing, 16)
                
                // Ongoing badge in bottom right corner
                if isOngoing {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("ONGOING")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.bottom, 16)
                    .padding(.trailing, 16)
                }
            }
        }
        .background(cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .contentShape(Rectangle()) // Make entire card tappable
        .shadow(color: Color.black, radius: 2, x: 0, y: 1)
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            showingQuickActions = true
        }
        .confirmationDialog("Quick Actions", isPresented: $showingQuickActions, titleVisibility: .hidden) {
            if canModify {
                Button("Reschedule") {
                    showingReschedule = true
                }
            } else {
                Button("Update Status") {
                    showingStatusPicker = true
                }
            }

            Button("Cancel", role: .cancel) {}
        }
        .padding(.vertical, 4)
        .padding(.horizontal)
        .sheet(isPresented: $showingReschedule) {
            if event.type == .task, let task = event.task {
                CalendarSchedulerSheet(
                    isPresented: $showingReschedule,
                    itemType: .task(task),
                    currentStartDate: event.startDate,
                    currentEndDate: event.endDate,
                    onScheduleUpdate: { newStart, newEnd in
                        updateTaskSchedule(task: task, startDate: newStart, endDate: newEnd)
                    }
                )
                .environmentObject(dataController)
            } else if event.type == .project, let project = associatedProject {
                CalendarSchedulerSheet(
                    isPresented: $showingReschedule,
                    itemType: .project(project),
                    currentStartDate: event.startDate,
                    currentEndDate: event.endDate,
                    onScheduleUpdate: { newStart, newEnd in
                        updateProjectSchedule(project: project, startDate: newStart, endDate: newEnd)
                    }
                )
                .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingStatusPicker) {
            if event.type == .task, let task = event.task {
                TaskStatusChangeSheet(task: task)
                    .environmentObject(dataController)
            } else if event.type == .project, let project = associatedProject {
                ProjectStatusChangeSheet(project: project)
                    .environmentObject(dataController)
            }
        }
    }
    
    // Use darker background color for card
    private var cardBackground: some View {
        OPSStyle.Colors.cardBackgroundDark
    }

    private func updateTaskSchedule(task: ProjectTask, startDate: Date, endDate: Date) {
        guard let calendarEvent = task.calendarEvent else { return }

        calendarEvent.startDate = startDate
        calendarEvent.endDate = endDate
        calendarEvent.needsSync = true

        do {
            try dataController.modelContext?.save()
        } catch {
            print("Error updating task schedule: \(error)")
        }
    }

    private func updateProjectSchedule(project: Project, startDate: Date, endDate: Date) {
        event.startDate = startDate
        event.endDate = endDate
        event.needsSync = true

        project.startDate = startDate
        project.endDate = endDate
        project.needsSync = true

        do {
            try dataController.modelContext?.save()
        } catch {
            print("Error updating project schedule: \(error)")
        }
    }
}