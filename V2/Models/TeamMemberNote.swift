//
//  TeamMemberNote.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-04.
//

import SwiftUI
import SwiftData

/// Model for storing notes specific to team members on a project
@Model
final class TeamMemberNote: Identifiable {
    var id: String
    var projectId: String
    var userId: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var needsSync: Bool = false
    
    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \Project.teamMemberNotes)
    var project: Project?
    
    @Relationship(deleteRule: .cascade, inverse: \User.notes)
    var user: User?
    
    init(id: String = UUID().uuidString, projectId: String, userId: String, content: String) {
        self.id = id
        self.projectId = projectId
        self.userId = userId
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}