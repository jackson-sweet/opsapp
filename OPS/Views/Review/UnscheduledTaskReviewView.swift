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
    private let reviewRepository = UnscheduledReviewRepository()

    @State private var session: TaskReviewSession
    @State private var currentTopIndex: Int = 0
    @State private var showBio: Bool = false
    @State private var selectedTask: ProjectTask? = nil
    @State private var showCancelConfirmation: Bool = false
    @State private var pendingCancelTask: ProjectTask? = nil
    @State private var showCrewPicker: Bool = false
    @State private var pendingAssignTask: ProjectTask? = nil
    @State private var manualScheduleTask: ProjectTask? = nil
    @State private var assignSelectedIds: Set<String> = []
    @State private var assignmentBaselineIds: Set<String> = []
    @State private var pendingSwipeTaskID: String? = nil
    @State private var pendingSwipeResolution: ((Bool) -> Void)? = nil
    @State private var manualScheduleWriteInFlight: Bool = false
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

    private enum AutoScheduleOutcome {
        case succeeded
        case requiresManualSchedule
        case failed
        case denied
    }

    private var activeTeamMembers: [User] {
        var seen = Set<String>()
        return fetchedTeamMembers.filter { member in
            guard !seen.contains(member.id) else { return false }
            seen.insert(member.id)
            return true
        }
    }

    /// The task currently on top of the card stack
    private var currentTask: ProjectTask? {
        guard currentTopIndex < session.tasks.count else { return nil }
        return session.tasks[currentTopIndex]
    }

    init(tasks: [ProjectTask]) {
        _session = State(initialValue: TaskReviewSession(tasks: tasks))
    }

    /// Whether the current top task is unassigned
    private var currentTaskIsUnassigned: Bool {
        currentTask?.getTeamMemberIds().isEmpty ?? true
    }

    private func openCrewPicker(
        for task: ProjectTask,
        selectedIds: Set<String>,
        resolution: @escaping (Bool) -> Void
    ) {
        holdResolution(for: task, resolution: resolution)
        pendingAssignTask = task
        assignSelectedIds = selectedIds
        assignmentBaselineIds = Set(task.getTeamMemberIds())
        pickerDidConfirm = false
        showCrewPicker = true
    }

    private var reviewAccessPolicy: UnscheduledReviewAccessPolicy {
        UnscheduledReviewAccessPolicy(
            currentUserID: dataController.currentUser?.id,
            taskEditScope: ReviewPermissionScope(
                PermissionStore.shared.scope(for: "tasks.edit")
            ),
            canAssignTasks: PermissionStore.shared.hasFullAccess("tasks.assign"),
            taskStatusScope: ReviewPermissionScope(
                PermissionStore.shared.scope(for: "tasks.change_status")
            ),
            calendarEditScope: ReviewPermissionScope(
                PermissionStore.shared.scope(for: "calendar.edit")
            )
        )
    }

    private func reviewState(for task: ProjectTask) -> UnscheduledReviewTaskState {
        UnscheduledReviewTaskState(
            taskTeamMemberIDs: task.getTeamMemberIds(),
            projectTeamMemberIDs: task.project?.getTeamMemberIds() ?? [],
            isScheduled: task.startDate != nil
        )
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            // Full-bleed card stack
            if !session.tasks.isEmpty && !showAllDone {
                TaskReviewCardStack(
                    tasks: session.tasks,
                    // This flow has a per-direction policy below; the legacy
                    // global calendar gate does not apply here.
                    hasCalendarAccess: true,
                    onSwipe: { _, _ in },
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
                    },
                    swipeResolutionProvider: handleSwipe,
                    directionAllowedProvider: { task, direction in
                        reviewAccessPolicy.allows(direction, task: reviewState(for: task))
                    },
                    onBlockedSwipe: { _, _ in
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        ToastCenter.shared.present(
                            Toast(label: "// ACTION NOT AVAILABLE FOR THIS TASK", tone: .warning)
                        )
                    },
                    onAdvance: { task, _ in
                        currentTopIndex += 1
                        finishReview(task)
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

                    // Respect the bottom safe area so the hint pills sit
                    // above the home indicator on notched devices instead
                    // of overlapping it. The card stack underneath still
                    // bleeds full-screen via its own ignoresSafeArea.
                    directionHints
                        .padding(.bottom, OPSStyle.Layout.spacing2)
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
        .sheet(isPresented: $showCrewPicker, onDismiss: {
            handleCrewPickerDismiss()
        }) {
            // Bug f3a3d66d / affinity ranking — rank the picker by who the
            // operator routinely assigns to THIS task type (vinyl, framing,
            // punchlist …) via the shared engine, so the usual crew is on top.
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
            }()
            let ranked = dataController.rankedTeamMembers(
                forTaskType: taskTypeId,
                companyId: dataController.currentUser?.companyId ?? "",
                candidates: liveTeamMembers
            )

            TeamMemberPickerSheet(
                selectedTeamMemberIds: $assignSelectedIds,
                allTeamMembers: ranked.ordered,
                recentMemberIds: ranked.usualCrewIds,
                taskTypeName: pendingAssignTask?.taskType?.display,
                onConfirm: { pickerDidConfirm = true }
            )
        }
        .sheet(item: $manualScheduleTask, onDismiss: {
            handleManualScheduleDismiss()
        }) { task in
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
                preselectedTeamMemberIds: Set(task.getTeamMemberIds()),
                emitsSuccessFeedbackOnConfirm: false
            )
            .environmentObject(dataController)
        }
        .alert("Cancel Task?", isPresented: $showCancelConfirmation) {
            Button("Keep Task", role: .cancel) {
                pendingCancelTask = nil
                resolvePendingSwipe(false)
            }
            Button("Cancel Task", role: .destructive) {
                if let task = pendingCancelTask {
                    Task {
                        let didCancel = await cancelTask(task)
                        resolvePendingSwipe(didCancel)
                    }
                    pendingCancelTask = nil
                }
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

    // MARK: - Direction Hints (context-dependent)

    private var directionHints: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            if let task = currentTask {
                let state = reviewState(for: task)

                if reviewAccessPolicy.allows(.left, task: state) {
                    hintPill(icon: "arrow.left", label: "SKIP", color: OPSStyle.Colors.tertiaryText)
                }
                if reviewAccessPolicy.allows(.right, task: state) {
                    hintPill(
                        icon: "arrow.right",
                        label: currentTaskIsUnassigned ? "ASSIGN" : "SCHEDULE",
                        color: currentTaskIsUnassigned
                            ? OPSStyle.Colors.primaryAccent
                            : OPSStyle.Colors.successStatus
                    )
                }
                if reviewAccessPolicy.allows(.up, task: state) {
                    hintPill(
                        icon: "arrow.up",
                        label: currentTaskIsUnassigned ? "ASSIGN" : "COMPLETE",
                        color: currentTaskIsUnassigned
                            ? OPSStyle.Colors.primaryAccent
                            : OPSStyle.Colors.successStatus
                    )
                }
                if reviewAccessPolicy.allows(.down, task: state) {
                    hintPill(icon: "arrow.down", label: "CANCEL", color: OPSStyle.Colors.errorStatus)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .animation(reduceMotion ? nil : OPSStyle.Animation.panel, value: currentTopIndex)
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

            if reduceMotion {
                celebrationScale = 1.0
                celebrationOpacity = 1.0
            } else {
                withAnimation(OPSStyle.Animation.flip) {
                    celebrationScale = 1.0
                }
                withAnimation(OPSStyle.Animation.panel.delay(OPSStyle.Animation.durationStagger)) {
                    celebrationOpacity = 1.0
                }
            }
        }
    }

    // MARK: - Swipe Handlers

    private func handleSwipe(
        _ task: ProjectTask,
        _ direction: SwipeDirection,
        resolution: @escaping (Bool) -> Void
    ) {
        guard task.status == .active else {
            presentTerminalTaskState(task)
            resolution(true)
            return
        }

        let state = reviewState(for: task)
        guard reviewAccessPolicy.allows(direction, task: state) else {
            presentActionDenied()
            resolution(false)
            return
        }

        switch direction {
        case .left:
            resolution(true)

        case .right:
            if state.isUnassigned {
                openCrewPicker(
                    for: task,
                    selectedIds: Set(task.getTeamMemberIds()),
                    resolution: resolution
                )
            } else {
                Task {
                    let outcome = await autoScheduleTask(task)
                    handleAutoScheduleOutcome(
                        outcome,
                        for: task,
                        resolution: resolution
                    )
                }
            }

        case .up:
            if state.isUnassigned {
                openCrewPicker(
                    for: task,
                    selectedIds: Set(task.getTeamMemberIds()),
                    resolution: resolution
                )
            } else {
                Task {
                    resolution(await markTaskComplete(task))
                }
            }

        case .down:
            holdResolution(for: task, resolution: resolution)
            pendingCancelTask = task
            showCancelConfirmation = true
        }
    }

    private func holdResolution(
        for task: ProjectTask,
        resolution: @escaping (Bool) -> Void
    ) {
        pendingSwipeTaskID = task.id
        pendingSwipeResolution = resolution
    }

    private func resolvePendingSwipe(_ didSucceed: Bool) {
        let resolution = pendingSwipeResolution
        pendingSwipeResolution = nil
        pendingSwipeTaskID = nil
        resolution?(didSucceed)
    }

    /// Apply the picker delta to the latest task assignment, then complete any
    /// permitted scheduling work before the card is allowed to advance.
    private func handleCrewPickerDismiss() {
        guard let task = pendingAssignTask else { return }

        let confirmed = pickerDidConfirm
        let baseline = assignmentBaselineIds
        let selected = assignSelectedIds

        pendingAssignTask = nil
        assignSelectedIds = []
        assignmentBaselineIds = []
        pickerDidConfirm = false

        guard pendingSwipeTaskID == task.id else {
            resolvePendingSwipe(false)
            return
        }

        guard task.status == .active else {
            presentTerminalTaskState(task)
            resolvePendingSwipe(true)
            return
        }

        guard confirmed else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            ToastCenter.shared.present(
                Toast(label: "// CREW UNCHANGED", tone: .warning)
            )
            resolvePendingSwipe(false)
            return
        }

        guard !selected.isEmpty else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            ToastCenter.shared.present(
                Toast(label: "// SELECT AT LEAST ONE CREW MEMBER", tone: .warning)
            )
            resolvePendingSwipe(false)
            return
        }

        Task {
            do {
                let committedIDs = try await reviewRepository.assignCrew(
                    taskID: task.id,
                    baseline: baseline,
                    selected: selected
                )
                try applyAuthoritativeCrew(committedIDs, to: task)

                guard task.startDate == nil else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    ToastCenter.shared.present(
                        Toast(label: "// CREW ASSIGNED", tone: .success)
                    )
                    resolvePendingSwipe(true)
                    return
                }

                let updatedState = reviewState(for: task)
                guard reviewAccessPolicy.canSchedule(updatedState) else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    ToastCenter.shared.present(
                        Toast(
                            label: "// CREW ASSIGNED — SCHEDULE ACCESS NEEDED",
                            tone: .warning
                        )
                    )
                    resolvePendingSwipe(true)
                    return
                }

                let outcome = await autoScheduleTask(task)
                handlePendingAutoScheduleOutcome(outcome, for: task)
            } catch {
                print("[UNSCHEDULED_REVIEW] Failed to assign crew: \(error)")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                ToastCenter.shared.present(
                    Toast(
                        label: "// CREW ASSIGNMENT FAILED — SWIPE TO RETRY",
                        tone: .error,
                        autoDismissAfter: 0
                    )
                )
                resolvePendingSwipe(false)
            }
        }
    }

    private func markTaskComplete(_ task: ProjectTask) async -> Bool {
        let taskTitle = task.displayTitle

        if task.status == .completed {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            ToastCenter.shared.present(Feedback.Task.alreadyComplete(taskTitle))
            return true
        }
        if task.status == .cancelled {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            ToastCenter.shared.present(
                Toast(label: "// TASK ALREADY CANCELLED", tone: .warning)
            )
            return true
        }

        do {
            try await reviewRepository.complete(taskID: task.id)
            try applyAuthoritativeStatus(.completed, to: task)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            ToastCenter.shared.present(Feedback.Task.completedTask(taskTitle))
            return true
        } catch {
            print("[UNSCHEDULED_REVIEW] Failed to mark task complete: \(error)")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            ToastCenter.shared.present(
                Toast(
                    label: "// COMPLETION FAILED — SWIPE TO RETRY",
                    tone: .error,
                    autoDismissAfter: 0
                )
            )
            return false
        }
    }

    private func cancelTask(_ task: ProjectTask) async -> Bool {
        if task.status == .cancelled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            ToastCenter.shared.present(
                Toast(label: "// TASK ALREADY CANCELLED", tone: .success)
            )
            return true
        }
        if task.status == .completed {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            ToastCenter.shared.present(Feedback.Task.alreadyComplete(task.displayTitle))
            return true
        }

        do {
            try await reviewRepository.cancel(taskID: task.id)
            try applyAuthoritativeStatus(.cancelled, to: task)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            ToastCenter.shared.present(
                Toast(label: "// TASK CANCELLED", tone: .success)
            )
            return true
        } catch {
            print("[UNSCHEDULED_REVIEW] Failed to cancel task: \(error)")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            ToastCenter.shared.present(
                Toast(
                    label: "// CANCELLATION FAILED — SWIPE TO RETRY",
                    tone: .error,
                    autoDismissAfter: 0
                )
            )
            return false
        }
    }

    private func autoScheduleTask(_ task: ProjectTask) async -> AutoScheduleOutcome {
        guard task.status == .active else {
            presentTerminalTaskState(task)
            return .succeeded
        }

        guard reviewAccessPolicy.canSchedule(reviewState(for: task)) else {
            presentScheduleDenied()
            return .denied
        }

        if let existingStart = task.startDate {
            let existingEnd = task.endDate ?? existingStart
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            ToastCenter.shared.present(
                Toast(
                    label: "// ALREADY SCHEDULED \(formatScheduledRange(start: existingStart, end: existingEnd))",
                    tone: .success
                )
            )
            return .succeeded
        }

        let plannedCrew = Set(task.getTeamMemberIds())
        let plan = await dataController.autoScheduleSingleTaskAsync(
            task,
            teamMemberIds: plannedCrew,
            anchorDate: Date()
        )

        // The calculation runs off-main. Revalidate every input that could
        // change through realtime before attempting the compare-and-set write.
        guard task.status == .active else {
            presentTerminalTaskState(task)
            return .succeeded
        }
        guard task.deletedAt == nil,
              task.project?.status.isActive == true else {
            ToastCenter.shared.present(
                Toast(label: "// TASK NO LONGER AVAILABLE", tone: .warning)
            )
            return .succeeded
        }
        guard task.startDate == nil else {
            let existingEnd = task.endDate ?? task.startDate!
            ToastCenter.shared.present(
                Toast(
                    label: "// ALREADY SCHEDULED \(formatScheduledRange(start: task.startDate!, end: existingEnd))",
                    tone: .success
                )
            )
            return .succeeded
        }
        guard Set(task.getTeamMemberIds()) == plannedCrew,
              reviewAccessPolicy.canSchedule(reviewState(for: task)) else {
            presentScheduleDenied()
            return .denied
        }

        guard let placement = plan.placements.first else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            ToastCenter.shared.present(
                Toast(
                    label: AutoScheduleFailureRecovery.message(for: plan),
                    tone: .warning
                )
            )
            return .requiresManualSchedule
        }

        do {
            let commit = try await reviewRepository.schedule(
                taskID: task.id,
                expectedCrew: plannedCrew,
                startDate: placement.startDate,
                endDate: placement.endDate,
                scheduleLocked: false
            )
            try applyAuthoritativeSchedule(
                startDate: commit.startDate,
                endDate: commit.endDate,
                to: task,
                scheduleLocked: false
            )
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            ToastCenter.shared.present(
                Feedback.Task.scheduledFor(
                    start: placement.startDate,
                    end: placement.endDate
                )
            )
            return .succeeded
        } catch {
            print("[UNSCHEDULED_REVIEW] Failed to auto-schedule task: \(error)")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            ToastCenter.shared.present(
                Toast(
                    label: "// SCHEDULE FAILED — SWIPE TO RETRY",
                    tone: .error,
                    autoDismissAfter: 0
                )
            )
            return .failed
        }
    }

    private func handleAutoScheduleOutcome(
        _ outcome: AutoScheduleOutcome,
        for task: ProjectTask,
        resolution: @escaping (Bool) -> Void
    ) {
        switch outcome {
        case .succeeded:
            resolution(true)
        case .requiresManualSchedule:
            holdResolution(for: task, resolution: resolution)
            manualScheduleTask = task
        case .failed, .denied:
            resolution(false)
        }
    }

    private func handlePendingAutoScheduleOutcome(
        _ outcome: AutoScheduleOutcome,
        for task: ProjectTask
    ) {
        switch outcome {
        case .succeeded:
            resolvePendingSwipe(true)
        case .requiresManualSchedule:
            manualScheduleTask = task
        case .failed, .denied:
            resolvePendingSwipe(false)
        }
    }

    private func manuallySchedule(_ task: ProjectTask, startDate: Date, endDate: Date) {
        guard task.status == .active else {
            presentTerminalTaskState(task)
            resolvePendingSwipe(true)
            return
        }

        guard reviewAccessPolicy.canSchedule(reviewState(for: task)) else {
            presentScheduleDenied()
            resolvePendingSwipe(false)
            return
        }

        manualScheduleWriteInFlight = true
        Task {
            do {
                let committed = try await reviewRepository.schedule(
                    taskID: task.id,
                    expectedCrew: Set(task.getTeamMemberIds()),
                    startDate: startDate,
                    endDate: endDate,
                    scheduleLocked: true
                )
                try applyAuthoritativeSchedule(
                    startDate: committed.startDate,
                    endDate: committed.endDate,
                    to: task,
                    scheduleLocked: true
                )
                manualScheduleWriteInFlight = false
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                ToastCenter.shared.present(
                    Feedback.Task.scheduledFor(start: startDate, end: endDate)
                )
                resolvePendingSwipe(true)
            } catch {
                print("[UNSCHEDULED_REVIEW] Failed to manually schedule task: \(error)")
                manualScheduleWriteInFlight = false
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                ToastCenter.shared.present(
                    Toast(
                        label: "// SCHEDULE FAILED — SWIPE TO RETRY",
                        tone: .error,
                        autoDismissAfter: 0
                    )
                )
                resolvePendingSwipe(false)
            }
        }
    }

    private func handleManualScheduleDismiss() {
        guard pendingSwipeResolution != nil, !manualScheduleWriteInFlight else { return }
        resolvePendingSwipe(false)
    }

    @MainActor
    private func applyAuthoritativeCrew(
        _ memberIDs: [String],
        to task: ProjectTask
    ) throws {
        guard dataController.syncEngine?.supersedeProjectTaskFields(
            entityID: task.id,
            with: ["team_member_ids": memberIDs]
        ) == true else {
            throw UnscheduledReviewRepositoryError.invalidResponse
        }
        let memberSet = Set(memberIDs.map { $0.lowercased() })
        task.setTeamMemberIds(memberIDs)
        task.teamMembers = fetchedTeamMembers.filter {
            memberSet.contains($0.id.lowercased())
        }
        task.needsSync = false
        try modelContext.save()
        dataController.notifyReviewSourcesChanged()
    }

    @MainActor
    private func applyAuthoritativeStatus(
        _ status: TaskStatus,
        to task: ProjectTask
    ) throws {
        guard dataController.syncEngine?.supersedeProjectTaskFields(
            entityID: task.id,
            with: ["status": status.rawValue]
        ) == true else {
            throw UnscheduledReviewRepositoryError.invalidResponse
        }
        task.status = status
        task.needsSync = false
        try modelContext.save()
        dataController.notifyReviewSourcesChanged()
    }

    @MainActor
    private func applyAuthoritativeSchedule(
        startDate: Date,
        endDate: Date,
        to task: ProjectTask,
        scheduleLocked: Bool
    ) throws {
        let duration = max(
            1,
            (Calendar.current.dateComponents(
                [.day],
                from: startDate,
                to: endDate
            ).day ?? 0) + 1
        )
        guard dataController.syncEngine?.supersedeProjectTaskFields(
            entityID: task.id,
            with: [
                "start_date": SupabaseDate.format(startDate),
                "end_date": SupabaseDate.format(endDate),
                "duration": duration,
                "schedule_locked": scheduleLocked,
            ]
        ) == true else {
            throw UnscheduledReviewRepositoryError.invalidResponse
        }
        task.startDate = startDate
        task.endDate = endDate
        task.duration = duration
        task.scheduleLocked = scheduleLocked
        task.needsSync = false
        try modelContext.save()
        dataController.notifyReviewSourcesChanged()
        Task { @MainActor in
            await CalendarMirrorService.shared.mirrorEvent(
                opsId: task.id,
                source: .projectTask
            )
        }
    }

    private func presentActionDenied() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        ToastCenter.shared.present(
            Toast(label: "// ACTION NOT AVAILABLE FOR THIS TASK", tone: .warning)
        )
    }

    private func presentScheduleDenied() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        ToastCenter.shared.present(
            Toast(label: "// CAN'T SCHEDULE — NOT ASSIGNED TO YOU", tone: .warning)
        )
    }

    private func presentTerminalTaskState(_ task: ProjectTask) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let label = task.status == .completed
            ? "// TASK ALREADY COMPLETE"
            : "// TASK ALREADY CANCELLED"
        ToastCenter.shared.present(Toast(label: label, tone: .success))
    }

    private func finishReview(_ task: ProjectTask) {
        guard session.markReviewed(taskID: task.id) else { return }
        checkCompletion()
    }

    private func checkCompletion() {
        if session.isComplete {
            withAnimation(
                reduceMotion
                    ? nil
                    : OPSStyle.Animation.page.delay(OPSStyle.Animation.durationStagger)
            ) {
                showAllDone = true
            }
        }
    }
}
