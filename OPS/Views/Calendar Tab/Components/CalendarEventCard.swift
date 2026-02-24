//
//  CalendarEventCard.swift
//  OPS
//
//  Card for displaying calendar events with proper task/project information
//

import SwiftUI

struct CalendarEventCard: View {
    let task: ProjectTask
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

    init(task: ProjectTask, isFirst: Bool, isOngoing: Bool = false, onTap: @escaping () -> Void) {
        self.task = task
        self.isFirst = isFirst
        self.isOngoing = isOngoing
        self.onTap = onTap
    }

    // Get the associated project for client and address info
    private var associatedProject: Project? {
        return task.project
    }

    // Get the color for the status bar and task type
    private var displayColor: Color {
        if let color = Color(hex: task.effectiveColor) {
            return color
        }
        return task.swiftUIColor
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
    private var typeDisplay: String {
        if let taskType = task.taskType {
            return taskType.display.uppercased()
        }
        return ""
    }

    // Get the badge color
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
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                            .fill(badgeColor.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                            .stroke(badgeColor.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
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
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                            .fill(OPSStyle.Colors.subtleBackground)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                            .stroke(OPSStyle.Colors.pinDotNeutral, lineWidth: OPSStyle.Layout.Border.standard)
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

            // Completed overlay - grey out and show badge
            if task.status == .completed {
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
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .fill(OPSStyle.Colors.statusColor(for: .completed))
                        )
                        .padding(8)
                }
            }

            // Cancelled overlay - grey out and show badge
            if task.status == .cancelled {
                ZStack(alignment: .topTrailing) {
                    // Grey overlay
                    OPSStyle.Colors.modalOverlay
                        .cornerRadius(OPSStyle.Layout.cornerRadius)

                    // Cancelled badge
                    Text("CANCELLED")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .fill(OPSStyle.Colors.inactiveStatus)
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
            CalendarSchedulerSheet(
                isPresented: $showingReschedule,
                itemType: .task(task),
                currentStartDate: task.startDate,
                currentEndDate: task.endDate,
                onScheduleUpdate: { newStart, newEnd in
                    updateTaskSchedule(task: task, startDate: newStart, endDate: newEnd)
                }
            )
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showingStatusPicker) {
            TaskStatusChangeSheet(task: task)
                .environmentObject(dataController)
        }
    }
    
    // Use darker background color for card
    private var cardBackground: some View {
        OPSStyle.Colors.cardBackgroundDark
    }

    private func updateTaskSchedule(task: ProjectTask, startDate: Date, endDate: Date) {
        Task {
            do {
                try await dataController.updateTaskSchedule(task: task, startDate: startDate, endDate: endDate)
            } catch {
                print("Error updating task schedule: \(error)")
            }
        }
    }
}