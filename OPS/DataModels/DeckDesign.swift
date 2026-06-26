//
//  DeckDesign.swift
//  OPS
//
//  SwiftData model for deck builder drawings.
//  Table: deck_designs
//

import Foundation
import DeckKit
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
        self.id = Self.canonicalUUIDString(id)
        self.companyId = Self.canonicalUUIDString(companyId)
        self.projectId = projectId.map(Self.canonicalUUIDString)
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
            let stamped = DeckSchemaMigration.stampFramingVersion(newValue)
            drawingDataJSON = stamped.toJSON()
            if let schemaVersion = stamped.schemaVersion {
                version = max(version, schemaVersion)
            }
            updatedAt = Date()
            needsSync = true
        }
    }

    // MARK: - Convenience

    func markForSync() {
        needsSync = true
        updatedAt = Date()
    }

    static func canonicalUUIDString(_ value: String) -> String {
        UUID(uuidString: value)?.uuidString.lowercased() ?? value
    }

    func isAttached(toProjectId projectId: String) -> Bool {
        guard let designProjectId = self.projectId else { return false }
        return Self.canonicalUUIDString(designProjectId) == Self.canonicalUUIDString(projectId)
    }

    var hasRenderableGeometry: Bool {
        if drawingData.isMultiLevel {
            return drawingData.levels.contains { !$0.vertices.isEmpty }
        }
        return !drawingData.vertices.isEmpty
    }

    static func displayCandidate(in designs: [DeckDesign], forProjectId projectId: String) -> DeckDesign? {
        let candidates = designs.filter {
            $0.deletedAt == nil && $0.isAttached(toProjectId: projectId)
        }

        let renderable = candidates.filter(\.hasRenderableGeometry)
        if let design = mostRecentlyUpdated(renderable) {
            return design
        }

        return mostRecentlyUpdated(candidates)
    }

    private static func mostRecentlyUpdated(_ designs: [DeckDesign]) -> DeckDesign? {
        designs.sorted {
            ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
        .first
    }
}
