//
//  TaskTypeDeletionSheet.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-10-07.
//

import SwiftUI
import SwiftData

struct TaskTypeDeletionSheet: View {
    let taskType: TaskType
    var onDeletionStarted: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @Query private var allTaskTypes: [TaskType]

    @State private var reassignmentMode: ReassignmentMode = .bulk
    @State private var reassignments: [String: String] = [:]
    @State private var tasksToDelete: Set<String> = []
    @State private var bulkSelectedTaskType: String?
    @State private var bulkDeleteAll = false
    @State private var isDeleting = false
    @State private var showingError = false
    @State private var errorMessage = ""

    private var taskTypeTasks: [ProjectTask] {
        taskType.tasks.sorted { $0.displayOrder < $1.displayOrder }
    }

    private var availableTaskTypes: [TaskType] {
        allTaskTypes.filter { $0.id != taskType.id }
    }

    private var canDeleteTaskType: Bool {
        if taskTypeTasks.isEmpty {
            return true
        }

        switch reassignmentMode {
        case .bulk:
            return bulkSelectedTaskType != nil || bulkDeleteAll
        case .individual:
            return taskTypeTasks.allSatisfy { task in
                reassignments[task.id] != nil || tasksToDelete.contains(task.id)
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DELETE TASK TYPE")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                                .frame(width: 12, height: 12)

                            if let icon = taskType.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                            }

                            Text(taskType.display)
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }

                        Text("\(taskTypeTasks.count) task\(taskTypeTasks.count == 1 ? "" : "s")")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                    if !taskTypeTasks.isEmpty {
                        SegmentedControl(
                            selection: $reassignmentMode,
                            options: [
                                (.bulk, "Bulk Reassign"),
                                (.individual, "Individual")
                            ]
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                        ScrollView {
                            VStack(spacing: 16) {
                                if reassignmentMode == .bulk {
                                    bulkReassignmentView
                                } else {
                                    individualReassignmentView
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 100)
                        }
                    } else {
                        Spacer()
                    }
                }

                Button(action: performDeletion) {
                    HStack {
                        if isDeleting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.errorStatus))
                                .scaleEffect(0.8)
                        } else {
                            Text("Delete Task Type")
                                .font(OPSStyle.Typography.body)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.ultraThinMaterial)
                    .foregroundColor(
                        canDeleteTaskType
                            ? OPSStyle.Colors.errorStatus
                            : OPSStyle.Colors.tertiaryText
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(
                                canDeleteTaskType
                                    ? OPSStyle.Colors.errorStatus
                                    : OPSStyle.Colors.tertiaryText,
                                lineWidth: 1.5
                            )
                    )
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .disabled(!canDeleteTaskType || isDeleting)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .disabled(isDeleting)
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var bulkReassignmentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !bulkDeleteAll {
                Text("Reassign all \(taskTypeTasks.count) task\(taskTypeTasks.count == 1 ? "" : "s") to:")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                TaskTypeSearchField(
                    selectedTaskTypeId: $bulkSelectedTaskType,
                    availableTaskTypes: availableTaskTypes,
                    placeholder: "Search for task type"
                )
            } else {
                Text("All \(taskTypeTasks.count) task\(taskTypeTasks.count == 1 ? "" : "s") will be deleted")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .italic()
            }

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    bulkDeleteAll.toggle()
                    if bulkDeleteAll {
                        bulkSelectedTaskType = nil
                    }
                }
            }) {
                HStack {
                    Image(systemName: bulkDeleteAll ? OPSStyle.Icons.close : OPSStyle.Icons.delete)
                        .font(OPSStyle.Typography.body)
                    Text(bulkDeleteAll ? "Don't Delete All Tasks" : "Delete All Tasks")
                        .font(OPSStyle.Typography.bodyBold)
                }
                .foregroundColor(bulkDeleteAll ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.errorStatus)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(bulkDeleteAll ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.errorStatus, lineWidth: 1.5)
                )
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }

    private var individualReassignmentView: some View {
        VStack(spacing: 12) {
            ForEach(taskTypeTasks) { task in
                TaskReassignmentRow(
                    task: task,
                    selectedTaskTypeId: binding(for: task.id),
                    markedForDeletion: tasksToDelete.contains(task.id),
                    availableTaskTypes: availableTaskTypes,
                    onToggleDelete: { toggleTaskDeletion(task.id) }
                )
            }
        }
    }

    private func binding(for taskId: String) -> Binding<String?> {
        Binding(
            get: { reassignments[taskId] },
            set: { reassignments[taskId] = $0 }
        )
    }

    private func toggleTaskDeletion(_ taskId: String) {
        if tasksToDelete.contains(taskId) {
            tasksToDelete.remove(taskId)
        } else {
            tasksToDelete.insert(taskId)
            reassignments.removeValue(forKey: taskId)
        }
    }

    private func performDeletion() {
        dismiss()
        onDeletionStarted?()

        Task {
            do {
                if reassignmentMode == .bulk {
                    if bulkDeleteAll {
                        for task in taskTypeTasks {
                            if let calendarEvent = task.calendarEvent {
                                await MainActor.run {
                                    modelContext.delete(calendarEvent)
                                }
                            }
                            await MainActor.run {
                                modelContext.delete(task)
                            }
                        }
                    } else if let newTaskTypeId = bulkSelectedTaskType,
                       let newTaskType = availableTaskTypes.first(where: { $0.id == newTaskTypeId }) {
                        for task in taskTypeTasks {
                            await MainActor.run {
                                task.taskType = newTaskType
                                task.taskTypeId = newTaskTypeId
                                task.taskColor = newTaskType.color
                            }
                            try await dataController.apiService.updateTaskType(id: task.id, taskTypeId: newTaskTypeId, taskColor: newTaskType.color)
                        }
                    }
                } else {
                    for task in taskTypeTasks {
                        if tasksToDelete.contains(task.id) {
                            if let calendarEvent = task.calendarEvent {
                                await MainActor.run {
                                    modelContext.delete(calendarEvent)
                                }
                            }
                            await MainActor.run {
                                modelContext.delete(task)
                            }
                        } else if let newTaskTypeId = reassignments[task.id],
                           let newTaskType = availableTaskTypes.first(where: { $0.id == newTaskTypeId }) {
                            await MainActor.run {
                                task.taskType = newTaskType
                                task.taskTypeId = newTaskTypeId
                                task.taskColor = newTaskType.color
                            }
                            try await dataController.apiService.updateTaskType(id: task.id, taskTypeId: newTaskTypeId, taskColor: newTaskType.color)
                        }
                    }
                }

                await MainActor.run {
                    do {
                        try modelContext.save()
                        print("[TASK_TYPE_DELETE] ✅ Task reassignments saved locally")
                    } catch {
                        print("[TASK_TYPE_DELETE] ❌ Error saving reassignments: \(error)")
                    }
                }

                print("[TASK_TYPE_DELETE] Deleting task type from Bubble: \(taskType.id)")
                try await dataController.apiService.deleteTaskType(id: taskType.id)
                print("[TASK_TYPE_DELETE] ✅ Task type deleted from Bubble")

                await MainActor.run {
                    modelContext.delete(taskType)
                    do {
                        try modelContext.save()
                        print("[TASK_TYPE_DELETE] ✅ Task type deleted locally")
                        NotificationCenter.default.post(name: NSNotification.Name("TaskTypeDeleted"), object: nil)
                    } catch {
                        print("[TASK_TYPE_DELETE] ❌ Error saving after local delete: \(error)")
                    }
                }
            } catch {
                print("[TASK_TYPE_DELETE] ❌ Error during deletion: \(error)")
            }
        }
    }
}

