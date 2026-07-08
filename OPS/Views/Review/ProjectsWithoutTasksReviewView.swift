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

    /// Id of the project whose inline details + quick-add composer are
    /// currently expanded. Only one card opens at a time.
    @State private var expandedProjectId: String? = nil
    @State private var addedTaskCountsByProjectId: [String: Int] = [:]

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
                        projectCard(project)
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

    private func projectCard(_ project: Project) -> some View {
        let isExpanded = expandedProjectId == project.id

        return VStack(alignment: .leading, spacing: 0) {
            Button(action: { toggleExpansion(for: project) }) {
                projectCardHeader(project, isExpanded: isExpanded)
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                    Divider()
                        .overlay(OPSStyle.Colors.line)
                        .padding(.top, OPSStyle.Layout.spacing1)

                    projectDetails(project)

                    InlineQuickTaskComposer(
                        project: project,
                        allTaskTypes: allTaskTypes,
                        savedCount: addedTaskCount(for: project),
                        onSaved: { handleTaskSaved(for: project) },
                        onCancel: { finishProjectReview(project) }
                    )
                }
                .padding(.top, OPSStyle.Layout.spacing2)
                .transition(composerTransition)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface(
            borderColor: isExpanded
                ? OPSStyle.Colors.line
                : OPSStyle.Colors.glassBorder
        )
        .contentShape(Rectangle())
    }

    private func projectCardHeader(_ project: Project, isExpanded: Bool) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            projectStatusGlyph(project)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(project.title.uppercased())
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text(daysSinceLabel(project).uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    if addedTaskCount(for: project) > 0 {
                        Text("·")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.textMute)

                        Text(taskAddedLabel(for: project))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.oliveTextM)
                    }
                }
            }

            Spacer(minLength: OPSStyle.Layout.spacing2)

            StatusBadge.forJobStatus(project.status, size: .small)

            Image(systemName: isExpanded ? OPSStyle.Icons.chevronUp : OPSStyle.Icons.chevronDown)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
        }
        .contentShape(Rectangle())
    }

    private func projectStatusGlyph(_ project: Project) -> some View {
        Circle()
            .fill(project.status.color.opacity(0.20))
            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            .overlay(
                Circle()
                    .stroke(project.status.color.opacity(0.75), lineWidth: OPSStyle.Layout.Border.standard)
            )
            .overlay(
                Image(systemName: "folder")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(project.status.color)
            )
    }

    private func projectDetails(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                ProjectReviewDetailCell(label: "CLIENT", value: cleanDetail(project.effectiveClientName))
                ProjectReviewDetailCell(label: "CREW", value: crewLabel(for: project))
            }

            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                ProjectReviewDetailCell(label: "START", value: dateLabel(project.startDate))
                ProjectReviewDetailCell(label: "ADDRESS", value: cleanDetail(project.address))
            }

            if let phone = project.effectiveClientPhone, !phone.isEmpty {
                ProjectReviewDetailLine(label: "PHONE", value: phone)
            }

            if let email = project.effectiveClientEmail, !email.isEmpty {
                ProjectReviewDetailLine(label: "EMAIL", value: email)
            }
        }
        .padding(OPSStyle.Layout.spacing2_5)
        .nestedCard()
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

    private func addedTaskCount(for project: Project) -> Int {
        addedTaskCountsByProjectId[project.id] ?? 0
    }

    private func taskAddedLabel(for project: Project) -> String {
        let count = addedTaskCount(for: project)
        return "\(count) TASK\(count == 1 ? "" : "S") ADDED"
    }

    private func crewLabel(for project: Project) -> String {
        let names = project.teamMembers
            .map(\.fullName)
            .filter { !$0.isEmpty }

        if names.isEmpty { return "—" }
        if names.count == 1 { return names[0] }
        return "\(names.count) CREW"
    }

    private func cleanDetail(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "—"
        }
        return value
    }

    private func dateLabel(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        return DateHelper.simpleDateString(from: date).uppercased()
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

    private func toggleExpansion(for project: Project) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if expandedProjectId == project.id {
            finishProjectReview(project)
        } else {
            expandedProjectId = project.id
        }
    }

    private func finishProjectReview(_ project: Project) {
        expandedProjectId = nil
        if addedTaskCount(for: project) > 0 {
            addedTaskCountsByProjectId[project.id] = nil
            recomputeProjects()
        }
    }

    private func handleTaskSaved(for project: Project) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        addedTaskCountsByProjectId[project.id, default: 0] += 1
    }
}

private struct ProjectReviewDetailCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.text3)

            Text(value)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(value == "—" ? OPSStyle.Colors.text3 : OPSStyle.Colors.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProjectReviewDetailLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
            Text(label)
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.text3)
                .frame(width: OPSStyle.Layout.touchTargetStandard, alignment: .leading)

            Text(value)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Inline Quick-Task Composer (bug fa5010b0)

/// Inline task creator embedded inside each expandable project card.
/// Mirrors the chip-based composer used in `ProjectFormSheet`: pick a
/// task type, pick a crew, pick a date, add the task, keep going.
///
/// On save the composer constructs a `ProjectTask`, persists it via
/// `DataController.createTask`, and calls back so the parent can
/// update its in-session added count while this card stays open.
private struct InlineQuickTaskComposer: View {
    let project: Project
    let allTaskTypes: [TaskType]
    let savedCount: Int
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

    init(project: Project, allTaskTypes: [TaskType], savedCount: Int, onSaved: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.project = project
        self.allTaskTypes = allTaskTypes
        self.savedCount = savedCount
        self.onSaved = onSaved
        self.onCancel = onCancel
        _draftTask = State(initialValue: Self.blankDraftTask())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                Text("// ADD TASK")
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(OPSStyle.Colors.text3)

                Spacer()

                if savedCount > 0 {
                    Text("\(savedCount) ADDED")
                        .font(OPSStyle.Typography.microLabel)
                        .foregroundColor(OPSStyle.Colors.oliveTextM)
                }
            }

            InlineTaskRow(
                task: draftTask,
                availableTaskTypes: allTaskTypes,
                teamMemberCount: draftTask.teamMemberIds.count,
                surfaceStyle: .nested,
                isEnabled: !saving,
                onTaskTypeChange: { newTypeId in
                    draftTask.taskTypeId = newTypeId
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
                    Text(savedCount > 0 ? "DONE" : "CANCEL")
                }
                .opsSecondaryButtonStyle()
                .disabled(saving)

                Button(action: { Task { await saveTask() } }) {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        if saving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText))
                                .scaleEffect(0.8)
                        }
                        Text(saving ? "ADDING" : "ADD TASK")
                    }
                }
                .opsPrimaryButtonStyle(isDisabled: !canSave || saving)
                .disabled(!canSave || saving)
            }
        }
        .padding(OPSStyle.Layout.spacing2_5)
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

    private static func blankDraftTask() -> LocalTask {
        LocalTask(
            id: UUID(),
            taskTypeId: "",
            customTitle: nil,
            status: .active,
            teamMemberIds: [],
            startDate: nil,
            endDate: nil
        )
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
            draftTask = Self.blankDraftTask()
            assignSelectedIds = []
            schedulerConfirmed = false
            schedulerDatesExisted = false
            schedulerStart = Date()
            schedulerEnd = schedulerStart
            onSaved()
        } catch {
            saving = false
            saveError = "Save failed. \(error.localizedDescription)"
        }
    }
}
