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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController

    @Query private var allTaskTypes: [TaskType]

    @State private var projects: [Project] = []

    /// Id of the project whose inline details + quick-add composer are
    /// currently expanded. Only one card opens at a time.
    @State private var expandedProjectId: String? = nil
    @State private var addedTasksByProjectId: [String: [LocalTask]] = [:]

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

                    ProjectTaskComposer(
                        tasks: addedTasksBinding(for: project),
                        availableTaskTypes: allTaskTypes.sorted {
                            $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending
                        },
                        companyId: project.companyId,
                        projectId: project.id,
                        canSchedule: project.canEditSchedule,
                        onSaveTask: { task in
                            try await persist(task, for: project)
                        },
                        onDeleteTask: { task in
                            try await delete(task, from: project)
                        }
                    )
                    .environmentObject(dataController)
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
        addedTasksByProjectId[project.id]?.count ?? 0
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
            addedTasksByProjectId[project.id] = nil
            recomputeProjects()
        }
    }

    private func addedTasksBinding(for project: Project) -> Binding<[LocalTask]> {
        Binding(
            get: { addedTasksByProjectId[project.id] ?? [] },
            set: { addedTasksByProjectId[project.id] = $0 }
        )
    }

    @MainActor
    private func persist(_ draft: LocalTask, for project: Project) async throws -> LocalTask {
        let existingTask: ProjectTask?
        if let existingTaskId = draft.existingTaskId {
            existingTask = try persistedTask(id: existingTaskId, project: project)
        } else {
            existingTask = nil
        }

        let taskType: TaskType?
        if let existingTask,
           existingTask.taskTypeId == draft.taskTypeId {
            taskType = allTaskTypes.first {
                $0.id == draft.taskTypeId && $0.companyId == project.companyId
            }
        } else {
            taskType = TaskTypeSelectionPolicy.selectableTaskTypes(
                from: allTaskTypes,
                companyId: project.companyId
            ).first { $0.id == draft.taskTypeId }
        }

        guard let taskType else {
            throw ProjectTaskComposerPersistenceError.missingTaskType
        }

        if let task = existingTask {
            task.taskTypeId = draft.taskTypeId
            task.taskType = taskType
            task.customTitle = draft.customTitle
            task.status = draft.status
            task.taskColor = taskType.color
            task.startDate = draft.startDate
            task.endDate = draft.endDate
            task.setTeamMemberIds(draft.teamMemberIds)
            try hydrateTeamMembers(for: task)
            try await dataController.updateTask(task: task)
            return draft
        }

        let task = ProjectTask(
            id: UUID().uuidString.lowercased(),
            projectId: project.id,
            taskTypeId: draft.taskTypeId,
            companyId: project.companyId,
            status: draft.status,
            taskColor: taskType.color
        )
        task.project = project
        task.taskType = taskType
        task.customTitle = draft.customTitle
        task.startDate = draft.startDate
        task.endDate = draft.endDate
        task.displayOrder = (project.tasks.map(\.displayOrder).max() ?? -1) + 1

        let resolvedIds = resolvedTeamMemberIds(
            explicitIds: draft.teamMemberIds,
            taskType: taskType,
            project: project
        )
        task.setTeamMemberIds(resolvedIds)
        try hydrateTeamMembers(for: task)
        try await dataController.createTask(task: task)

        var savedDraft = draft
        savedDraft.teamMemberIds = resolvedIds
        savedDraft.existingTaskId = task.id
        return savedDraft
    }

    @MainActor
    private func delete(_ draft: LocalTask, from project: Project) async throws {
        guard let existingTaskId = draft.existingTaskId,
              let task = try persistedTask(id: existingTaskId, project: project) else {
            return
        }
        try await dataController.deleteTask(task)
    }

    private func persistedTask(id: String, project: Project) throws -> ProjectTask? {
        if let task = project.tasks.first(where: { $0.id == id }) {
            return task
        }

        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { task in task.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func hydrateTeamMembers(for task: ProjectTask) throws {
        let memberIds = task.getTeamMemberIds()
        guard !memberIds.isEmpty else {
            task.teamMembers = []
            return
        }

        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate<User> { user in memberIds.contains(user.id) }
        )
        task.teamMembers = try modelContext.fetch(descriptor)
    }

    private func resolvedTeamMemberIds(
        explicitIds: [String],
        taskType: TaskType,
        project: Project
    ) -> [String] {
        if !explicitIds.isEmpty { return explicitIds }
        if !taskType.defaultTeamMemberIdsString.isEmpty {
            return taskType.defaultTeamMemberIdsString
                .components(separatedBy: ",")
                .filter { !$0.isEmpty }
        }
        return project.teamMembers.map(\.id)
    }
}

private enum ProjectTaskComposerPersistenceError: Error {
    case missingTaskType
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
