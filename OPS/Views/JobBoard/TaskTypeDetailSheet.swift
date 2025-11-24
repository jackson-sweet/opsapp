//
//  TaskTypeDetailSheet.swift
//  OPS
//
//  Created by Assistant on 2025-09-26.
//

import SwiftUI
import SwiftData

struct TaskTypeDetailSheet: View {
    let taskType: TaskType
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @Query private var allTaskTypes: [TaskType]
    @State private var showingEditForm = false
    @State private var showingDeletionSheet = false

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        // Task Type Header
                        SectionCard(
                            icon: taskType.icon ?? "checklist",
                            title: "Task Type"
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(taskType.display)
                                    .font(OPSStyle.Typography.title)
                                    .foregroundColor(OPSStyle.Colors.primaryText)

                                Text(taskType.isDefault ? "Default Task Type" : "Custom Task Type")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        }

                        // Properties
                        SectionCard(
                            icon: "list.bullet",
                            title: "Properties",
                            contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                        ) {
                            VStack(spacing: 0) {
                                PropertyRow(
                                    label: "Name",
                                    value: taskType.display
                                )

                                Divider()
                                    .background(OPSStyle.Colors.cardBorder)

                                PropertyRow(
                                    label: "Icon",
                                    value: taskType.icon ?? "checklist"
                                )

                                Divider()
                                    .background(OPSStyle.Colors.cardBorder)

                                HStack {
                                    Text("COLOR")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    Spacer()

                                    Circle()
                                        .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                                        .frame(width: 24, height: 24)
                                }
                                .padding(OPSStyle.Layout.spacing3)

                                Divider()
                                    .background(OPSStyle.Colors.cardBorder)

                                PropertyRow(
                                    label: "Type",
                                    value: taskType.isDefault ? "System Default" : "User Created"
                                )
                            }
                        }

