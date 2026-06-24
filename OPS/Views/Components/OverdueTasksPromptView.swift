//
//  OverdueTasksPromptView.swift
//  OPS
//
//  Full-screen prompt shown on app open when the operator has tasks that were
//  scheduled to be finished by now but are still open. Mirrors the
//  CompanySetupPromptView pattern (full-screen, tokenized, snoozeable) — the
//  same "we noticed something you should close out" nudge, applied to overdue
//  work instead of a half-finished company profile.
//
//  Why: overdue-but-unmarked tasks are silent drift. The work is usually done
//  (or abandoned) but never closed out, which quietly rots the job board and
//  every report that reads off task status. A proactive, dismissible prompt the
//  moment the app opens lets the operator close the loop in one tap each.
//
//  Scope: tasks ASSIGNED TO the current user (their own work to close out).
//  Completing a task you're assigned to needs no special permission — it is the
//  crew's own status to set — so this is ungated beyond the assignment check.
//

import SwiftUI
import SwiftData

struct OverdueTasksPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    // Live task list — recomputes as tasks are completed so rows fall away the
    // instant they're marked done.
    @Query(filter: #Predicate<ProjectTask> { $0.deletedAt == nil })
    private var allTasks: [ProjectTask]

    /// Ids already being completed — removed from the visible list immediately
    /// for a clean fall-away while the async status write lands.
    @State private var completingTaskIds: Set<String> = []
    @State private var taskToOpen: ProjectTask?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Snooze Token

    private static let snoozeKey = "overdueTasksPromptSnoozedUntil"

    /// Whether the prompt should surface this launch. Mirrors
    /// CompanySetupPromptView.shouldShowPrompt: a cheap, side-effect-free gate
    /// ContentView calls once per session.
    static func shouldShowPrompt(dataController: DataController) -> Bool {
        guard let userId = dataController.currentUser?.id else { return false }

        // Snooze gate — respect a "Later" dismissal until it expires.
        if let until = UserDefaults.standard.object(forKey: snoozeKey) as? Date,
           Date() < until {
            return false
        }

        return dataController.getAllProjects().contains { project in
            project.tasks.contains { task in
                task.deletedAt == nil && task.isOverdue && task.getTeamMemberIds().contains(userId)
            }
        }
    }

    /// Snooze the prompt for 24h so it doesn't re-fire on every launch.
    private func snooze() {
        UserDefaults.standard.set(
            Date().addingTimeInterval(24 * 60 * 60),
            forKey: Self.snoozeKey
        )
    }

    // MARK: - Derived

    private var overdueTasks: [ProjectTask] {
        guard let userId = dataController.currentUser?.id else { return [] }
        let filtered: [ProjectTask] = allTasks.filter { task in
            guard task.isOverdue else { return false }
            guard !completingTaskIds.contains(task.id) else { return false }
            return task.getTeamMemberIds().contains(userId)
        }
        return filtered.sorted { lhs, rhs in
            (lhs.endDate ?? Date.distantFuture) < (rhs.endDate ?? Date.distantFuture)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                subtitleRow

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(overdueTasks, id: \.id) { task in
                            overdueCard(task)
                                .transition(reduceMotion
                                    ? .opacity
                                    : .move(edge: .leading).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.bottom, OPSStyle.Layout.spacing4)
                    .animation(OPSStyle.Animation.standard, value: overdueTasks.map(\.id))
                }

                Spacer(minLength: 0)

                laterButton
            }
        }
        .interactiveDismissDisabled(false)
        .fullScreenCover(item: $taskToOpen) { task in
            if let project = task.project {
                NavigationView {
                    ProjectDetailsView(project: project, initialSelectedTask: task)
                        .environmentObject(dataController)
                }
            }
        }
        // If the operator clears every overdue task, the job is done — get out
        // of their way.
        .onChange(of: overdueTasks.isEmpty) { _, empty in
            if empty { dismiss() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("OVERDUE")
                .font(OPSStyle.Typography.pageTitle)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text)

            Spacer()

            Button {
                snooze()
                dismiss()
            } label: {
                Image(systemName: OPSStyle.Icons.xmark)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    private var subtitleRow: some View {
        HStack {
            Text("Due by now, still open. Mark what's done.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            // The single urgency signal. `rose` is the system's overdue/error
            // TEXT token (#B58289); brick (`errorStatus`) is border/dot only.
            Text("\(overdueTasks.count)")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.rose)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing1)
        .padding(.bottom, OPSStyle.Layout.spacing4)
    }

    // MARK: - Card

    private func overdueCard(_ task: ProjectTask) -> some View {
        HStack(spacing: 0) {
            // Left edge — structural only. Every row shares the one overdue
            // state, so a per-card brick bar just repeats the alarm down the
            // list. Neutral, mirroring the sibling CompanySetupPromptView's
            // not-yet-complete card. (Brick is a border/dot token, not a fill.)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(OPSStyle.Colors.cardBorder)
                .frame(width: 3)
                .padding(.vertical, OPSStyle.Layout.spacing2)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                // Project title
                Text(task.project?.title ?? "Project")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                // Task badge + overdue meta + the close-it-out action, on one
                // row so the card stays compact and the action reads as a quiet
                // affordance instead of a full-width bar.
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    TaskBadge(
                        name: task.taskType?.display ?? "Task",
                        color: Color(hex: task.taskColor) ?? OPSStyle.Colors.primaryAccent,
                        size: .medium
                    )

                    // `rose` (#B58289) is the system's overdue/error TEXT token;
                    // brick (`errorStatus`) is border/dot only.
                    Text(overdueLabel(for: task))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.rose)

                    Spacer(minLength: OPSStyle.Layout.spacing2)

                    // Primary action — a quiet accent chip, not a solid
                    // full-width fill. With one action per card, repeated solid
                    // accent bars are the loudness; the chip keeps the tap
                    // obvious (44pt, accent, checkmark) while staying calm.
                    // Mirrors the sibling's USE MINE / ADD chip vocabulary.
                    Button(action: { markDone(task) }) {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Image(systemName: OPSStyle.Icons.checkmark)
                                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .bold))
                            Text("MARK DONE")
                                .font(OPSStyle.Typography.captionBold)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .frame(height: OPSStyle.Layout.touchTargetMin)
                        .background(OPSStyle.Colors.primaryAccent.opacity(0.12))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Mark done: \(task.project?.title ?? "task")")
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassSurface()
        .contentShape(Rectangle())
        // Tap anywhere on the card (outside the button) to open the task for a
        // fuller review — reschedule, cancel, add a completion note.
        .onTapGesture { taskToOpen = task }
        // A bare onTapGesture isn't a VoiceOver action — expose the open-task
        // path explicitly so it's reachable alongside MARK DONE.
        .accessibilityAction(named: "Open task") { taskToOpen = task }
    }

    // MARK: - Later

    private var laterButton: some View {
        Button {
            snooze()
            dismiss()
        } label: {
            Text("Later")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetMin)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.bottom, OPSStyle.Layout.spacing4)
    }

    // MARK: - Actions

    private func markDone(_ task: ProjectTask) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(OPSStyle.Animation.standard) {
            _ = completingTaskIds.insert(task.id)
        }
        Task {
            do {
                try await dataController.updateTaskStatus(task: task, to: .completed)
            } catch {
                // Revert the optimistic removal so the operator can retry.
                await MainActor.run {
                    withAnimation(OPSStyle.Animation.standard) {
                        completingTaskIds.remove(task.id)
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    /// "3d overdue" by calendar-day difference; "Overdue" when it slipped today.
    private func overdueLabel(for task: ProjectTask) -> String {
        guard let end = task.endDate else { return "Overdue" }
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: end),
            to: cal.startOfDay(for: Date())
        ).day ?? 0
        return days >= 1 ? "\(days)d overdue" : "Overdue"
    }
}
