//
//  CalendarTaskScope.swift
//  OPS
//
//  The calendar's "may this task appear, for this operator, right now" rule, lifted
//  out of CalendarViewModel so exactly one implementation answers it — on the main
//  actor for the surfaces that already hold live models, and on the DataActor for
//  the rebuild passes that must not fault relationships on the main thread
//  (bug 1bade6dd: every schedule commit fanned out to a full main-thread rescan and
//  froze the screen for seconds).
//
//  Scoping contract — the same one DataActor+HomeRollup states: the CALLER decides.
//  Permission answers are read from PermissionStore on the main actor and frozen
//  into `CalendarTaskScope`; the off-main pass never re-derives visibility, so it
//  cannot disagree with what the on-screen surfaces show.
//

import Foundation
import SwiftData

/// Everything the calendar's visibility decision depends on, as a value that can
/// cross an actor boundary.
struct CalendarTaskScope: Sendable, Equatable {

    /// The schedule's ALL / MINE / one-crew-member scope. Mirrors
    /// `CalendarViewModel.ScheduleScope`, which cannot itself cross the boundary
    /// (it lives on a view model that owns live models).
    enum Mode: Sendable, Equatable {
        case all
        case mine
        case member(String)
    }

    let mode: Mode
    /// The signed-in operator. Empty only when there is no session, in which case
    /// no assignment test can pass — matching the `guard let user` bail the
    /// main-thread paths take.
    let userId: String
    let companyId: String?
    /// `PermissionStore.can("calendar.view", requiredScope: "all")` — the same gate
    /// `CalendarViewModel.shouldShowTeamMemberFilter` reads.
    let canViewAllCalendar: Bool
    /// `PermissionStore.hasFullAccess("tasks.view")`.
    let hasFullTaskAccess: Bool

    let selectedTeamMemberIds: Set<String>
    let selectedTaskTypeIds: Set<String>
    let selectedClientIds: Set<String>
    let selectedStatuses: Set<Status>
}

/// The pure rule. Takes live models but holds no isolation of its own, so the same
/// function body runs against the main context's rows and against the DataActor's.
enum CalendarTaskScoping {

    /// The week canvas's scope gate. Branch-for-branch what `rebuildWeekCache` ran
    /// inline before it moved off the main thread.
    static func admitsForWeekCanvas(_ task: ProjectTask, scope: CalendarTaskScope) -> Bool {
        switch scope.mode {
        case .all:
            if scope.canViewAllCalendar { return task.companyId == scope.companyId }
            if scope.hasFullTaskAccess { return task.companyId == scope.companyId }
            return isAssigned(task, to: scope.userId)
        case .mine:
            if scope.hasFullTaskAccess { return task.companyId == scope.companyId }
            return isAssigned(task, to: scope.userId)
        case .member(let memberId):
            guard task.companyId == scope.companyId else { return false }
            return isAssigned(task, to: memberId)
        }
    }

    /// The month grid's scope gate — `DataController.getAllScheduledTasks`'s branch.
    /// It deliberately ignores `mode`: the grid has always shown everything the
    /// operator may see and let `passesFilters` do the narrowing.
    static func admitsForMonthGrid(_ task: ProjectTask, scope: CalendarTaskScope) -> Bool {
        if scope.hasFullTaskAccess { return task.companyId == scope.companyId }
        return isAssigned(task, to: scope.userId)
    }

    /// Assignment: the task's own crew, or — when the task names nobody this person
    /// is on — the project's. Both id-string and relationship forms are consulted
    /// because assignment is stored twice (a comma-joined string plus a to-many
    /// relationship) and either can be the one that is populated.
    static func isAssigned(_ task: ProjectTask, to memberId: String) -> Bool {
        guard !memberId.isEmpty else { return false }
        if task.getTeamMemberIds().contains(memberId)
            || task.teamMembers.contains(where: { $0.id == memberId }) {
            return true
        }
        guard let project = task.project else { return false }
        return project.getTeamMemberIds().contains(memberId)
            || project.teamMembers.contains(where: { $0.id == memberId })
    }

    /// The filter chain every calendar surface shares — commitment visibility first
    /// (unwon and filed-away work never reaches the crew/type/client cuts), then the
    /// operator's own filter selections. Row-at-a-time so callers can fuse it with
    /// their scope gate in a single pass.
    static func passesFilters(
        _ task: ProjectTask,
        scope: CalendarTaskScope,
        hiddenProjectIds: Set<String>
    ) -> Bool {
        guard CalendarTaskVisibility.includes(
            projectId: task.projectId,
            hiddenProjectIds: hiddenProjectIds
        ) else { return false }

        if !scope.selectedTeamMemberIds.isEmpty {
            let onCrew = task.teamMembers.contains { scope.selectedTeamMemberIds.contains($0.id) }
                || task.getTeamMemberIds().contains { scope.selectedTeamMemberIds.contains($0) }
            guard onCrew else { return false }
        }

        if !scope.selectedTaskTypeIds.isEmpty {
            let taskTypeId = task.taskTypeId
            guard !taskTypeId.isEmpty, scope.selectedTaskTypeIds.contains(taskTypeId) else { return false }
        }

        if !scope.selectedClientIds.isEmpty {
            guard let clientId = task.project?.clientId,
                  scope.selectedClientIds.contains(clientId) else { return false }
        }

        if !scope.selectedStatuses.isEmpty {
            guard let status = task.project?.status,
                  scope.selectedStatuses.contains(status) else { return false }
        }

        return true
    }
}
