//
//  ProjectsWithoutTasksDetector.swift
//  OPS
//
//  Computes the list of operational projects (accepted or in-progress)
//  that have zero tasks attached. These are projects an admin has
//  committed to but never broke down into work — invisible on the schedule
//  and impossible for crews to act on. Mirrors StaleEstimateDetector so
//  it plugs into the same periodic review-check pipeline.
//

import Foundation

struct ProjectsWithoutTasksDetector {

    /// Project statuses considered "operational" for the purposes of this
    /// check. A project in one of these stages has been committed to and
    /// should have at least one task to be actionable.
    /// - `.accepted`: client said yes, work hasn't started
    /// - `.inProgress`: work is actively underway
    /// Excludes terminal states (`.completed`, `.closed`, `.archived`) where
    /// "no tasks" is no longer actionable.
    static let actionableStatuses: Set<Status> = [.accepted, .inProgress]

    /// Returns projects in `accepted` or `inProgress` status with no tasks
    /// attached, sorted by `lastSyncedAt` descending so the freshest commitments
    /// surface first (most likely to need urgent task planning).
    static func projectsWithoutTasks(
        from projects: [Project]
    ) -> [Project] {
        projects
            .filter { $0.deletedAt == nil }
            .filter { actionableStatuses.contains($0.status) }
            .filter { $0.tasks.filter { $0.deletedAt == nil }.isEmpty }
            .sorted { (lhs, rhs) in
                let lhsStamp = lhs.lastSyncedAt ?? lhs.startDate ?? .distantPast
                let rhsStamp = rhs.lastSyncedAt ?? rhs.startDate ?? .distantPast
                return lhsStamp > rhsStamp
            }
    }
}
