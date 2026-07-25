//
//  TaskTypeSettingsLogic.swift
//  OPS
//
//  Pure list rules for Settings.Tasks.
//

import Foundation

enum TaskTypeLoadState: Equatable {
    case loading
    case loaded
    case failed
}

enum TaskTypeSettingsLogic {
    /// A non-empty local cache is usable offline. An empty cache is not
    /// authoritative until a remote refresh completes successfully.
    static func loadState(
        hasCachedTaskTypes: Bool,
        remoteRefreshSucceeded: Bool?
    ) -> TaskTypeLoadState {
        if hasCachedTaskTypes {
            return .loaded
        }

        switch remoteRefreshSucceeded {
        case .some(true):
            return .loaded
        case .some(false):
            return .failed
        case .none:
            return .loading
        }
    }

    static func visibleTaskTypes(_ taskTypes: [TaskType], companyId: String) -> [TaskType] {
        taskTypes.filter { taskType in
            taskType.companyId == companyId && taskType.deletedAt == nil
        }
    }

    static func sortedTaskTypes(_ taskTypes: [TaskType]) -> [TaskType] {
        let custom = taskTypes
            .filter { !$0.isDefault }
            .sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
        let defaults = taskTypes
            .filter(\.isDefault)
            .sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
        return custom + defaults
    }

    static func activeTaskCount(
        for taskType: TaskType,
        in tasks: [ProjectTask]
    ) -> Int {
        tasksUsing(taskType, in: tasks).count
    }

    static func tasksUsing(
        _ taskType: TaskType,
        in tasks: [ProjectTask]
    ) -> [ProjectTask] {
        let taskTypeId = taskType.id.lowercased()
        let companyId = taskType.companyId.lowercased()

        return tasks.filter { task in
            task.deletedAt == nil
                && task.companyId.lowercased() == companyId
                && task.taskTypeId.lowercased() == taskTypeId
        }
    }
}
