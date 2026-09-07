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

    /// The `drawing_data` payload the server and this device last agreed on —
    /// the merge base for inbound conflict resolution. Set ONLY when a push is
    /// confirmed or a server snapshot is accepted; a local edit never moves it.
    ///
    /// Local SwiftData V26 field; V16–V25 use the frozen released shape.
    /// Migration leaves it nil (unknown). A clean legacy row seeds its base
    /// from the pre-edit payload on the first write; an already-dirty legacy
    /// row keeps its unknown base until the server confirms. Bug 9f4aeaf8.
    var syncedDrawingJSON: String?

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
        // A clean row's pre-edit payload is its known server snapshot (or the
        // empty default of a brand-new design). A dirty legacy row can already
        // hold unsent geometry from BEFORE V26: seeding that content as the base
        // would turn an unchanged save into a false acknowledgement. Keep its
        // base unknown and needsSync authoritative until a confirmed push.
        if syncedDrawingJSON == nil && !needsSync {
            syncedDrawingJSON = drawingDataJSON
        }
        drawingDataJSON = json
        drawingDataCache.store(drawing, json: json)
        updatedAt = Date()
        needsSync = true
    }

    /// True when the local drawing holds content the server has not confirmed.
    ///
    /// With a recorded merge base this is a pure content comparison — the only
    /// honest signal, and the reason this exists: the timestamps it replaced
    /// compared a server trigger clock against a device clock and always
    /// resolved for the server (bug 9f4aeaf8).
    ///
    /// With no recorded base, `needsSync` remains the authorship signal. This
    /// includes dirty rows upgraded from V25, even after another local save.
    /// Clean legacy rows still accept inbound geometry; dirty legacy rows stay
    /// protected until a confirmed push establishes their server baseline.
    var hasUnsyncedDrawing: Bool {
        guard let syncedDrawingJSON else { return needsSync }
        return syncedDrawingJSON != drawingDataJSON
    }

    /// Records that the current local drawing is now what the server holds.
    /// Called on a confirmed outbound push and on an accepted inbound snapshot.
    func markDrawingSynced() {
        syncedDrawingJSON = drawingDataJSON
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
