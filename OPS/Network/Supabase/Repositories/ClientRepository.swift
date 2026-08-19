//
//  ClientRepository.swift
//  OPS
//
//  Repository for Client and SubClient entity operations via Supabase.
//  Tables: clients, sub_clients
//
//  Column note: phone is stored as `phone_number` in both clients and sub_clients tables.
//

import Foundation
import Supabase

class ClientRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch Clients

    func fetchAll(since: Date? = nil, scope: String = "all", userId: String? = nil) async throws -> [SupabaseClientDTO] {
        var query = client
            .from("clients")
            .select()
            .eq("company_id", value: companyId)

        if let since = since {
            query = query.gte("updated_at", value: isoString(since))
        }

        // Permission scope filtering
        // Clients don't have team_member_ids, so "assigned" falls through to "all".
        // Only "own" scope restricts to creator.
        if scope == "own", let userId = userId {
            query = query.eq("created_by", value: userId)
        }

        let response: [SupabaseClientDTO] = try await query
            .order("created_at", ascending: false)
            .executeResilient(label: "clients")
        return response
    }

    func fetchOne(_ id: String) async throws -> SupabaseClientDTO {
        try await client
            .from("clients")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    // MARK: - Create Client

    /// Deliberately asks for NO representation.
    ///
    /// `.select()` after `.insert()` appends `Prefer: return=representation`
    /// (supabase-swift `PostgrestTransformBuilder.select`), PostgREST turns that
    /// into `INSERT … RETURNING`, and Postgres then applies the table's SELECT
    /// policies to the new row as an INSERT check — evaluated in `ExecInsert`
    /// BEFORE the tuple is written. `clients.role_scope_read` resolved the row by
    /// re-reading `public.clients` by id, found nothing (the row does not exist
    /// yet), and rejected the whole statement with
    /// `42501 new row violates row-level security policy "role_scope_read"`.
    /// A real customer was lost that way on the founder's phone (2026-08-19).
    ///
    /// Both callers — `OutboundProcessor.handleClient` and
    /// `DataActor.handleClient` — discarded the returned DTO, so the
    /// representation bought nothing and cost the write. The policy itself is
    /// repaired server-side (`20260819044939_client_project_read_policy_row_columns.sql`);
    /// this removes the trigger so the create cannot depend on that fix landing.
    func create(_ dto: SupabaseClientDTO) async throws {
        try await client
            .from("clients")
            .insert(dto)
            .execute()
    }

    // MARK: - Upsert Client

    func upsert(_ dto: SupabaseClientDTO) async throws {
        try await client
            .from("clients")
            .upsert(dto)
            .execute()
    }

    // MARK: - Update Client

    func updateContact(
        clientId: String,
        name: String,
        email: String?,
        phone: String?,
        address: String?
    ) async throws {
        struct ContactUpdate: Codable {
            let name: String
            let email: String?
            let phone_number: String?
            let address: String?
            let updated_at: String
        }
        let payload = ContactUpdate(
            name: name,
            email: email,
            phone_number: phone,
            address: address,
            updated_at: isoNow()
        )
        try await client
            .from("clients")
            .update(payload)
            .eq("id", value: clientId)
            .execute()
    }

    // MARK: - Soft Delete Client

    func softDelete(_ id: String) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        try await client
            .from("clients")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Sub-Clients

    func fetchSubClients(for clientId: String) async throws -> [SupabaseSubClientDTO] {
        let response: [SupabaseSubClientDTO] = try await client
            .from("sub_clients")
            .select()
            .eq("client_id", value: clientId)
            .order("created_at", ascending: true)
            .execute()
            .value
        return response
    }

    func createSubClient(
        clientId: String,
        name: String,
        title: String?,
        email: String?,
        phone: String?,
        address: String?
    ) async throws -> SupabaseSubClientDTO {
        struct NewSubClient: Codable {
            let client_id: String
            let company_id: String
            let name: String
            let title: String?
            let email: String?
            let phone_number: String?
            let address: String?
        }
        let payload = NewSubClient(
            client_id: clientId,
            company_id: companyId,
            name: name,
            title: title,
            email: email,
            phone_number: phone,
            address: address
        )
        let response: SupabaseSubClientDTO = try await client
            .from("sub_clients")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func deleteSubClient(_ id: String) async throws {
        try await client
            .from("sub_clients")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Update SubClient

    func updateSubClient(
        subClientId: String,
        name: String?,
        title: String?,
        email: String?,
        phone: String?,
        address: String?
    ) async throws {
        struct SubClientUpdate: Codable {
            let name: String?
            let title: String?
            let email: String?
            let phone_number: String?
            let address: String?
            let updated_at: String
        }
        let payload = SubClientUpdate(
            name: name,
            title: title,
            email: email,
            phone_number: phone,
            address: address,
            updated_at: isoNow()
        )
        try await client
            .from("sub_clients")
            .update(payload)
            .eq("id", value: subClientId)
            .execute()
    }

    // MARK: - Fetch All SubClients (for InboundProcessor)

    func fetchAllSubClients(since: Date? = nil) async throws -> [SupabaseSubClientDTO] {
        var query = client
            .from("sub_clients")
            .select()
            .eq("company_id", value: companyId)

        if let since = since {
            query = query.gte("updated_at", value: isoString(since))
        }

        let response: [SupabaseSubClientDTO] = try await query
            .order("created_at", ascending: true)
            .executeResilient(label: "clients")
        return response
    }

    // MARK: - Update Client Fields (generic)

    func updateFields(_ clientId: String, fields: [String: AnyJSON]) async throws {
        var payload = fields
        payload["updated_at"] = .string(isoNow())
        let response = try await client
            .from("clients")
            .update(payload)
            .eq("id", value: clientId)
            .select("id")
            .execute()
        try SupabaseWriteGuard.requireAffectedRow(
            response: response.data,
            table: "clients",
            id: clientId,
            fields: payload
        )
    }
}

// MARK: - ISO8601 Helpers

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func isoString(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}
