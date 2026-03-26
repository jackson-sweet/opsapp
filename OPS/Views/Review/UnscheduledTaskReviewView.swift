//
//  UnscheduledTaskReviewView.swift
//  OPS
//
//  Full-screen Tinder-style review for tasks that are unscheduled or unassigned.
//  Actions adapt based on task state:
//  - Unassigned: right = assign crew (must assign before scheduling)
//  - Unscheduled (assigned): right = auto-schedule
//  - Up = assign/edit crew always, Left = skip, Down = cancel
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
    @State private var crewPickerSource: CrewPickerSource = .swipeUp
    @State private var showAllDone: Bool = false
    @State private var celebrationScale: CGFloat = 0
    @State private var celebrationOpacity: Double = 0

    @Query private var allTeamMembers: [TeamMember]

    /// Tracks why the crew picker was opened
    private enum CrewPickerSource {
        case swipeUp    // Explicit assign action
        case swipeRight // Must assign before auto-scheduling
    }

    private var activeTeamMembers: [TeamMember] {
        var seen = Set<String>()
        return allTeamMembers.filter { member in
            guard !seen.contains(member.id) else { return false }
            seen.insert(member.id)
            return true
        }
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
            TeamMemberPickerSheet(
                selectedTeamMemberIds: $assignSelectedIds,
                allTeamMembers: activeTeamMembers
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
            return SwipeActionConfig(label: "ASSIGN CREW", icon: "person.badge.plus", color: OPSStyle.Colors.primaryAccent)
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

            hintPill(icon: "arrow.up", label: "ASSIGN", color: OPSStyle.Colors.primaryAccent)
            hintPill(icon: "arrow.down", label: "CANCEL", color: OPSStyle.Colors.errorStatus)
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: currentTopIndex)
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
                crewPickerSource = .swipeRight
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
            // Assign/edit crew
            pendingAssignTask = task
            assignSelectedIds = Set(task.getTeamMemberIds())
            crewPickerSource = .swipeUp
            showCrewPicker = true

        case .down:
            // Cancel — show confirmation
            pendingCancelTask = task
            showCancelConfirmation = true
        }
    }

    /// Called when crew picker is dismissed
    private func handleCrewPickerDismiss() {
        guard let task = pendingAssignTask else { return }

        if !assignSelectedIds.isEmpty {
            // Apply crew assignment
            Task {
                try? await dataController.updateTaskTeamMembers(
                    task: task,
                    memberIds: Array(assignSelectedIds)
                )

                // If triggered by swipe-right on unassigned task, also auto-schedule
                if crewPickerSource == .swipeRight && task.startDate == nil {
                    await MainActor.run {
                        autoScheduleTask(task)
                    }
                }
            }
        }

        reviewedCount += 1
        pendingAssignTask = nil
        assignSelectedIds = []
        checkCompletion()
    }

    private func autoScheduleTask(_ task: ProjectTask) {
        let plan = dataController.autoScheduleSingleTask(
            task,
            teamMemberIds: Set(task.getTeamMemberIds()),
            anchorDate: Date()
        )

        if let placement = plan.placements.first {
            task.startDate = placement.startDate
            task.endDate = placement.endDate
            task.needsSync = true

            dataController.syncEngine.recordOperation(
                entityType: .projectTask,
                entityId: task.id,
                operationType: "update",
                changedFields: [
                    "start_date": ISO8601DateFormatter().string(from: placement.startDate),
                    "end_date": ISO8601DateFormatter().string(from: placement.endDate)
                ]
            )

            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
