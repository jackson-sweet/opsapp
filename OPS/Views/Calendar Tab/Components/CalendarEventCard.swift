//
//  CalendarEventCard.swift
//  OPS
//
//  Card for displaying calendar events with proper task/project information
//

import SwiftUI

enum DayPosition { case start, middle, end, single }

struct CalendarEventCard: View {
    let task: ProjectTask
    let isFirst: Bool
    let isOngoing: Bool
    let dayPosition: DayPosition
    let showLabels: Bool
    let onTap: () -> Void
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @State private var showingReschedule = false
    @State private var showingQuickActions = false
    @State private var showingStatusPicker = false

    private var canModify: Bool {
        permissionStore.can("calendar.edit")
    }

    init(task: ProjectTask, isFirst: Bool, isOngoing: Bool = false,
         dayPosition: DayPosition = .single, showLabels: Bool = true,
         onTap: @escaping () -> Void) {
        self.task = task
        self.isFirst = isFirst
        self.isOngoing = isOngoing
        self.dayPosition = dayPosition
        self.showLabels = showLabels
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
        let components = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        if components.count >= 2 {
            return "\(components[0]), \(components[1])"
        } else if components.count == 1 {
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

    // MARK: - Multi-day bleed logic

    private var isMultiDay: Bool { dayPosition != .single }
    private var bleedsRight: Bool { dayPosition == .start || dayPosition == .middle }
    private var bleedsLeft: Bool { dayPosition == .end || dayPosition == .middle }

    /// Rounded corners depend on which edges connect to adjacent days
    private var visibleCorners: UIRectCorner {
        switch dayPosition {
        case .single: return .allCorners
        case .start:  return [.topLeft, .bottomLeft]
        case .end:    return [.topRight, .bottomRight]
        case .middle: return []
        }
    }

    var body: some View {
        GeometryReader { geo in
            let rightBleed: CGFloat = bleedsRight ? 32 : 0
            let leftBleed: CGFloat = bleedsLeft ? 32 : 0
            let totalWidth = geo.size.width + rightBleed + leftBleed

            ZStack(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    // Left color stripe — only on first day of event and single-day
                    if !bleedsLeft && dayPosition != .middle {
                        Rectangle()
                            .fill(displayColor)
                            .frame(width: 4)
                    }

                    // Content — opacity controlled by showLabels
                    // When bleedsLeft, add extra leading padding to compensate for the
                    // leftward offset (32pt) and the missing left color stripe (4pt)
                    VStack(alignment: .leading, spacing: 5) {
                        if let project = associatedProject {
                            Text(project.title)
                                .font(OPSStyle.Typography.bodyEmphasis)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .textCase(.uppercase)
                                .lineLimit(1)

                            Text(project.effectiveClientName)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .lineLimit(1)

                            Text(formattedAddress)
                                .font(OPSStyle.Typography.microLabel)
                                .foregroundColor(OPSStyle.Colors.primaryText.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, bleedsLeft ? (leftBleed + 4 + 14 + 20) : 14)
                    .padding(.trailing, 14)
                    .padding(.vertical, 14)
                    .opacity(showLabels ? 1 : 0)

                }
                .frame(width: totalWidth, height: 64)
                .background(OPSStyle.Colors.cardBackgroundDark)
                // Top colored stripe for all multi-day events
                .overlay(alignment: .top) {
                    if isMultiDay {
                        Rectangle()
                            .fill(displayColor)
                            .frame(height: 2)
                    }
                }
                .clipShape(
                    OPSRoundedCornerShape(radius: 2, corners: visibleCorners)
                )
                .overlay(
                    OPSCardBorder(radius: 2, bleedsRight: bleedsRight, bleedsLeft: bleedsLeft)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
                // Right-edge gradient fade for bleed
                .overlay(
                    Group {
                        if bleedsRight {
                            HStack {
                                Spacer()
                                LinearGradient(
                                    colors: [.clear, OPSStyle.Colors.cardBackgroundDark],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 40)
                            }
                        }
                    }
                )
                // Left-edge gradient fade for bleed
                .overlay(
                    Group {
                        if bleedsLeft {
                            HStack {
                                LinearGradient(
                                    colors: [OPSStyle.Colors.cardBackgroundDark, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 40)
                                Spacer()
                            }
                        }
                    }
                )

                // Dimming overlay for completed/cancelled (covers full card including bleed)
                if task.status == .completed || task.status == .cancelled {
                    OPSStyle.Colors.modalOverlay
                        .frame(width: totalWidth, height: 64)
                        .clipShape(OPSRoundedCornerShape(radius: 2, corners: visibleCorners))
                }
            }
            .offset(x: bleedsLeft ? -leftBleed : 0)
        }
        .frame(height: 64)
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
        // Bug a6517f42 — schedule cards previously sat at 4pt vertical padding
        // (8pt total gap between cards), which read as cramped. Bumped to 8pt
        // (16pt total gap) for breathing room. The DayCanvas spacer height
        // (72pt) already accounts for 64pt card + 8pt vertical padding, so the
        // unified-task-list cross-day alignment stays correct.
        .padding(.vertical, 8)
        .padding(.leading, bleedsLeft ? 0 : 20)
        .padding(.trailing, bleedsRight ? 0 : 20)
        // Task type badge — top-right, shown on ALL days of the task
        .overlay(alignment: .topTrailing) {
            if !typeDisplay.isEmpty && showLabels {
                Text(typeDisplay)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(badgeColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(badgeColor.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(badgeColor.opacity(0.35), lineWidth: 0.5)
                    )
                    .padding(.top, 4 + 14) // 4pt vertical padding + 14pt card inset
                    .padding(.trailing, 34)
            }
        }
        // Status badge — bottom-right, shown on ALL days for completed/cancelled
        .overlay(alignment: .bottomTrailing) {
            if showLabels && (task.status == .completed || task.status == .cancelled) {
                Text(task.status == .completed ? "COMPLETED" : "CANCELLED")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(task.status == .completed ?
                                OPSStyle.Colors.statusColor(for: .completed) :
                                OPSStyle.Colors.inactiveStatus)
                    )
                    .padding(.bottom, 4 + 8) // 4pt vertical padding + 8pt card inset
                    .padding(.trailing, 34)
            }
        }
        .sheet(isPresented: $showingReschedule) {
            CalendarSchedulerSheet(
                isPresented: $showingReschedule,
                itemType: .task(task),
                currentStartDate: task.startDate,
                currentEndDate: task.endDate,
                onScheduleUpdate: { newStart, newEnd in
                    updateTaskSchedule(task: task, startDate: newStart, endDate: newEnd)
                },
                onClearDates: {
                    clearTaskDates(task: task)
                }
            )
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showingStatusPicker) {
            TaskStatusChangeSheet(task: task)
                .environmentObject(dataController)
        }
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

    private func clearTaskDates(task: ProjectTask) {
        let projectId = task.project?.id

        // Capture other tasks' dates for project date recalculation
        let scheduledTaskDates: [(start: Date, end: Date)]? = task.project?.tasks.compactMap { t in
            guard t.id != task.id,
                  let start = t.startDate,
                  let end = t.endDate else { return nil }
            return (start, end)
        }

        task.startDate = nil
        task.endDate = nil
        task.duration = 0
        task.needsSync = true

        dataController.scheduledTasksDidChange.toggle()

        Task {
            do {
                try await dataController.updateTaskFields(
                    taskId: task.id,
                    fields: [
                        "start_date": .null,
                        "end_date": .null,
                        "duration": .integer(0)
                    ]
                )

                if let project = task.project {
                    if let dates = scheduledTaskDates, !dates.isEmpty {
                        let earliestStart = dates.map { $0.start }.min()
                        let latestEnd = dates.map { $0.end }.max()
                        if let start = earliestStart, let end = latestEnd {
                            try await dataController.updateProjectDates(
                                project: project, startDate: start, endDate: end
                            )
                        }
                    } else {
                        try await dataController.updateProjectDates(
                            project: project, startDate: nil, endDate: nil
                        )
                    }
                }
            } catch {
                print("Error clearing task dates: \(error)")
            }
        }
    }
}

// MARK: - Shape helpers for rounded corners and borders

private struct OPSRoundedCornerShape: Shape {
    let radius: CGFloat
    let corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

private struct OPSRoundedCornerBorder: Shape {
    let radius: CGFloat
    let bleedsRight: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = radius
        if bleedsRight {
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                        radius: r, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r))
        }
        return path
    }
}

/// Border that skips edges which bleed into adjacent day columns
private struct OPSCardBorder: Shape {
    let radius: CGFloat
    let bleedsRight: Bool
    let bleedsLeft: Bool

    func path(in rect: CGRect) -> Path {
        if !bleedsRight && !bleedsLeft {
            var path = Path()
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius))
            return path
        }

        var path = Path()
        let r = radius

        // Top edge
        let topLeft = bleedsLeft ? rect.minX : rect.minX + r
        let topRight = bleedsRight ? rect.maxX : rect.maxX - r
        path.move(to: CGPoint(x: topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: topRight, y: rect.minY))

        // Top-right corner + right edge (if visible)
        if !bleedsRight {
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                        radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }

        // Bottom edge
        let bottomRight = bleedsRight ? rect.maxX : rect.maxX - r
        let bottomLeft = bleedsLeft ? rect.minX : rect.minX + r
        path.move(to: CGPoint(x: bottomRight, y: rect.maxY))
        path.addLine(to: CGPoint(x: bottomLeft, y: rect.maxY))

        // Bottom-left corner + left edge (if visible)
        if !bleedsLeft {
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                        radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }

        return path
    }
}
