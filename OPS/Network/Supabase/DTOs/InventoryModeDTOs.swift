//
//  InventoryModeDTOs.swift
//  OPS
//
//  Phase 6 company inventory operating-mode contracts.
//
//  Inventory mode is the explicit, server-authoritative switch that decides
//  whether estimate acceptance and task completion perform material-demand
//  work. It is NEVER inferred from catalog rows, stock presence, or
//  permissions — it is read from `company_inventory_settings` and written only
//  through the permission-gated `public.set_company_inventory_mode` RPC.
//

import Foundation

/// The two valid company inventory operating modes. A company with no
/// `company_inventory_settings` row is treated as `.off` (the table default).
enum InventoryMode: String, Codable, CaseIterable, Equatable {
    /// No projected demand, no material warnings, no missing-mapping
    /// notifications, no stock deduction.
    case off
    /// Estimate acceptance creates projected demand and warnings; task
    /// completion deducts stock and writes final history.
    case tracked

    /// Tolerant parse from any server string. Unknown / nil → `.off`, because
    /// the absence of an explicit `tracked` value must never silently enable
    /// material work.
    init(serverValue: String?) {
        switch serverValue?.lowercased() {
        case InventoryMode.tracked.rawValue:
            self = .tracked
        default:
            self = .off
        }
    }

    var isTracked: Bool { self == .tracked }
}

/// Read shape for `public.company_inventory_settings`. SELECT is allowed for any
/// same-company user (write requires `catalog.manage`).
struct CompanyInventorySettingsDTO: Codable, Equatable {
    let companyId: String
    let inventoryMode: String
    let enabledAt: String?
    let disabledAt: String?
    let updatedBy: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case inventoryMode = "inventory_mode"
        case enabledAt = "enabled_at"
        case disabledAt = "disabled_at"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var mode: InventoryMode { InventoryMode(serverValue: inventoryMode) }
}

/// Return shape of `public.set_company_inventory_mode(p_company_id, p_inventory_mode)`.
struct SetInventoryModeResponseDTO: Codable, Equatable {
    let ok: Bool
    let companyId: String
    let inventoryMode: String
    let previousInventoryMode: String
    let updatedBy: String?
    /// Count of open projected-demand rows released when switching to `off`.
    let releasedDemands: Int
    /// Count of `inventory_mode_released` snapshots written when switching to `off`.
    let releaseSnapshots: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case companyId = "company_id"
        case inventoryMode = "inventory_mode"
        case previousInventoryMode = "previous_inventory_mode"
        case updatedBy = "updated_by"
        case releasedDemands = "released_demands"
        case releaseSnapshots = "release_snapshots"
    }

    var mode: InventoryMode { InventoryMode(serverValue: inventoryMode) }
    var previousMode: InventoryMode { InventoryMode(serverValue: previousInventoryMode) }
}
