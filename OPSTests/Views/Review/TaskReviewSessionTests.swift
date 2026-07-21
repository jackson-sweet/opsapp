//
//  TaskReviewSessionTests.swift
//  OPSTests
//
//  Regression coverage for stable Task Review ordering and progress.
//

import XCTest
@testable import OPS

final class TaskReviewSessionTests: XCTestCase {

    func testSessionKeepsOriginalOrderWhenLiveSourceShrinks() {
        let first = makeTask(id: "first")
        let second = makeTask(id: "second")
        let third = makeTask(id: "third")
        var liveTasks = [first, second, third]

        let session = TaskReviewSession(tasks: liveTasks)
        liveTasks.removeFirst()

        XCTAssertEqual(liveTasks.map(\.id), ["second", "third"])
        XCTAssertEqual(session.tasks.map(\.id), ["first", "second", "third"])
    }

    func testMarkReviewedCountsKnownTaskExactlyOnce() {
        var session = TaskReviewSession(tasks: [makeTask(id: "first"), makeTask(id: "second")])

        XCTAssertTrue(session.markReviewed(taskID: "first"))
        XCTAssertFalse(session.markReviewed(taskID: "first"))
        XCTAssertFalse(session.markReviewed(taskID: "unknown"))
        XCTAssertEqual(session.reviewedCount, 1)
        XCTAssertEqual(session.remainingCount, 1)
    }

    func testReviewingFirstTaskLeavesSecondTaskNext() {
        var session = TaskReviewSession(tasks: [
            makeTask(id: "first"),
            makeTask(id: "second"),
            makeTask(id: "third")
        ])

        session.markReviewed(taskID: "first")

        XCTAssertEqual(session.tasks[session.reviewedCount].id, "second")
        XCTAssertFalse(session.isComplete)
    }

    func testSessionCompletesOnlyAfterEverySnapshotTaskIsReviewed() {
        var session = TaskReviewSession(tasks: [makeTask(id: "first"), makeTask(id: "second")])

        session.markReviewed(taskID: "first")
        XCTAssertFalse(session.isComplete)

        session.markReviewed(taskID: "second")
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.remainingCount, 0)
    }

    func testSessionDeduplicatesRepeatedTaskIDsWithoutChangingFirstSeenOrder() {
        let first = makeTask(id: "first")
        let duplicateFirst = makeTask(id: "first")
        let second = makeTask(id: "second")

        let session = TaskReviewSession(tasks: [first, duplicateFirst, second])

        XCTAssertEqual(session.tasks.map(\.id), ["first", "second"])
        XCTAssertEqual(session.totalCount, 2)
    }

    private func makeTask(id: String) -> ProjectTask {
        ProjectTask(
            id: id,
            projectId: "project",
            taskTypeId: "task-type",
            companyId: "company"
        )
    }
}
