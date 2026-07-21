//
//  TaskCompletionReviewView.swift
//  OPS
//
//  Full-screen Tinder-style task completion review.
//  Allows completing, skipping, rescheduling, or cancelling tasks.
//

import SwiftUI
import SwiftData

struct TaskCompletionReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.wizardStateManager) private var wizardStateManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var permissionStore: PermissionStore
    @EnvironmentObject var dataController: DataController

    @State private var session: TaskReviewSession
    @State private var showBio: Bool = false
    @State private var selectedTask: ProjectTask? = nil
    @State private var showRescheduleSheet: Bool = false
    @State private var pendingRescheduleTask: ProjectTask? = nil
    @State private var showCancelConfirmation: Bool = false
    @State private var pendingCancelTask: ProjectTask? = nil
    @State private var showAllDone: Bool = false
    @State private var celebrationScale: CGFloat = 0
    @State private var celebrationOpacity: Double = 0

    /// Screen-level gate for the swipe-up "Reschedule" affordance and legend hint:
    /// true when the user holds any calendar.edit grant. The actual reschedule is
    /// gated per-task in `handleSwipe` (own-scope → only the user's own tasks).
    private var hasCalendarAccess: Bool {
        permissionStore.canEditAnySchedule
    }

    init(tasks: [ProjectTask]) {
        _session = State(initialValue: TaskReviewSession(tasks: tasks))
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            // Full-bleed card stack when actively reviewing
            if !session.tasks.isEmpty && !showAllDone {
                TaskReviewCardStack(
                    tasks: session.tasks,
                    hasCalendarAccess: hasCalendarAccess,
                    onSwipe: handleSwipe,
                    onTapCard: { task in
                        selectedTask = task
                        showBio = true
                    }
                )
                .ignoresSafeArea()
            }

            // UI overlay
            VStack(spacing: 0) {
                header
                    .padding(.top, OPSStyle.Layout.spacing2)

                if session.tasks.isEmpty {
                    emptyStateView
                } else if showAllDone {
                    allDoneView
                } else {
                    Spacer()

                    // Counter
                    Text("\(session.reviewedCount) OF \(session.totalCount) REVIEWED")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                        .padding(.bottom, OPSStyle.Layout.spacing2)

                    directionHints
                        .padding(.bottom, OPSStyle.Layout.spacing2)
                        .ignoresSafeArea(.container, edges: .bottom)
                        .wizardTarget("task_free_review", style: .row)
                }
            }
        }
        .sheet(isPresented: $showBio) {
            if let task = selectedTask {
                TaskBioSheet(
                    task: task,
                    onDismiss: { showBio = false }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showRescheduleSheet, onDismiss: {
            finishPendingReschedule()
        }) {
            if let task = pendingRescheduleTask {
                TaskRescheduleSheet(
                    task: task,
                    onRescheduled: {
                        finishPendingReschedule()
                    },
                    onDismiss: {
                        finishPendingReschedule()
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .alert("Cancel Task?", isPresented: $showCancelConfirmation) {
            Button("Keep Task", role: .cancel) {
                // User chose not to cancel — count as reviewed
                if let task = pendingCancelTask {
                    pendingCancelTask = nil
                    finishReview(task)
                }
            }
            Button("Cancel Task", role: .destructive) {
                if let task = pendingCancelTask {
                    cancelTask(task)
                    pendingCancelTask = nil
                    finishReview(task)
                }
            }
        } message: {
            Text("This will cancel the task. You can reactivate it later if needed.")
        }
        .onAppear {
            // Wizard system: notify task review opened
            NotificationCenter.default.post(
                name: Notification.Name("WizardTaskReviewOpened"),
                object: nil
            )
            // Evaluate prerequisites on appear for the first swipe step
            wizardStateManager?.evaluateStepPrerequisites(
                taskReviewCardCount: session.remainingCount
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardEvaluatePrerequisites"))) { _ in
            // Re-evaluate with current remaining card count.
            // Handles auto-skip for: swipe steps when cards run out, swipe-up without calendar.edit.
            wizardStateManager?.evaluateStepPrerequisites(
                taskReviewCardCount: session.remainingCount
            )
        }
        .onDisappear {
            // Wizard system: notify task review dismissed (step 5 completion)
            NotificationCenter.default.post(
                name: Notification.Name("WizardTaskReviewDismissed"),
                object: nil
            )
            // Wizard system: notify screen dismissed (exit prompt trigger).
            // Delay so step completion notifications process first — mirrors
            // the FABMenu and TeamInvite patterns.
            DispatchQueue.main.asyncAfter(deadline: .now() + OPSStyle.Animation.durationHover) {
                NotificationCenter.default.post(
                    name: Notification.Name("WizardScreenDismissed"),
                    object: nil,
                    userInfo: ["screen": "TaskReview"]
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("TASK REVIEW")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                if !session.tasks.isEmpty {
                    Text("\(session.totalCount) TASK\(session.totalCount == 1 ? "" : "S")")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Direction Hints

    private var directionHints: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            hintPill(icon: "arrow.left", label: "SKIP", color: OPSStyle.Colors.tertiaryText)
            hintPill(icon: "arrow.right", label: "COMPLETE", color: OPSStyle.Colors.successStatus)
            if hasCalendarAccess {
                hintPill(icon: "arrow.up", label: "RESCHEDULE", color: OPSStyle.Colors.primaryAccent)
            }
            hintPill(icon: "arrow.down", label: "CANCEL", color: OPSStyle.Colors.errorStatus)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func hintPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
        }
        .foregroundColor(color)
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .padding(.vertical, OPSStyle.Layout.spacing1)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()

            Text("NO TASKS TO REVIEW")
                .font(OPSStyle.Typography.headingLarge)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("All tasks are up to date")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Spacer()

            Button(action: { dismiss() }) {
                HStack {
                    Text("DONE")
                        .font(OPSStyle.Typography.button)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                }
                .foregroundColor(OPSStyle.Colors.invertedText)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetStandard)
                .background(OPSStyle.Colors.primaryText)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    // MARK: - All Done

    private var allDoneView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()

            // Icon with accent ring
            ZStack {
                Circle()
                    .stroke(OPSStyle.Colors.successStatus.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 140, height: 140)
                    .scaleEffect(celebrationScale)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(OPSStyle.Colors.successStatus)
                    .scaleEffect(celebrationScale)
            }

            Text("ALL CAUGHT UP")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .opacity(celebrationOpacity)

            Text("All tasks have been reviewed")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .opacity(celebrationOpacity)

            Spacer()

            Button(action: { dismiss() }) {
                HStack {
                    Text("DONE")
                        .font(OPSStyle.Typography.button)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                }
                .foregroundColor(OPSStyle.Colors.invertedText)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetStandard)
                .background(OPSStyle.Colors.primaryText)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
            .opacity(celebrationOpacity)
        }
        .onAppear {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            withAnimation(celebrationScaleAnimation) {
                celebrationScale = 1.0
            }
            withAnimation(celebrationOpacityAnimation) {
                celebrationOpacity = 1.0
            }
        }
    }

    // MARK: - Motion (spec: one curve, no spring; reduce-motion → near-instant)

    private var celebrationScaleAnimation: Animation {
        reduceMotion
            ? OPSStyle.Animation.hover
            : OPSStyle.Animation.flip
    }

    private var celebrationOpacityAnimation: Animation {
        OPSStyle.Animation.panel.delay(OPSStyle.Animation.durationStagger)
    }

    private var allDoneTransitionAnimation: Animation {
        reduceMotion
            ? OPSStyle.Animation.hover.delay(OPSStyle.Animation.durationStagger)
            : OPSStyle.Animation.page.delay(OPSStyle.Animation.durationStagger)
    }

    // MARK: - Swipe Handlers

    private func handleSwipe(_ task: ProjectTask, _ direction: SwipeDirection) {
        switch direction {
        case .right:
            // Complete via the canonical path (saves, records a SyncOperation,
            // pushes). Mirrors UnscheduledTaskReviewView.markTaskComplete: a
            // realtime-race guard so a task already completed elsewhere doesn't
            // re-fire the team notification storm, and a RETRY toast on failure
            // instead of silently leaving the task active to reappear next time.
            completeTask(task)
            finishReview(task, wizardNotification: "WizardTaskSwipedRight")
        case .left:
            // Skip — no changes
            finishReview(task, wizardNotification: "WizardTaskSwipedLeft")
        case .up:
            // Reschedule — gated per-task on calendar.edit (own-scope users may
            // reschedule only their own tasks). A swipe-up on a task the user
            // can't reschedule falls through to a no-op skip.
            guard task.canEditSchedule else {
                finishReview(task, wizardNotification: "WizardTaskSwipedLeft")
                return
            }
            // WizardTaskSwipedUp is deferred to the reschedule sheet callbacks
            // so the wizard doesn't advance while the sheet is still visible.
            pendingRescheduleTask = task
            showRescheduleSheet = true
        case .down:
            // Cancel — show confirmation
            pendingCancelTask = task
            showCancelConfirmation = true
        }
    }

    private func finishPendingReschedule() {
        guard let task = pendingRescheduleTask else { return }
        pendingRescheduleTask = nil
        finishReview(task, wizardNotification: "WizardTaskSwipedUp")
    }

    private func finishReview(_ task: ProjectTask, wizardNotification: String? = nil) {
        guard session.markReviewed(taskID: task.id) else { return }
        let remainingCount = session.remainingCount

        if let wizardNotification {
            NotificationCenter.default.post(
                name: Notification.Name(wizardNotification),
                object: nil
            )
        }

        // Let a matching completion notification advance first, then evaluate
        // the new step. If the operator used a different direction, this still
        // skips an impossible swipe step when the final card is gone.
        DispatchQueue.main.async {
            wizardStateManager?.evaluateStepPrerequisites(
                taskReviewCardCount: remainingCount
            )
        }

        checkCompletion()
    }

    /// Complete a task via the canonical DataController path with the same
    /// rigor as `UnscheduledTaskReviewView.markTaskComplete`: a realtime-race
    /// guard (bug adc0feb3) so a task already completed on another device
    /// doesn't re-emit the team notification/push/analytics storm, the success
    /// haptic deferred until the write actually resolves, and a persistent
    /// RETRY toast on failure so a swipe that didn't persist isn't silently
    /// counted as done (it would otherwise reappear in the next review stack
    /// with no explanation).
    private func completeTask(_ task: ProjectTask) {
        if task.status == .completed {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            ToastCenter.shared.present(Feedback.Task.alreadyComplete(task.displayTitle))
            return
        }
        Task {
            do {
                try await dataController.updateTaskStatus(task: task, to: .completed)
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    ToastCenter.shared.present(Feedback.Task.completed)
                }
            } catch {
                print("[TASK_REVIEW] Failed to complete task: \(error)")
                let capturedTask = task
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    ToastCenter.shared.present(
                        Toast(
                            label: "// COULDN'T MARK COMPLETE — TRY AGAIN",
                            tone: .error,
                            autoDismissAfter: 0,
                            action: ToastAction(label: "RETRY") {
                                completeTask(capturedTask)
                            }
                        )
                    )
                }
            }
        }
    }

    /// Cancel a task via the canonical path with a RETRY toast on failure —
    /// the cancel confirmation already advanced the queue, so without feedback
    /// a failed cancel would leave the task active with no explanation (same
    /// gap the complete path had).
    private func cancelTask(_ task: ProjectTask) {
        Task {
            do {
                try await dataController.updateTaskStatus(task: task, to: .cancelled)
            } catch {
                print("[TASK_REVIEW] Failed to cancel task: \(error)")
                let capturedTask = task
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    ToastCenter.shared.present(
                        Toast(
                            label: "// COULDN'T CANCEL — TRY AGAIN",
                            tone: .error,
                            autoDismissAfter: 0,
                            action: ToastAction(label: "RETRY") {
                                cancelTask(capturedTask)
                            }
                        )
                    )
                }
            }
        }
    }

    private func checkCompletion() {
        if session.isComplete {
            withAnimation(allDoneTransitionAnimation) {
                showAllDone = true
            }
        }
    }
}