                        // Usage Stats
                        SectionCard(
                            icon: "chart.bar.fill",
                            title: "Usage"
                        ) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Used in Projects")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                    Text("0")
                                        .font(OPSStyle.Typography.title)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Total Tasks")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                    Text("0")
                                        .font(OPSStyle.Typography.title)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                }
                            }
                        }

                        if !taskType.isDefault {
                            // Edit/Delete buttons for custom task types
                            VStack(spacing: OPSStyle.Layout.spacing2) {
                                Button(action: {
                                    showingEditForm = true
                                }) {
                                    HStack {
                                        Image(systemName: OPSStyle.Icons.pencil)
                                            .font(.system(size: 16))
                                        Text("EDIT TASK TYPE")
                                            .font(OPSStyle.Typography.bodyBold)
                                    }
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(OPSStyle.Layout.spacing3)
                                    .background(OPSStyle.Colors.primaryAccent)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                }

                                Button(action: {
                                    showingDeletionSheet = true
                                }) {
                                    HStack {
                                        Image(systemName: OPSStyle.Icons.trash)
                                            .font(.system(size: 16))
                                        Text("DELETE TASK TYPE")
                                            .font(OPSStyle.Typography.bodyBold)
                                    }
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                                    .frame(maxWidth: .infinity)
                                    .padding(OPSStyle.Layout.spacing3)
                                    .background(OPSStyle.Colors.errorStatus.opacity(0.1))
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.errorStatus.opacity(0.3), lineWidth: 1)
                                    )
                                }
                            }
                            .padding(.top, OPSStyle.Layout.spacing3)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .navigationTitle(taskType.display.uppercased())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("DONE") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .sheet(isPresented: $showingEditForm) {
            TaskTypeSheet(mode: .edit(taskType: taskType) {
                showingEditForm = false
            })
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showingDeletionSheet) {
            DeletionSheet(
                item: taskType,
                itemType: "Task Type",
                childItems: taskType.tasks.sorted { $0.displayOrder < $1.displayOrder },
                childType: "Task",
                availableReassignments: allTaskTypes,
                getItemDisplay: { taskType in
                    AnyView(
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
                    )
                },
                filterAvailableItems: { taskTypes in
                    taskTypes.filter { $0.id != taskType.id }
                },
                getChildId: { $0.id },
                getReassignmentId: { $0.id },
                renderReassignmentRow: { task, selectedId, markedForDeletion, available, onToggleDelete in
                    AnyView(
                        TaskReassignmentRow(
                            task: task,
                            selectedTaskTypeId: selectedId,
                            markedForDeletion: markedForDeletion,
                            availableTaskTypes: available,
                            onToggleDelete: onToggleDelete
                        )
                    )
                },
                renderSearchField: { selectedId, available in
                    AnyView(
                        SearchField(
                            selectedId: selectedId,
                            items: available,
                            placeholder: "Search for task type",
                            leadingIcon: "square.grid.2x2.fill",
                            getId: { $0.id },
                            getDisplayText: { $0.display },
                            getSubtitle: { taskType in
                                taskType.tasks.count > 0
                                    ? "\(taskType.tasks.count) task\(taskType.tasks.count == 1 ? "" : "s")"
                                    : nil
                            },
                            getLeadingAccessory: { taskType in
                                AnyView(
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                                            .frame(width: 8, height: 8)

                                        if let icon = taskType.icon {
                                            Image(systemName: icon)
                                                .font(.system(size: 14))
                                                .foregroundColor(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                                        }
                                    }
                                )
                            }
                        )
                    )
                },
                onDelete: { taskType, reassignments, deletions in
                    let taskTypeTasks = taskType.tasks.sorted { $0.displayOrder < $1.displayOrder }
                    let availableTaskTypes = allTaskTypes.filter { $0.id != taskType.id }

                    // Check if bulk operation
                    let uniqueAssignments = Set(reassignments.values)
                    if uniqueAssignments.count == 1, let bulkTaskTypeId = uniqueAssignments.first {
                        // Bulk reassignment
                        if let newTaskType = availableTaskTypes.first(where: { $0.id == bulkTaskTypeId }) {
                            for task in taskTypeTasks {
                                await MainActor.run {
                                    task.taskType = newTaskType
                                    task.taskTypeId = bulkTaskTypeId
                                    task.taskColor = newTaskType.color
                                }
                                try await dataController.apiService.updateTaskType(id: task.id, taskTypeId: bulkTaskTypeId, taskColor: newTaskType.color)
                            }
                        }
                    } else if deletions.count == taskTypeTasks.count {
                        // Bulk delete all tasks
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
                    } else {
                        // Individual mode
                        for task in taskTypeTasks {
                            if deletions.contains(task.id) {
                                // Delete task and associated calendar event
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
                                // Reassign task to new task type
                                await MainActor.run {
                                    task.taskType = newTaskType
                                    task.taskTypeId = newTaskTypeId
                                    task.taskColor = newTaskType.color
                                }
                                try await dataController.apiService.updateTaskType(id: task.id, taskTypeId: newTaskTypeId, taskColor: newTaskType.color)
                            }
                        }
                    }

                    // Save task reassignments
                    await MainActor.run {
                        do {
                            try modelContext.save()
                            print("[TASK_TYPE_DELETE] ✅ Task reassignments saved locally")
                        } catch {
                            print("[TASK_TYPE_DELETE] ❌ Error saving reassignments: \(error)")
                        }
                    }

                    // Delete task type from Bubble
                    print("[TASK_TYPE_DELETE] Deleting task type from Bubble: \(taskType.id)")
                    try await dataController.apiService.deleteTaskType(id: taskType.id)
                    print("[TASK_TYPE_DELETE] ✅ Task type deleted from Bubble")

                    // Delete task type locally
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
                },
                onDeletionStarted: {
                    // Dismiss immediately (like the original implementation)
                    dismiss()
                }
            )
            .environmentObject(dataController)
        }
    }
}

struct PropertyRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Spacer()

            Text(value)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
    }
}