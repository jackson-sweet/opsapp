//
//  JobBoardCardModels.swift
//  OPS
//
//  Everything a job-board card row needs from its model, resolved ONCE per body
//  render instead of once per element that happens to want it.
//
//  Before this existed, a single task card re-derived its own subtitle, title,
//  accent color, and metadata by fetching the WHOLE project table twice and the
//  whole task-type table three times, per render, per card — repaid on every
//  scroll recycle. The lookups are gone entirely: `ProjectTask` already owns
//  `project` and `taskType` SwiftData relationships, wired from the same id
//  columns the fetches were matching on (`InboundProcessor.linkAllRelationships`).
//
//  The project card's progress bars and UNSCHEDULED badge each walked
//  `project.tasks` three or four times; both are one pass here.
//
//  These are plain values with no SwiftUI in them so the derivation is testable
//  on its own — see `OPSTests/JobBoard/JobBoardCardModelTests.swift`.
//

import Foundation

// MARK: - Shared text rules

enum JobBoardCardText {
    /// Street number + street name only — the city never fits the metadata row.
    static func streetOnly(_ address: String) -> String {
        let components = address.components(separatedBy: ",")
        if let streetAddress = components.first?.trimmingCharacters(in: .whitespaces), !streetAddress.isEmpty {
            return streetAddress
        }
        return address.formatAsSimpleAddress()
    }

    /// The metadata row's date cell. `—` is the empty state, per DESIGN.md's
    /// Numbers rule (the old card rendered `-`; centralizing the cell here is
    /// what made the spec-compliance fix a one-token change).
    static func dateText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return DateHelper.simpleDateString(from: date)
    }

    /// Parent-project resolution for a task row.
    ///
    /// The relationship replaces `getAllProjects().first { $0.id == task.projectId }`,
    /// and that fetch is predicated `deletedAt == nil` — so a task whose parent
    /// has been tombstoned resolved to nil there and must resolve to nil here.
    /// Same graceful fallback as a project that never existed: "No project",
    /// and no address cell in the metadata row.
    static func liveProject(of task: ProjectTask) -> Project? {
        guard let project = task.project, project.deletedAt == nil else { return nil }
        return project
    }
}

// MARK: - Project card

/// One ordered segment of a project card's task-progress bar.
enum JobBoardTaskProgressState {
    case completed
    case active
    case cancelled
}

struct JobBoardProjectCardModel {
    /// Metadata row, in order: address, start date, crew count.
    let addressText: String
    let dateText: String
    let teamCount: Int
    let isAssignedToMe: Bool
    let showsUnscheduledBadge: Bool
    /// Completed first, then active, then cancelled — the bar's reading order.
    let progress: [JobBoardTaskProgressState]

    /// - Parameters:
    ///   - hasFullProjectView: `projects.view` at full scope. A crew member
    ///     scoped to their own rows never sees the ASSIGNED TO ME badge, since
    ///     every row they can see is theirs.
    static func make(
        project: Project,
        currentUserId: String?,
        hasFullProjectView: Bool
    ) -> JobBoardProjectCardModel {
        // One pass over project.tasks answers three questions the card used to
        // ask separately: the progress bar's segments, whether any live task is
        // unscheduled, and whether the project has any tasks at all.
        var completed: [JobBoardTaskProgressState] = []
        var active: [JobBoardTaskProgressState] = []
        var cancelled: [JobBoardTaskProgressState] = []
        var hasAnyTask = false
        var hasRelevantTask = false     // not completed, not cancelled
        var hasUnscheduledRelevantTask = false

        for task in project.tasks {
            hasAnyTask = true

            if task.deletedAt == nil {
                switch task.status {
                case .completed: completed.append(.completed)
                case .cancelled: cancelled.append(.cancelled)
                case .active:    active.append(.active)
                }
            }

            // The UNSCHEDULED rule reads every task row, tombstoned or not —
            // preserved verbatim from the badge's original predicate.
            if task.status != .completed && task.status != .cancelled {
                hasRelevantTask = true
                if task.startDate == nil {
                    hasUnscheduledRelevantTask = true
                }
            }
        }

        let showsUnscheduled: Bool
        if !hasAnyTask {
            showsUnscheduled = true          // no tasks at all — nothing is scheduled
        } else if !hasRelevantTask {
            showsUnscheduled = false         // everything is done or cancelled
        } else {
            showsUnscheduled = hasUnscheduledRelevantTask
        }

        let isAssigned: Bool = {
            guard hasFullProjectView, let currentUserId else { return false }
            return project.getTeamMemberIds().contains(currentUserId)
        }()

        let address = project.address
        return JobBoardProjectCardModel(
            addressText: (address?.isEmpty == false) ? JobBoardCardText.streetOnly(address!) : "NO ADDRESS",
            dateText: JobBoardCardText.dateText(project.startDate),
            teamCount: project.teamMembers.count,
            isAssignedToMe: isAssigned,
            showsUnscheduledBadge: showsUnscheduled,
            progress: completed + active + cancelled
        )
    }
}

/// The kanban card's compact progress readout — completed / total over the
/// project's live, non-cancelled tasks. One pass instead of two filters.
struct JobBoardCompactProgress {
    let completed: Int
    let total: Int

    static func make(project: Project) -> JobBoardCompactProgress {
        var completed = 0
        var total = 0
        for task in project.tasks where task.deletedAt == nil && task.status != .cancelled {
            total += 1
            if task.status == .completed { completed += 1 }
        }
        return JobBoardCompactProgress(completed: completed, total: total)
    }
}

// MARK: - Task card

struct JobBoardTaskCardModel {
    /// Task type display, uppercased. `TASK` when the type can't be resolved.
    let title: String
    /// "<project> - <client>", or `No project` when the parent is gone.
    let subtitle: String
    /// nil when no parent project resolves — that card shows no address cell.
    let addressText: String?
    let dateText: String
    let teamCount: Int
    /// Task type color as stored hex; nil when the type can't be resolved.
    let typeColorHex: String?
    let isReadyToStart: Bool
    let isAssignedToMe: Bool
    let isUnscheduled: Bool

    /// - Parameters:
    ///   - hasFullTaskView: `tasks.view` at full scope — see the project model.
    static func make(
        task: ProjectTask,
        currentUserId: String?,
        hasFullTaskView: Bool
    ) -> JobBoardTaskCardModel {
        let project = JobBoardCardText.liveProject(of: task)
        let taskType = task.taskType

        let addressText: String? = project.map { project in
            let address = project.address
            return (address?.isEmpty == false) ? JobBoardCardText.streetOnly(address!) : "NO ADDRESS"
        }

        let subtitle: String = {
            guard let project else { return "No project" }
            return "\(project.title) - \(project.effectiveClientName)"
        }()

        // One split of the assignee CSV serves both the badge and the crew count.
        let teamMemberIds = task.getTeamMemberIds()
        let isAssigned: Bool = {
            guard hasFullTaskView, let currentUserId else { return false }
            return teamMemberIds.contains(currentUserId)
        }()

        return JobBoardTaskCardModel(
            title: taskType.map { $0.display.uppercased() } ?? "TASK",
            subtitle: subtitle,
            addressText: addressText,
            dateText: JobBoardCardText.dateText(task.startDate),
            teamCount: teamMemberIds.count,
            typeColorHex: taskType?.color,
            isReadyToStart: task.isReadyToStart,
            isAssignedToMe: isAssigned,
            isUnscheduled: task.startDate == nil
        )
    }
}
