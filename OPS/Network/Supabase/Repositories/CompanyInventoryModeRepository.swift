//
//  CompanyInventoryModeRepository.swift
//  OPS
//
//  Reads the current company inventory mode from `company_inventory_settings`
//  and toggles it through the permission-gated `public.set_company_inventory_mode`
//  RPC. The RPC — not the client — owns the side effects of turning tracking
//  off (releasing open projected demand, writing release snapshots). iOS only
//  reflects the resulting mode in the UI.
//

import Foundation
import Supabase

/// Test seam for the inventory-mode read/write surface so view models and the
/// toggle control can be exercised without a live Supabase client.
protocol InventoryModeClient {
    /// Current mode for the company. A missing settings row resolves to `.off`.
    func fetchInventoryMode() async throws -> InventoryMode
    /// Toggles the mode via the server RPC and returns the structured result.
    func setInventoryMode(_ mode: InventoryMode) async throws -> SetInventoryModeResponseDTO
}

final class CompanyInventoryModeRepository: InventoryModeClient {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchInventoryMode() async throws -> InventoryMode {
        let rows: [CompanyInventorySettingsDTO] = try await client
            .from("company_inventory_settings")
            .select("company_id,inventory_mode,enabled_at,disabled_at,updated_by,created_at,updated_at")
            .eq("company_id", value: companyId)
            .limit(1)
            .execute()
            .value

        // No row means tracking was never enabled — treat as `off`, never as an
        // error and never as `tracked`.
        return rows.first?.mode ?? .off
    }

    func setInventoryMode(_ mode: InventoryMode) async throws -> SetInventoryModeResponseDTO {
        struct Params: Encodable {
            let p_company_id: String
            let p_inventory_mode: String
        }

        return try await client
            .rpc(
                "set_company_inventory_mode",
                params: Params(
                    p_company_id: companyId,
                    p_inventory_mode: mode.rawValue
                )
            )
            .execute()
            .value
    }
}
