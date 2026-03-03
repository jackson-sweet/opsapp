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
         dayPosition: DayPosition = .single, onTap: @escaping () -> Void) {
        self.task = task
        self.isFirst = isFirst
        self.isOngoing = isOngoing
        self.dayPosition = dayPosition
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

    var body: some View {
        GeometryReader { geo in
            let bleedsRight = dayPosition == .start || dayPosition == .middle
            let bleedWidth: CGFloat = bleedsRight ? 32 : 0
            let totalWidth = geo.size.width + bleedWidth

            ZStack(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    // Left color stripe
                    Rectangle()
                        .fill(displayColor)
                        .frame(width: 4)

                    // Content
                    VStack(alignment: .leading, spacing: 5) {
                        if let project = associatedProject {
                            Text(project.title)
                                .font(.custom("Mohave-SemiBold", size: 15))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .textCase(.uppercase)
                                .lineLimit(1)

                            Text(project.effectiveClientName)
                                .font(.custom("Kosugi-Regular", size: 12))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .lineLimit(1)

                            Text(formattedAddress)
                                .font(.custom("Kosugi-Regular", size: 11))
                                .foregroundColor(OPSStyle.Colors.primaryText.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)

                    // Task type badge (top-right, only if not bleeding far right)
                    if !typeDisplay.isEmpty && !bleedsRight {
                        VStack {
                            Text(typeDisplay)
                                .font(.custom("Kosugi-Regular", size: 9))
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
                            Spacer()
                        }
                        .padding(.top, 14)
                        .padding(.trailing, 14)
                    }
                }
                .frame(width: totalWidth, height: 64)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .clipShape(
                    OPSRoundedCornerShape(
                        radius: 2,
                        corners: bleedsRight ? [.topLeft, .bottomLeft] : .allCorners
                    )
                )
                .overlay(
                    OPSRoundedCornerBorder(radius: 2, bleedsRight: bleedsRight)
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

                // Completed overlay (on top of card)
                if task.status == .completed {
                    ZStack(alignment: .topTrailing) {
                        OPSStyle.Colors.modalOverlay
                            .clipShape(OPSRoundedCornerShape(radius: 2, corners: bleedsRight ? [.topLeft, .bottomLeft] : .allCorners))
                        Text("COMPLETED")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(OPSStyle.Colors.statusColor(for: .completed))
                            )
                            .padding(8)
                    }
                    .frame(width: totalWidth, height: 64)
                }

                // Cancelled overlay (on top of card)
                if task.status == .cancelled {
                    ZStack(alignment: .topTrailing) {
                        OPSStyle.Colors.modalOverlay
                            .clipShape(OPSRoundedCornerShape(radius: 2, corners: bleedsRight ? [.topLeft, .bottomLeft] : .allCorners))
                        Text("CANCELLED")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(OPSStyle.Colors.inactiveStatus)
                            )
                            .padding(8)
                    }
                    .frame(width: totalWidth, height: 64)
                }
            }
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
            // Top edge (no right corner)
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            // Top-left corner
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true)
            // Left side
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            // Bottom-left corner
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                        radius: r, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            // Bottom edge
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r))
        }
        return path
    }
}
