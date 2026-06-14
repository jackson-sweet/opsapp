//
//  InlineTaskRow.swift
//  OPS
//
//  Compact single-line task editor row used inside ProjectFormSheet.
//  Replaces the modal-on-modal "add task → full sheet" flow with inline
//  chip-based quick inputs for type, team, schedule. Status, notes, and
//  dependencies remain accessible via long-press → "Open full editor".
//

import SwiftUI

/// Single-line inline task editor row.
///
/// Layout (left to right):
/// - 4pt colored rail (task-type color, or `text3` when unset)
/// - TYPE menu chip (flex width, primary identity, required)
/// - TEAM chip (icon + count, opens parent's team-picker sheet)
/// - DATE chip (icon + abbreviated date, opens parent's scheduler sheet)
/// - Open editor chevron (opens the full `TaskFormSheet`)
/// - Delete (trailing)
///
/// Status changes, full notes editing, dependencies, duplication, and the
/// destructive confirmation all live in a `.contextMenu` reached by
/// long-pressing the row. Tapping the row body (between or around chips)
/// also opens the full `TaskFormSheet`, but bug 705cc320 surfaced that the
/// implicit tap was undiscoverable — the trailing chevron is the explicit
/// affordance.
///
/// All tokens come from `OPSStyle`; no hardcoded colors, fonts, spacing,
/// or motion values. Reduced-motion is respected via `accessibleEaseInOut`.
struct InlineTaskRow: View {
    // MARK: - Inputs

    let task: LocalTask
    /// Task types available to the menu, already ordered by recency.
    let availableTaskTypes: [TaskType]
    /// Number of unique team members assigned (resolved by parent).
    let teamMemberCount: Int

    /// When false (tutorial gating), chips do not respond to taps.
    let isEnabled: Bool

    // MARK: - Callbacks (parent owns mutation)

    let onTaskTypeChange: (String) -> Void
    let onCreateNewTaskType: () -> Void
    let onTeamTap: () -> Void
    let onDateTap: () -> Void
    let onStatusChange: (TaskStatus) -> Void
    let onOpenFullEditor: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    // MARK: - Derived

    private var taskType: TaskType? {
        availableTaskTypes.first { $0.id == task.taskTypeId }
    }

    private var typeColor: Color {
        if let hex = taskType?.color, let c = Color(hex: hex) { return c }
        return OPSStyle.Colors.text3
    }

    private var typeLabel: String {
        (taskType?.display ?? "Select type").uppercased()
    }

    private var hasType: Bool { taskType != nil }

    private var dateLabel: String {
        guard let start = task.startDate else { return "—" }
        let startStr = DateHelper.simpleDateString(from: start).uppercased()
        if let end = task.endDate,
           !Calendar.current.isDate(start, inSameDayAs: end) {
            let endStr = DateHelper.simpleDateString(from: end).uppercased()
            return "\(startStr) – \(endStr)"
        }
        return startStr
    }

    private var isTerminal: Bool { task.status.isTerminal }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Color rail
            Rectangle()
                .fill(typeColor)
                .frame(width: 4)

