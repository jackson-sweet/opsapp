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
