//
//  JobBoardListRules.swift
//  OPS
//

import CoreGraphics
import Foundation

enum DirectionalDragAxis: Equatable {
    case undecided
    case horizontal
    case vertical
}

struct DirectionalDragClassifier {
    private static let axisThreshold: CGFloat = 12
    private static let horizontalDominanceRatio: CGFloat = 3

    static func axis(forTranslation translation: CGSize) -> DirectionalDragAxis {
        let absW = abs(translation.width)
        let absH = abs(translation.height)

        guard absW > axisThreshold || absH > axisThreshold else {
            return .undecided
        }

        return absW > absH * horizontalDominanceRatio ? .horizontal : .vertical
    }
}

struct JobBoardTaskFiltering {
    static func visibleTasks(from projects: [Project]) -> [ProjectTask] {
        var seenTaskIds = Set<String>()
        var visibleTasks: [ProjectTask] = []

        for project in projects where project.isJobBoardTaskListVisible {
            for task in project.tasks where task.deletedAt == nil {
                guard seenTaskIds.insert(task.id).inserted else {
                    // Duplicate rows are a sync-layer bug worth seeing while
                    // debugging, but this runs inside the dedup loop of a list
                    // build — in a release build it is per-duplicate logging on
                    // the main thread, every pass.
                    #if DEBUG
                    print("[JOB_BOARD] Duplicate task hidden from active list: \(task.id)")
                    #endif
                    continue
                }
                visibleTasks.append(task)
            }
        }

        return visibleTasks
    }

