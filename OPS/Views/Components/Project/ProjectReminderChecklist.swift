//
//  ProjectReminderChecklist.swift
//  OPS
//
//  Reminder checklist embedded inside the project detail view. Shows every
//  open reminder for the project's tasks, grouped by task, with checkbox /
//  dismiss controls per item. Optimistic local writes; reverts on server
//  failure. See bug 4f00c2d7 + spec
//  docs/superpowers/specs/2026-05-10-task-reminders-design.md.
//

import SwiftUI
import SwiftData

struct ProjectReminderChecklist: View {
    let project: Project
    @Environment(\.modelContext) private var modelContext

    /// Group reminders by their parent task. Only tasks that have at least
    /// one non-cleared reminder show up here — completed/cancelled tasks
    /// are excluded so the section disappears when work is done.
    private var groupedReminders: [(task: ProjectTask, reminders: [TaskReminder])] {
        let openTasks = project.tasks
            .filter { $0.deletedAt == nil && $0.status != .cancelled }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }

        return openTasks.compactMap { task in
            let visible = task.reminders
                .filter { $0.deletedAt == nil }
                .sorted {
                    // active first, then by fire time
                    if $0.isCleared != $1.isCleared { return !$0.isCleared }
                    let aFire = $0.firesAt ?? .distantFuture
                    let bFire = $1.firesAt ?? .distantFuture
                    return aFire < bFire
                }
            return visible.isEmpty ? nil : (task, visible)
        }
    }

    var body: some View {
        if groupedReminders.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text("REMINDERS")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Spacer()
                    Text(openCountLabel)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.horizontal, 16)

                VStack(spacing: OPSStyle.Layout.spacing3) {
                    ForEach(Array(groupedReminders.enumerated()), id: \.offset) { _, group in
                        TaskRemindersGroup(task: group.task, reminders: group.reminders)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var openCountLabel: String {
        let active = groupedReminders.flatMap(\.reminders).filter { !$0.isCleared }.count
        let total = groupedReminders.flatMap(\.reminders).count
        return "\(active)/\(total) OPEN"
    }
}

// MARK: - Per-task group

private struct TaskRemindersGroup: View {
    let task: ProjectTask
    let reminders: [TaskReminder]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent)
                    .frame(width: 8, height: 8)
                Text(task.displayTitle.uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)

            VStack(spacing: 0) {
                ForEach(Array(reminders.enumerated()), id: \.element.id) { index, reminder in
                    ReminderRow(reminder: reminder)
                    if index < reminders.count - 1 {
                        Divider().background(OPSStyle.Colors.cardBorder)
                    }
                }
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

// MARK: - Individual reminder row

private struct ReminderRow: View {
    @Bindable var reminder: TaskReminder
    @Environment(\.modelContext) private var modelContext
    @State private var isWorking = false
    @State private var error: String? = nil

    private var subhead: String {
        var parts: [String] = [reminder.leadTimeDisplay]
        if let due = reminder.dueDisplay {
            parts.append(due)
        }
        if let by = reminder.acknowledgedBy, reminder.isAcknowledged {
            parts.append("acknowledged \(initials(for: by))")
        } else if reminder.isDismissed {
            parts.append("dismissed")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing3) {
            checkboxOrDismissControl

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.label)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(reminder.isCleared ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                    .strikethrough(reminder.isAcknowledged)
                Text("// " + subhead.lowercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            if !reminder.requiresAck && !reminder.isCleared {
                Button {
                    Task { await dismiss() }
                } label: {
                    Text("DISMISS")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(height: OPSStyle.Layout.touchTargetMin)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var checkboxOrDismissControl: some View {
        if reminder.requiresAck {
            Button {
                Task { await toggle() }
            } label: {
                Image(systemName: reminder.isAcknowledged ? OPSStyle.Icons.checkmarkSquareFill : "square")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(reminder.isAcknowledged ? OPSStyle.Colors.successStatus : OPSStyle.Colors.secondaryText)
                    .frame(width: 44, height: 44)
            }
            .disabled(isWorking)
        } else {
            // Non-ack reminders: show a hollow circle, optional optimistic tick.
            Button {
                Task { await toggle() }
            } label: {
                Group {
                    if reminder.isAcknowledged {
                        Image(OPSStyle.Icons.checkmarkCircleFill)
                    } else {
                        Image(systemName: "circle")
                    }
                }
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(reminder.isAcknowledged ? OPSStyle.Colors.successStatus : OPSStyle.Colors.tertiaryText)
                    .frame(width: 44, height: 44)
            }
            .disabled(isWorking)
        }
    }

    // MARK: - Behaviors

    @MainActor
    private func toggle() async {
        guard !isWorking else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isWorking = true
        defer { isWorking = false }

        if reminder.isAcknowledged {
            // Un-ack
            reminder.acknowledgedAt = nil
            reminder.acknowledgedBy = nil
            do {
                try await TaskReminderRepository.shared.unacknowledge(id: reminder.id)
                try modelContext.save()
            } catch {
                // Revert local on failure
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                await refreshFromServer()
            }
        } else {
            let userId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
            let now = Date()
            reminder.acknowledgedAt = now
            reminder.acknowledgedBy = userId
            do {
                try await TaskReminderRepository.shared.acknowledge(id: reminder.id, userId: userId)
                try modelContext.save()
                // Cancel pending local notification since the reminder is cleared
                await NotificationManager.shared.cancelTaskReminder(reminder.id)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                await refreshFromServer()
            }
        }
    }

    @MainActor
    private func dismiss() async {
        guard !isWorking else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isWorking = true
        defer { isWorking = false }

        let now = Date()
        reminder.dismissedAt = now
        do {
            try await TaskReminderRepository.shared.dismiss(id: reminder.id)
            try modelContext.save()
            await NotificationManager.shared.cancelTaskReminder(reminder.id)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            await refreshFromServer()
        }
    }

    @MainActor
    private func refreshFromServer() async {
        // Best-effort re-fetch on failure to undo the optimistic local write.
        do {
            let dtos = try await TaskReminderRepository.shared.fetchInstancesForTask(reminder.taskId)
            if let fresh = dtos.first(where: { $0.id == reminder.id }) {
                fresh.apply(to: reminder)
                try modelContext.save()
            }
        } catch {
            // Swallow — UI will reconcile on next pull.
        }
    }

    private func initials(for userId: String) -> String {
        // Best-effort — the row doesn't have a User by-id lookup, so fall
        // back to the first 4 chars of the uuid. Future: pass userById map.
        String(userId.prefix(4)).uppercased()
    }
}
