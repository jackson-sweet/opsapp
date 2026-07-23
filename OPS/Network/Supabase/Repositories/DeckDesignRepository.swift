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

    // MARK: - Fetch for Opportunity

    /// Decks drawn on a lead. Same resilient row-by-row decode as the project
    /// path — LeadDetailView's self-repair fetch must survive one corrupt row.
    func fetchForOpportunity(_ opportunityId: String) async throws -> [SupabaseDeckDesignDTO] {
        let data = try await client
            .from("deck_designs")
            .select()
            .eq("company_id", value: companyId)
            .eq("opportunity_id", value: opportunityId)
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

    // MARK: - Link to Opportunity (server-guarded)

    /// Attaches an ORPHAN deck design (`opportunity_id IS NULL`) to a lead.
    ///
    /// A direct PATCH of `opportunity_id` is blocked server-side by the reparent
    /// guard trigger; this RPC mints the reparent token inside the transaction,
    /// so it is the ONLY legal path to attach an existing design to a lead. It is
    /// idempotent: re-linking to the SAME lead returns `already_linked:true`
    /// (callers treat that as success), while a DIFFERENT lead raises SQLSTATE
    /// 23514 and a missing/foreign/deleted row raises 42501/P0002 — all permanent,
    /// so the outbound op parks rather than looping.
    func linkToOpportunity(
        designId: String,
        opportunityId: String
    ) async throws -> DeckDesignLinkResult {
        struct Params: Encodable {
            let p_design_id: String
            let p_target_opportunity_id: String
        }
        return try await client
            .rpc(
                "link_deck_design_to_opportunity_guarded",
                params: Params(
                    p_design_id: designId,
                    p_target_opportunity_id: opportunityId
                )
            )
            .execute()
            .value
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

/// Decoded result of `link_deck_design_to_opportunity_guarded`.
///
/// The RPC returns jsonb `{ok, already_linked, design_id, opportunity_id}`.
/// `alreadyLinked` is true when the design was already attached to the requested
/// lead (an idempotent retry) — callers treat it as success. Every field is
/// decoded defensively so a future server-shape drift degrades to `ok:false`
/// instead of throwing a decode error that would misclassify as transient.
struct DeckDesignLinkResult: Decodable {
    let ok: Bool
    let alreadyLinked: Bool
    let designId: String?
    let opportunityId: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case alreadyLinked = "already_linked"
        case designId      = "design_id"
        case opportunityId = "opportunity_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        alreadyLinked = try container.decodeIfPresent(Bool.self, forKey: .alreadyLinked) ?? false
        designId = try container.decodeIfPresent(String.self, forKey: .designId)
        opportunityId = try container.decodeIfPresent(String.self, forKey: .opportunityId)
    }
}
