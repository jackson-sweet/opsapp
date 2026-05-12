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
            .execute()
            .value
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
        try await client
            .from("project_photo_annotations")
            .update(payload)
            .eq("id", value: annotationId)
            .execute()
    }

    // MARK: - Soft Delete

    func softDelete(_ annotationId: String) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        try await client
            .from("project_photo_annotations")
            .update(payload)
            .eq("id", value: annotationId)
            .execute()
    }
}

// MARK: - ISO8601 Helpers

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}
