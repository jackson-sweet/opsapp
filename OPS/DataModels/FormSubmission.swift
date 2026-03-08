//
//  FormSubmission.swift
//  OPS
//
//  Submitted form with JSON responses — supports offline-first sync
//

import SwiftData
import Foundation

@Model
class FormSubmission: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var formTemplateId: String
    var projectId: String?
    var taskId: String?
    var responses: Data?
    var completedAt: Date?
    var completedBy: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = true

    init(
        id: String = UUID().uuidString,
        companyId: String,
        formTemplateId: String,
        projectId: String? = nil,
        taskId: String? = nil,
        completedBy: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.formTemplateId = formTemplateId
        self.projectId = projectId
        self.taskId = taskId
        self.completedBy = completedBy
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
