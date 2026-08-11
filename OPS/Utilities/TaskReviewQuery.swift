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
//  Every queue comes in two shapes: one that fetches the task table itself, and
//  one that takes an already-fetched `tasks:` array. The fetching shape is a
//  one-line delegate onto the array shape, so scoping cannot diverge between
//  them. The array shape serves callers that need several queues at once — the
//  FAB badge derived five counts from four entry points, each re-fetching the
//  whole task table on the main thread on every sync completion and every
//  schedule mutation, from every tab. One fetch now feeds them all.
//

import Foundation

enum TaskReviewQuery {

    /// Permission-scoped task list. Users with full `tasks.view` access see
    /// every task in the company; everyone else sees only tasks they're
    /// assigned to. This is the scope every review surface — and now every
    /// review COUNT — shares.
    static func scopedTasks(dataController: DataController) -> [ProjectTask] {
        scopedTasks(tasks: dataController.getAllTasks(), dataController: dataController)
    }

    /// `scopedTasks(dataController:)` over an already-fetched task list.
    /// Pass `getAllTasks()` output; the soft-delete gate lives there. Under
    /// `tasks.view=all` this returns the array verbatim, tombstones included.
    static func scopedTasks(
        tasks: [ProjectTask],
        dataController: DataController
    ) -> [ProjectTask] {
        if PermissionStore.shared.hasFullAccess("tasks.view") {
            return tasks
        }
        if let userId = dataController.currentUser?.id {
            return tasks.filter { task in
                task.getTeamMemberIds().contains(userId)
            }
        }
        return []
    }

    /// Mutation-scoped rows for Unassigned Review. Live project_tasks RLS
    /// accepts tasks.edit=all, or tasks.edit=assigned when the operator is on
    /// the task or its project. A view-only grant must never produce an
    /// actionable review card.
    static func editableTasks(dataController: DataController) -> [ProjectTask] {
        editableTasks(tasks: dataController.getAllTasks(), dataController: dataController)
    }

    /// `editableTasks(dataController:)` over an already-fetched task list.
    /// Pass `getAllTasks()` output; the soft-delete gate lives there. Under
    /// `tasks.edit=all` this returns the array verbatim, tombstones included.
    static func editableTasks(
        tasks allTasks: [ProjectTask],
        dataController: DataController
    ) -> [ProjectTask] {
        switch PermissionStore.shared.scope(for: "tasks.edit") {
        case "all":
            return allTasks
        case "assigned":
            guard let userID = dataController.currentUser?.id.lowercased() else {
                return []
            }
            return allTasks.filter { task in
                task.getTeamMemberIds().contains {
                    $0.lowercased() == userID
                } || (task.project?.getTeamMemberIds().contains {
                    $0.lowercased() == userID
                } ?? false)
            }
        default:
            return []
        }
    }

    /// Overdue-completion review queue: active, non-deleted tasks whose
    /// scheduled completion (endDate, falling back to startDate) is before the
    /// end of today. Sorted oldest-first to match the review stack ordering.
    static func overdueReviewTasks(dataController: DataController) -> [ProjectTask] {
        overdueReviewTasks(tasks: dataController.getAllTasks(), dataController: dataController)
    }

    /// `overdueReviewTasks(dataController:)` over an already-fetched task list.
    static func overdueReviewTasks(
        tasks: [ProjectTask],
        dataController: DataController
    ) -> [ProjectTask] {
        let calendar = Calendar.current
        let endOfToday = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )
        return scopedTasks(tasks: tasks, dataController: dataController)
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
        unscheduledReviewTasks(tasks: dataController.getAllTasks(), dataController: dataController)
    }

    /// `unscheduledReviewTasks(dataController:)` over an already-fetched task list.
    static func unscheduledReviewTasks(
        tasks: [ProjectTask],
        dataController: DataController
    ) -> [ProjectTask] {
        let policy = UnscheduledReviewAccessPolicy(
            currentUserID: dataController.currentUser?.id,
            taskEditScope: ReviewPermissionScope(
                PermissionStore.shared.scope(for: "tasks.edit")
            ),
            canAssignTasks: PermissionStore.shared.hasFullAccess("tasks.assign"),
            taskStatusScope: ReviewPermissionScope(
                PermissionStore.shared.scope(for: "tasks.change_status")
            ),
            calendarEditScope: ReviewPermissionScope(
                PermissionStore.shared.scope(for: "calendar.edit")
            )
        )

        return editableTasks(tasks: tasks, dataController: dataController)
            .filter { task in
                let state = UnscheduledReviewTaskState(
                    taskTeamMemberIDs: task.getTeamMemberIds(),
                    projectTeamMemberIDs: task.project?.getTeamMemberIds() ?? [],
                    isScheduled: task.startDate != nil
                )
                return task.status == .active
                    && task.deletedAt == nil
                    && (task.project?.status.isActive ?? false)
                    && (task.startDate == nil || task.getTeamMemberIds().isEmpty)
                    && policy.hasAvailableMutation(for: state)
            }
            .sorted { ($0.project?.title ?? "") < ($1.project?.title ?? "") }
    }
}