    /// The task list's three sections, built ONCE from one filter+sort pass.
    ///
    /// The list used to derive `filteredTasks` separately for the active,
    /// completed, and cancelled partitions and for each `isEmpty` check in the
    /// body — six full passes per render, each one re-fetching every project
    /// and task type and re-running five filters and a sort.
    ///
    /// `taskTypesById` is nil when there is no signed-in company, which is the
    /// old `guard let companyId … else { return [] }`: no rows in any section.
    static func sections(
        visibleTasks: [ProjectTask],
        projectsById: [String: Project],
        taskTypesById: [String: TaskType]?,
        assignedToUserId: String?,
        selectedStatuses: Set<TaskStatus>,
        selectedTaskTypeIds: Set<String>,
        selectedTeamMemberIds: Set<String>,
        searchText: String,
        sortOption: TaskSortOption
    ) -> JobBoardTaskSections {
        guard let taskTypesById else {
            return JobBoardTaskSections(visible: visibleTasks, active: [], completed: [], cancelled: [])
        }

        var filtered = visibleTasks.filter { projectsById[$0.projectId] != nil }

        if let assignedToUserId {
            filtered = filtered.filter { $0.getTeamMemberIds().contains(assignedToUserId) }
        }

        if !selectedStatuses.isEmpty {
            filtered = filtered.filter { selectedStatuses.contains($0.status) }
        }

        if !selectedTaskTypeIds.isEmpty {
            filtered = filtered.filter { selectedTaskTypeIds.contains($0.taskTypeId) }
        }

        if !selectedTeamMemberIds.isEmpty {
            filtered = filtered.filter { task in
                !Set(task.getTeamMemberIds()).intersection(selectedTeamMemberIds).isEmpty
            }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { task in
                let taskTypeName = taskTypesById[task.taskTypeId]?.display ?? ""
                let projectName = projectsById[task.projectId]?.title ?? ""

                return taskTypeName.localizedCaseInsensitiveContains(searchText) ||
                       projectName.localizedCaseInsensitiveContains(searchText) ||
                       (task.taskNotes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        let sorted = sortedTasks(filtered, sortOption: sortOption)

        var active: [ProjectTask] = []
        var completed: [ProjectTask] = []
        var cancelled: [ProjectTask] = []
        for task in sorted {
            switch task.status {
            case .completed: completed.append(task)
            case .cancelled: cancelled.append(task)
            case .active:    active.append(task)
            }
        }

        return JobBoardTaskSections(
            visible: visibleTasks,
            active: active,
            completed: completed,
            cancelled: cancelled
        )
    }

    static func sortedTasks(_ tasks: [ProjectTask], sortOption: TaskSortOption) -> [ProjectTask] {
        switch sortOption {
        case .latestEdited:
            // Mirror the project-list "latestEdited" rule: most recent of
            // lastSyncedAt or scheduledDate. lastSyncedAt is updated on every
            // outbound sync, so it tracks "user just touched this".
            return tasks.sorted(by: { t1, t2 in
                let s1 = t1.lastSyncedAt ?? t1.scheduledDate ?? Date.distantPast
                let s2 = t2.lastSyncedAt ?? t2.scheduledDate ?? Date.distantPast
                return s1 > s2
            })
        case .earliestEdited:
            return tasks.sorted(by: { t1, t2 in
                let s1 = t1.lastSyncedAt ?? t1.scheduledDate ?? Date.distantFuture
                let s2 = t2.lastSyncedAt ?? t2.scheduledDate ?? Date.distantFuture
                return s1 < s2
            })
        case .scheduledDateDescending:
            return tasks.sorted(by: { ($0.scheduledDate ?? Date.distantPast) > ($1.scheduledDate ?? Date.distantPast) })
        case .scheduledDateAscending:
            return tasks.sorted(by: { ($0.scheduledDate ?? Date.distantPast) < ($1.scheduledDate ?? Date.distantPast) })
        case .statusAscending:
            return tasks.sorted(by: { $0.status.sortOrder < $1.status.sortOrder })
        case .statusDescending:
            return tasks.sorted(by: { $0.status.sortOrder > $1.status.sortOrder })
        }
    }
}

/// The task list's sections, plus the unfiltered visible set the empty state
/// keys off — so a render reads one value instead of rebuilding four.
struct JobBoardTaskSections {
    let visible: [ProjectTask]
    let active: [ProjectTask]
    let completed: [ProjectTask]
    let cancelled: [ProjectTask]
}

struct JobBoardProjectFiltering {
    static func sortedProjects(_ projects: [Project], sortOption: ProjectSortOption) -> [Project] {
        switch sortOption {
        case .latestEdited:
            return projects.sorted { lhs, rhs in
                recencyStamp(for: lhs) > recencyStamp(for: rhs)
            }
        case .earliestEdited:
            return projects.sorted { lhs, rhs in
                recencyStamp(for: lhs) < recencyStamp(for: rhs)
            }
        case .scheduledDateDescending:
            return projects.sorted { lhs, rhs in
                let lhsUnscheduled = isUnscheduledActiveProject(lhs)
                let rhsUnscheduled = isUnscheduledActiveProject(rhs)
                let lhsUnassigned = isUnassignedActiveProject(lhs)
                let rhsUnassigned = isUnassignedActiveProject(rhs)

                if lhsUnscheduled != rhsUnscheduled { return lhsUnscheduled }
                if lhsUnassigned != rhsUnassigned { return lhsUnassigned }
                return (lhs.startDate ?? Date.distantPast) > (rhs.startDate ?? Date.distantPast)
            }
        case .scheduledDateAscending:
            return projects.sorted { lhs, rhs in
                let lhsUnscheduled = isUnscheduledActiveProject(lhs)
                let rhsUnscheduled = isUnscheduledActiveProject(rhs)
                let lhsUnassigned = isUnassignedActiveProject(lhs)
                let rhsUnassigned = isUnassignedActiveProject(rhs)

                if lhsUnscheduled != rhsUnscheduled { return lhsUnscheduled }
                if lhsUnassigned != rhsUnassigned { return lhsUnassigned }
                return (lhs.startDate ?? Date.distantPast) < (rhs.startDate ?? Date.distantPast)
            }
        case .statusAscending:
            return projects.sorted { lhs, rhs in
                let lhsUnscheduled = isUnscheduledActiveProject(lhs)
                let rhsUnscheduled = isUnscheduledActiveProject(rhs)
                let lhsUnassigned = isUnassignedActiveProject(lhs)
                let rhsUnassigned = isUnassignedActiveProject(rhs)

                if lhsUnscheduled != rhsUnscheduled { return lhsUnscheduled }
                if lhsUnassigned != rhsUnassigned { return lhsUnassigned }
                return lhs.status.sortOrder < rhs.status.sortOrder
            }
        case .statusDescending:
            return projects.sorted { lhs, rhs in
                let lhsUnscheduled = isUnscheduledActiveProject(lhs)
                let rhsUnscheduled = isUnscheduledActiveProject(rhs)
                let lhsUnassigned = isUnassignedActiveProject(lhs)
                let rhsUnassigned = isUnassignedActiveProject(rhs)

                if lhsUnscheduled != rhsUnscheduled { return lhsUnscheduled }
                if lhsUnassigned != rhsUnassigned { return lhsUnassigned }
                return lhs.status.sortOrder > rhs.status.sortOrder
            }
        }
    }

    static func projectSections(
        from projects: [Project],
        sortOption: ProjectSortOption
    ) -> JobBoardProjectSections {
        let sorted = sortedProjects(projects, sortOption: sortOption)
        return JobBoardProjectSections(
            active: sorted.filter { $0.status != .closed && $0.status != .archived },
            closed: sorted.filter { $0.status == .closed },
            archived: sorted.filter { $0.status == .archived }
        )
    }

    static func kanbanProjects(
        from projects: [Project],
        activeOnly: Bool = false,
        assignedToMe: Bool,
        currentUserId: String?,
        selectedStatuses: Set<Status>,
        selectedTeamMemberIds: Set<String>
    ) -> [Project] {
        var filtered = projects.filter {
            $0.deletedAt == nil && $0.status != .closed && $0.status != .archived
        }

        if activeOnly {
            filtered = filtered.filter { $0.status.isActive }
        }

        if assignedToMe, let currentUserId {
            filtered = filtered.filter { $0.getTeamMemberIds().contains(currentUserId) }
        }

        if !selectedStatuses.isEmpty {
            filtered = filtered.filter { selectedStatuses.contains($0.status) }
        }

        if !selectedTeamMemberIds.isEmpty {
            filtered = filtered.filter { project in
                !Set(project.getTeamMemberIds()).intersection(selectedTeamMemberIds).isEmpty
            }
        }

        return filtered
    }

    /// Bug 70a4d9fd — "most recently touched" stamp for the latest/earliest
    /// edited sorts. Shared with the project pickers so one definition of
    /// "last modified" serves the whole app.
    private static func recencyStamp(for project: Project) -> Date {
        ProjectRecency.stamp(for: project)
    }

    private static func isUnscheduledActiveProject(_ project: Project) -> Bool {
        (project.startDate == nil || project.endDate == nil) &&
            project.status != .closed &&
            project.status != .archived
    }

    private static func isUnassignedActiveProject(_ project: Project) -> Bool {
        project.teamMembers.isEmpty &&
            project.status != .closed &&
            project.status != .archived
    }
}

struct JobBoardProjectSections {
    let active: [Project]
    let closed: [Project]
    let archived: [Project]
}

struct ProjectListOrdering {
    static func activeFirst(_ projects: [Project]) -> [Project] {
        projects
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in
                let lhsGroup = visibilityGroup(for: lhs.status)
                let rhsGroup = visibilityGroup(for: rhs.status)

                if lhsGroup != rhsGroup {
                    return lhsGroup < rhsGroup
                }

                let lhsDate = recencyDate(for: lhs)
                let rhsDate = recencyDate(for: rhs)

                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private static func visibilityGroup(for status: Status) -> Int {
        switch status {
        case .closed:
            return 1
        case .archived:
            return 2
        default:
            return 0
        }
    }

    private static func recencyDate(for project: Project) -> Date {
        project.startDate ??
            project.completedAt ??
            project.updatedAt ??
            project.lastSyncedAt ??
            project.createdAt ??
            .distantPast
    }
}

private extension Project {
    var isJobBoardTaskListVisible: Bool {
        // The job board task list shows work for ACTIVE projects only — those
        // accepted and underway (`.accepted` / `.inProgress`). Pre-acceptance
        // projects (`.rfq`, `.estimated`) haven't been greenlit, so their tasks
        // must not surface here; terminal projects (`.completed`, `.closed`,
        // `.archived`) are done. Gating on `Status.isActive` keeps this the
        // single source of truth and in lockstep with the job board PROJECT
        // list (`JobBoardProjectListView`), which already filters on `isActive`.
        deletedAt == nil && status.isActive
    }
}
