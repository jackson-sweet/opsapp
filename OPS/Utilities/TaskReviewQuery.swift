//
//  TaskReviewQuery.swift
//  OPS
//
//  Single source of truth for the task-review queues.
//
//  The overdue-completion and unscheduled review queues are surfaced in four
//  places: the periodic notification check (AppState.checkOverdueTasks), the
//  persistent rail (ReviewThresholdService), the JobBoard header entries
//  (computeReviewableTasks / computeUnscheduledTasks), and the FAB review menu
//  (computeFABReviewableTasks / computeFABIncompleteTasks). Each held its own
//  copy of the predicate, and they had drifted:
//
//    1. The periodic push counted EVERY task in the company (no permission
//       scope) while every surface the user actually opens is scoped to their
//       own assignments — so a crew member got a push reading "15 tasks past
//       scheduled completion" but opened a stack with only their own handful.
//    2. The unscheduled COUNT omitted the `project.status.isActive` gate that
//       the unscheduled STACK applies, so "LOOSE ENDS — N tasks with no date or
//       crew" counted tasks on inactive/unsynced projects that never appeared
//       in the review.
//
//  Centralizing the predicates here guarantees the count the user is promised
//  is identical to the stack they open.
//

import Foundation

enum TaskReviewQuery {

    /// Permission-scoped task list. Users with full `tasks.view` access see
    /// every task in the company; everyone else sees only tasks they're
    /// assigned to. This is the scope every review surface — and now every
    /// review COUNT — shares.
    static func scopedTasks(dataController: DataController) -> [ProjectTask] {
        if PermissionStore.shared.hasFullAccess("tasks.view") {
            return dataController.getAllTasks()
        }
        if let userId = dataController.currentUser?.id {
            return dataController.getAllTasks().filter { task in
                task.getTeamMemberIds().contains(userId)
            }
        }
        return []
    }

    /// Overdue-completion review queue: active, non-deleted tasks whose
    /// scheduled completion (endDate, falling back to startDate) is before the
    /// end of today. Sorted oldest-first to match the review stack ordering.
    static func overdueReviewTasks(dataController: DataController) -> [ProjectTask] {
        let calendar = Calendar.current
        let endOfToday = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )
        return scopedTasks(dataController: dataController)
            .filter { task in
                guard task.status == .active, task.deletedAt == nil else { return false }
                // Prefer scheduled completion (endDate), fall back to startDate.
                guard let scheduledDate = task.endDate ?? task.startDate else { return false }
                return scheduledDate < endOfToday
            }
            .sorted {
                let a = $0.endDate ?? $0.startDate ?? .distantPast
                let b = $1.endDate ?? $1.startDate ?? .distantPast
                return a < b
            }
    }

    /// Unscheduled / unassigned review queue: active, non-deleted tasks on an
    /// ACTIVE project that are missing a start date or have no crew assigned.
    ///
    /// The `project.status.isActive` gate matters: a task whose project is
    /// rfq/estimated/completed/closed/archived — or whose project relationship
    /// hasn't synced locally (`?? false`) — is not schedulable work and must not
    /// be surfaced as a "loose end". Mirrors `isJobBoardTaskListVisible`.
    static func unscheduledReviewTasks(dataController: DataController) -> [ProjectTask] {
        return scopedTasks(dataController: dataController)
            .filter { task in
                task.status == .active
                    && task.deletedAt == nil
                    && (task.project?.status.isActive ?? false)
                    && (task.startDate == nil || task.getTeamMemberIds().isEmpty)
            }
            .sorted { ($0.project?.title ?? "") < ($1.project?.title ?? "") }
    }
}