struct TaskReassignmentRow: View {
    let task: ProjectTask
    @Binding var selectedTaskTypeId: String?
    let markedForDeletion: Bool
    let availableTaskTypes: [TaskType]
    let onToggleDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(task.status.color)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.displayTitle)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(markedForDeletion ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryText)

                    HStack(spacing: 4) {
                        if let projectTitle = task.project?.title {
                            Text(projectTitle)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }

                        if let clientName = task.project?.client?.name {
                            if task.project?.title != nil {
                                Text("•")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            Text(clientName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                }

                if markedForDeletion {
                    Spacer()
                    Text("Will be deleted")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .italic()
                }
            }

            if markedForDeletion {
                Button(action: onToggleDelete) {
                    HStack {
                        Image(systemName: OPSStyle.Icons.close)
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.errorStatus)

                        Text("Don't Delete Task")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.errorStatus)

                        Spacer()
                    }
                    .padding(12)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
                }
            } else {
                HStack(spacing: 8) {
                    TaskTypeSearchField(
                        selectedTaskTypeId: $selectedTaskTypeId,
                        availableTaskTypes: availableTaskTypes,
                        placeholder: "Search for task type"
                    )

                    Button(action: onToggleDelete) {
                        Image(systemName: OPSStyle.Icons.delete)
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .frame(width: 44, height: 44)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                            )
                    }
                }
            }
        }
    }
}

struct TaskTypeSearchField: View {
    @Binding var selectedTaskTypeId: String?
    let availableTaskTypes: [TaskType]
    let placeholder: String

    @State private var searchText: String = ""
    @State private var showingSuggestions = false
    @FocusState private var isFocused: Bool

    private var filteredTaskTypes: [TaskType] {
        if searchText.isEmpty {
            return availableTaskTypes.sorted { $0.display < $1.display }
        }
        return availableTaskTypes
            .filter { $0.display.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.display < $1.display }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                TextField(placeholder, text: $searchText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .focused($isFocused)
                    .onChange(of: searchText) { _, newValue in
                        if !newValue.isEmpty {
                            showingSuggestions = true
                        } else {
                            showingSuggestions = false
                        }
                    }
                    .onTapGesture {
                        showingSuggestions = true
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        selectedTaskTypeId = nil
                        showingSuggestions = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(12)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )

            if showingSuggestions && !filteredTaskTypes.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredTaskTypes.prefix(5)) { taskType in
                        Button(action: {
                            selectTaskType(taskType)
                        }) {
                            HStack {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                                        .frame(width: 8, height: 8)

                                    if let icon = taskType.icon {
                                        Image(systemName: icon)
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(taskType.display)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                            .lineLimit(1)

                                        if taskType.tasks.count > 0 {
                                            Text("\(taskType.tasks.count) task\(taskType.tasks.count == 1 ? "" : "s")")
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        }
                                    }
                                }

                                Spacer()

                                if selectedTaskTypeId == taskType.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14))
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(PlainButtonStyle())

                        if taskType.id != filteredTaskTypes.prefix(5).last?.id {
                            Divider()
                                .background(OPSStyle.Colors.tertiaryText.opacity(0.3))
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                )
                .shadow(color: OPSStyle.Colors.shadowColor, radius: 8, x: 0, y: 4)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showingSuggestions)
        .onAppear {
            if let id = selectedTaskTypeId,
               let taskType = availableTaskTypes.first(where: { $0.id == id }) {
                searchText = taskType.display
            }
        }
    }

    private func selectTaskType(_ taskType: TaskType) {
        selectedTaskTypeId = taskType.id
        searchText = taskType.display
        showingSuggestions = false
        isFocused = false
    }
}
