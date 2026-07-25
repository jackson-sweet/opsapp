//
//  TaskTypeUsageSheet.swift
//  OPS
//
//  Compact task-usage manager for a TaskType. Selection stays local until the
//  operator explicitly chooses a target and confirms the reassignment.
//

import SwiftData
import SwiftUI

@MainActor
struct TaskTypeUsageSheet: View {
    let source: TaskType
    let allCompanyTypes: [TaskType]

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    @Query private var queriedActiveTasks: [ProjectTask]

    @State private var selectedTaskIds: Set<String> = []
    @State private var showingTargetPicker = false
    @State private var isReassigning = false
    @State private var reassignmentError: String?

    init(source: TaskType, allCompanyTypes: [TaskType]) {
        self.source = source
        self.allCompanyTypes = allCompanyTypes

        _queriedActiveTasks = Query(
            filter: #Predicate<ProjectTask> { task in
                task.deletedAt == nil
            }
        )
    }

    private var sourceTasks: [ProjectTask] {
        TaskTypeSettingsLogic.tasksUsing(
            source,
            in: queriedActiveTasks
        ).sorted { lhs, rhs in
            if lhs.status.sortOrder != rhs.status.sortOrder {
                return lhs.status.sortOrder < rhs.status.sortOrder
            }

            let projectComparison = projectName(for: lhs)
                .localizedCaseInsensitiveCompare(projectName(for: rhs))
            if projectComparison != .orderedSame {
                return projectComparison == .orderedAscending
            }

            let titleComparison = lhs.displayTitle
                .localizedCaseInsensitiveCompare(rhs.displayTitle)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }

            return lhs.id < rhs.id
        }
    }

    private var availableTaskIds: Set<String> {
        Set(sourceTasks.map(\.id))
    }

    private var candidateTargets: [TaskType] {
        allCompanyTypes
            .filter {
                $0.id != source.id
                    && $0.companyId == source.companyId
                    && $0.deletedAt == nil
            }
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault {
                    return !lhs.isDefault && rhs.isDefault
                }
                return lhs.display.localizedCaseInsensitiveCompare(rhs.display) == .orderedAscending
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            selectionBar

            ScrollView {
                if sourceTasks.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !selectedTaskIds.isEmpty {
                reassignmentActionBar
            }
        }
        .sheet(isPresented: $showingTargetPicker) {
            TaskTypeReassignmentTargetSheet(
                source: source,
                candidates: candidateTargets,
                taskCount: selectedTaskIds.count,
                isProcessing: isReassigning,
                onConfirm: performReassignment
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .errorToast($reassignmentError, label: Feedback.Err.batchUpdateFailed)
        .interactiveDismissDisabled(isReassigning)
        .onChange(of: availableTaskIds) { _, currentIds in
            selectedTaskIds.formIntersection(currentIds)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("TASKS USING TYPE")
                    .font(OPSStyle.Typography.screenTitle(for: "TASKS USING TYPE"))
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                        .fill(Color(hex: source.color) ?? OPSStyle.Colors.text3)
                        .frame(
                            width: OPSStyle.Layout.spacing1,
                            height: OPSStyle.Layout.IconSize.sm
                        )
                        .accessibilityHidden(true)

                    Text(source.display)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.text2)
                        .lineLimit(1)

                    if source.isDefault {
                        Text("DEFAULT")
                            .font(OPSStyle.Typography.badgeCake)
                            .foregroundColor(OPSStyle.Colors.text2)
                            .padding(.horizontal, OPSStyle.Layout.spacing2)
                            .padding(.vertical, OPSStyle.Layout.spacing1)
                            .background(OPSStyle.Colors.surfaceInput)
                            .cornerRadius(OPSStyle.Layout.chipRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                    .stroke(
                                        OPSStyle.Colors.line,
                                        lineWidth: OPSStyle.Layout.Border.standard
                                    )
                            )
                    }
                }
            }

            Spacer(minLength: OPSStyle.Layout.spacing2)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: OPSStyle.Icons.close)
                    .font(.system(
                        size: OPSStyle.Layout.IconSize.md,
                        weight: .medium
                    ))
                    .foregroundColor(OPSStyle.Colors.text2)
                    .frame(
                        width: OPSStyle.Layout.touchTargetMin,
                        height: OPSStyle.Layout.touchTargetMin
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close task usage")
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing3)
    }

    private var selectionBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(selectionSummary)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text2)
                .monospacedDigit()

            Spacer(minLength: OPSStyle.Layout.spacing2)

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                selectedTaskIds = availableTaskIds
            } label: {
                Text("SELECT ALL")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(
                        canSelectAll ? OPSStyle.Colors.text2 : OPSStyle.Colors.textMute
                    )
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSelectAll)
            .accessibilityLabel("Select all \(sourceTasks.count) tasks")

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                selectedTaskIds.removeAll()
            } label: {
                Text("CLEAR")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(
                        selectedTaskIds.isEmpty
                            ? OPSStyle.Colors.textMute
                            : OPSStyle.Colors.text2
                    )
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(selectedTaskIds.isEmpty)
            .accessibilityLabel("Clear task selection")
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .background(OPSStyle.Colors.surfaceInput)
        .overlay(alignment: .top) {
            OPSStyle.Colors.line
                .frame(height: OPSStyle.Layout.Border.standard)
        }
        .overlay(alignment: .bottom) {
            OPSStyle.Colors.line
                .frame(height: OPSStyle.Layout.Border.standard)
        }
    }

    private var selectionSummary: String {
        if selectedTaskIds.isEmpty {
            return taskCountLabel(sourceTasks.count)
        }
        return "\(selectedTaskIds.count) OF \(sourceTasks.count) SELECTED"
    }

    private var canSelectAll: Bool {
        !sourceTasks.isEmpty && selectedTaskIds != availableTaskIds
    }

    // MARK: - Task List

    private var taskList: some View {
        LazyVStack(spacing: 0) {
            ForEach(sourceTasks, id: \.id) { task in
                taskRow(task)

                if task.id != sourceTasks.last?.id {
                    OPSStyle.Colors.line
                        .frame(height: OPSStyle.Layout.Border.standard)
                        .padding(.leading, OPSStyle.Layout.touchTargetMin + OPSStyle.Layout.spacing3)
                }
            }
        }
        .glassSurface()
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing4)
    }

    private func taskRow(_ task: ProjectTask) -> some View {
        let isSelected = selectedTaskIds.contains(task.id)

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            if isSelected {
                selectedTaskIds.remove(task.id)
            } else {
                selectedTaskIds.insert(task.id)
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                selectionControl(isSelected: isSelected)

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(task.displayTitle)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1)

                    Text(taskContext(for: task))
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(1)
                }

                Spacer(minLength: OPSStyle.Layout.spacing2)

                statusBadge(task.status)
            }
            .padding(.trailing, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(task.displayTitle), \(projectName(for: task)), \(clientName(for: task)), \(task.status.displayName)"
        )
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isSelected ? "Double tap to clear selection" : "Double tap to select")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectionControl(isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .fill(isSelected ? OPSStyle.Colors.oliveFillM : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .stroke(
                            isSelected ? OPSStyle.Colors.oliveLineM : OPSStyle.Colors.line,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )

            if isSelected {
                Image(systemName: OPSStyle.Icons.checkmark)
                    .font(.system(
                        size: OPSStyle.Layout.IconSize.sm,
                        weight: .semibold
                    ))
                    .foregroundColor(OPSStyle.Colors.oliveTextM)
            }
        }
        .frame(
            width: OPSStyle.Layout.IconSize.lg,
            height: OPSStyle.Layout.IconSize.lg
        )
        .frame(
            width: OPSStyle.Layout.touchTargetMin,
            height: OPSStyle.Layout.touchTargetMin
        )
        .accessibilityHidden(true)
    }

    private func statusBadge(_ status: TaskStatus) -> some View {
        Text(status.displayName.uppercased())
            .font(OPSStyle.Typography.tagLabel)
            .foregroundColor(status.usageForeground)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .background(status.usageBackground)
            .cornerRadius(OPSStyle.Layout.chipRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(
                        status.usageBorder,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("0")
                .font(OPSStyle.Typography.heroNumberCondensed)
                .foregroundColor(OPSStyle.Colors.text3)
                .monospacedDigit()

            Text("// NO TASKS USING TYPE")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.textMute)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.vertical, OPSStyle.Layout.touchTargetStandard)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No tasks use \(source.display)")
    }

    // MARK: - Reassignment

    private var reassignmentActionBar: some View {
        OPSFloatingButtonBar {
            Button {
                guard !candidateTargets.isEmpty, !isReassigning else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingTargetPicker = true
            } label: {
                Text(isReassigning ? "REASSIGNING" : "REASSIGN \(selectedTaskIds.count)")
            }
            .buttonStyle(
                TaskTypeUsagePrimaryButtonStyle(
                    isDisabled: candidateTargets.isEmpty || isReassigning
                )
            )
            .disabled(candidateTargets.isEmpty || isReassigning)
            .accessibilityLabel(
                candidateTargets.isEmpty
                    ? "No other task types are available"
                    : "Reassign \(selectedTaskIds.count) selected tasks"
            )
        }
    }

    private func performReassignment(to target: TaskType) {
        let taskIds = selectedTaskIds
        guard !taskIds.isEmpty, !isReassigning else { return }

        isReassigning = true
        defer { isReassigning = false }

        do {
            let result = try dataController.reassignTasks(
                taskIds: Array(taskIds),
                fromTaskTypeId: source.id,
                toTaskTypeId: target.id
            )

            selectedTaskIds.removeAll()
            showingTargetPicker = false

            let movedCount = result.movedTaskIds.count
            ToastCenter.shared.present(
                Toast(
                    label: "// \(taskCountLabel(movedCount)) REASSIGNED",
                    tone: .success
                )
            )
        } catch {
            reassignmentError = error.localizedDescription
        }
    }

    // MARK: - Row Metadata

    private func projectName(for task: ProjectTask) -> String {
        nonempty(task.project?.title) ?? "UNLINKED PROJECT"
    }

    private func clientName(for task: ProjectTask) -> String {
        nonempty(task.project?.effectiveClientName) ?? "NO CLIENT"
    }

    private func taskContext(for task: ProjectTask) -> String {
        "\(projectName(for: task).uppercased()) · \(clientName(for: task).uppercased())"
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Target Picker

@MainActor
private struct TaskTypeReassignmentTargetSheet: View {
    let source: TaskType
    let candidates: [TaskType]
    let taskCount: Int
    let isProcessing: Bool
    let onConfirm: (TaskType) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var allTasks: [ProjectTask]

    @State private var selectedTargetId: String?
    @State private var showingConfirmation = false

    private var selectedTarget: TaskType? {
        guard let selectedTargetId else { return nil }
        return candidates.first { $0.id == selectedTargetId }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            summary

            ScrollView {
                if candidates.isEmpty {
                    emptyState
                } else {
                    targetList
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selectedTarget != nil {
                confirmationActionBar
            }
        }
        .alert(
            "MOVE \(taskCountLabel(taskCount))?",
            isPresented: $showingConfirmation,
            presenting: selectedTarget
        ) { target in
            Button("CANCEL", role: .cancel) {}
            Button("REASSIGN") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onConfirm(target)
            }
        } message: { target in
            Text(
                "Move \(taskCountLabel(taskCount).lowercased()) from \(source.display) to \(target.display). Status, schedule, project, and crew stay unchanged."
            )
        }
        .interactiveDismissDisabled(isProcessing)
    }

    private var header: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            Text("REASSIGN TASKS")
                .font(OPSStyle.Typography.screenTitle(for: "REASSIGN TASKS"))
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(1)

            Spacer(minLength: OPSStyle.Layout.spacing2)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: OPSStyle.Icons.close)
                    .font(.system(
                        size: OPSStyle.Layout.IconSize.md,
                        weight: .medium
                    ))
                    .foregroundColor(OPSStyle.Colors.text2)
                    .frame(
                        width: OPSStyle.Layout.touchTargetMin,
                        height: OPSStyle.Layout.touchTargetMin
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            .accessibilityLabel("Close target picker")
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing3)
    }

    private var summary: some View {
        HStack {
            Text("\(taskCountLabel(taskCount)) FROM \(source.display.uppercased())")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text2)
                .monospacedDigit()
                .lineLimit(1)

            Spacer()
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .background(OPSStyle.Colors.surfaceInput)
        .overlay(alignment: .top) {
            OPSStyle.Colors.line
                .frame(height: OPSStyle.Layout.Border.standard)
        }
        .overlay(alignment: .bottom) {
            OPSStyle.Colors.line
                .frame(height: OPSStyle.Layout.Border.standard)
        }
    }

    private var targetList: some View {
        LazyVStack(spacing: 0) {
            ForEach(candidates) { target in
                targetRow(target)

                if target.id != candidates.last?.id {
                    OPSStyle.Colors.line
                        .frame(height: OPSStyle.Layout.Border.standard)
                        .padding(.leading, OPSStyle.Layout.spacing3 + OPSStyle.Layout.spacing1)
                }
            }
        }
        .glassSurface()
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing4)
    }

    private func targetRow(_ target: TaskType) -> some View {
        let isSelected = selectedTargetId == target.id
        let usageCount = TaskTypeSettingsLogic.activeTaskCount(
            for: target,
            in: allTasks
        )

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedTargetId = target.id
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .fill(Color(hex: target.color) ?? OPSStyle.Colors.text3)
                    .frame(
                        width: OPSStyle.Layout.spacing1,
                        height: OPSStyle.Layout.touchTargetMin
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(target.display)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1)

                    Text(taskCountLabel(usageCount))
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .monospacedDigit()
                }

                Spacer(minLength: OPSStyle.Layout.spacing2)

                if target.isDefault {
                    Text("DEFAULT")
                        .font(OPSStyle.Typography.badgeCake)
                        .foregroundColor(OPSStyle.Colors.text2)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .background(OPSStyle.Colors.surfaceInput)
                        .cornerRadius(OPSStyle.Layout.chipRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                .stroke(
                                    OPSStyle.Colors.line,
                                    lineWidth: OPSStyle.Layout.Border.standard
                                )
                        )
                }

                Image(
                    systemName: isSelected
                        ? OPSStyle.Icons.checkmarkSquareFill
                        : OPSStyle.Icons.square
                )
                .font(.system(size: OPSStyle.Layout.IconSize.lg))
                .foregroundColor(
                    isSelected ? OPSStyle.Colors.oliveTextM : OPSStyle.Colors.text3
                )
                .frame(
                    width: OPSStyle.Layout.touchTargetMin,
                    height: OPSStyle.Layout.touchTargetMin
                )
                .accessibilityHidden(true)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Reassign to \(target.display), \(usageCount) current tasks\(target.isDefault ? ", default type" : "")"
        )
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to choose this target")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var confirmationActionBar: some View {
        OPSFloatingButtonBar {
            Button {
                guard selectedTarget != nil, !isProcessing else { return }
                showingConfirmation = true
            } label: {
                Text(isProcessing ? "REASSIGNING" : "REASSIGN \(taskCount)")
            }
            .buttonStyle(
                TaskTypeUsagePrimaryButtonStyle(isDisabled: isProcessing)
            )
            .disabled(isProcessing)
            .accessibilityLabel("Confirm target for \(taskCount) tasks")
        }
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("0")
                .font(OPSStyle.Typography.heroNumberCondensed)
                .foregroundColor(OPSStyle.Colors.text3)
                .monospacedDigit()

            Text("// NO TARGET TYPES")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.textMute)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.vertical, OPSStyle.Layout.touchTargetStandard)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No other task types are available")
    }
}

