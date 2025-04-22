//
//  SwiftDataHelper.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//


import Foundation
import SwiftData

/// Helper functions for dealing with SwiftData relationships
/// This removes the complexity from your main code
struct SwiftDataHelper {
    
    /// Safely connects a project with its team members
    /// Works around the get-only property limitations of SwiftData relationships
    static func connectProjectToTeamMembers(project: Project, users: [User], in context: ModelContext) {
        // Store the relationship in SwiftData's graph
        for user in users {
            // This tells SwiftData to establish the relationship from both sides
            context.linkedBatches(for: [Project.self, User.self]).addLinks(from: project, to: user)
        }
        
        // Make sure the IDs are stored for offline reference
        project.teamMemberIds = users.map { $0.id }
        
        // Save the changes
        try? context.save()
    }
    
    /// Safely assigns projects to a user
    /// Works around the get-only property limitations of SwiftData relationships
    static func assignProjectsToUser(user: User, projects: [Project], in context: ModelContext) {
        // Store the relationship in SwiftData's graph
        for project in projects {
            // This tells SwiftData to establish the relationship from both sides
            context.linkedBatches(for: [User.self, Project.self]).addLinks(from: user, to: project)
        }
        
        // Save the changes
        try? context.save()
    }
}