//
//  DeckDesignDTOs.swift
//  OPS
//
//  Data Transfer Objects for deck_designs Supabase table.
//

import Foundation

struct SupabaseDeckDesignDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let projectId: String?
    let opportunityId: String?
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
        case companyId     = "company_id"
        case projectId     = "project_id"
        case opportunityId = "opportunity_id"
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
            opportunityId: opportunityId,
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
            opportunityId: model.opportunityId,
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
        "company_id", "project_id", "opportunity_id", "title", "drawing_data",
        "thumbnail_url", "version", "created_by",
        "created_at", "updated_at", "deleted_at"
    ]

    func applyServerSnapshot(
        _ dto: SupabaseDeckDesignDTO,
        accepting requestedFields: Set<String>
    ) {
        // Stale-overwrite guard (deck-revert data loss — LUPIN, 2026-06-19),
        // rebuilt on content instead of clocks (bug 9f4aeaf8).
        //
        // The guard this replaced compared two different clocks. The server's
        // `updated_at` is written by a Postgres BEFORE UPDATE trigger
        // (`NEW.updated_at = now()`) AFTER the push lands; the local `updatedAt`
        // is stamped by the device clock in `storeDrawingData` BEFORE the push
        // is even queued. The server stamp is therefore later than the local one
        // for identical content, by the whole deferPush + queue + network
        // latency — so `serverIsNewer` was effectively always true, the
        // protective subtract effectively never ran, and a delta re-pull was
        // free to write pre-session server geometry over the session's
        // autosaved work.
        //
        // The rule now: an inbound snapshot may replace locally-authored
        // content only when the local row holds nothing the server has not
        // already confirmed. `syncedDrawingJSON` is that merge base. Timestamps
        // stay a tiebreak for genuinely remote edits — never a licence to
        // discard local work.
        let serverUpdatedAt = dto.updatedAt.flatMap { SupabaseDate.parse($0) }

        // Server strictly older than local → the whole snapshot is stale; ignore it.
        if let server = serverUpdatedAt, let local = updatedAt, server < local {
            return
        }

        var acceptedFields = requestedFields
        let serverPayload = dto.drawingData.toJSON()
        let localHoldsUnpushedContent = hasUnsyncedDrawing

        if localHoldsUnpushedContent {
            // The server's copy is a genuine remote edit only if it differs from
            // the base we last agreed on too. Anything else is an echo of our
            // own push or a replica-lagged read, and must not touch content this
            // device authored. With no recorded base there is nothing to compare
            // against, so the local row wins until its own push confirms and
            // sets one — which `recordConfirmedPush` does on completion.
            let serverMovedOffBase = syncedDrawingJSON.map { $0 != serverPayload } ?? false
            if !serverMovedOffBase {
                acceptedFields.subtract(["drawing_data", "title", "thumbnail_url", "version"])
            }
        }

        if acceptedFields.contains("company_id") { companyId = dto.companyId }
        if acceptedFields.contains("project_id") { projectId = dto.projectId }
        if acceptedFields.contains("opportunity_id") { opportunityId = dto.opportunityId }
        if acceptedFields.contains("title") { title = dto.title }
        if acceptedFields.contains("drawing_data") { drawingDataJSON = serverPayload }
        if acceptedFields.contains("thumbnail_url") { thumbnailURL = dto.thumbnailUrl }
        if acceptedFields.contains("version") { version = dto.version }
        if acceptedFields.contains("created_by") { createdBy = dto.createdBy }
        if acceptedFields.contains("created_at") {
            createdAt = SupabaseDate.parse(dto.createdAt) ?? createdAt
        }
        // Only ever move the local stamp FORWARD to a value we can parse. The
        // previous form assigned the flatMap result directly, so a null or
        // unparseable server timestamp nilled `updatedAt` — and the stale guard
        // above, which needs a local timestamp to compare, could then never fire
        // on that row again. Bug 9f4aeaf8.
        if acceptedFields.contains("updated_at"),
           let parsedUpdatedAt = serverUpdatedAt {
            updatedAt = parsedUpdatedAt
        }
        if acceptedFields.contains("deleted_at") {
            deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
        }

        if acceptedFields.contains("drawing_data") {
            // We just took the server's payload — it is now the agreed base.
            markDrawingSynced()
        }
        // A row that still holds unpushed content must stay flagged whatever a
        // merge decided about `needsSync` elsewhere, or the next pull finds
        // nothing to protect and the work is gone.
        if localHoldsUnpushedContent, hasUnsyncedDrawing {
            needsSync = true
        }
    }
}