            // Chips + open + delete. `typeChip` is the only flex element —
            // team / date / open / delete are intrinsic, so the type chip
            // absorbs all remaining horizontal space and the row stays
            // single-line on iPhone widths.
            HStack(spacing: OPSStyle.Layout.spacing2) {
                typeChip
                teamChip
                dateChip
                openEditorButton
                deleteButton
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetLarge)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .opacity(isTerminal ? OPSStyle.Layout.Opacity.strong : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isEnabled else { return }
            onOpenFullEditor()
        }
        .contextMenu {
            contextMenuContent
        }
        .allowsHitTesting(isEnabled)
    }

    // MARK: - Type chip (Menu)

    private var typeChip: some View {
        Menu {
            ForEach(availableTaskTypes, id: \.id) { type in
                Button {
                    chipHaptic()
                    onTaskTypeChange(type.id)
                } label: {
                    HStack {
                        Text(type.display)
                        if type.id == task.taskTypeId {
                            Spacer()
                            Image(systemName: OPSStyle.Icons.checkmark)
                        }
                    }
                }
            }

            Divider()

            Button {
                onCreateNewTaskType()
            } label: {
                Label("New Task Type", systemImage: OPSStyle.Icons.plus)
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text(typeLabel)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(
                        hasType
                            ? OPSStyle.Colors.text
                            : OPSStyle.Colors.text3
                    )
                    .strikethrough(isTerminal, color: OPSStyle.Colors.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: OPSStyle.Icons.chevronDown)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
            .background(OPSStyle.Colors.surfaceInput)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(
                        hasType ? OPSStyle.Colors.line : OPSStyle.Colors.brickLine,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .menuOrder(.fixed)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Team chip

    private var teamChip: some View {
        Button {
            chipHaptic()
            onTeamTap()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Image(systemName: OPSStyle.Icons.personTwo)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(
                        teamMemberCount > 0
                            ? OPSStyle.Colors.text2
                            : OPSStyle.Colors.text3
                    )

                Text(teamMemberCount > 0 ? "\(teamMemberCount)" : "—")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(
                        teamMemberCount > 0
                            ? OPSStyle.Colors.text2
                            : OPSStyle.Colors.text3
                    )
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .background(OPSStyle.Colors.surfaceInput)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date chip

    private var dateChip: some View {
        Button {
            chipHaptic()
            onDateTap()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Image(systemName: OPSStyle.Icons.calendar)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(
                        task.startDate != nil
                            ? OPSStyle.Colors.text2
                            : OPSStyle.Colors.text3
                    )

                Text(dateLabel)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(
                        task.startDate != nil
                            ? OPSStyle.Colors.text2
                            : OPSStyle.Colors.text3
                    )
                    .lineLimit(1)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .background(OPSStyle.Colors.surfaceInput)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Open editor (bug 705cc320)

    /// Trailing chevron that opens the full `TaskFormSheet` for status notes,
    /// dependencies, and other advanced fields. The row body itself is also
    /// tappable, but the chevron is the visible "this row drills in"
    /// affordance the inline pattern was missing.
    private var openEditorButton: some View {
        Button {
            chipHaptic()
            onOpenFullEditor()
        } label: {
            Image(systemName: OPSStyle.Icons.chevronRight)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.text3)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open full task editor")
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button {
            #if !targetEnvironment(simulator)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            #endif
            onDelete()
        } label: {
            Image(systemName: OPSStyle.Icons.xmark)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.rose)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            onOpenFullEditor()
        } label: {
            Label("Open Full Editor", systemImage: OPSStyle.Icons.pencil)
        }

        Button {
            onDuplicate()
        } label: {
            Label("Duplicate", systemImage: OPSStyle.Icons.copy)
        }

        Divider()

        // Status quick-change
        if task.status != .active {
            Button {
                onStatusChange(.active)
            } label: {
                Label("Mark Active", systemImage: OPSStyle.Icons.circle)
            }
        }
        if task.status != .completed {
            Button {
                onStatusChange(.completed)
            } label: {
                Label("Mark Completed", systemImage: OPSStyle.Icons.checkmarkCircle)
            }
        }
        if task.status != .cancelled {
            Button {
                onStatusChange(.cancelled)
            } label: {
                Label("Cancel Task", systemImage: OPSStyle.Icons.xmarkCircle)
            }
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: OPSStyle.Icons.delete)
        }
    }

    // MARK: - Haptics

    private func chipHaptic() {
        #if !targetEnvironment(simulator)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }
}

// MARK: - Preview

#Preview {
    let previewType = TaskType(
        id: "tt-electrical",
        display: "Electrical",
        color: "#6F94B0",
        companyId: "co-1"
    )

    return VStack(spacing: OPSStyle.Layout.spacing2_5) {
        InlineTaskRow(
            task: LocalTask(
                id: UUID(),
                taskTypeId: "tt-electrical",
                status: .active,
                teamMemberIds: ["u1", "u2", "u3"],
                startDate: Date()
            ),
            availableTaskTypes: [previewType],
            teamMemberCount: 3,
            isEnabled: true,
            onTaskTypeChange: { _ in },
            onCreateNewTaskType: {},
            onTeamTap: {},
            onDateTap: {},
            onStatusChange: { _ in },
            onOpenFullEditor: {},
            onDuplicate: {},
            onDelete: {}
        )

        InlineTaskRow(
            task: LocalTask(
                id: UUID(),
                taskTypeId: "",
                status: .active,
                teamMemberIds: [],
                startDate: nil
            ),
            availableTaskTypes: [previewType],
            teamMemberCount: 0,
            isEnabled: true,
            onTaskTypeChange: { _ in },
            onCreateNewTaskType: {},
            onTeamTap: {},
            onDateTap: {},
            onStatusChange: { _ in },
            onOpenFullEditor: {},
            onDuplicate: {},
            onDelete: {}
        )

        InlineTaskRow(
            task: LocalTask(
                id: UUID(),
                taskTypeId: "tt-electrical",
                status: .completed,
                teamMemberIds: ["u1"],
                startDate: Date(),
                endDate: Calendar.current.date(byAdding: .day, value: 2, to: Date())
            ),
            availableTaskTypes: [previewType],
            teamMemberCount: 1,
            isEnabled: true,
            onTaskTypeChange: { _ in },
            onCreateNewTaskType: {},
            onTeamTap: {},
            onDateTap: {},
            onStatusChange: { _ in },
            onOpenFullEditor: {},
            onDuplicate: {},
            onDelete: {}
        )
    }
    .padding()
    .background(OPSStyle.Colors.background)
}
