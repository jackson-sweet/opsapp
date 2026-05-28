//
//  TaskDetailPopupSheet.swift
//  OPS
//
//  Task detail sheet shown from project details task list.
//  Dates row tappable to open scheduler. Team row expands inline.
//

import SwiftUI

struct TaskDetailPopupSheet: View {
    let task: ProjectTask
    let onSelect: (ProjectTask) -> Void
    let onComplete: (ProjectTask) -> Void
    let onReschedule: (ProjectTask) -> Void
    let onCancel: (ProjectTask) -> Void
    let onScheduleTap: ((ProjectTask) -> Void)?
    @Binding var selectedTeamMemberIds: Set<String>
    let allTeamMembers: [TeamMember]
    var isProjectCompleted: Bool = false
    /// Bug 0aa825fe + 62481022 — fired only when the operator explicitly taps
    /// DONE on the inline team picker. Drag-to-dismiss does NOT call this, so
    /// the parent can keep the save off the sheet-dismiss critical path
    /// (which was tearing down ProjectDetails via the SwiftData notification
    /// cascade triggered mid-animation by updateTaskTeamMembers' multiple
    /// modelContext.save() calls).
    var onCommitTeam: ((Set<String>) -> Void)? = nil

    @State private var showReopenAlert = false
    @State private var showCancelAlert = false
    @State private var showTeamPicker = false
    /// Draft team selection that lives only inside this sheet — the operator
    /// can tap rows freely without each tap immediately mutating the parent
    /// state. Only committed back to `selectedTeamMemberIds` when DONE is
    /// tapped. Resets from the committed value every time the picker
    /// expands so a discarded picker leaves no trace.
    @State private var draftTeamMemberIds: Set<String> = []

    private var isInactive: Bool {
        task.status == .completed || task.status == .cancelled
    }

