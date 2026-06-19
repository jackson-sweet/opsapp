//
//  DeckDesignRepository.swift
//  OPS
//
//  Repository for DeckDesign entity operations via Supabase.
//  Table: deck_designs
//

import Foundation
import Supabase

class DeckDesignRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch All (for InboundProcessor)

    func fetchAll(since: Date? = nil) async throws -> [SupabaseDeckDesignDTO] {
        var query = client
            .from("deck_designs")
            .select()
            .eq("company_id", value: companyId)

        if let since = since {
            query = query.gte("updated_at", value: ISO8601DateFormatter().string(from: since))
        }

        // Decode row-by-row so a single corrupt drawing_data can't fail the whole
        // batch — one undecodable deck must never black out every deck (the crew
        // deck-blackout bug). execute() (no decoded type) returns the raw rows.
        let data = try await query
            .order("created_at", ascending: false)
            .execute()
            .data
        return Self.decodeResilient(data)
    }

    // MARK: - Fetch for Project

    func fetchForProject(_ projectId: String) async throws -> [SupabaseDeckDesignDTO] {
        // Row-by-row decode (see fetchAll) — the DeckTabView self-repair path must
        // also survive a single corrupt row instead of showing nothing.
        let data = try await client
            .from("deck_designs")
            .select()
            .eq("company_id", value: companyId)
            .eq("project_id", value: projectId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .data
        return Self.decodeResilient(data)
    }

    // MARK: - Decode Resilience

    /// Decode a `deck_designs` array row-by-row, skipping any row whose JSON fails
    /// to decode (e.g. a corrupt `drawing_data`) instead of failing the whole
    /// batch — a single bad row must never strand every deck. Every DTO field is
    /// String/Int/Codable-struct, so a plain JSONDecoder matches the SDK's decode.
    static func decodeResilient(_ data: Data) -> [SupabaseDeckDesignDTO] {
        let decoder = JSONDecoder()
        guard let elements = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            // Not a JSON array — fall back to a strict decode, else empty.
            return (try? decoder.decode([SupabaseDeckDesignDTO].self, from: data)) ?? []
        }
        var decoded: [SupabaseDeckDesignDTO] = []
        decoded.reserveCapacity(elements.count)
        for element in elements {
            guard let rowData = try? JSONSerialization.data(withJSONObject: element) else { continue }
            do {
                decoded.append(try decoder.decode(SupabaseDeckDesignDTO.self, from: rowData))
            } catch {
                print("[DECK_SYNC] skipping undecodable deck_designs row: \(error)")
            }
        }
        return decoded
    }

    // MARK: - Create

    func create(_ dto: SupabaseDeckDesignDTO) async throws -> SupabaseDeckDesignDTO {
        try await client
            .from("deck_designs")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Upsert

    func upsert(_ dto: SupabaseDeckDesignDTO) async throws {
        try await client
            .from("deck_designs")
            .upsert(dto)
            .execute()
    }

    // MARK: - Update Fields

    func updateFields(_ id: String, fields: [String: AnyJSON]) async throws {
        var payload = fields
        payload["updated_at"] = .string(isoNow())

        try await client
            .from("deck_designs")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Soft Delete

    func softDelete(_ id: String) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        try await client
            .from("deck_designs")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }
}

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}
