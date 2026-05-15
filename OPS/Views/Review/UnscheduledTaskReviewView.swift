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

    private enum ToastKind {
        case success
        case error
    }

    private var activeTeamMembers: [User] {
        var seen = Set<String>()
        return fetchedTeamMembers.filter { member in
            guard !seen.contains(member.id) else { return false }
            seen.insert(member.id)
            return true
        }
    }

    /// Bug f3a3d66d — order `activeTeamMembers` by recency-for-task-type
    /// when a task type is known, otherwise fall back to the alphabetical
    /// order already provided. Mirrors `ProjectFormSheet.teamUsersOrdered`
    /// so the two pickers feel consistent.
    private func teamUsersOrdered(forTaskTypeId taskTypeId: String) -> [User] {
        let alphaSorted = activeTeamMembers

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

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            // Full-bleed card stack
            if !tasks.isEmpty && !showAllDone {
                TaskReviewCardStack(
                    tasks: tasks,
                    hasCalendarAccess: true,
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

                    directionHints
                        .padding(.bottom, 8)
                        .ignoresSafeArea(.container, edges: .bottom)
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
            let taskTypeId = pendingAssignTask?.taskTypeId ?? ""
            let ordered = teamUsersOrdered(forTaskTypeId: taskTypeId)
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
            // TeamMember projection carried).
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(OPSStyle.Colors.cardBackground.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
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
        .allowsHitTesting(false)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: toastMessage)
    }

    private func showToast(_ message: String, kind: ToastKind) {
        toastDismissTask?.cancel()
        toastMessage = message
        toastKind = kind

        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            toastMessage = nil
        }
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
        currentTopIndex += 1

        switch direction {
        case .right:
            let isUnassigned = task.getTeamMemberIds().isEmpty
            if isUnassigned {
                // Task has no crew — open picker, then auto-schedule after assignment
                pendingAssignTask = task
                assignSelectedIds = []
                pickerDidConfirm = false
                showCrewPicker = true
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
                pendingAssignTask = task
                assignSelectedIds = Set(task.getTeamMemberIds())
                pickerDidConfirm = false
                showCrewPicker = true
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

        // Bug 040e4482 — only commit the picker selections when the operator
        // explicitly tapped DONE. Drag-to-dismiss is a back-out gesture; the
        // ephemeral row taps the user made while exploring should not turn
        // into a silent crew assignment + auto-schedule. The card still
        // counts as reviewed since the operator has seen and decided on it.
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
            showToast("NO CREW SELECTED — TASK LEFT UNASSIGNED", kind: .error)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }

        reviewedCount += 1
        pendingAssignTask = nil
        assignSelectedIds = []
        pickerDidConfirm = false
        checkCompletion()
    }

    private func markTaskComplete(_ task: ProjectTask) {
        // Canonical path — persists status, records SyncOperation, fires
        // team-completion notifications, tracks analytics.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let taskTitle = task.displayTitle

        Task {
            do {
                try await dataController.updateTaskStatus(task: task, to: .completed)
                await MainActor.run {
                    showToast("COMPLETED — \(taskTitle.uppercased())", kind: .success)
                }
            } catch {
                print("[UNSCHEDULED_REVIEW] Failed to mark task complete: \(error)")
                await MainActor.run {
                    showToast("COULDN'T MARK COMPLETE — TRY AGAIN", kind: .error)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func autoScheduleTask(_ task: ProjectTask) {
        let plan = dataController.autoScheduleSingleTask(
            task,
            teamMemberIds: Set(task.getTeamMemberIds()),
            anchorDate: Date()
        )

        // If the scheduler couldn't place the task, surface why — previously
        // this was a silent no-op ("swipe has no visible effect").
        guard let placement = plan.placements.first else {
            let reason = plan.conflicts.first?.message ?? "no available slot"
            showToast("COULDN'T SCHEDULE — \(reason.uppercased())", kind: .error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let capturedStart = placement.startDate
        let capturedEnd = placement.endDate

        // Canonical path — saves context, computes duration, records the
        // SyncOperation, and fires schedule-change notifications to team
        // members. Previous inline write skipped duration, the save, and
        // the notifications.
        Task {
            do {
                try await dataController.updateTaskSchedule(
                    task: task,
                    startDate: capturedStart,
                    endDate: capturedEnd
                )
                await MainActor.run {
                    showToast(
                        "SCHEDULED \(formatScheduledRange(start: capturedStart, end: capturedEnd))",
                        kind: .success
                    )
                }
            } catch {
                print("[UNSCHEDULED_REVIEW] Failed to auto-schedule task: \(error)")
                await MainActor.run {
                    showToast("SCHEDULE FAILED — TAP TASK LATER TO RETRY", kind: .error)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func checkCompletion() {
        if reviewedCount >= tasks.count {
            withAnimation(.spring().delay(0.3)) {
                showAllDone = true
            }
        }
    }
}
