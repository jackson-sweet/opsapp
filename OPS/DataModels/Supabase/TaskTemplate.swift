//
//  TaskTemplate.swift
//  OPS
//
//  Sub-task scaffolding under a TaskType. When a LABOR line item lands in
//  an approved estimate, one ProjectTask is generated per TaskTemplate row
//  (e.g. TaskType "Deck Work" → ["Footings", "Framing", "Vinyl Membrane"]).
//  Authoring lives inside `TaskTypeSheet`'s DEFAULT SUB-TASKS section.
//

import SwiftData
import Foundation

@Model
class TaskTemplate: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var taskTypeId: String                       // text mirror — historical / legacy column
    var taskTypeRef: String?                     // uuid FK to task_types.id — the authoritative pointer
    var title: String
    var templateDescription: String?
    var estimatedHours: Double?
    var displayOrder: Int
    var defaultTeamMemberIdsString: String = ""  // Comma-separated crew user IDs, mirrors TaskType
    var createdAt: Date
    var updatedAt: Date?

    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        taskTypeId: String,
        taskTypeRef: String? = nil,
        title: String,
        templateDescription: String? = nil,
        estimatedHours: Double? = nil,
        displayOrder: Int = 0,
        defaultTeamMemberIds: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.taskTypeId = taskTypeId
        self.taskTypeRef = taskTypeRef ?? taskTypeId
        self.title = title
        self.templateDescription = templateDescription
        self.estimatedHours = estimatedHours
        self.displayOrder = displayOrder
        self.defaultTeamMemberIdsString = defaultTeamMemberIds.joined(separator: ",")
        self.createdAt = createdAt
    }

    /// SwiftData can't persist arrays of primitives without extra work, so
    /// the crew override is stored as a comma-separated string. Splitting on
    /// commas with empty-filter keeps the round-trip lossless for the empty
    /// case (which is the default — overrides are rare).
    var defaultTeamMemberIds: [String] {
        get {
            defaultTeamMemberIdsString
                .split(separator: ",")
                .map { String($0) }
                .filter { !$0.isEmpty }
        }
        set {
            defaultTeamMemberIdsString = newValue.joined(separator: ",")
        }
    }
}
