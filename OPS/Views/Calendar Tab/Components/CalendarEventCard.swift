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
    // Task-only scheduling migration: All events are task events
    private var associatedProject: Project? {
        if let task = event.task {
            return task.project
        }
        return event.project
    }
    
    // Get the color for the status bar and task type
    // Task-only scheduling migration: Use task color
    private var displayColor: Color {
        if let task = event.task,
           let color = Color(hex: task.effectiveColor) {
            return color
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
    
    // Get the display text for task type
    // Task-only scheduling migration: All events show task type
    private var typeDisplay: String {
        if let task = event.task, let taskType = task.taskType {
            return taskType.display.uppercased()
        }
        return ""
    }

    // Get the badge color
    // Task-only scheduling migration: Use display color for all events
    private var badgeColor: Color {
        return displayColor
    }
    
    var body: some View {
        ZStack {
            // Card container
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

            // Completed overlay - grey out and show badge
            // Task-only scheduling migration: Only check task completion
            if event.task?.status == .completed {
                ZStack(alignment: .topTrailing) {
                    // Grey overlay
                    OPSStyle.Colors.modalOverlay
                        .cornerRadius(OPSStyle.Layout.cornerRadius)

                    // Completed badge
                    Text("COMPLETED")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(OPSStyle.Colors.statusColor(for: .completed))
                        )
                        .padding(8)
                }
            }
        }
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
            // Task-only scheduling migration: All events are task events
            if let task = event.task {
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
            }
        }
        .sheet(isPresented: $showingStatusPicker) {
            // Task-only scheduling migration: All events are task events
            if let task = event.task {
                TaskStatusChangeSheet(task: task)
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

        Task {
            do {
                try await dataController.updateCalendarEvent(event: calendarEvent, startDate: startDate, endDate: endDate)
            } catch {
                print("Error updating task schedule: \(error)")
            }
        }
    }

    private func updateProjectSchedule(project: Project, startDate: Date, endDate: Date) {
        Task {
            do {
                try await dataController.rescheduleProject(
                    project,
                    startDate: startDate,
                    endDate: endDate,
                    calendarEvent: event
                )
                print("[CALENDAR_EVENT_CARD] ✅ Project rescheduled successfully")
            } catch {
                print("[CALENDAR_EVENT_CARD] ❌ Error rescheduling project: \(error)")
            }
        }
    }
}