    private var teamDraftIsDirty: Bool {
        draftTeamMemberIds != selectedTeamMemberIds
    }

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
                    header
                    if task.status == .active {
                        completeButton
                    } else if task.status == .completed {
                        reopenButton
                    }
                    infoCard
                    actionButtons
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.background)
        .environment(\.colorScheme, .dark)
        .opsSheet(detents: [.medium, .large])
        .alert("Reopen Task?", isPresented: $showReopenAlert) {
            Button("Reopen", role: .destructive) {
                onComplete(task)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to reopen this task? It will be set back to active status.")
        }
        .alert("Cancel Task?", isPresented: $showCancelAlert) {
            Button("Confirm", role: .destructive) {
                onCancel(task)
            }
            Button("Leave Open", role: .cancel) {}
        } message: {
            Text("This task will be marked as cancelled.")
        }
    }

    // MARK: - Header

    private var header: some View {
        let taskColor = Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent

        return VStack(alignment: .leading, spacing: 12) {
            // Task type badge + status pill
            HStack(spacing: 8) {
                TaskBadge(
                    name: task.taskType?.display ?? "Task",
                    color: taskColor,
                    size: .medium,
                    faded: task.status == .completed
                )

                StatusBadgePill(
                    text: task.status.displayName.uppercased(),
                    color: task.status.color,
                    size: .medium
                )

                Spacer()
            }

            // Title
            Text(task.displayTitle)
                .font(OPSStyle.Typography.headingBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .opacity(task.status == .completed ? 0.5 : 1.0)

            // Notes (if present)
            if let notes = task.taskNotes, !notes.isEmpty {
                Text(notes)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(3)
            }
        }
    }

    // MARK: - Complete Button

    private var completeButton: some View {
        Button(action: {
            onComplete(task)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                Text("MARK COMPLETE")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(0.5)
            }
            .foregroundColor(OPSStyle.Colors.successStatus)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(OPSStyle.Colors.successStatus.opacity(0.1))
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.successStatus.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Reopen Button

    private var reopenButton: some View {
        Button(action: {
            showReopenAlert = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                Text("REOPEN TASK")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(0.5)
            }
            .foregroundColor(OPSStyle.Colors.warningStatus)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(OPSStyle.Colors.warningStatus.opacity(0.1))
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.warningStatus.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(spacing: 0) {
            datesRow

            divider

            if task.status == .completed, let completionDate = task.completionDate {
                infoRow(
                    icon: "checkmark.circle",
                    label: "COMPLETED",
                    value: DateHelper.simpleDateString(from: completionDate)
                )
                divider
            }

            teamHeader

            if showTeamPicker {
                teamMemberList
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Dates Row (tappable — opens scheduler)

    private var datesRow: some View {
        Button(action: {
            onScheduleTap?(task)
        }) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DATES")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(dateRangeText)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                Spacer()

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var dateRangeText: String {
        if let start = task.startDate, let end = task.endDate {
            return "\(DateHelper.simpleDateString(from: start)) → \(DateHelper.simpleDateString(from: end))"
        }
        return "Not scheduled"
    }

    // MARK: - Team Header (tap to expand inline picker)

    private var teamHeader: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                if showTeamPicker {
                    // Collapsing without DONE = discard. Draft is reset on
                    // the next open via the `if !showTeamPicker` branch.
                    showTeamPicker = false
                } else {
                    // Opening — seed the draft from the committed selection
                    // so the picker shows what's actually on the task, not
                    // a stale draft from an earlier abandoned session.
                    draftTeamMemberIds = selectedTeamMemberIds
                    showTeamPicker = true
                }
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "person.2")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text("TEAM")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    if selectedTeamMemberIds.isEmpty {
                        Text("Tap to assign team")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    } else {
                        let selectedMembers = allTeamMembers.filter { selectedTeamMemberIds.contains($0.id) }
                        if selectedMembers.isEmpty {
                            // IDs exist but members not loaded yet — show count
                            Text("\(selectedTeamMemberIds.count) assigned")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        } else {
                            HStack(spacing: -6) {
                                ForEach(selectedMembers.prefix(5), id: \.id) { member in
                                    Circle()
                                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.3))
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Text(member.initials)
                                                .font(OPSStyle.Typography.miniLabel)
                                                .foregroundColor(OPSStyle.Colors.primaryText)
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(OPSStyle.Colors.cardBackgroundDark, lineWidth: 2)
                                        )
                                }
                                if selectedMembers.count > 5 {
                                    Text("+\(selectedMembers.count - 5)")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                        .padding(.leading, 8)
                                }
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: showTeamPicker ? "chevron.down" : OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Inline Team Member List

    private var teamMemberList: some View {
        VStack(spacing: 0) {
            // Bug 53552d03 — keep the explicit commit controls immediately
            // below the TEAM header. The operator must not have to scroll
            // through the crew roster before DONE is visible.
            teamCommitRow

            ForEach(allTeamMembers, id: \.id) { member in
                let isSelected = draftTeamMemberIds.contains(member.id)

                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if isSelected {
                        draftTeamMemberIds.remove(member.id)
                    } else {
                        draftTeamMemberIds.insert(member.id)
                    }
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))

                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(member.initials)
                                    .font(OPSStyle.Typography.microLabel)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(member.fullName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Text(member.role)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.bottom, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var teamCommitRow: some View {
        HStack(spacing: 10) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTeamPicker = false
                }
            }) {
                Text("CANCEL")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(0.5)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("taskDetailTeamCancelButton")

            Button(action: {
                let committed = draftTeamMemberIds
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                // Update the binding so subsequent reads see the new
                // committed value, then collapse the picker. The actual
                // SwiftData write happens via onCommitTeam in the parent —
                // the parent defers it off the dismiss critical path.
                selectedTeamMemberIds = committed
                onCommitTeam?(committed)
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTeamPicker = false
                }
            }) {
                Text("DONE")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(0.5)
                    .foregroundColor(teamDraftIsDirty
                        ? OPSStyle.Colors.invertedText
                        : OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(teamDraftIsDirty
                        ? OPSStyle.Colors.primaryAccent
                        : OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!teamDraftIsDirty)
            .accessibilityIdentifier("taskDetailTeamDoneButton")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Static Info Row

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

    private var divider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorder)
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if isInactive {
                Button(action: {
                    showReopenAlert = true
                }) {
                    Text("REOPEN TO SELECT")
                        .font(OPSStyle.Typography.captionBold)
                        .tracking(0.5)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(OPSStyle.Colors.warningStatus.opacity(0.1))
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.warningStatus.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Button(action: {
                    onSelect(task)
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
            }

            if task.status == .active && !isProjectCompleted {
                Button(action: {
                    showCancelAlert = true
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
}
