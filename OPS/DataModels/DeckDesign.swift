//
//  DeckDesign.swift
//  OPS
//
//  SwiftData model for deck builder drawings.
//  Table: deck_designs
//

import Foundation
import SwiftData

@Model
final class DeckDesign: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var projectId: String?           // nil for standalone sketches
    var title: String
    var drawingDataJSON: String      // DeckDrawingData serialized as JSON
    var thumbnailURL: String?        // S3 URL of rendered PNG
    var localThumbnailPath: String?  // local filesystem path (offline)
    var version: Int = 1
    var createdBy: String?           // user ID

    // Sync fields (required by OPS pattern)
    var needsSync: Bool = false
    var lastSyncedAt: Date?
    var syncPriority: Int = 1
    var deletedAt: Date?

    // Timestamps
    var createdAt: Date
    var updatedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        projectId: String? = nil,
        title: String = "Untitled Deck",
        drawingDataJSON: String = "{}",
        createdBy: String? = nil
    ) {
        self.id = id
        self.companyId = companyId
        self.projectId = projectId
        self.title = title
        self.drawingDataJSON = drawingDataJSON
        self.createdBy = createdBy
        self.createdAt = Date()
    }

    // MARK: - Drawing Data Accessors

    var drawingData: DeckDrawingData {
        get {
            DeckDrawingData.fromJSON(drawingDataJSON) ?? DeckDrawingData()
        }
        set {
            drawingDataJSON = newValue.toJSON()
            updatedAt = Date()
            needsSync = true
        }
    }

    // MARK: - Convenience

    func markForSync() {
        needsSync = true
        updatedAt = Date()
    }
}
