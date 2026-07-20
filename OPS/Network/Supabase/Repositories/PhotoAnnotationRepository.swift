//
//  PhotoAnnotationRepository.swift
//  OPS
//
//  Repository for PhotoAnnotation entity operations via Supabase.
//  Table: project_photo_annotations
//

import Foundation
import Supabase

class PhotoAnnotationRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch All (for InboundProcessor)

    // Sync pulls go through the `get_photo_annotations_since` SECURITY DEFINER
    // RPC so tombstones (deleted_at IS NOT NULL) flow through to local
    // SwiftData. The table's SELECT policy filters them out per spec §13.1.
    func fetchAll(since: Date? = nil) async throws -> [PhotoAnnotationDTO] {
        let params = GetPhotoAnnotationsSinceParams(
            p_since: since.map { ISO8601DateFormatter().string(from: $0) }
        )
        let response: [PhotoAnnotationDTO] = try await client
            .rpc("get_photo_annotations_since", params: params)
            .executeResilient(label: "photo_annotations")
        return response
    }

    private struct GetPhotoAnnotationsSinceParams: Encodable {
        let p_since: String?
    }

    // MARK: - Fetch

    func fetchForProject(_ projectId: String) async throws -> [PhotoAnnotationDTO] {
        try await client
            .from("project_photo_annotations")
            .select()
            .eq("company_id", value: companyId)
            .eq("project_id", value: projectId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchForPhoto(projectId: String, photoURL: String) async throws -> PhotoAnnotationDTO? {
        let results: [PhotoAnnotationDTO] = try await client
            .from("project_photo_annotations")
            .select()
            .eq("company_id", value: companyId)
            .eq("project_id", value: projectId)
            .eq("photo_url", value: photoURL)
            .is("deleted_at", value: nil)
            .limit(1)
            .execute()
            .value
        return results.first
    }

    // MARK: - Upsert

    func upsert(_ dto: UpsertPhotoAnnotationDTO) async throws -> PhotoAnnotationDTO {
        try await client
            .from("project_photo_annotations")
            .upsert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Create / Update

    func create(_ dto: UpsertPhotoAnnotationDTO) async throws -> PhotoAnnotationDTO {
        try await client
            .from("project_photo_annotations")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    /// Legacy single-overlay update. Still used by the offline-sweep path until
    /// the save rewrite (spec step 7) routes everything through `upsertLayer`.
    func updateAnnotation(_ annotationId: String, annotationUrl: String?, note: String) async throws {
        struct AnnotationUpdate: Codable {
            let annotation_url: String?
            let note: String
            let updated_at: String
        }
        let payload = AnnotationUpdate(
            annotation_url: annotationUrl,
            note: note,
            updated_at: isoNow()
        )
        let affected: [AffectedRow] = try await client
            .from("project_photo_annotations")
            .update(payload)
            .eq("id", value: annotationId)
            .select("id")
            .execute()
            .value
        guard !affected.isEmpty else {
            throw AnnotationSyncError.writeNotApplied(annotationId: annotationId)
        }
    }

    /// Note-only update. annotation_url is now owned by `upsert_markup_layer`
    /// (per-author layers), so the note is the only shared scalar edited directly.
    func updateNote(_ annotationId: String, note: String) async throws {
        struct NoteUpdate: Codable {
            let note: String
            let updated_at: String
        }
        let payload = NoteUpdate(note: note, updated_at: isoNow())
        try await client
            .from("project_photo_annotations")
            .update(payload)
            .eq("id", value: annotationId)
            .execute()
    }

    // MARK: - Markup layers (collaborative markup, spec 2026-06-23)

    /// Upsert the CALLER'S OWN markup layer through the SECURITY DEFINER
    /// `upsert_markup_layer` RPC. The server merges the `layers` array by layerId
    /// and appends the change event ATOMICALLY — never a wholesale `.update().eq(id)`
    /// (that is last-writer-wins and would drop a peer's just-landed layer). The
    /// RPC enforces layerId == caller user id, so peers' layers are untouchable.
    /// Returns the fully-merged server row so the caller can refresh local state.
    func upsertLayer(
        annotationId: String,
        layer: MarkupLayer,
        changeEvent: MarkupChangeEvent?,
        beforeSnapshotURL: String? = nil,
        afterSnapshotURL: String? = nil
    ) async throws -> PhotoAnnotationDTO {
        let params = UpsertMarkupLayerParams(
            p_annotation_id: annotationId,
            p_layer: Self.anyJSON(from: layer),
            p_change_event: changeEvent.map(Self.anyJSON(from:)),
            p_before_url: beforeSnapshotURL,
            p_after_url: afterSnapshotURL
        )
        return try await client
            .rpc("upsert_markup_layer", params: params)
            .execute()
            .value
    }

    private struct UpsertMarkupLayerParams: Encodable {
        let p_annotation_id: String
        let p_layer: AnyJSON
        let p_change_event: AnyJSON?
        let p_before_url: String?
        let p_after_url: String?
    }

    // Hand-built AnyJSON (NOT JSONSerialization round-tripping) so Bool never
    // collapses to Int via NSNumber, and the jsonb keys match the RPC exactly.
    private static func anyJSON(from layer: MarkupLayer) -> AnyJSON {
        var object: [String: AnyJSON] = [
            "layerId": .string(layer.layerId),
            "authorId": .string(layer.authorId),
            "authorName": .string(layer.authorName),
            "visibleDefault": .bool(layer.visibleDefault),
            "zIndex": .integer(layer.zIndex),
            "createdAt": .string(SupabaseDate.format(layer.createdAt)),
            "updatedAt": .string(SupabaseDate.format(layer.updatedAt)),
            "overlayUrl": layer.overlayUrl.map(AnyJSON.string) ?? .null,
            "strokeRef": layer.strokeRef.map(AnyJSON.string) ?? .null
        ]
        if let strokeCount = layer.strokeCount {
            object["strokeCount"] = .integer(strokeCount)
        }
        // Omit clearedAt when nil so the RPC reads `->> 'clearedAt'` as NULL = active.
        if let clearedAt = layer.clearedAt {
            object["clearedAt"] = .string(SupabaseDate.format(clearedAt))
        }
        return .object(object)
    }

    private static func anyJSON(from event: MarkupChangeEvent) -> AnyJSON {
        var object: [String: AnyJSON] = [
            "eventId": .string(event.eventId),
            "authorId": .string(event.authorId),
            "authorName": .string(event.authorName),
            "action": .string(event.action.rawValue),
            "at": .string(SupabaseDate.format(event.at)),
            "beforeSnapshotUrl": event.beforeSnapshotUrl.map(AnyJSON.string) ?? .null,
            "afterSnapshotUrl": event.afterSnapshotUrl.map(AnyJSON.string) ?? .null
        ]
        if let delta = event.strokeDelta {
            object["strokeDelta"] = .integer(delta)
        }
        return .object(object)
    }

    // MARK: - Soft Delete

    /// Tombstone an annotation. RPC-first: `soft_delete_photo_annotation` is
    /// SECURITY DEFINER, so it works regardless of the RLS shape that made
    /// the direct UPDATE structurally impossible from 2026-05-12 onward
    /// (SELECT policies are applied as WITH CHECK options against the NEW
    /// row of any UPDATE that reads the table; the SELECT policy's
    /// `deleted_at IS NULL` therefore rejected every tombstone write —
    /// bugs 452bab04/0415504f). Until that server migration is applied the
    /// RPC does not exist (PGRST202); we remember that for the session and
    /// fall back to the legacy direct UPDATE so the two can ship in either
    /// order — the fallback carries zero-row detection so an RLS-filtered
    /// no-op can never masquerade as success again.
    func softDelete(_ annotationId: String) async throws {
        if !Self.softDeleteRPCUnavailable {
            do {
                try await client
                    .rpc(
                        "soft_delete_photo_annotation",
                        params: SoftDeleteRPCParams(p_annotation_id: annotationId.lowercased())
                    )
                    .execute()
                return
            } catch let error as PostgrestError where error.code == "PGRST202" {
                // RPC not deployed yet — skip the wasted round-trip for the
                // rest of this session and use the legacy path.
                Self.softDeleteRPCUnavailable = true
            }
        }

        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        let affected: [AffectedRow] = try await client
            .from("project_photo_annotations")
            .update(payload)
            .eq("id", value: annotationId)
            .select("id")
            .execute()
            .value
        guard !affected.isEmpty else {
            throw AnnotationSyncError.writeNotApplied(annotationId: annotationId)
        }
    }

    /// Session-scoped memo: true once the soft-delete RPC has answered
    /// PGRST202 (function missing — server migration pending). Written and
    /// read only from the @MainActor sync managers.
    private static var softDeleteRPCUnavailable = false

    private struct SoftDeleteRPCParams: Encodable {
        let p_annotation_id: String
    }

    /// Row-id payload decoded from PostgREST RETURNING. Presence proves the
    /// write matched a row — RLS silently filters mismatches (0 rows, HTTP
    /// 2xx) instead of erroring, which previously let dead writes report
    /// success and mark themselves synced.
    private struct AffectedRow: Decodable {
        let id: String
    }
}

// MARK: - ISO8601 Helpers

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}
