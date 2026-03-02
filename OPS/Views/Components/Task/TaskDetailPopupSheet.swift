//
//  TaskDetailPopupSheet.swift
//  OPS
//
//  Half-sheet popup showing task details and action buttons.
//  Presented when tapping a task in the project details task list.
//

import SwiftUI

struct TaskDetailPopupSheet: View {
    let task: ProjectTask
    let onSelect: (ProjectTask) -> Void
    let onComplete: (ProjectTask) -> Void
    let onReschedule: (ProjectTask) -> Void
    let onCancel: (ProjectTask) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: - Header
                    header

                    // MARK: - Info Rows
                    infoCard

                    // MARK: - Actions
                    actionButtons
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .background(OPSStyle.Colors.background)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            let taskColor = Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent
            TaskBadge(
                name: task.displayTitle,
                color: taskColor,
                size: .large,
                faded: task.status == .completed
            )

            StatusBadgePill(
                text: task.status.displayName.uppercased(),
                color: task.status.color,
                size: .medium
            )

            Spacer()
        }
    }

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(spacing: 0) {
            // Dates row
            infoRow(
                icon: "calendar",
                label: "DATES",
                value: dateRangeText
            )

            divider

            // Completed date (only if completed)
            if task.status == .completed, let completionDate = task.completionDate {
                infoRow(
                    icon: "checkmark.circle",
                    label: "COMPLETED",
                    value: DateHelper.simpleDateString(from: completionDate)
                )
                divider
            }

            // Team row
            teamRow

            divider

            // Address row
            infoRow(
                icon: "mappin",
                label: "ADDRESS",
                value: task.project?.address ?? "No address"
            )
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
    }

    private var dateRangeText: String {
        if let start = task.startDate, let end = task.endDate {
            return "\(DateHelper.simpleDateString(from: start)) → \(DateHelper.simpleDateString(from: end))"
        }
        return "Not scheduled"
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(value)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var teamRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text("TEAM")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                if task.teamMembers.isEmpty {
                    Text("No team assigned")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                } else {
                    HStack(spacing: -6) {
                        ForEach(task.teamMembers.prefix(5), id: \.id) { member in
                            let memberInitials = "\(member.firstName.prefix(1).uppercased())\(member.lastName.prefix(1).uppercased())"
                            Circle()
                                .fill(OPSStyle.Colors.primaryAccent.opacity(0.3))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Text(memberInitials)
                                        .font(.custom("Kosugi-Regular", size: 10))
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(OPSStyle.Colors.cardBackgroundDark, lineWidth: 2)
                                )
                        }
                        if task.teamMembers.count > 5 {
                            Text("+\(task.teamMembers.count - 5)")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .padding(.leading, 8)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorder)
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            // SELECT THIS TASK
            Button(action: {
                onSelect(task)
                dismiss()
            }) {
                Text("SELECT THIS TASK")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(0.5)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
            }
            .buttonStyle(PlainButtonStyle())

            HStack(spacing: 10) {
                // COMPLETE / REOPEN
                let isCompleted = task.status == .completed
                Button(action: {
                    onComplete(task)
                    dismiss()
                }) {
                    Text(isCompleted ? "REOPEN" : "COMPLETE")
                        .font(OPSStyle.Typography.captionBold)
                        .tracking(0.5)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())

                // RESCHEDULE
                Button(action: {
                    onReschedule(task)
                    dismiss()
                }) {
                    Text("RESCHEDULE")
                        .font(OPSStyle.Typography.captionBold)
                        .tracking(0.5)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }

            // CANCEL TASK
            Button(action: {
                onCancel(task)
                dismiss()
            }) {
                Text("CANCEL TASK")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(0.5)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(OPSStyle.Colors.errorStatus.opacity(0.1))
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.errorStatus.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}
