//
//  ProjectsWithoutTasksReviewView.swift
//  OPS
//
//  Simple list view for the "projects in accepted/in-progress with zero tasks"
//  rail notification deep link. Tapping a row opens the project details so the
//  admin can add the missing tasks. Mirrors the OPS list-view pattern used by
//  ExpensesListView (header + scrollable card list + empty state).
//

import SwiftUI
import SwiftData

struct ProjectsWithoutTasksReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var dataController: DataController

    @Query private var allTaskTypes: [TaskType]

    @State private var projects: [Project] = []

    /// Bug fa5010b0 — id of the project whose inline quick-add composer
    /// is currently expanded. Only one composer at a time; tapping a
    /// different row collapses the previous one. `nil` means every row
    /// is in its collapsed default state.
    @State private var expandedProjectId: String? = nil

    // MARK: - Motion (spec: one curve, no spring; reduce-motion → fade only)

    private var expandAnimation: Animation {
        reduceMotion
            ? OPSStyle.Animation.hover
            : OPSStyle.Animation.standard
    }

    /// Inline composer transition: full reveal with slide on default, fade
    /// only when reduce-motion is on (per DESIGN.md §8 fallback).
    private var composerTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .top))
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                content
            }
        }
        .trackScreen("ProjectsNeedingTasks")
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .onAppear {
            recomputeProjects()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: OPSStyle.Icons.chevronLeft)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)

            Spacer()

            Text("PROJECTS NEEDING TASKS")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            Spacer().frame(width: OPSStyle.Layout.touchTargetMin)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2_5)
        .padding(.bottom, OPSStyle.Layout.spacing2)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if projects.isEmpty {
            emptyState
        } else {
            countLabel
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, OPSStyle.Layout.spacing2)

            ScrollView {
                LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(projects, id: \.id) { project in
                        VStack(spacing: 0) {
                            Button(action: { toggleExpansion(for: project) }) {
                                row(project)
                            }
                            .buttonStyle(PlainButtonStyle())

                            if expandedProjectId == project.id {
                                InlineQuickTaskComposer(
                                    project: project,
                                    allTaskTypes: allTaskTypes,
                                    onSaved: { handleTaskSaved() },
                                    onCancel: { collapseRow() }
                                )
                                .padding(.top, OPSStyle.Layout.spacing2)
                                .transition(composerTransition)
                            }
                        }
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, OPSStyle.Layout.spacing4)
                .animation(expandAnimation, value: expandedProjectId)
            }
        }
    }

    private var countLabel: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Text("\(projects.count) PROJECT\(projects.count == 1 ? "" : "S")")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("// no tasks attached")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Spacer()
        }
    }

    // MARK: - Row

    private func row(_ project: Project) -> some View {
        return HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Circle()
                .fill(project.status.color.opacity(0.25))
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(project.status.color, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .overlay(
                    Image(systemName: "folder")
                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        .foregroundColor(project.status.color)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(project.title.uppercased())
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text(project.status.displayName.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(project.status.color)

                    Text("·")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Text(daysSinceLabel(project))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            Spacer()

            Image(systemName: OPSStyle.Icons.chevronRight)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
        .contentShape(Rectangle())
    }

    // MARK: - Row helpers

    private func daysSinceLabel(_ project: Project) -> String {
        let recency = project.lastSyncedAt ?? project.startDate
        guard let recency = recency else { return "no date" }
        let days = max(0, Calendar.current.dateComponents([.day], from: recency, to: Date()).day ?? 0)
        if days < 1 { return "today" }
        if days == 1 { return "1 day ago" }
        if days < 30 { return "\(days) days ago" }
        let months = days / 30
        return "\(months)mo ago"
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(OPSStyle.Typography.largeTitle)
                .foregroundColor(OPSStyle.Colors.successStatus.opacity(0.7))

            Text("ALL CAUGHT UP")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("Every active project has at least one task.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func recomputeProjects() {
        let all = dataController.getProjects()
        projects = ProjectsWithoutTasksDetector.projectsWithoutTasks(from: all)
    }

    /// Bug fa5010b0 — tap toggles the inline composer instead of
    /// navigating away. The operator wants to fix the "no tasks" state
    /// without leaving the review list; bouncing into project details
    /// just to drop in a single task was friction.
    private func toggleExpansion(for project: Project) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if expandedProjectId == project.id {
            expandedProjectId = nil
        } else {
            expandedProjectId = project.id
        }
    }

    private func collapseRow() {
        expandedProjectId = nil
    }

    private func handleTaskSaved() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        expandedProjectId = nil
        // The project just got a task — it should drop out of the
        // "needs tasks" list on the next pass. Recompute against the
        // latest local state.
        recomputeProjects()
    }
}

// MARK: - Inline Quick-Task Composer (bug fa5010b0)

/// Single-shot inline task creator embedded inside each expandable row
/// of `ProjectsWithoutTasksReviewView`. Mirrors the chip-based inline
/// composer used in `ProjectFormSheet` so the two flows feel like the
/// same control: pick a task type, pick a crew, pick a date, save.
///
/// On save the composer constructs a `ProjectTask`, persists it via
/// `DataController.createTask`, and calls back so the parent can
/// collapse + refresh.
private struct InlineQuickTaskComposer: View {
    let project: Project
    let allTaskTypes: [TaskType]
    let onSaved: () -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext

    @State private var draftTask: LocalTask
    @State private var assignSelectedIds: Set<String> = []
    @State private var showCrewPicker = false
    @State private var showScheduler = false
    @State private var schedulerStart: Date = Date()
    @State private var schedulerEnd: Date = Date()
    @State private var schedulerConfirmed = false
    @State private var schedulerDatesExisted = false
    @State private var fetchedTeamUsers: [User] = []
    @State private var saving = false
    @State private var saveError: String? = nil

    init(project: Project, allTaskTypes: [TaskType], onSaved: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.project = project
        self.allTaskTypes = allTaskTypes
        self.onSaved = onSaved
        self.onCancel = onCancel
        _draftTask = State(initialValue: LocalTask(
            id: UUID(),
            taskTypeId: "",
            customTitle: nil,
            status: .active,
            teamMemberIds: [],
            startDate: nil,
            endDate: nil
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            InlineTaskRow(
                task: draftTask,
                availableTaskTypes: allTaskTypes,
                teamMemberCount: draftTask.teamMemberIds.count,
                isEnabled: !saving,
                onTaskTypeChange: { newTypeId in
                    draftTask.taskTypeId = newTypeId
                    // Bug fa5010b0 — clear any crew the user picked
                    // before they chose a type so the "recent for type"
                    // suggestions get a clean slate on the next tap.
                    if assignSelectedIds.isEmpty == false && draftTask.teamMemberIds.isEmpty {
                        // no-op — keep the user's prior selection if any
                    }
                },
                onCreateNewTaskType: { /* inline composer doesn't surface task-type creation */ },
                onTeamTap: { presentCrewPicker() },
                onDateTap: { presentScheduler() },
                onStatusChange: { newStatus in draftTask.status = newStatus },
                onOpenFullEditor: { /* full editor would navigate away, keep inline */ },
                onDuplicate: { /* not meaningful with a single draft row */ },
                onDelete: { onCancel() }
            )

            if let saveError = saveError {
                Text(saveError)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button(action: onCancel) {
                    Text("CANCEL")
                        .font(OPSStyle.Typography.captionBold)
                        .tracking(0.8)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OPSStyle.Layout.spacing2_5)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(saving)

                Button(action: { Task { await saveTask() } }) {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        if saving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText))
                                .scaleEffect(0.8)
                        }
                        Text(saving ? "SAVING" : "SAVE TASK")
                            .font(OPSStyle.Typography.captionBold)
                            .tracking(0.8)
                            .foregroundColor(OPSStyle.Colors.invertedText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .background(canSave ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!canSave || saving)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface(borderColor: OPSStyle.Colors.primaryAccent.opacity(0.5))
        .onAppear { loadTeamUsers() }
        .sheet(isPresented: $showCrewPicker, onDismiss: { handleCrewPickerDismiss() }) {
            crewPickerSheet
        }
        .sheet(isPresented: $showScheduler, onDismiss: { handleSchedulerDismiss() }) {
            schedulerSheet
        }
    }

    // MARK: - Save eligibility

    private var canSave: Bool {
        !draftTask.taskTypeId.isEmpty &&
        allTaskTypes.contains(where: { $0.id == draftTask.taskTypeId })
    }

    // MARK: - Team picker

    private var crewPickerSheet: some View {
        let ranked: (ordered: [User], usualCrewIds: Set<String>) = {
            guard let companyId = dataController.currentUser?.companyId else {
                return (fetchedTeamUsers.sorted {
                    $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
                }, [])
            }
            return dataController.rankedTeamMembers(
                forTaskType: draftTask.taskTypeId,
                companyId: companyId,
                candidates: fetchedTeamUsers
            )
        }()
        return TeamMemberPickerSheet(
            selectedTeamMemberIds: $assignSelectedIds,
            allTeamMembers: ranked.ordered,
            recentMemberIds: ranked.usualCrewIds,
            taskTypeName: allTaskTypes.first { $0.id == draftTask.taskTypeId }?.display
        )
    }

    private func presentCrewPicker() {
        guard !saving else { return }
        assignSelectedIds = Set(draftTask.teamMemberIds)
        showCrewPicker = true
    }

    private func handleCrewPickerDismiss() {
        draftTask.teamMemberIds = Array(assignSelectedIds)
    }

    // MARK: - Scheduler

    private var schedulerSheet: some View {
        CalendarSchedulerSheet(
            isPresented: $showScheduler,
            itemType: .draftTask(
                taskTypeId: draftTask.taskTypeId,
                teamMemberIds: draftTask.teamMemberIds,
                projectId: project.id
            ),
            currentStartDate: schedulerStart,
            currentEndDate: schedulerEnd,
            onScheduleUpdate: { newStart, newEnd in
                schedulerConfirmed = true
                draftTask.startDate = newStart
                draftTask.endDate = newEnd
            },
            onClearDates: {
                draftTask.startDate = nil
                draftTask.endDate = nil
            },
            preselectedTeamMemberIds: assignSelectedIds.isEmpty ? nil : assignSelectedIds
        )
        .environmentObject(dataController)
    }

    private func presentScheduler() {
        guard !saving else { return }
        // Scheduling a draft is gated on calendar.edit, scope-aware on the project
        // (own-scope → only projects the user is on). Crew / Unassigned (no grant)
        // can review and create tasks but never set their schedule.
        guard project.canEditSchedule else { return }
        schedulerDatesExisted = draftTask.startDate != nil
        schedulerConfirmed = false
        schedulerStart = draftTask.startDate ?? Date()
        schedulerEnd = draftTask.endDate ?? schedulerStart
        showScheduler = true
    }

    private func handleSchedulerDismiss() {
        // Same convention as ProjectFormSheet: a sheet dismissed without
        // confirmation rolls back dates that didn't exist before opening.
        if !schedulerConfirmed && !schedulerDatesExisted {
            draftTask.startDate = nil
            draftTask.endDate = nil
        }
    }

    // MARK: - Save

    private func loadTeamUsers() {
        guard let companyId = dataController.currentUser?.companyId else { return }
        fetchedTeamUsers = dataController.getTeamMembers(companyId: companyId)
            .sorted { $0.fullName.localizedCompare($1.fullName) == .orderedAscending }
    }

    @MainActor
    private func saveTask() async {
        guard canSave, !saving else { return }
        guard let modelContext = dataController.modelContext else {
            saveError = "Local store unavailable."
            return
        }
        guard let taskType = allTaskTypes.first(where: { $0.id == draftTask.taskTypeId }) else {
            saveError = "Pick a task type to save."
            return
        }
        guard let companyId = dataController.currentUser?.companyId else {
            saveError = "Missing company context."
            return
        }

        saving = true
        saveError = nil

        let taskId = UUID().uuidString.lowercased()
        let task = ProjectTask(
            id: taskId,
            projectId: project.id,
            taskTypeId: draftTask.taskTypeId,
            companyId: companyId,
            status: draftTask.status,
            taskColor: taskType.color
        )
        task.project = project
        task.taskType = taskType
        task.startDate = draftTask.startDate
        task.endDate = draftTask.endDate

        // Resolve team members: explicit picks > task-type default > project team.
        let resolvedIds: [String]
        if !draftTask.teamMemberIds.isEmpty {
            resolvedIds = draftTask.teamMemberIds
        } else if !taskType.defaultTeamMemberIdsString.isEmpty {
            resolvedIds = taskType.defaultTeamMemberIdsString
                .components(separatedBy: ",")
                .filter { !$0.isEmpty }
        } else {
            resolvedIds = project.teamMembers.map { $0.id }
        }
        task.setTeamMemberIds(resolvedIds)
        let lowercaseIds = task.getTeamMemberIds()
        if !lowercaseIds.isEmpty {
            let descriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { user in lowercaseIds.contains(user.id) }
            )
            task.teamMembers = (try? modelContext.fetch(descriptor)) ?? []
        }

        do {
            try await dataController.createTask(task: task)
            saving = false
            onSaved()
        } catch {
            saving = false
            saveError = "Save failed. \(error.localizedDescription)"
        }
    }
}
