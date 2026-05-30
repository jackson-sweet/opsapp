//
//  UniversalSearchScheduleTargeting.swift
//  OPS
//
//  Pure routing logic for Universal Search schedule quick actions.
//

import Foundation

enum UniversalSearchScheduleTarget: Equatable {
    case task(String)
    case chooseTask(String)
    case unavailable
}

enum UniversalSearchScheduleTargeting {
    static func target(forProject project: Project) -> UniversalSearchScheduleTarget {
        let tasks = schedulableTasks(forProject: project)

        switch tasks.count {
        case 0:
            return .unavailable
        case 1:
            return .task(tasks[0].id)
        default:
            return .chooseTask(project.id)
        }
    }

    static func schedulableTasks(forProject project: Project) -> [ProjectTask] {
        project.tasks.filter { task in
            task.deletedAt == nil && !task.status.isTerminal
        }
    }

    static func accessibilityLabel(forProject project: Project) -> String {
        switch target(forProject: project) {
        case .task: return "Schedule task"
        case .chooseTask: return "Choose task to schedule"
        case .unavailable: return "No tasks to schedule"
        }
    }
}
