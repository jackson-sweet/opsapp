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
    @EnvironmentObject var permissionStore: PermissionStore

    let tasks: [ProjectTask]

    @State private var reviewedCount: Int = 0
    @State private var showBio: Bool = false
    @State private var selectedTask: ProjectTask? = nil
    @State private var showRescheduleSheet: Bool = false
    @State private var pendingRescheduleTask: ProjectTask? = nil
    @State private var showCancelConfirmation: Bool = false
    @State private var pendingCancelTask: ProjectTask? = nil
    @State private var showAllDone: Bool = false
    @State private var celebrationScale: CGFloat = 0
    @State private var celebrationOpacity: Double = 0

    private var hasCalendarAccess: Bool {
        permissionStore.can("calendar.edit")
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            // Full-bleed card stack when actively reviewing
            if !tasks.isEmpty && !showAllDone {
                TaskReviewCardStack(
                    tasks: tasks,
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
                    .padding(.top, 8)

                if tasks.isEmpty {
                    emptyStateView
                } else if showAllDone {
                    allDoneView
                } else {
                    Spacer()

                    // Counter
                    Text("\(reviewedCount) OF \(tasks.count) REVIEWED")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                        .padding(.bottom, 8)

                    directionHints
                        .padding(.bottom, 8)
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
        .sheet(isPresented: $showRescheduleSheet) {
            if let task = pendingRescheduleTask {
                TaskRescheduleSheet(
                    task: task,
                    onRescheduled: {
                        reviewedCount += 1
                        NotificationCenter.default.post(name: Notification.Name("WizardTaskSwipedUp"), object: nil)
                        checkCompletion()
                    },
                    onDismiss: {
                        // User dismissed without rescheduling — still count as reviewed
                        reviewedCount += 1
                        NotificationCenter.default.post(name: Notification.Name("WizardTaskSwipedUp"), object: nil)
                        checkCompletion()
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .alert("Cancel Task?", isPresented: $showCancelConfirmation) {
            Button("Keep Task", role: .cancel) {
                // User chose not to cancel — count as reviewed
                reviewedCount += 1
                pendingCancelTask = nil
                checkCompletion()
            }
            Button("Cancel Task", role: .destructive) {
                if let task = pendingCancelTask {
                    task.status = .cancelled
                    task.needsSync = true
                }
                reviewedCount += 1
                pendingCancelTask = nil
                checkCompletion()
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
                taskReviewCardCount: max(0, tasks.count - reviewedCount)
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardEvaluatePrerequisites"))) { _ in
            // Re-evaluate with current remaining card count.
            // Handles auto-skip for: swipe steps when cards run out, swipe-up without calendar.edit.
            wizardStateManager?.evaluateStepPrerequisites(
                taskReviewCardCount: max(0, tasks.count - reviewedCount)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
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
                if !tasks.isEmpty {
                    Text("\(tasks.count) TASK\(tasks.count == 1 ? "" : "S")")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Direction Hints

    private var directionHints: some View {
        HStack(spacing: 12) {
            hintPill(icon: "arrow.left", label: "SKIP", color: OPSStyle.Colors.tertiaryText)
            hintPill(icon: "arrow.right", label: "COMPLETE", color: OPSStyle.Colors.successStatus)
            if hasCalendarAccess {
                hintPill(icon: "arrow.up", label: "RESCHEDULE", color: OPSStyle.Colors.primaryAccent)
            }
            hintPill(icon: "arrow.down", label: "CANCEL", color: OPSStyle.Colors.errorStatus)
        }
        .padding(.horizontal, 16)
    }

    private func hintPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
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
                .padding(.horizontal, 20)
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
        VStack(spacing: 16) {
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
                .padding(.horizontal, 20)
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

            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                celebrationScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                celebrationOpacity = 1.0
            }
        }
    }

    // MARK: - Swipe Handlers

    private func handleSwipe(_ task: ProjectTask, _ direction: SwipeDirection) {
        reviewedCount += 1

        switch direction {
        case .right:
            // Complete
            task.status = .completed
            task.needsSync = true
            NotificationCenter.default.post(name: Notification.Name("WizardTaskSwipedRight"), object: nil)
        case .left:
            // Skip — no changes
            NotificationCenter.default.post(name: Notification.Name("WizardTaskSwipedLeft"), object: nil)
            break
        case .up:
            // Reschedule — decrement count, will re-increment on complete/dismiss.
            // WizardTaskSwipedUp is deferred to the reschedule sheet callbacks
            // so the wizard doesn't advance while the sheet is still visible.
            reviewedCount -= 1
            pendingRescheduleTask = task
            showRescheduleSheet = true
        case .down:
            // Cancel — show confirmation
            reviewedCount -= 1
            pendingCancelTask = task
            showCancelConfirmation = true
        }

        checkCompletion()
    }

    private func checkCompletion() {
        if reviewedCount >= tasks.count {
            withAnimation(.spring().delay(0.3)) {
                showAllDone = true
            }
        }
    }
}
