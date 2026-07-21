//
//  ProjectReviewSessionTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

final class ProjectReviewSessionTests: XCTestCase {

    func testQueuePlacesOverdueFirstAndDeduplicatesCompletedOverlap() {
        let oldest = makeProject(id: "oldest", completedDaysAgo: 40)
        let newerOverdue = makeProject(id: "newer-overdue", completedDaysAgo: 20)
        let recent = makeProject(id: "recent", completedDaysAgo: 2)

        let session = ProjectReviewSession(
            overdueProjects: [newerOverdue, oldest],
            completedProjects: [recent, oldest, newerOverdue]
        )

        XCTAssertEqual(session.projects.map(\.id), ["oldest", "newer-overdue", "recent"])
        XCTAssertEqual(session.totalCount, 3)
    }

    func testSessionRetainsOpeningSnapshotWhenLiveSourceChanges() {
        let first = makeProject(id: "first", completedDaysAgo: 30)
        let second = makeProject(id: "second", completedDaysAgo: 4)
        var liveCompleted = [first, second]

        let session = ProjectReviewSession(
            overdueProjects: [first],
            completedProjects: liveCompleted
        )
        liveCompleted.removeFirst()

        XCTAssertEqual(liveCompleted.map(\.id), ["second"])
        XCTAssertEqual(session.projects.map(\.id), ["first", "second"])
    }

    func testProgressIsExactlyOnceAndRejectsUnknownProject() {
        let first = makeProject(id: "first", completedDaysAgo: 30)
        let second = makeProject(id: "second", completedDaysAgo: 4)
        var session = ProjectReviewSession(
            overdueProjects: [first],
            completedProjects: [first, second]
        )

        XCTAssertTrue(session.markReviewed(projectID: first.id))
        XCTAssertFalse(session.markReviewed(projectID: first.id))
        XCTAssertFalse(session.markReviewed(projectID: "unknown"))
        XCTAssertEqual(session.reviewedCount, 1)
        XCTAssertEqual(session.remainingCount, 1)
        XCTAssertFalse(session.isComplete)

        XCTAssertTrue(session.markReviewed(projectID: second.id))
        XCTAssertTrue(session.isComplete)
    }

    func testCanonicalCountMatchesExactSessionTotal() {
        let overdue = makeProject(id: "overdue", completedDaysAgo: 30)
        let recent = makeProject(id: "recent", completedDaysAgo: 1)

        XCTAssertEqual(
            ProjectReviewSession.reviewCount(
                overdueProjects: [overdue],
                completedProjects: [overdue, recent]
            ),
            2
        )
    }

    func testCanonicalSnapshotFiltersProjectsOutsideAssignedEditScope() {
        let assigned = makeProject(id: "assigned", completedDaysAgo: 30)
        assigned.setTeamMemberIds(["operator"])
        let other = makeProject(id: "other", completedDaysAgo: 30)
        other.setTeamMemberIds(["someone-else"])
        let policy = PaymentReviewAccessPolicy(
            currentUserID: "operator",
            projectEditScope: .assigned,
            canViewInvoices: false,
            canSendInvoices: false,
            canEditInvoices: false
        )

        let snapshot = ProjectReviewQuery.snapshot(
            projects: [other, assigned],
            thresholdDays: 14,
            accessPolicy: policy
        )

        XCTAssertEqual(snapshot.projects.map(\.id), ["assigned"])
        XCTAssertEqual(snapshot.count, 1)
    }

    private func makeProject(id: String, completedDaysAgo: Int) -> Project {
        let project = Project(id: id, title: id, status: .completed)
        project.companyId = "company"
        project.completedAt = Calendar.current.date(
            byAdding: .day,
            value: -completedDaysAgo,
            to: Date()
        )
        return project
    }
}
