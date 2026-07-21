//
//  ProjectReviewSession.swift
//  OPS
//
//  Stable, de-duplicated project queue and exactly-once progress for one
//  Payment Review presentation.
//

import Foundation

struct ProjectReviewSession {
    let projects: [Project]

    private let projectIDs: Set<String>
    private(set) var reviewedProjectIDs: Set<String> = []

    init(overdueProjects: [Project], completedProjects: [Project]) {
        let orderedOverdue = Self.sorted(overdueProjects)
        var seen = Set<String>()
        var snapshot: [Project] = []

        for project in orderedOverdue where seen.insert(project.id).inserted {
            snapshot.append(project)
        }
        for project in Self.sorted(completedProjects)
        where seen.insert(project.id).inserted {
            snapshot.append(project)
        }

        projects = snapshot
        projectIDs = seen
    }

    init(projects: [Project]) {
        var seen = Set<String>()
        self.projects = projects.filter { seen.insert($0.id).inserted }
        projectIDs = seen
    }

    static func reviewCount(
        overdueProjects: [Project],
        completedProjects: [Project]
    ) -> Int {
        ProjectReviewSession(
            overdueProjects: overdueProjects,
            completedProjects: completedProjects
        ).totalCount
    }

    var totalCount: Int { projects.count }
    var reviewedCount: Int { reviewedProjectIDs.count }
    var remainingCount: Int { totalCount - reviewedCount }
    var isComplete: Bool { !projects.isEmpty && remainingCount == 0 }

    @discardableResult
    mutating func markReviewed(projectID: String) -> Bool {
        guard projectIDs.contains(projectID) else { return false }
        return reviewedProjectIDs.insert(projectID).inserted
    }

    private static func sorted(_ projects: [Project]) -> [Project] {
        projects.sorted { lhs, rhs in
            let lhsDate = lhs.completedAt ?? .distantFuture
            let rhsDate = rhs.completedAt ?? .distantFuture
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.id < rhs.id
        }
    }
}
