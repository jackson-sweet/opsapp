//
//  TaskLineItem.swift
//  OPS
//
//  Reusable task line item component used in task lists across the app.
//  Based on ProjectFormSheet design: colored left border, title, date/team metadata, status badge.
//

import SwiftUI

/// Reusable task line item with consistent styling
///
/// Features:
/// - Colored left border based on task type
/// - Task type title (uppercased)
/// - Date and team member count metadata row
/// - Status badge in top right
/// - Optional delete button
/// - Long press gesture support for quick actions
///
/// Usage:
/// ```swift
/// // For ProjectTask (persisted)
/// TaskLineItem(
///     title: task.taskType?.display ?? "Task",
///     color: Color(hex: task.taskColor) ?? .blue,
///     status: task.status,
///     startDate: task.calendarEvent?.startDate,
///     teamMemberCount: task.getTeamMemberIds().count,
///     onTap: { /* handle tap */ },
///     onDelete: canDelete ? { /* handle delete */ } : nil
/// )
///
/// // For LocalTask (draft)
/// TaskLineItem(
///     title: taskType?.display ?? "Task",
///     color: taskColor,
///     status: localTask.status,
///     startDate: localTask.startDate,
///     teamMemberCount: localTask.teamMemberIds.count,
///     onTap: { /* handle tap */ },
///     onDelete: { /* handle delete */ }
/// )
/// ```
struct TaskLineItem: View {
    let title: String
    let color: Color
    let status: TaskStatus
    let startDate: Date?
    let teamMemberCount: Int
    let onTap: () -> Void
    let onDelete: (() -> Void)?
    let onLongPress: (() -> Void)?

    @State private var isLongPressing = false
    @State private var hasTriggeredHaptic = false

    init(
        title: String,
        color: Color,
        status: TaskStatus,
        startDate: Date? = nil,
        teamMemberCount: Int = 0,
        onTap: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil
    ) {
        self.title = title
        self.color = color
        self.status = status
        self.startDate = startDate
        self.teamMemberCount = teamMemberCount
        self.onTap = onTap
        self.onDelete = onDelete
        self.onLongPress = onLongPress
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Colored left border
                Rectangle()
                    .fill(color)
                    .frame(width: 4)

                // Main tappable content area
                VStack(alignment: .leading, spacing: 8) {
                    // Title
                    Text(title.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Metadata row with icons
                    HStack(spacing: 12) {
                        // Calendar icon + date
                        HStack(spacing: 4) {
                            Image(systemName: OPSStyle.Icons.calendar)
                                .font(.system(size: 11))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            if let date = startDate {
                                Text(DateHelper.simpleDateString(from: date))
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .lineLimit(1)
                            } else {
                                Text("—")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }

                        // Team icon + count
                        HStack(spacing: 4) {
                            Image(systemName: OPSStyle.Icons.personTwo)
                                .font(.system(size: 11))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text("\(teamMemberCount)")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .onTapGesture {
                    onTap()
                }

                Spacer()

                // Delete button (if provided)
                if let onDelete = onDelete {
                    Button(action: {
                        #if !targetEnvironment(simulator)
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        #endif
                        onDelete()
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .font(.system(size: 16))
                            .padding(.trailing, 16)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // Status badge overlay - top right
            VStack {
                HStack {
                    Spacer()
                    Text(status.displayName.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(status.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(status.color.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(status.color, lineWidth: 1)
                        )
                        .padding(.trailing, onDelete != nil ? 52 : 16)
                }
                Spacer()
            }
            .padding(.top, 8)
        }
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
        .scaleEffect(isLongPressing ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isLongPressing)
        .if(onLongPress != nil) { view in
            view.onLongPressGesture(minimumDuration: 0.3) {
                onLongPress?()
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
        }
    }
}

// MARK: - Conditional Modifier Extension

extension View {
    /// Applies the given transform if the given condition evaluates to `true`.
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        TaskLineItem(
            title: "Electrical",
            color: .blue,
            status: .active,
            startDate: Date(),
            teamMemberCount: 3,
            onTap: {},
            onDelete: {}
        )

        TaskLineItem(
            title: "Plumbing",
            color: .orange,
            status: .completed,
            startDate: nil,
            teamMemberCount: 1,
            onTap: {},
            onDelete: nil,
            onLongPress: {}
        )

        TaskLineItem(
            title: "Framing",
            color: .green,
            status: .cancelled,
            startDate: Date().addingTimeInterval(-86400),
            teamMemberCount: 5,
            onTap: {}
        )
    }
    .padding()
    .background(OPSStyle.Colors.background)
}
