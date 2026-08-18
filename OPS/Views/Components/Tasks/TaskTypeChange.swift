//
//  TaskTypeChange.swift
//  OPS
//
//  Committing a task-type change, in one place.
//
//  A mis-typed job gets spotted wherever the operator happens to be looking —
//  the kanban board, or the task list inside a project. Both offer the same
//  Change Type action, both raise the same `TaskTypePickerSheet`, and both land
//  the write through here, so the two routes are literally one flow (item f15fff4f).
//

import SwiftUI
import UIKit

@MainActor
enum TaskTypeChange {

    /// Commit a task type picked from a long-press menu.
    ///
    /// Routed through `DataController.updateTaskFields` rather than a bare
    /// `modelContext.save()` so the edit is queued for sync instead of being
    /// stranded on this device, and the calendars are told to repaint because the
    /// type drives every job's colour and title.
    static func commit(task: ProjectTask, to picked: TaskType, dataController: DataController) {
        guard picked.id != task.taskTypeId else { return }
        let taskId = task.id
        let newTypeId = picked.id

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        ToastCenter.shared.present(Feedback.Task.typeUpdated)

        // Deferred off the picker's dismiss critical path for the same reason
        // ProjectDetails defers its type commit: `updateTaskFields` saves the model
        // context, and that notification cascade landing mid sheet animation is what
        // tore down the host view in bugs 0aa825fe / 62481022.
        DispatchQueue.main.async {
            Task {
                do {
                    try await dataController.updateTaskFields(
                        taskId: taskId,
                        fields: ["task_type_id": .string(newTypeId)]
                    )
                    dataController.notifyReviewSourcesChanged()
                } catch {
                    print("[TASK_TYPE_CHANGE] Task type update failed: \(error)")
                }
            }
        }
    }
}
