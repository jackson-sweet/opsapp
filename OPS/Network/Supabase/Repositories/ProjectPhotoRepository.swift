//
//  ProjectPhotoRepository.swift
//  OPS
//
//  Repository for ProjectPhoto reads via Supabase.
//  Table: project_photos (RLS: company-wide read via `company_isolation`).
//
//  Read-only for the sync engine — photo rows are written by
//  `ImageSyncManager.insertProjectPhotoRows`. `fetchAll(since:)` powers the
//  InboundProcessor full/delta passes; `fetchForProject` powers on-demand
//  gallery refresh when a project opens.
//

import Foundation
import Supabase

class ProjectPhotoRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch All (for InboundProcessor)

    func fetchAll(since: Date? = nil) async throws -> [ProjectPhotoDTO] {
        var query = client
            .from("project_photos")
            .select()
            .eq("company_id", value: companyId)

        if let since = since {
            query = query.gte("updated_at", value: ISO8601DateFormatter().string(from: since))
        }

        let response: [ProjectPhotoDTO] = try await query
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
    }

    // MARK: - Fetch For Project

    func fetchForProject(_ projectId: String) async throws -> [ProjectPhotoDTO] {
        try await client
            .from("project_photos")
            .select()
            .eq("company_id", value: companyId)
            .eq("project_id", value: projectId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .value
    }
}
