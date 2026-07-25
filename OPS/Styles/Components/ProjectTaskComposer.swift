//
//  ProjectTaskComposer.swift
//  OPS
//
//  Shared task composer used by project creation and task-gap review.
//  Keeps suggestions, committed task summaries, and the expanded manual
//  editor visually attached to the project being edited.
//

import SwiftUI
import SwiftData

enum ProjectTaskComposerLogic {
    static func task(from suggestion: TaskSuggestion, id: UUID = UUID()) -> LocalTask {
        LocalTask(
            id: id,
            taskTypeId: suggestion.taskTypeId,
            status: .active,
            teamMemberIds: suggestion.teamMemberIds
        )
    }

    static func saving(_ task: LocalTask, in tasks: [LocalTask]) -> [LocalTask] {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            return tasks + [task]
        }

        var updated = tasks
        updated[index] = task
        return updated
    }

    static func removing(taskId: UUID, from tasks: [LocalTask]) -> [LocalTask] {
        tasks.filter { $0.id != taskId }
    }

    static func tasksForParentSave(
        committedTasks: [LocalTask],
        pendingTask: LocalTask?,
        pendingTaskIsVisible: Bool = true,
        validTaskTypeIds: Set<String>
    ) -> [LocalTask] {
        guard pendingTaskIsVisible,
              let pendingTask,
              validTaskTypeIds.contains(pendingTask.taskTypeId) else {
            return committedTasks
        }

        return saving(pendingTask, in: committedTasks)
    }
}

/// Shared task-adding surface for project creation and project review.
/// Suggestions commit in one tap; manual and existing tasks use the same
/// full-width editor while committed tasks remain visible in the list.
struct ProjectTaskComposer: View {
    @Binding private var tasks: [LocalTask]

    let availableTaskTypes: [TaskType]
    let companyId: String?
    let projectId: String?
    let canSchedule: Bool
    let isEnabled: Bool
    let isAddEnabled: Bool
    let isAddHighlighted: Bool
    let addButtonTarget: String?
    let onManualAddRequested: (() -> Bool)?
    let onSaveTask: (LocalTask) async throws -> LocalTask
    let onDeleteTask: (LocalTask) async throws -> Void
    private let externalEditorTask: Binding<LocalTask?>?

    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @Query private var allUsers: [User]

    @State private var localEditorTask: LocalTask?
    @State private var sheetTarget: SheetTarget?
    @State private var savingTaskId: UUID?
    @State private var taskPendingDeletion: LocalTask?
    @State private var actionError: String?
    @State private var schedulerStart = Date()
    @State private var schedulerEnd = Date()
    @State private var schedulerConfirmed = false
    @State private var schedulerDatesExisted = false
    @State private var wasPresentingScheduler = false

    private enum SheetTarget: Identifiable {
        case crew
        case schedule
        case createTaskType
        case advanced(LocalTask)

        var id: String {
            switch self {
            case .crew: return "crew"
            case .schedule: return "schedule"
            case .createTaskType: return "create-task-type"
            case .advanced(let task): return "advanced:\(task.id.uuidString)"
            }
        }
    }

    init(
        tasks: Binding<[LocalTask]>,
        availableTaskTypes: [TaskType],
        companyId: String?,
        projectId: String?,
        canSchedule: Bool,
        isEnabled: Bool = true,
        isAddEnabled: Bool = true,
        isAddHighlighted: Bool = false,
        addButtonTarget: String? = nil,
        onManualAddRequested: (() -> Bool)? = nil,
        onSaveTask: @escaping (LocalTask) async throws -> LocalTask,
        onDeleteTask: @escaping (LocalTask) async throws -> Void,
        editorTask: Binding<LocalTask?>? = nil
    ) {
        _tasks = tasks
        self.availableTaskTypes = availableTaskTypes
        self.companyId = companyId
        self.projectId = projectId
        self.canSchedule = canSchedule
        self.isEnabled = isEnabled
        self.isAddEnabled = isAddEnabled
        self.isAddHighlighted = isAddHighlighted
        self.addButtonTarget = addButtonTarget
        self.onManualAddRequested = onManualAddRequested
        self.onSaveTask = onSaveTask
        self.onDeleteTask = onDeleteTask
        self.externalEditorTask = editorTask
    }

