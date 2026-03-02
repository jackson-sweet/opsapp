//
//  PhotoAnnotation.swift
//  OPS
//
//  Drawing overlay and text note for a project photo — Supabase-backed
//

import SwiftData
import Foundation

@Model
class PhotoAnnotation: Identifiable {
    @Attribute(.unique) var id: String
    var projectId: String
    var companyId: String
    var photoURL: String
    var annotationURL: String?
    var note: String
    var authorId: String
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?

    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    // Local-only: PKDrawing data for offline editing
    var localDrawingData: Data?

    init(
        id: String = UUID().uuidString,
        projectId: String,
        companyId: String,
        photoURL: String,
        authorId: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.companyId = companyId
        self.photoURL = photoURL
        self.note = ""
        self.authorId = authorId
        self.createdAt = createdAt
    }
}
