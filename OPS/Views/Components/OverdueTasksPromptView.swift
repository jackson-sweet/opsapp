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

enum OverdueReviewPresentation {
    static let failureLabel = "// COULD NOT MARK DONE"

    static func actionLabel(hasError: Bool) -> String {
        hasError ? "TRY AGAIN" : "MARK DONE"
    }

    static func stacksAction(for dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    static func isReviewComplete(
        visibleTaskCount: Int,
        pendingCompletionCount: Int
    ) -> Bool {
        visibleTaskCount == 0 && pendingCompletionCount == 0
    }
}

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
    @State private var completionErrors: [String: String] = [:]
    @State private var taskToOpen: ProjectTask?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    private var reviewComplete: Bool {
        OverdueReviewPresentation.isReviewComplete(
            visibleTaskCount: overdueTasks.count,
            pendingCompletionCount: completingTaskIds.count
        )
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
                    LazyVStack(spacing: 0) {
                        ForEach(Array(overdueTasks.enumerated()), id: \.element.id) { index, task in
                            overdueRow(task)
                                .transition(.opacity)

                            if index < overdueTasks.count - 1 {
                                Divider()
                                    .overlay(OPSStyle.Colors.cardBorder)
                                    .padding(.leading, OPSStyle.Layout.spacing3)
                            }
                        }
                    }
                    .glassSurface()
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
        .onAppear {
            if reviewComplete { dismiss() }
        }
        .onChange(of: reviewComplete) { _, complete in
            if complete { dismiss() }
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

    // MARK: - Recovery ledger

    private func overdueRow(_ task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Button {
                taskToOpen = task
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text(task.project?.title ?? "Project")
                            .font(OPSStyle.Typography.microLabel)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(task.displayTitle)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: OPSStyle.Layout.spacing2)

                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
            }
            .buttonStyle(.plain)

            if let error = completionErrors[task.id] {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(OverdueReviewPresentation.failureLabel)
                        .font(OPSStyle.Typography.microLabel)
                        .foregroundColor(OPSStyle.Colors.errorText)

                    Text(error)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if OverdueReviewPresentation.stacksAction(for: dynamicTypeSize) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    overdueMetadata(task)
                    completionButton(task, fillsWidth: true)
                }
            } else {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    overdueMetadata(task)
                    Spacer(minLength: OPSStyle.Layout.spacing2)
                    completionButton(task, fillsWidth: false)
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func overdueMetadata(_ task: ProjectTask) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Circle()
                .fill(OPSStyle.Colors.rose)
                .frame(width: OPSStyle.Layout.spacing2, height: OPSStyle.Layout.spacing2)

            Text(overdueLabel(for: task))
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.rose)
        }
    }

    private func completionButton(_ task: ProjectTask, fillsWidth: Bool) -> some View {
        let hasError = completionErrors[task.id] != nil
        return Button(action: { markDone(task) }) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Image(systemName: OPSStyle.Icons.checkmark)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .bold))
                Text(OverdueReviewPresentation.actionLabel(hasError: hasError))
                    .font(OPSStyle.Typography.captionBold)
            }
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(
                maxWidth: fillsWidth ? .infinity : nil,
                minHeight: OPSStyle.Layout.touchTargetMin,
                alignment: .center
            )
            .background(OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .strokeBorder(
                        OPSStyle.Colors.primaryAccent,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(OverdueReviewPresentation.actionLabel(hasError: hasError)): \(task.displayTitle)")
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
        completionErrors[task.id] = nil
        withAnimation(OPSStyle.Animation.standard) {
            _ = completingTaskIds.insert(task.id)
        }
        Task {
            do {
                try await dataController.updateTaskStatus(task: task, to: .completed)
                await MainActor.run {
                    completingTaskIds.remove(task.id)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                // Revert the optimistic removal so the operator can retry.
                await MainActor.run {
                    withAnimation(OPSStyle.Animation.standard) {
                        completingTaskIds.remove(task.id)
                    }
                    completionErrors[task.id] = "Task stayed open. Check your connection and try again."
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