    /// `availableTaskTypes` intentionally remains the raw cache so existing
    /// rows can resolve a retained deleted type's historical name and color.
    /// Every option-producing path uses this active same-company subset.
    private var selectableTaskTypes: [TaskType] {
        guard let companyId, !companyId.isEmpty else { return [] }
        return TaskTypeSelectionPolicy.selectableTaskTypes(
            from: availableTaskTypes,
            companyId: companyId
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            suggestionsSection

            if !tasks.isEmpty {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(tasks) { task in
                        taskRow(task)
                    }
                }
            }

            if let editorTask, isNewTask(editorTask) {
                editorCard(editorTask)
            }

            if editorTask == nil {
                manualAddButton
            }

            if let actionError {
                Text(actionError)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
            }
        }
        .sheet(item: $sheetTarget, onDismiss: handleSheetDismiss) { target in
            sheet(for: target)
        }
        .alert(
            "DELETE TASK?",
            isPresented: deleteAlertBinding,
            presenting: taskPendingDeletion
        ) { task in
            Button("Delete", role: .destructive) {
                Task { await delete(task) }
            }
            Button("Cancel", role: .cancel) {
                taskPendingDeletion = nil
            }
        } message: { task in
            Text("Remove \(taskTypeName(for: task)) from this project.")
        }
    }

    private var editorTask: LocalTask? {
        get { externalEditorTask?.wrappedValue ?? localEditorTask }
        nonmutating set {
            if let externalEditorTask {
                externalEditorTask.wrappedValue = newValue
            } else {
                localEditorTask = newValue
            }
        }
    }

    // MARK: - Suggestions

    @ViewBuilder
    private var suggestionsSection: some View {
        let items = suggestions
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("SUGGESTED")
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(OPSStyle.Colors.text3)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(items) { suggestion in
                            suggestionButton(suggestion)
                                .containerRelativeFrame(
                                    .horizontal,
                                    count: 5,
                                    span: 4,
                                    spacing: OPSStyle.Layout.spacing2
                                )
                        }
                    }
                }
            }
        }
    }

    private var suggestions: [TaskSuggestion] {
        guard isEnabled, let companyId, !companyId.isEmpty else { return [] }

        let selections = tasks.map {
            TaskSuggestionSelection(
                taskTypeId: $0.taskTypeId,
                teamMemberIds: $0.teamMemberIds
            )
        }
        let computed = TaskSuggestionEngine.suggestions(
            context: modelContext,
            companyId: companyId,
            activeMemberIds: activeMemberIds,
            excluding: selections
        )
        return computed.filter {
            selectableTaskType(for: $0.taskTypeId) != nil
        }
    }

    private func suggestionButton(_ suggestion: TaskSuggestion) -> some View {
        let isSaving = savingTaskId == suggestionTaskId(suggestion)

        return Button {
            Task { await saveSuggestion(suggestion) }
        } label: {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(taskTypeColor(for: suggestion.taskTypeId))
                    .frame(width: OPSStyle.Layout.Border.thick)

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(taskTypeName(for: suggestion.taskTypeId))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1)

                    Text(crewSummary(suggestion.teamMemberIds))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(1)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .padding(.vertical, OPSStyle.Layout.spacing2)

                Spacer(minLength: OPSStyle.Layout.spacing2)

                if isSaving {
                    ProgressView()
                        .tint(OPSStyle.Colors.opsAccent)
                        .frame(
                            width: OPSStyle.Layout.touchTargetMin,
                            height: OPSStyle.Layout.touchTargetMin
                        )
                } else {
                    Image(systemName: OPSStyle.Icons.plusCircleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.opsAccent)
                        .frame(
                            width: OPSStyle.Layout.touchTargetMin,
                            height: OPSStyle.Layout.touchTargetMin
                        )
                }
            }
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .nestedCard()
        }
        .buttonStyle(.plain)
        .disabled(savingTaskId != nil)
        .accessibilityLabel("Add \(taskTypeName(for: suggestion.taskTypeId))")
    }

    // MARK: - Saved rows

    private func taskRow(_ task: LocalTask) -> some View {
        VStack(spacing: 0) {
            Button {
                toggleEditor(for: task)
            } label: {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(taskTypeColor(for: task.taskTypeId))
                        .frame(width: OPSStyle.Layout.Border.thick)

                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text(taskTypeName(for: task))
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.text)
                            .strikethrough(task.status.isTerminal, color: OPSStyle.Colors.text3)
                            .lineLimit(1)

                        Text(taskMetadata(task))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.text3)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .padding(.vertical, OPSStyle.Layout.spacing2)

                    Spacer(minLength: OPSStyle.Layout.spacing2)

                    if savingTaskId == task.id {
                        ProgressView()
                            .tint(OPSStyle.Colors.opsAccent)
                            .frame(
                                width: OPSStyle.Layout.touchTargetMin,
                                height: OPSStyle.Layout.touchTargetMin
                            )
                    } else {
                        Image(
                            systemName: editorTask?.id == task.id
                                ? OPSStyle.Icons.chevronUp
                                : OPSStyle.Icons.chevronDown
                        )
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.text3)
                        .frame(
                            width: OPSStyle.Layout.touchTargetMin,
                            height: OPSStyle.Layout.touchTargetMin
                        )
                    }
                }
                .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(
                !isEnabled ||
                savingTaskId != nil ||
                (editorTask != nil && editorTask?.id != task.id)
            )

            if let editorTask, editorTask.id == task.id {
                Divider()
                    .overlay(OPSStyle.Colors.line)

                editorFields(editorTask)
                    .padding(OPSStyle.Layout.spacing2_5)
            }
        }
        .nestedCard()
        .opacity(task.status.isTerminal ? OPSStyle.Layout.Opacity.strong : 1)
    }

    private func editorCard(_ task: LocalTask) -> some View {
        editorFields(task)
            .padding(OPSStyle.Layout.spacing2_5)
            .nestedCard()
    }

    private func editorFields(_ task: LocalTask) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            taskTypeField(task)
            crewField(task)
            scheduleField(task)
            editorActions(task)
        }
    }

    private func taskTypeField(_ task: LocalTask) -> some View {
        Menu {
            ForEach(selectableTaskTypes, id: \.id) { type in
                Button(type.display) {
                    updateEditor { $0.taskTypeId = type.id }
                }
            }

            Divider()

            Button {
                sheetTarget = .createTaskType
            } label: {
                Label("New Task Type", systemImage: OPSStyle.Icons.plus)
            }
        } label: {
            editorFieldLabel(
                label: "TASK TYPE",
                value: task.taskTypeId.isEmpty
                    ? "Select task type"
                    : taskTypeName(for: task.taskTypeId),
                systemImage: OPSStyle.Icons.checklist,
                valueColor: task.taskTypeId.isEmpty ? OPSStyle.Colors.text3 : OPSStyle.Colors.text
            )
        }
        .disabled(!isEnabled || savingTaskId != nil)
    }

    private func crewField(_ task: LocalTask) -> some View {
        Button {
            sheetTarget = .crew
        } label: {
            editorFieldLabel(
                label: "CREW",
                value: crewSummary(task.teamMemberIds),
                systemImage: OPSStyle.Icons.personTwo,
                valueColor: task.teamMemberIds.isEmpty ? OPSStyle.Colors.text3 : OPSStyle.Colors.text
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || savingTaskId != nil)
    }

    private func scheduleField(_ task: LocalTask) -> some View {
        Button {
            presentScheduler(for: task)
        } label: {
            editorFieldLabel(
                label: "SCHEDULE",
                value: scheduleSummary(task),
                systemImage: OPSStyle.Icons.calendar,
                valueColor: task.startDate == nil ? OPSStyle.Colors.text3 : OPSStyle.Colors.text
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || !canSchedule || savingTaskId != nil)
        .opacity(canSchedule ? 1 : OPSStyle.Layout.Opacity.medium)
    }

    private func editorFieldLabel(
        label: String,
        value: String,
        systemImage: String,
        valueColor: Color
    ) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: systemImage)
                .font(.system(size: OPSStyle.Layout.IconSize.md))
                .foregroundColor(OPSStyle.Colors.text3)
                .frame(
                    width: OPSStyle.Layout.touchTargetMin,
                    height: OPSStyle.Layout.touchTargetMin
                )

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(label)
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(OPSStyle.Colors.text3)

                Text(value)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(valueColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Image(systemName: OPSStyle.Icons.chevronRight)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .padding(.vertical, OPSStyle.Layout.spacing1)
        .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetLarge)
        .background(OPSStyle.Colors.surfaceInput)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .contentShape(Rectangle())
    }

    private func editorActions(_ task: LocalTask) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            if !isNewTask(task) {
                Button {
                    sheetTarget = .advanced(task)
                } label: {
                    Image(systemName: OPSStyle.Icons.ellipsis)
                }
                .opsIconButtonStyle()
                .accessibilityLabel("More task details")

                Button {
                    taskPendingDeletion = task
                } label: {
                    Image(systemName: OPSStyle.Icons.delete)
                }
                .opsIconButtonStyle(foregroundColor: OPSStyle.Colors.rose)
                .accessibilityLabel("Delete task")
            }

            Spacer(minLength: 0)

            Button("Cancel") {
                editorTask = nil
                actionError = nil
            }
            .opsSecondaryButtonStyle()

            Button(isNewTask(task) ? "Add" : "Save") {
                Task { await save(task) }
            }
            .opsPrimaryButtonStyle(isDisabled: !canSave(task) || savingTaskId != nil)
            .disabled(!canSave(task) || savingTaskId != nil)
        }
    }

    // MARK: - Add button

    @ViewBuilder
    private var manualAddButton: some View {
        if let addButtonTarget {
            manualAddButtonContent
                .wizardTarget(addButtonTarget)
        } else {
            manualAddButtonContent
        }
    }

    private var manualAddButtonContent: some View {
        Button(action: beginManualTask) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.plus)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))

                Text(tasks.isEmpty ? "ADD TASK" : "ADD ANOTHER TASK")
                    .font(OPSStyle.Typography.buttonLabel)
            }
            .foregroundColor(
                isAddHighlighted
                    ? OPSStyle.Colors.secondaryText
                    : OPSStyle.Colors.opsAccent
            )
            .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.surfaceInput)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(
                        isAddHighlighted
                            ? OPSStyle.Colors.inputFieldBorder
                            : OPSStyle.Colors.opsAccent.opacity(OPSStyle.Layout.Opacity.light),
                        style: StrokeStyle(
                            lineWidth: OPSStyle.Layout.Border.thick,
                            dash: [OPSStyle.Layout.spacing1]
                        )
                    )
            )
            .modifier(TutorialPulseModifier(isHighlighted: isAddHighlighted))
        }
        .buttonStyle(.plain)
        .disabled(!isAddEnabled || savingTaskId != nil)
        .opacity(isAddEnabled ? 1 : OPSStyle.Layout.Opacity.medium)
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheet(for target: SheetTarget) -> some View {
        switch target {
        case .crew:
            TeamMemberPickerSheet(
                selectedTeamMemberIds: editorTeamBinding,
                allTeamMembers: rankedTeamMembers,
                recentMemberIds: usualCrewIds,
                taskTypeName: editorTask.map { taskTypeName(for: $0.taskTypeId) }
            )
            .environmentObject(dataController)

        case .schedule:
            if let editorTask {
                CalendarSchedulerSheet(
                    isPresented: schedulerIsPresentedBinding,
                    itemType: .draftTask(
                        taskTypeId: editorTask.taskTypeId,
                        teamMemberIds: editorTask.teamMemberIds,
                        projectId: projectId
                    ),
                    currentStartDate: schedulerStart,
                    currentEndDate: schedulerEnd,
                    onScheduleUpdate: { newStart, newEnd in
                        schedulerConfirmed = true
                        updateEditor {
                            $0.startDate = newStart
                            $0.endDate = newEnd
                        }
                    },
                    onClearDates: {
                        updateEditor {
                            $0.startDate = nil
                            $0.endDate = nil
                        }
                    },
                    preselectedTeamMemberIds: editorTask.teamMemberIds.isEmpty
                        ? nil
                        : Set(editorTask.teamMemberIds)
                )
                .environmentObject(dataController)
            }

        case .createTaskType:
            TaskTypeSheet(mode: .create { newType in
                updateEditor { $0.taskTypeId = newType.id }
            })
            .environmentObject(dataController)

        case .advanced(let task):
            TaskFormSheet(draftMode: .editDraft(task)) { savedTask in
                var merged = savedTask
                merged.existingTaskId = task.existingTaskId
                Task { await save(merged) }
            }
            .environmentObject(dataController)
        }
    }

    private var editorTeamBinding: Binding<Set<String>> {
        Binding(
            get: { Set(editorTask?.teamMemberIds ?? []) },
            set: { newValue in
                updateEditor { $0.teamMemberIds = Array(newValue).sorted() }
            }
        )
    }

    private var schedulerIsPresentedBinding: Binding<Bool> {
        Binding(
            get: {
                if case .schedule = sheetTarget { return true }
                return false
            },
            set: { isPresented in
                if !isPresented { sheetTarget = nil }
            }
        )
    }

    private func handleSheetDismiss() {
        if wasPresentingScheduler && !schedulerConfirmed && !schedulerDatesExisted {
            updateEditor {
                $0.startDate = nil
                $0.endDate = nil
            }
        }
        wasPresentingScheduler = false
        schedulerConfirmed = false
        schedulerDatesExisted = false
    }

    // MARK: - Actions

    private func beginManualTask() {
        if onManualAddRequested?() == false { return }

        actionError = nil
        editorTask = LocalTask(
            id: UUID(),
            taskTypeId: "",
            status: .active
        )
        taskHaptic(.light)
    }

    private func toggleEditor(for task: LocalTask) {
        actionError = nil
        editorTask = editorTask?.id == task.id ? nil : task
        taskHaptic(.light)
    }

    private func presentScheduler(for task: LocalTask) {
        guard canSchedule else { return }
        schedulerDatesExisted = task.startDate != nil
        schedulerConfirmed = false
        schedulerStart = task.startDate ?? Date()
        schedulerEnd = task.endDate ?? schedulerStart
        wasPresentingScheduler = true
        sheetTarget = .schedule
    }

    @MainActor
    private func saveSuggestion(_ suggestion: TaskSuggestion) async {
        let task = ProjectTaskComposerLogic.task(
            from: suggestion,
            id: suggestionTaskId(suggestion)
        )
        await save(task, leaveEditorOpen: true)
    }

    @MainActor
    private func save(_ task: LocalTask, leaveEditorOpen: Bool = false) async {
        guard canSave(task), savingTaskId == nil else { return }

        savingTaskId = task.id
        actionError = nil
        do {
            let savedTask = try await onSaveTask(task)
            tasks = ProjectTaskComposerLogic.saving(savedTask, in: tasks)
            if !leaveEditorOpen { editorTask = nil }
            taskHaptic(.medium)
        } catch {
            actionError = "Task could not be saved. Try again."
        }
        savingTaskId = nil
    }

    @MainActor
    private func delete(_ task: LocalTask) async {
        guard savingTaskId == nil else { return }

        taskPendingDeletion = nil
        savingTaskId = task.id
        actionError = nil
        do {
            try await onDeleteTask(task)
            tasks = ProjectTaskComposerLogic.removing(taskId: task.id, from: tasks)
            if editorTask?.id == task.id { editorTask = nil }
            taskHaptic(.medium)
        } catch {
            actionError = "Task could not be deleted. Try again."
        }
        savingTaskId = nil
    }

    private func updateEditor(_ update: (inout LocalTask) -> Void) {
        guard var task = editorTask else { return }
        update(&task)
        editorTask = task
        actionError = nil
    }

    // MARK: - Derived values

    private var activeCompanyUsers: [User] {
        guard let companyId else { return [] }
        return allUsers.filter {
            $0.companyId == companyId &&
            $0.deletedAt == nil &&
            $0.isActive != false
        }
    }

    private var activeMemberIds: Set<String> {
        Set(activeCompanyUsers.map { $0.id.lowercased() })
    }

    private var userById: [String: User] {
        activeCompanyUsers.reduce(into: [:]) { result, user in
            result[user.id.lowercased()] = user
        }
    }

    private var rankedTeamMembers: [User] {
        guard let companyId, let taskTypeId = editorTask?.taskTypeId else {
            return activeCompanyUsers.sorted {
                $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }
        }
        return dataController.rankedTeamMembers(
            forTaskType: taskTypeId,
            companyId: companyId,
            candidates: activeCompanyUsers
        ).ordered
    }

    private var usualCrewIds: Set<String> {
        guard let companyId, let taskTypeId = editorTask?.taskTypeId else { return [] }
        return dataController.rankedTeamMembers(
            forTaskType: taskTypeId,
            companyId: companyId,
            candidates: activeCompanyUsers
        ).usualCrewIds
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { taskPendingDeletion != nil },
            set: { isPresented in
                if !isPresented { taskPendingDeletion = nil }
            }
        )
    }

    private func isNewTask(_ task: LocalTask) -> Bool {
        !tasks.contains { $0.id == task.id }
    }

    private func canSave(_ task: LocalTask) -> Bool {
        guard !task.taskTypeId.isEmpty else { return false }
        if selectableTaskType(for: task.taskTypeId) != nil {
            return true
        }

        // A persisted task may keep its unchanged deleted same-company type
        // while other fields are edited. New tasks and changed selections
        // always require an active selectable type.
        guard let companyId,
              let original = tasks.first(where: { $0.id == task.id }),
              original.taskTypeId == task.taskTypeId,
              let historicalType = taskType(for: task.taskTypeId) else {
            return false
        }
        return historicalType.companyId == companyId
    }

    private func selectableTaskType(for id: String) -> TaskType? {
        selectableTaskTypes.first { $0.id == id }
    }

    private func taskType(for id: String) -> TaskType? {
        availableTaskTypes.first { $0.id == id }
    }

    private func taskTypeName(for id: String) -> String {
        taskType(for: id)?.display.uppercased() ?? "TASK"
    }

    private func taskTypeName(for task: LocalTask) -> String {
        if let customTitle = task.customTitle,
           !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customTitle.uppercased()
        }
        return taskTypeName(for: task.taskTypeId)
    }

    private func taskTypeColor(for id: String) -> Color {
        guard let hex = taskType(for: id)?.color, let color = Color(hex: hex) else {
            return OPSStyle.Colors.text3
        }
        return color
    }

    private func crewSummary(_ memberIds: [String]) -> String {
        let members = memberIds.compactMap { userById[$0.lowercased()] }
        guard let first = members.first else { return "UNASSIGNED" }
        if members.count == 1 { return first.fullName.uppercased() }
        return "\(first.firstName.uppercased()) +\(members.count - 1)"
    }

    private func scheduleSummary(_ task: LocalTask) -> String {
        guard let start = task.startDate else { return "NOT SCHEDULED" }
        let startLabel = DateHelper.simpleDateString(from: start).uppercased()
        guard let end = task.endDate,
              !Calendar.current.isDate(start, inSameDayAs: end) else {
            return startLabel
        }
        return "\(startLabel) - \(DateHelper.simpleDateString(from: end).uppercased())"
    }

    private func taskMetadata(_ task: LocalTask) -> String {
        "\(crewSummary(task.teamMemberIds))  /  \(scheduleSummary(task))"
    }

    private func suggestionTaskId(_ suggestion: TaskSuggestion) -> UUID {
        let bytes = Array(suggestion.keyHash.utf8)
        var uuidBytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in bytes.enumerated() {
            uuidBytes[index % 16] ^= byte
        }
        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }

    private func taskHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if !targetEnvironment(simulator)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }
}
