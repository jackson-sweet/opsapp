//
//  TaskTypeSettingsLogic.swift
//  OPS
//
//  Pure list rules for Settings.Tasks.
//

import Foundation

enum TaskTypeSettingsLogic {
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
}
