//
//  TimeEntry.swift
//  OPS
//
//  Time tracking entry for field crew — supports offline-first sync
//

import SwiftData
import Foundation

@Model
class TimeEntry: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var userId: String
    var projectId: String?
    var taskId: String?
    var startTime: Date
    var endTime: Date?
    var duration: TimeInterval
    var notes: String
    var isRunning: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = true

    init(
        id: String = UUID().uuidString,
        companyId: String,
        userId: String,
        projectId: String? = nil,
        taskId: String? = nil,
        startTime: Date = Date(),
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.userId = userId
        self.projectId = projectId
        self.taskId = taskId
        self.startTime = startTime
        self.endTime = nil
        self.duration = 0
        self.notes = notes
        self.isRunning = true
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    // MARK: - Actions

    func stop() {
        let now = Date()
        endTime = now
        duration = now.timeIntervalSince(startTime)
        isRunning = false
        updatedAt = now
        needsSync = true
    }
}
