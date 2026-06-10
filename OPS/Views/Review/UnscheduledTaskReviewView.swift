//
//  UnscheduledTaskReviewView.swift
//  OPS
//
//  Full-screen Tinder-style review for tasks that are unscheduled or unassigned.
//  Actions adapt based on task state:
//  - Unassigned: right = assign crew (must assign before scheduling), up = assign crew
//  - Unscheduled (assigned): right = auto-schedule, up = mark complete
//  - Left = skip, Down = cancel
//

import SwiftUI
import SwiftData

struct UnscheduledTaskReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var dataController: DataController

    let tasks: [ProjectTask]

    @State private var reviewedCount: Int = 0
    @State private var currentTopIndex: Int = 0
    @State private var showBio: Bool = false
    @State private var selectedTask: ProjectTask? = nil
    @State private var showCancelConfirmation: Bool = false
    @State private var pendingCancelTask: ProjectTask? = nil
    @State private var showCrewPicker: Bool = false
    @State private var pendingAssignTask: ProjectTask? = nil
    @State private var assignPickerCountsAsReview: Bool = true
    @State private var manualScheduleTask: ProjectTask? = nil
    @State private var assignSelectedIds: Set<String> = []
    /// Bug 040e4482 — true only after the operator explicitly taps DONE in
    /// the crew picker. Drag-to-dismiss leaves this false so we treat the
    /// gesture as a back-out instead of silently applying whatever rows the
    /// operator was tapping through.
    @State private var pickerDidConfirm: Bool = false
    @State private var showAllDone: Bool = false
    @State private var celebrationScale: CGFloat = 0
    @State private var celebrationOpacity: Double = 0
    /// Full User objects so the crew picker shows real profile photos.
    @State private var fetchedTeamMembers: [User] = []

    // Transient confirmation banner so swipes have visible effect
    // (previously auto-schedule and mark-complete fired silently).
    @State private var toastMessage: String? = nil
    @State private var toastKind: ToastKind = .success
    @State private var toastDismissTask: Task<Void, Never>? = nil
    /// Bug e90acdaf — when mark-complete or auto-schedule fails, the card
    /// has already left the stack. Holding the failed task + action here
    /// powers the RETRY button on the persistent error toast so the
    /// operator has an in-flow recovery path instead of being told to
    /// "try again" with no surface to do so.
    @State private var retryContext: RetryContext? = nil
    @State private var retryInFlight: Bool = false

    private enum ToastKind {
        case success
        case error
    }

    private enum RetryAction {
        case autoSchedule
        case assignCrew
        case manualSchedule
        case markComplete
    }

    private struct RetryContext {
        let task: ProjectTask
        let action: RetryAction
    }

    private var activeTeamMembers: [User] {
        var seen = Set<String>()
        return fetchedTeamMembers.filter { member in
            guard !seen.contains(member.id) else { return false }
            seen.insert(member.id)
            return true
        }
    }

    /// Bug f3a3d66d — order the supplied member list by recency-for-task-
    /// type when a task type is known, otherwise fall back to the
    /// alphabetical order already provided. Mirrors
    /// `ProjectFormSheet.teamUsersOrdered` so the two pickers feel
    /// consistent. Accepts an explicit member list so callers can opt
    /// between the .onAppear snapshot and a fresh fetch.
    private func teamUsersOrdered(forTaskTypeId taskTypeId: String, members: [User]) -> [User] {
        let alphaSorted = members

        guard !taskTypeId.isEmpty,
              let companyId = dataController.currentUser?.companyId else {
            return alphaSorted
        }

        let recentIds = dataController.recentTeamMemberIds(
            forTaskType: taskTypeId,
            companyId: companyId
        )
        guard !recentIds.isEmpty else { return alphaSorted }

        let recencyIndex = Dictionary(
            uniqueKeysWithValues: recentIds.enumerated().map { ($1, $0) }
        )
        let recentSet = Set(recentIds)
        let recentTier = alphaSorted
            .filter { recentSet.contains($0.id) }
            .sorted { lhs, rhs in
                (recencyIndex[lhs.id] ?? Int.max) < (recencyIndex[rhs.id] ?? Int.max)
            }
        let restTier = alphaSorted.filter { !recentSet.contains($0.id) }
        return recentTier + restTier
    }

    /// The task currently on top of the card stack
    private var currentTask: ProjectTask? {
        guard currentTopIndex < tasks.count else { return nil }
        return tasks[currentTopIndex]
    }

    /// Whether the current top task is unassigned
    private var currentTaskIsUnassigned: Bool {
        currentTask?.getTeamMemberIds().isEmpty ?? true
    }

    private func openCrewPicker(
        for task: ProjectTask,
        selectedIds: Set<String>,
        countsAsReview: Bool
    ) {
        pendingAssignTask = task
        assignSelectedIds = selectedIds
        assignPickerCountsAsReview = countsAsReview
        pickerDidConfirm = false
        showCrewPicker = true
    }

    private func retryAction(for recoveryAction: AutoScheduleFailureRecoveryAction?) -> RetryAction {
        switch recoveryAction {
        case .assignCrew:
            return .assignCrew
        case .manualSchedule, .none:
            return .manualSchedule
        }
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            // Full-bleed card stack
            if !tasks.isEmpty && !showAllDone {
                TaskReviewCardStack(
                    tasks: tasks,
                    // Swipe-to-schedule is gated on calendar.edit (any grant shows
                    // the affordance; the schedule mutations are gated per-task).
                    // Crew / Unassigned (no grant) review without a schedule swipe.
                    hasCalendarAccess: PermissionStore.shared.canEditAnySchedule,
                    onSwipe: handleSwipe,
                    onTapCard: { task in
                        selectedTask = task
                        showBio = true
                    },
                    taskActionConfigProvider: { task, direction in
                        configForTask(task, direction: direction)
                    },
                    blockedDirections: [],
                    badgeProvider: { task in
                        let isUnscheduled = task.startDate == nil
                        let isUnassigned = task.getTeamMemberIds().isEmpty
                        if isUnscheduled && isUnassigned {
                            return ("UNSCHEDULED & UNASSIGNED", OPSStyle.Colors.errorStatus)
                        } else if isUnscheduled {
                            return ("UNSCHEDULED", OPSStyle.Colors.warningStatus)
                        } else {
                            return ("UNASSIGNED", OPSStyle.Colors.warningStatus)
                        }
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

                    // Respect the bottom safe area so the hint pills sit
                    // above the home indicator on notched devices instead
                    // of overlapping it. The card stack underneath still
                    // bleeds full-screen via its own ignoresSafeArea.
                    directionHints
                        .padding(.bottom, 8)
                }
            }

            // Confirmation banner (success/error) sits above card stack
            toastOverlay
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
        .sheet(isPresented: $showCrewPicker, onDismiss: {
            handleCrewPickerDismiss()
        }) {
            // Bug f3a3d66d — order the picker by "recent for this task
            // type" before falling back to alphabetical, so the operator
            // sees the people they routinely assign to demo / framing /
            // punchlist (etc.) at the top instead of having to scroll.
            //
            // Bug 040e4482 — pull a fresh team-member list every time the
            // picker presents instead of trusting the .onAppear snapshot.
            // Realtime sync can add (or deactivate) members while the
            // review is open, and a stale list silently hides them from
            // the operator.
            let taskTypeId = pendingAssignTask?.taskTypeId ?? ""
            let liveTeamMembers: [User] = {
                guard let companyId = dataController.currentUser?.companyId else {
                    return activeTeamMembers
                }
                return dataController.getTeamMembers(companyId: companyId)
                    .sorted { $0.fullName < $1.fullName }
            }()
            let ordered = teamUsersOrdered(forTaskTypeId: taskTypeId, members: liveTeamMembers)
            let recentIds: Set<String> = {
                guard !taskTypeId.isEmpty,
                      let companyId = dataController.currentUser?.companyId else {
                    return []
                }
                return Set(dataController.recentTeamMemberIds(
                    forTaskType: taskTypeId,
                    companyId: companyId
                ))
            }()

            TeamMemberPickerSheet(
                selectedTeamMemberIds: $assignSelectedIds,
                allTeamMembers: ordered,
                recentMemberIds: recentIds,
                onConfirm: { pickerDidConfirm = true }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $manualScheduleTask) { task in
            CalendarSchedulerSheet(
                isPresented: Binding(
                    get: { manualScheduleTask != nil },
                    set: { if !$0 { manualScheduleTask = nil } }
                ),
                itemType: .task(task),
                currentStartDate: task.startDate,
                currentEndDate: task.endDate,
                onScheduleUpdate: { start, end in
                    manuallySchedule(task, startDate: start, endDate: end)
                },
                onClearDates: nil,
                preselectedTeamMemberIds: Set(task.getTeamMemberIds())
            )
            .environmentObject(dataController)
        }
        .alert("Cancel Task?", isPresented: $showCancelConfirmation) {
            Button("Keep Task", role: .cancel) {
                reviewedCount += 1
                pendingCancelTask = nil
                checkCompletion()
            }
            Button("Cancel Task", role: .destructive) {
                if let task = pendingCancelTask {
                    // Canonical path — saves, records SyncOperation, pushes.
                    Task {
                        do {
                            try await dataController.updateTaskStatus(task: task, to: .cancelled)
                        } catch {
                            print("[UNSCHEDULED_REVIEW] Failed to cancel task: \(error)")
                        }
                    }
                }
                reviewedCount += 1
                pendingCancelTask = nil
                checkCompletion()
            }
        } message: {
            Text("This will cancel the task. You can reactivate it later if needed.")
        }
        .onAppear {
            // Fetch team members as full User objects so the crew picker shows
            // real profile photos (UserAvatar needs profileImageData /
            // profileImageURL / userColor — none of which the lightweight
            // TeamMember projection carried). The picker also re-fetches on
            // present (bug 040e4482) so this snapshot is just the warm
            // start.
            if let companyId = dataController.currentUser?.companyId {
                fetchedTeamMembers = dataController.getTeamMembers(companyId: companyId)
                    .sorted { $0.fullName < $1.fullName }
            }
        }
        .onDisappear {
            // Tear down the in-flight toast-dismiss Task so it doesn't outlive
            // the view and write to stale @State after the user has closed
            // the review.
            toastDismissTask?.cancel()
            toastDismissTask = nil
        }
    }

    // MARK: - Per-Task Config

    /// Returns the appropriate stamp config based on task state
    private func configForTask(_ task: ProjectTask, direction: SwipeDirection) -> SwipeActionConfig {
        let isUnassigned = task.getTeamMemberIds().isEmpty

        switch direction {
        case .right:
            if isUnassigned {
                // Must assign crew first
                return SwipeActionConfig(label: "ASSIGN CREW", icon: "person.badge.plus", color: OPSStyle.Colors.primaryAccent)
            } else {
                // Already assigned — can auto-schedule
                return SwipeActionConfig(label: "AUTO SCHEDULE", icon: "calendar.badge.plus", color: OPSStyle.Colors.successStatus)
            }
        case .left:
            return SwipeActionConfig(label: "SKIP", icon: "arrow.right.circle", color: OPSStyle.Colors.tertiaryText)
        case .up:
            if isUnassigned {
                // No crew yet — can't complete; assign first.
                return SwipeActionConfig(label: "ASSIGN CREW", icon: "person.badge.plus", color: OPSStyle.Colors.primaryAccent)
            } else {
                // Already assigned — swipe up marks the work done.
                return SwipeActionConfig(label: "MARK COMPLETE", icon: "checkmark.circle", color: OPSStyle.Colors.successStatus)
            }
        case .down:
            return SwipeActionConfig(label: "CANCEL", icon: "xmark.circle", color: OPSStyle.Colors.errorStatus)
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
                Text("UNASSIGNED REVIEW")
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

    // MARK: - Direction Hints (context-dependent)

    private var directionHints: some View {
        HStack(spacing: 12) {
            hintPill(icon: "arrow.left", label: "SKIP", color: OPSStyle.Colors.tertiaryText)

            // Right hint changes based on current card
            if currentTaskIsUnassigned {
                hintPill(icon: "arrow.right", label: "ASSIGN", color: OPSStyle.Colors.primaryAccent)
            } else {
                hintPill(icon: "arrow.right", label: "SCHEDULE", color: OPSStyle.Colors.successStatus)
            }

            // Up hint changes based on current card
            if currentTaskIsUnassigned {
                hintPill(icon: "arrow.up", label: "ASSIGN", color: OPSStyle.Colors.primaryAccent)
            } else {
                hintPill(icon: "arrow.up", label: "COMPLETE", color: OPSStyle.Colors.successStatus)
            }

            hintPill(icon: "arrow.down", label: "CANCEL", color: OPSStyle.Colors.errorStatus)
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: currentTopIndex)
    }

    // MARK: - Toast Overlay

    @ViewBuilder
    private var toastOverlay: some View {
        VStack {
            if let message = toastMessage {
                HStack(spacing: 10) {
                    Image(systemName: toastKind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(toastKind == .success ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                    Text(message)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if retryContext != nil {
                        Button(action: performRetry) {
                            Text(toastActionLabel)
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(OPSStyle.Colors.errorStatus.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .strokeBorder(OPSStyle.Colors.errorStatus.opacity(0.45), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(retryInFlight)
                        .opacity(retryInFlight ? 0.5 : 1)
                        .accessibilityLabel(toastActionAccessibilityLabel)

                        Button(action: dismissToast) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(OPSStyle.Colors.cardBackground.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .contentShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .strokeBorder((toastKind == .success ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus).opacity(0.35), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 10, y: 4)
                .padding(.horizontal, 16)
                .padding(.top, 68)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        // Hits pass through to the card stack unless the retry toast is up —
        // we don't want a transient success toast eating swipe gestures. The
        // pill's contentShape keeps hits inside the rounded rectangle even
        // when retry buttons widen it.
        .allowsHitTesting(retryContext != nil)
        .animation(toastAnimation, value: toastMessage)
    }

    private var toastActionLabel: String {
        guard let context = retryContext else { return "RETRY" }
        switch context.action {
        case .autoSchedule, .markComplete:
            return "RETRY"
        case .assignCrew:
            return "ASSIGN CREW"
        case .manualSchedule:
            return "SCHEDULE"
        }
    }

    private var toastActionAccessibilityLabel: String {
        guard let context = retryContext else { return "Retry failed action" }
        switch context.action {
        case .autoSchedule, .markComplete:
            return "Retry failed action"
        case .assignCrew:
            return "Assign crew"
        case .manualSchedule:
            return "Schedule manually"
        }
    }

    private var toastAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.35, dampingFraction: 0.82)
    }

    private func showToast(_ message: String, kind: ToastKind, retry: RetryContext? = nil) {
        toastDismissTask?.cancel()
        toastMessage = message
        toastKind = kind
        retryContext = retry
        retryInFlight = false

        // Bug e90acdaf — error toasts that carry a RETRY action persist until
        // the operator acts on them; the failed task may already be several
        // cards behind the current top so we can't trust a 2.6s fuse. Plain
        // errors still auto-dismiss, but on a longer fuse than successes so
        // the operator has time to read the failure reason.
        let lifetimeNanoseconds: UInt64? = {
            if retry != nil { return nil }
            if kind == .error { return 6_000_000_000 }
            return 2_600_000_000
        }()

        guard let nanos = lifetimeNanoseconds else { return }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            toastMessage = nil
            retryContext = nil
        }
    }

    private func performRetry() {
        guard let ctx = retryContext, !retryInFlight else { return }
        retryInFlight = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Clear the failed-action toast immediately. The retried action shows
        // its own result toast; leaving the previous "TRY AGAIN" message up
        // while the retry is in flight would conflict with whatever lands
        // a moment later.
        toastDismissTask?.cancel()
        toastMessage = nil
        let captured = ctx
        retryContext = nil

        switch captured.action {
        case .autoSchedule: autoScheduleTask(captured.task)
        case .assignCrew:
            openCrewPicker(
                for: captured.task,
                selectedIds: Set(captured.task.getTeamMemberIds()),
                countsAsReview: false
            )
        case .manualSchedule: manualScheduleTask = captured.task
        case .markComplete: markTaskComplete(captured.task)
        }
        retryInFlight = false
    }

    private func dismissToast() {
        toastDismissTask?.cancel()
        toastMessage = nil
        retryContext = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func formatScheduledRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        let startStr = formatter.string(from: start).uppercased()
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return "FOR \(startStr)"
        }
        let endStr = formatter.string(from: end).uppercased()
        return "FOR \(startStr) – \(endStr)"
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

            Text("All tasks are scheduled and assigned")
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

            // Crisp ease-out scale for reduce-motion users; the spring keeps
            // the original celebratory snap for everyone else. The opacity
            // fade is gentle in both modes so the text "lands" with the
            // visual rather than ahead of it.
            let scaleAnimation: Animation = reduceMotion
                ? .easeOut(duration: 0.25)
                : .spring(response: 0.5, dampingFraction: 0.6)
            withAnimation(scaleAnimation) {
                celebrationScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                celebrationOpacity = 1.0
            }
        }
    }

    // MARK: - Swipe Handlers

    private func handleSwipe(_ task: ProjectTask, _ direction: SwipeDirection) {
        currentTopIndex += 1

        switch direction {
        case .right:
            let isUnassigned = task.getTeamMemberIds().isEmpty
            if isUnassigned {
                // Task has no crew — open picker, then auto-schedule after assignment
                openCrewPicker(for: task, selectedIds: [], countsAsReview: true)
            } else {
                // Already assigned — auto-schedule immediately
                autoScheduleTask(task)
                reviewedCount += 1
                checkCompletion()
            }

        case .left:
            // Skip — no changes
            reviewedCount += 1
            checkCompletion()

        case .up:
            let isUnassigned = task.getTeamMemberIds().isEmpty
            if isUnassigned {
                // No crew yet — open picker so user can assign. After the
                // picker resolves, the dismiss handler auto-schedules the
                // task so the operator's "resolve this card" intent is
                // honored end-to-end instead of leaving the task assigned
                // but still unscheduled.
                openCrewPicker(
                    for: task,
                    selectedIds: Set(task.getTeamMemberIds()),
                    countsAsReview: true
                )
            } else {
                // Assigned — mark complete via canonical path.
                markTaskComplete(task)
                reviewedCount += 1
                checkCompletion()
            }

        case .down:
            // Cancel — show confirmation
            pendingCancelTask = task
            showCancelConfirmation = true
        }
    }

    /// Called when crew picker is dismissed
    private func handleCrewPickerDismiss() {
        guard let task = pendingAssignTask else { return }
        let countsAsReview = assignPickerCountsAsReview

        // Bug 040e4482 — only commit the picker selections when the operator
        // explicitly tapped DONE. Drag-to-dismiss is a back-out gesture; the
        // ephemeral row taps the user made while exploring should not turn
        // into a silent crew assignment + auto-schedule. Swipe-opened
        // pickers still count the card as reviewed; retry-opened pickers
        // keep the original review count intact.
        let confirmed = pickerDidConfirm
        let selectionsToApply = confirmed ? assignSelectedIds : Set<String>()

        if !selectionsToApply.isEmpty {
            // Apply crew assignment, then auto-schedule when the task still
            // has no dates. The card has been bumped from the review stack
            // either way — the operator's intent is "resolve this," so we
            // finish the job rather than leaving the task assigned but
            // still unscheduled.
            let shouldAutoSchedule = task.startDate == nil
            Task {
                try? await dataController.updateTaskTeamMembers(
                    task: task,
                    memberIds: Array(selectionsToApply)
                )

                if shouldAutoSchedule {
                    await MainActor.run {
                        autoScheduleTask(task)
                    }
                }
            }
        } else if confirmed {
            // Operator hit DONE with no selections — explicit no-op. Surface
            // a toast so the swipe has a visible effect instead of feeling
            // like the gesture was swallowed.
            showToast(
                "NO CREW SELECTED — TASK LEFT UNASSIGNED",
                kind: .error,
                retry: countsAsReview ? nil : RetryContext(task: task, action: .assignCrew)
            )
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        } else if !countsAsReview {
            showToast(
                "CREW MISSING — ASSIGN CREW",
                kind: .error,
                retry: RetryContext(task: task, action: .assignCrew)
            )
        }

        if countsAsReview {
            reviewedCount += 1
        }
        pendingAssignTask = nil
        assignPickerCountsAsReview = true
        assignSelectedIds = []
        pickerDidConfirm = false
        if countsAsReview {
            checkCompletion()
        }
    }

    private func markTaskComplete(_ task: ProjectTask) {
        // Canonical path — persists status, records SyncOperation, fires
        // team-completion notifications, tracks analytics. Haptic semantics
        // demand the success notification fire only after the write
        // actually succeeds; an optimistic success buzz followed by an
        // error toast is worse than no buzz at all.
        let taskTitle = task.displayTitle

        // Bug adc0feb3 — realtime sync may have completed this task between
        // the operator opening the review and swiping the card. Skip the
        // canonical path entirely; firing it again would re-emit team
        // notifications, push, and analytics for a state change that didn't
        // actually happen on this device.
        if task.status == .completed {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showToast("ALREADY COMPLETE — \(taskTitle.uppercased())", kind: .success)
            return
        }

        Task {
            do {
                try await dataController.updateTaskStatus(task: task, to: .completed)
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showToast("COMPLETED — \(taskTitle.uppercased())", kind: .success)
                }
            } catch {
                print("[UNSCHEDULED_REVIEW] Failed to mark task complete: \(error)")
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    showToast(
                        "COULDN'T MARK COMPLETE — TRY AGAIN",
                        kind: .error,
                        retry: RetryContext(task: task, action: .markComplete)
                    )
                }
            }
        }
    }

    private func autoScheduleTask(_ task: ProjectTask) {
        guard task.canEditSchedule else { return }
        // Bug adc0feb3 — realtime sync can land a schedule on the task
        // between the operator opening this review and swiping the card.
        // Re-running the scheduler here would overwrite the dates that
        // just arrived (the operator never saw them). Treat the swipe as
        // a confirm of the already-applied schedule instead.
        if let existingStart = task.startDate, let existingEnd = task.endDate {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showToast(
                "ALREADY SCHEDULED \(formatScheduledRange(start: existingStart, end: existingEnd))",
                kind: .success
            )
            return
        }

        let plan = dataController.autoScheduleSingleTask(
            task,
            teamMemberIds: Set(task.getTeamMemberIds()),
            anchorDate: Date()
        )

        // If the scheduler couldn't place the task, keep the recovery in-flow
        // instead of leaving the operator with a dead-end error toast.
        guard let placement = plan.placements.first else {
            let recoveryAction = retryAction(
                for: AutoScheduleFailureRecovery.recoveryAction(for: plan)
            )
            showToast(
                AutoScheduleFailureRecovery.message(for: plan),
                kind: .error,
                retry: RetryContext(task: task, action: recoveryAction)
            )
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        let capturedStart = placement.startDate
        let capturedEnd = placement.endDate

        // Canonical path — saves context, computes duration, records the
        // SyncOperation, and fires schedule-change notifications to team
        // members. Haptic fires after the write so the buzz reflects what
        // actually happened, not what we hoped would happen.
        Task {
            do {
                try await dataController.updateTaskSchedule(
                    task: task,
                    startDate: capturedStart,
                    endDate: capturedEnd
                )
                await MainActor.run {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showToast(
                        "SCHEDULED \(formatScheduledRange(start: capturedStart, end: capturedEnd))",
                        kind: .success
                    )
                }
            } catch {
                print("[UNSCHEDULED_REVIEW] Failed to auto-schedule task: \(error)")
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    showToast(
                        "SCHEDULE FAILED — TRY AGAIN",
                        kind: .error,
                        retry: RetryContext(task: task, action: .autoSchedule)
                    )
                }
            }
        }
    }

    private func manuallySchedule(_ task: ProjectTask, startDate: Date, endDate: Date) {
        guard task.canEditSchedule else { return }
        Task {
            do {
                try await dataController.updateTaskSchedule(
                    task: task,
                    startDate: startDate,
                    endDate: endDate
                )
                await MainActor.run {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showToast(
                        "SCHEDULED \(formatScheduledRange(start: startDate, end: endDate))",
                        kind: .success
                    )
                }
            } catch {
                print("[UNSCHEDULED_REVIEW] Failed to manually schedule task: \(error)")
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    showToast(
                        "SCHEDULE FAILED — TRY AGAIN",
                        kind: .error,
                        retry: RetryContext(task: task, action: .manualSchedule)
                    )
                }
            }
        }
    }

    private func checkCompletion() {
        if reviewedCount >= tasks.count {
            let transition: Animation = reduceMotion
                ? .easeInOut(duration: 0.25).delay(0.3)
                : .spring().delay(0.3)
            withAnimation(transition) {
                showAllDone = true
            }
        }
    }
}
