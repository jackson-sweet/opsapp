//
//  DeckDesign.swift
//  OPS
//
//  SwiftData model for deck builder drawings.
//  Table: deck_designs
//

import Foundation
import SwiftData

/// Per-model decode cache for the persisted drawing payload.
///
/// SwiftUI can ask a deck host whether it has renderable geometry many times
/// in a single pull gesture. `DeckDrawingData.fromJSON` performs both Codable
/// decoding and integrity repair, so repeating it on every body evaluation can
/// monopolize the main thread long enough for the iOS watchdog to terminate the
/// app. The exact source string is the cache key, which also makes direct
/// server-sync replacements self-invalidating.
final class DeckDrawingDataCache {
    private var sourceJSON: String?
    private var decodedDrawing: DeckDrawingData?

    func resolve(
        json: String,
        decoder: (String) -> DeckDrawingData? = { DeckDrawingData.fromJSON($0) }
    ) -> DeckDrawingData {
        if sourceJSON == json, let decodedDrawing {
            return decodedDrawing
        }

        let decoded = decoder(json) ?? DeckDrawingData()
        sourceJSON = json
        decodedDrawing = decoded
        return decoded
    }

    func store(_ drawing: DeckDrawingData, json: String) {
        sourceJSON = json
        decodedDrawing = drawing
    }
}

@Model
final class DeckDesign: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var projectId: String?           // nil for standalone sketches
    var opportunityId: String?       // set when the deck was drawn on a LEAD;
                                     // survives conversion (project_id gains the
                                     // link server-side, this stays as provenance)
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

    /// Runtime-only reference storage. Mutating the cache's internals does not
    /// publish a SwiftData model change, so reads during a gesture do not create
    /// a new AttributeGraph update cycle.
    @Transient private var drawingDataCache = DeckDrawingDataCache()

    init(
        id: String = UUID().uuidString,
        companyId: String,
        projectId: String? = nil,
        opportunityId: String? = nil,
        title: String = "Untitled Deck",
        drawingDataJSON: String = "{}",
        createdBy: String? = nil
    ) {
        self.id = Self.canonicalUUIDString(id)
        self.companyId = Self.canonicalUUIDString(companyId)
        self.projectId = projectId.map(Self.canonicalUUIDString)
        self.opportunityId = opportunityId.map(Self.canonicalUUIDString)
        self.title = title
        self.drawingDataJSON = drawingDataJSON
        self.createdBy = createdBy
        self.createdAt = Date()
    }

    // MARK: - Drawing Data Accessors

    var drawingData: DeckDrawingData {
        get {
            drawingDataCache.resolve(json: drawingDataJSON)
        }
        set {
            let json = newValue.toJSON()
            storeDrawingData(newValue, json: json)
        }
    }

    /// Stores a drawing whose canonical JSON has already been produced by the
    /// save boundary. This avoids repeating the full encoder pass for the model
    /// setter and outbound sync payload.
    func storeDrawingData(_ drawing: DeckDrawingData, json: String) {
        drawingDataJSON = json
        drawingDataCache.store(drawing, json: json)
        updatedAt = Date()
        needsSync = true
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

    func isAttached(toOpportunityId opportunityId: String) -> Bool {
        guard let designOpportunityId = self.opportunityId else { return false }
        return Self.canonicalUUIDString(designOpportunityId) == Self.canonicalUUIDString(opportunityId)
    }

    var hasRenderableGeometry: Bool {
        let drawing = drawingData
        if drawing.isMultiLevel {
            return drawing.levels.contains { !$0.vertices.isEmpty }
        }
        return !drawing.vertices.isEmpty
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

    /// Same selection rule as the project variant, scoped to a lead: prefer
    /// the most recently updated design with drawable geometry, fall back to
    /// the most recent at all. A converted lead's deck (project_id now set)
    /// still qualifies — the lead keeps showing its deck after WON.
    static func displayCandidate(in designs: [DeckDesign], forOpportunityId opportunityId: String) -> DeckDesign? {
        let candidates = designs.filter {
            $0.deletedAt == nil && $0.isAttached(toOpportunityId: opportunityId)
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
