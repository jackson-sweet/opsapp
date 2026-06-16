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
                    print("[JOB_BOARD] Duplicate task hidden from active list: \(task.id)")
                    continue
                }
                visibleTasks.append(task)
            }
        }

        return visibleTasks
    }
}

struct JobBoardProjectFiltering {
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
