//
//  ProjectReviewQuery.swift
//  OPS
//
//  One permission-scoped, de-duplicated source for the Payment Review sheet,
//  Job Board header, FAB badge, and persistent notification rail.
//

import Foundation

struct ProjectReviewSnapshot {
    let overdueProjects: [Project]
    let completedProjects: [Project]
    let projects: [Project]

    var count: Int { projects.count }
}

enum ProjectReviewQuery {
    static func snapshot(
        dataController: DataController,
        permissionStore: PermissionStore = .shared
    ) -> ProjectReviewSnapshot {
        snapshot(
            projects: dataController.getProjects(),
            dataController: dataController,
            permissionStore: permissionStore
        )
    }

    /// `snapshot(dataController:permissionStore:)` over an already-fetched
    /// project list — same threshold lookup, same access policy, no second
    /// whole-table fetch. For callers that already hold the projects, notably
    /// the FAB badge, which needs the completed/closed tally from the same rows.
    static func snapshot(
        projects: [Project],
        dataController: DataController,
        permissionStore: PermissionStore = .shared
    ) -> ProjectReviewSnapshot {
        let threshold: Int
        if let companyID = dataController.currentUser?.companyId,
           let company = dataController.getCompany(id: companyID) {
            threshold = company.overdueReviewThresholdDays
        } else {
            threshold = 14
        }

        let policy = PaymentReviewAccessPolicy(
            currentUserID: dataController.currentUser?.id,
            projectEditScope: ReviewPermissionScope(
                permissionStore.scope(for: "projects.edit")
            ),
            canViewInvoices: false,
            canSendInvoices: false,
            canEditInvoices: false
        )
        return snapshot(
            projects: projects,
            thresholdDays: threshold,
            accessPolicy: policy
        )
    }

    static func snapshot(
        projects: [Project],
        thresholdDays: Int,
        accessPolicy: PaymentReviewAccessPolicy
    ) -> ProjectReviewSnapshot {
        let completed = projects.filter { project in
            project.status == .completed
                && project.deletedAt == nil
                && accessPolicy.canClose(
                    projectTeamMemberIDs: projectAccessIDs(project)
                )
        }
        let overdue = OverdueProjectDetector.overdueProjects(
            from: completed,
            thresholdDays: thresholdDays
        )
        let session = ProjectReviewSession(
            overdueProjects: overdue,
            completedProjects: completed
        )
        return ProjectReviewSnapshot(
            overdueProjects: overdue,
            completedProjects: completed,
            projects: session.projects
        )
    }

    private static func projectAccessIDs(_ project: Project) -> [String] {
        project.getTeamMemberIds() + project.tasks.flatMap { $0.getTeamMemberIds() }
    }
}