// MARK: - Local Presentation

private struct TaskTypeUsagePrimaryButtonStyle: ButtonStyle {
    let isDisabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.buttonLabel)
            .textCase(.uppercase)
            .foregroundColor(foregroundColor(isPressed: configuration.isPressed))
            .frame(maxWidth: .infinity)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(
                        isDisabled ? OPSStyle.Colors.line : OPSStyle.Colors.opsAccent,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        if isDisabled {
            return OPSStyle.Colors.textMute
        }
        return isPressed ? OPSStyle.Colors.invertedText : OPSStyle.Colors.opsAccent
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard !isDisabled, isPressed else { return .clear }
        return OPSStyle.Colors.opsAccent
    }
}

private extension TaskStatus {
    var usageForeground: Color {
        switch self {
        case .active:
            return OPSStyle.Colors.text2
        case .completed:
            return OPSStyle.Colors.oliveTextM
        case .cancelled:
            return OPSStyle.Colors.roseTextM
        }
    }

    var usageBackground: Color {
        switch self {
        case .active:
            return OPSStyle.Colors.surfaceInput
        case .completed:
            return OPSStyle.Colors.oliveFillM
        case .cancelled:
            return OPSStyle.Colors.roseFillM
        }
    }

    var usageBorder: Color {
        switch self {
        case .active:
            return OPSStyle.Colors.line
        case .completed:
            return OPSStyle.Colors.oliveLineM
        case .cancelled:
            return OPSStyle.Colors.roseLineM
        }
    }
}

private func taskCountLabel(_ count: Int) -> String {
    "\(count) \(count == 1 ? "TASK" : "TASKS")"
}
