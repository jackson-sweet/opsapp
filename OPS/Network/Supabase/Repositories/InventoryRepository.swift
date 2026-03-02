//
//  InventoryRepository.swift
//  OPS
//
//  Repository for Inventory operations via Supabase.
//

import Foundation
import Supabase

class InventoryRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Items

    func fetchAllItems() async throws -> [InventoryItemReadDTO] {
        try await client
            .from("inventory_items")
            .select()
            .eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
            .order("name", ascending: true)
            .execute()
            .value
    }

    func createItem(_ dto: CreateInventoryItemDTO) async throws -> InventoryItemReadDTO {
        try await client
            .from("inventory_items")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func updateItem(_ id: String, fields: UpdateInventoryItemDTO) async throws -> InventoryItemReadDTO {
        try await client
            .from("inventory_items")
            .update(fields)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func softDeleteItem(_ id: String) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        try await client
            .from("inventory_items")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Units

    func fetchAllUnits() async throws -> [InventoryUnitReadDTO] {
        try await client
            .from("inventory_units")
            .select()
            .eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
            .order("sort_order", ascending: true)
            .execute()
            .value
    }

    func createUnit(_ dto: CreateInventoryUnitDTO) async throws -> InventoryUnitReadDTO {
        try await client
            .from("inventory_units")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func softDeleteUnit(_ id: String) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        try await client
            .from("inventory_units")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    func createDefaultUnits() async throws -> [InventoryUnitReadDTO] {
        let defaults = [
            ("ea", true, 0), ("box", false, 1), ("ft", false, 2),
            ("m", false, 3), ("kg", false, 4), ("lb", false, 5),
            ("gal", false, 6), ("L", false, 7), ("roll", false, 8),
            ("sheet", false, 9), ("bag", false, 10), ("pallet", false, 11)
        ]
        var results: [InventoryUnitReadDTO] = []
        for (display, isDefault, sortOrder) in defaults {
            let dto = CreateInventoryUnitDTO(
                companyId: companyId,
                display: display,
                isDefault: isDefault,
                sortOrder: sortOrder
            )
            let created: InventoryUnitReadDTO = try await client
                .from("inventory_units")
                .insert(dto)
                .select()
                .single()
                .execute()
                .value
            results.append(created)
        }
        return results
    }

    // MARK: - Tags

    func fetchAllTags() async throws -> [InventoryTagReadDTO] {
        try await client
            .from("inventory_tags")
            .select()
            .eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
            .order("name", ascending: true)
            .execute()
            .value
    }

    func createTag(_ dto: CreateInventoryTagDTO) async throws -> InventoryTagReadDTO {
        try await client
            .from("inventory_tags")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func updateTag(_ id: String, fields: UpdateInventoryTagDTO) async throws -> InventoryTagReadDTO {
        try await client
            .from("inventory_tags")
            .update(fields)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func softDeleteTag(_ id: String) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        try await client
            .from("inventory_tags")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Item-Tag Junction

    func fetchAllItemTags() async throws -> [InventoryItemTagReadDTO] {
        try await client
            .from("inventory_item_tags")
            .select()
            .execute()
            .value
    }

    func setItemTags(itemId: String, tagIds: [String]) async throws {
        // Delete existing tags for this item
        try await client
            .from("inventory_item_tags")
            .delete()
            .eq("item_id", value: itemId)
            .execute()

        // Insert new tags
        guard !tagIds.isEmpty else { return }
        let rows = tagIds.map { ["item_id": itemId, "tag_id": $0] }
        try await client
            .from("inventory_item_tags")
            .insert(rows)
            .execute()
    }

    // MARK: - Snapshots

    func fetchSnapshots() async throws -> [InventorySnapshotReadDTO] {
        try await client
            .from("inventory_snapshots")
            .select()
            .eq("company_id", value: companyId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchSnapshotItems(snapshotId: String) async throws -> [InventorySnapshotItemReadDTO] {
        try await client
            .from("inventory_snapshot_items")
            .select()
            .eq("snapshot_id", value: snapshotId)
            .order("name", ascending: true)
            .execute()
            .value
    }

    func createFullSnapshot(
        userId: String?,
        isAutomatic: Bool,
        items: [CreateInventorySnapshotItemDTO],
        notes: String?
    ) async throws -> InventorySnapshotReadDTO {
        // Create the snapshot header
        let snapshotDTO = CreateInventorySnapshotDTO(
            companyId: companyId,
            createdById: userId,
            isAutomatic: isAutomatic,
            itemCount: items.count,
            notes: notes
        )
        let snapshot: InventorySnapshotReadDTO = try await client
            .from("inventory_snapshots")
            .insert(snapshotDTO)
            .select()
            .single()
            .execute()
            .value

        // Insert all snapshot items with the new snapshot ID
        if !items.isEmpty {
            let snapshotItems = items.map { item in
                CreateInventorySnapshotItemDTO(
                    snapshotId: snapshot.id,
                    originalItemId: item.originalItemId,
                    name: item.name,
                    quantity: item.quantity,
                    unitDisplay: item.unitDisplay,
                    sku: item.sku,
                    tagsString: item.tagsString,
                    description: item.description
                )
            }
            try await client
                .from("inventory_snapshot_items")
                .insert(snapshotItems)
                .execute()
        }

        return snapshot
    }
}

// MARK: - ISO8601 Helpers

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}
