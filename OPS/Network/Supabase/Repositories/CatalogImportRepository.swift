//
//  CatalogImportRepository.swift
//  OPS
//
//  Thin wrapper around the catalog_import_validate / catalog_import_apply
//  RPCs. Both calls are atomic on the server side — the iOS preview
//  screen calls validate() first (no writes), and only on user confirm
//  does the apply() path ever run.
//
//  See: OPS/Migrations/2026-05-08-catalog-import-rpc.sql for the SQL.
//

import Foundation
import Supabase

class CatalogImportRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    /// Dry-run. Runs the same per-row validation as `apply` but never
    /// INSERTs. Returns either `success: true, totals: ...` or
    /// `success: false, errors: [...]` — the iOS preview screen renders
    /// each error verbatim so the user can fix the CSV and retry.
    func validate(_ payload: CatalogImportPayload) async throws -> CatalogImportResult {
        try await callRPC("catalog_import_validate", payload: payload)
    }

    /// Atomic apply. ROLLBACK on any validation failure; INSERTs every
    /// family + variant in a single transaction on success.
    func apply(_ payload: CatalogImportPayload) async throws -> CatalogImportResult {
        try await callRPC("catalog_import_apply", payload: payload)
    }

    // MARK: - Private

    private struct ImportRPCParams: Encodable {
        let p_company_id: String
        let p_payload: CatalogImportPayload
    }

    private func callRPC(_ name: String, payload: CatalogImportPayload) async throws -> CatalogImportResult {
        let params = ImportRPCParams(p_company_id: companyId, p_payload: payload)
        return try await client.rpc(name, params: params).execute().value
    }
}
