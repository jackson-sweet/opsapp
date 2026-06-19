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

    /// Sync variant: includes soft-deleted rows so the local store can mirror tombstones.
    /// `since` filters by `updated_at` (delta sync) — pass nil for a full pull.
    func fetchItemsForSync(since: Date? = nil) async throws -> [InventoryItemReadDTO] {
        var query = client
            .from("inventory_items")
            .select()
            .eq("company_id", value: companyId)
        if let since = since {
            query = query.gte("updated_at", value: isoString(since))
        }
        return try await query
            .order("updated_at", ascending: true)
            .executeResilient(label: "inventory")
    }

    func fetchDeletedItemIds(since: Date) async throws -> [String] {
        struct IdRow: Codable { let id: String }
        let rows: [IdRow] = try await client
            .from("inventory_items")
            .select("id")
            .eq("company_id", value: companyId)
            .not("deleted_at", operator: .is, value: "null")
            .gte("deleted_at", value: isoString(since))
            .execute()
            .value
        return rows.map { $0.id }
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

    func fetchUnitsForSync(since: Date? = nil) async throws -> [InventoryUnitReadDTO] {
        var query = client
            .from("inventory_units")
            .select()
            .eq("company_id", value: companyId)
        if let since = since {
            query = query.gte("updated_at", value: isoString(since))
        }
        return try await query
            .order("updated_at", ascending: true)
            .executeResilient(label: "inventory")
    }

    func fetchDeletedUnitIds(since: Date) async throws -> [String] {
        struct IdRow: Codable { let id: String }
        let rows: [IdRow] = try await client
            .from("inventory_units")
            .select("id")
            .eq("company_id", value: companyId)
            .not("deleted_at", operator: .is, value: "null")
            .gte("deleted_at", value: isoString(since))
            .execute()
            .value
        return rows.map { $0.id }
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

    func fetchTagsForSync(since: Date? = nil) async throws -> [InventoryTagReadDTO] {
        var query = client
            .from("inventory_tags")
            .select()
            .eq("company_id", value: companyId)
        if let since = since {
            query = query.gte("updated_at", value: isoString(since))
        }
        return try await query
            .order("updated_at", ascending: true)
            .executeResilient(label: "inventory")
    }

    func fetchDeletedTagIds(since: Date) async throws -> [String] {
        struct IdRow: Codable { let id: String }
        let rows: [IdRow] = try await client
            .from("inventory_tags")
            .select("id")
            .eq("company_id", value: companyId)
            .not("deleted_at", operator: .is, value: "null")
            .gte("deleted_at", value: isoString(since))
            .execute()
            .value
        return rows.map { $0.id }
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

    /// Fetches every join row visible to the caller — kept for legacy callers.
    /// Sync uses `fetchItemTagsForCompany()` which filters via the items table.
    func fetchAllItemTags() async throws -> [InventoryItemTagReadDTO] {
        try await client
            .from("inventory_item_tags")
            .select()
            .execute()
            .value
    }

    /// Fetch every (item_id, tag_id) join row whose item belongs to this company.
    /// `inventory_item_tags` has no timestamps, so this is always a full pull —
    /// fine in practice (a few hundred rows max per company).
    func fetchItemTagsForCompany() async throws -> [InventoryItemTagReadDTO] {
        struct Joined: Codable {
            let id: String
            let itemId: String
            let tagId: String
            enum CodingKeys: String, CodingKey {
                case id
                case itemId = "item_id"
                case tagId = "tag_id"
            }
        }
        // Filter join rows whose parent item belongs to this company.
        let rows: [Joined] = try await client
            .from("inventory_item_tags")
            .select("id, item_id, tag_id, inventory_items!inner(company_id)")
            .eq("inventory_items.company_id", value: companyId)
            .executeResilient(label: "inventory")
        return rows.map { InventoryItemTagReadDTO(id: $0.id, itemId: $0.itemId, tagId: $0.tagId) }
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

    /// Snapshots are immutable (no updated_at, no deleted_at); delta filters on `created_at`.
    func fetchSnapshotsForSync(since: Date? = nil) async throws -> [InventorySnapshotReadDTO] {
        var query = client
            .from("inventory_snapshots")
            .select()
            .eq("company_id", value: companyId)
        if let since = since {
            query = query.gte("created_at", value: isoString(since))
        }
        return try await query
            .order("created_at", ascending: true)
            .executeResilient(label: "inventory")
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

    /// Bulk fetch snapshot items for an arbitrary set of snapshot ids.
    /// Used during sync to populate items for newly-pulled snapshots.
    func fetchSnapshotItemsForSnapshots(_ snapshotIds: [String]) async throws -> [InventorySnapshotItemReadDTO] {
        guard !snapshotIds.isEmpty else { return [] }
        return try await client
            .from("inventory_snapshot_items")
            .select()
            .in("snapshot_id", values: snapshotIds)
            .executeResilient(label: "inventory")
    }

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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
