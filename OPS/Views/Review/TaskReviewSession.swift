//
//  TaskReviewSession.swift
//  OPS
//
//  Stable, exactly-once progress for a single Task Review presentation.
//

import Foundation

struct TaskReviewSession {
    let tasks: [ProjectTask]

    private let taskIDs: Set<String>
    private(set) var reviewedTaskIDs: Set<String> = []

    init(tasks: [ProjectTask]) {
        var seenTaskIDs: Set<String> = []
        self.tasks = tasks.filter { task in
            seenTaskIDs.insert(task.id).inserted
        }
        taskIDs = seenTaskIDs
    }

    var totalCount: Int {
        tasks.count
    }

    var reviewedCount: Int {
        reviewedTaskIDs.count
    }

    var remainingCount: Int {
        totalCount - reviewedCount
    }

    var isComplete: Bool {
        !tasks.isEmpty && remainingCount == 0
    }

    @discardableResult
    mutating func markReviewed(taskID: String) -> Bool {
        guard taskIDs.contains(taskID) else { return false }
        return reviewedTaskIDs.insert(taskID).inserted
    }
}
