//
//  DeckDesignDTOs.swift
//  OPS
//
//  Data Transfer Objects for deck_designs Supabase table.
//

import Foundation
import DeckKit

struct SupabaseDeckDesignDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let projectId: String?
    let title: String
    let drawingData: DeckDrawingData   // JSONB — decoded directly as Codable struct
    let thumbnailUrl: String?
    let version: Int
    let createdBy: String?
    let createdAt: String
    let updatedAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId    = "company_id"
        case projectId    = "project_id"
        case title
        case drawingData  = "drawing_data"
        case thumbnailUrl = "thumbnail_url"
        case version
        case createdBy    = "created_by"
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
        case deletedAt    = "deleted_at"
    }

    func toModel() -> DeckDesign {
        let model = DeckDesign(
            id: id,
            companyId: companyId,
            projectId: projectId,
            title: title,
            drawingDataJSON: drawingData.toJSON(),
            createdBy: createdBy
        )
        model.thumbnailURL = thumbnailUrl
        model.version = version
        model.createdAt = SupabaseDate.parse(createdAt) ?? Date()
        if let updatedAt = updatedAt {
            model.updatedAt = SupabaseDate.parse(updatedAt)
        }
        if let deletedAt = deletedAt {
            model.deletedAt = SupabaseDate.parse(deletedAt)
        }
        return model
    }

    static func fromModel(_ model: DeckDesign) -> SupabaseDeckDesignDTO {
        SupabaseDeckDesignDTO(
            id: model.id,
            companyId: model.companyId,
            projectId: model.projectId,
            title: model.title,
            drawingData: model.drawingData,
            thumbnailUrl: model.thumbnailURL,
            version: model.version,
            createdBy: model.createdBy,
            createdAt: ISO8601DateFormatter().string(from: model.createdAt),
            updatedAt: model.updatedAt.map { ISO8601DateFormatter().string(from: $0) },
            deletedAt: model.deletedAt.map { ISO8601DateFormatter().string(from: $0) }
        )
    }
}

extension DeckDesign {
    static let serverMergeFields: [String] = [
        "company_id", "project_id", "title", "drawing_data",
        "thumbnail_url", "version", "created_by",
        "created_at", "updated_at", "deleted_at"
    ]

    func applyServerSnapshot(
        _ dto: SupabaseDeckDesignDTO,
        accepting requestedFields: Set<String>
    ) {
        // Stale-overwrite guard (deck-revert data loss — LUPIN, 2026-06-19).
        // An inbound merge must never overwrite locally-authored content with a
        // server snapshot that is OLDER than, or an unconfirmed echo of, the
        // local row. After a save+push completes, the pending SyncOperation that
        // was the ONLY thing protecting drawing_data flips to "completed"; the
        // 300s delta-overlap re-pull then re-fetches the very same deck, and a
        // replica-lagged read can hand back a pre-edit row. Without this guard,
        // applyServerSnapshot wrote that stale drawing_data over the just-saved
        // geometry — silently reverting renamed levels + new geometry. The DTO
        // already carries updated_at; we simply refuse to apply a stale snapshot.
        let serverUpdatedAt = dto.updatedAt.flatMap { SupabaseDate.parse($0) }

        // Server strictly older than local → the whole snapshot is stale; ignore it.
        if let server = serverUpdatedAt, let local = updatedAt, server < local {
            return
        }

        var acceptedFields = requestedFields

        // Local row still has unconfirmed edits and the server copy is NOT
        // strictly newer → keep our locally-authored content rather than let an
        // echo/replica-lagged read round-trip-clobber it. A genuinely newer
        // server edit (server > local) is still applied normally.
        if needsSync {
            let serverIsNewer = serverUpdatedAt.flatMap { s in updatedAt.map { s > $0 } } ?? false
            if !serverIsNewer {
                acceptedFields.subtract(["drawing_data", "title", "thumbnail_url", "version"])
            }
        }

        if acceptedFields.contains("company_id") { companyId = dto.companyId }
        if acceptedFields.contains("project_id") { projectId = dto.projectId }
        if acceptedFields.contains("title") { title = dto.title }
        if acceptedFields.contains("drawing_data") { drawingDataJSON = dto.drawingData.toJSON() }
        if acceptedFields.contains("thumbnail_url") { thumbnailURL = dto.thumbnailUrl }
        if acceptedFields.contains("version") { version = dto.version }
        if acceptedFields.contains("created_by") { createdBy = dto.createdBy }
        if acceptedFields.contains("created_at") {
            createdAt = SupabaseDate.parse(dto.createdAt) ?? createdAt
        }
        if acceptedFields.contains("updated_at") {
            updatedAt = dto.updatedAt.flatMap { SupabaseDate.parse($0) }
        }
        if acceptedFields.contains("deleted_at") {
            deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
        }
    }
}
