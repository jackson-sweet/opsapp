//
//  TaskTypeSelectionPolicy.swift
//  OPS
//
//  Shared eligibility rules for user-facing task type choices.
//

import Foundation

enum TaskTypeSelectionPolicy {
    /// Returns task types that may be offered as a new user choice.
    ///
    /// Soft-deleted rows remain in the local cache so sync and historical
    /// references can resolve them, but they must never appear in a picker or
    /// filter. Callers may omit `companyId` when their input is already scoped.
    /// Input order is preserved so each surface can retain its own sort policy.
    static func selectableTaskTypes(
        from taskTypes: [TaskType],
        companyId: String? = nil
    ) -> [TaskType] {
        taskTypes.filter { taskType in
            guard taskType.deletedAt == nil else { return false }
            guard let companyId else { return true }
            return taskType.companyId == companyId
        }
    }

    /// Removes selections that are no longer present in the selectable set.
    static func sanitizedSelection(
        _ selection: Set<String>,
        from taskTypes: [TaskType],
        companyId: String? = nil
    ) -> Set<String> {
        let selectableIds = Set(
            selectableTaskTypes(from: taskTypes, companyId: companyId).map(\.id)
        )
        return selection.intersection(selectableIds)
    }

    /// Resolves a task type that may be persisted on a task row.
    ///
    /// Active same-company types are always valid. A soft-deleted type is only
    /// valid when it is the unchanged original value of an existing task,
    /// preserving historical rows without allowing a tombstone to become a
    /// new or changed selection.
    static func persistableTaskType(
        id: String,
        originalTaskTypeId: String? = nil,
        from taskTypes: [TaskType],
        companyId: String
    ) -> TaskType? {
        if let selectable = selectableTaskTypes(
            from: taskTypes,
            companyId: companyId
        ).first(where: { $0.id == id }) {
            return selectable
        }

        guard originalTaskTypeId == id else { return nil }
        return taskTypes.first {
            $0.id == id && $0.companyId == companyId
        }
    }
}
