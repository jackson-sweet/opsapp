//
//  InventoryEndpoints.swift
//  OPS
//
//  API endpoints for inventory management
//

import Foundation

/// Extension for inventory-related API endpoints
extension APIService {

    // MARK: - InventoryUnit Fetching

    /// Fetch all inventory units for a company (via Company relationship)
    /// - Parameter companyId: The company ID
    /// - Returns: Array of inventory unit DTOs
    func fetchCompanyInventoryUnits(companyId: String) async throws -> [InventoryUnitDTO] {
        print("[API_INVENTORY_UNITS] 📦 Fetching inventory units for company: \(companyId)")

        // Fetch company to get inventory unit IDs from the relationship
        let company = try await fetchCompany(id: companyId)

        // Extract inventory unit IDs from the company's inventoryUnits relationship
        guard let unitRefs = company.inventoryUnits, !unitRefs.isEmpty else {
            print("[API_INVENTORY_UNITS] ⚠️ No inventory units found on company")
            return []
        }

        let unitIds = unitRefs.compactMap { $0.stringValue }
        print("[API_INVENTORY_UNITS] 🔍 Found \(unitIds.count) inventory unit IDs on company")

        // Fetch the specific inventory units by their IDs
        return try await fetchInventoryUnitsByIds(ids: unitIds)
    }

    /// Fetch specific inventory units by their IDs
    /// - Parameter ids: Array of inventory unit IDs to fetch
    /// - Returns: Array of inventory unit DTOs
    func fetchInventoryUnitsByIds(ids: [String]) async throws -> [InventoryUnitDTO] {
        guard !ids.isEmpty else { return [] }

        print("[API_INVENTORY_UNITS] 🔍 Fetching \(ids.count) units by IDs...")
        print("[API_INVENTORY_UNITS] 📡 Using object type: '\(BubbleFields.Types.inventoryUnit)'")

        // Create constraint for fetching specific IDs
        let constraints = [
            [
                "key": "_id",
                "constraint_type": "in",
                "value": ids
            ]
        ]

        let units: [InventoryUnitDTO] = try await fetchBubbleObjectsWithArrayConstraints(
            objectType: BubbleFields.Types.inventoryUnit,
            constraints: constraints,
            sortField: BubbleFields.InventoryUnit.sortOrder
        )

        print("[API_INVENTORY_UNITS] ✅ Fetched \(units.count) inventory units")
        for unit in units {
            print("[API_INVENTORY_UNITS]   - \(unit.id): \(unit.display)")
        }
        return units
    }

    /// Fetch a single inventory unit by ID
    /// - Parameter id: The inventory unit ID
    /// - Returns: InventoryUnit DTO
    func fetchInventoryUnit(id: String) async throws -> InventoryUnitDTO {
        return try await fetchBubbleObject(
            objectType: BubbleFields.Types.inventoryUnit,
            id: id
        )
    }

    // MARK: - InventoryUnit Creation

    /// Create a new inventory unit
    /// - Parameter unit: The inventory unit DTO to create
    /// - Returns: The created inventory unit DTO with server-assigned ID
    func createInventoryUnit(_ unit: InventoryUnitDTO) async throws -> InventoryUnitDTO {
        print("[API_INVENTORY_UNIT_CREATE] 🔵 Starting inventory unit creation")
        print("[API_INVENTORY_UNIT_CREATE] Display: \(unit.display)")

        var unitData: [String: Any] = [
            BubbleFields.InventoryUnit.display: unit.display
        ]

        if let company = unit.company {
            unitData[BubbleFields.InventoryUnit.company] = company
        }
        if let isDefault = unit.isDefault {
            unitData[BubbleFields.InventoryUnit.isDefault] = isDefault
        }
        if let sortOrder = unit.sortOrder {
            unitData[BubbleFields.InventoryUnit.sortOrder] = sortOrder
        }

        let bodyData = try JSONSerialization.data(withJSONObject: unitData)

        print("[API_INVENTORY_UNIT_CREATE] 📡 Sending POST request to Bubble...")
        let response: InventoryUnitCreationResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.inventoryUnit)",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )

        print("[API_INVENTORY_UNIT_CREATE] ✅ Bubble returned ID: \(response.id)")

        return InventoryUnitDTO(
            id: response.id,
            display: unit.display,
            company: unit.company,
            isDefault: unit.isDefault,
            sortOrder: unit.sortOrder,
            createdDate: nil,
            modifiedDate: nil
        )
    }

    /// Create default inventory units for a company via Bubble workflow
    /// - Parameter companyId: The company ID
    /// - Returns: Array of created inventory unit DTOs
    func createDefaultInventoryUnits(companyId: String) async throws -> [InventoryUnitDTO] {
        print("[API_INVENTORY_UNITS] 🔵 Creating default inventory units for company: \(companyId)")

        let parameters: [String: Any] = [
            "company": companyId
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: parameters)

        print("[API_INVENTORY_UNITS] 📡 Calling Bubble workflow...")

        // Try different response formats since Bubble workflows can return data in various structures

        // Try 1: BubbleWorkflowResponse with "response" key containing array
        do {
            let response: BubbleWorkflowResponse<[InventoryUnitDTO]> = try await executeRequest(
                endpoint: "api/1.1/wf/create_default_inventory_units",
                method: "POST",
                body: bodyData,
                requiresAuth: false
            )
            print("[API_INVENTORY_UNITS] ✅ Decoded as BubbleWorkflowResponse: \(response.response?.count ?? 0) units")
            if let units = response.response, !units.isEmpty {
                return units
            }
        } catch {
            print("[API_INVENTORY_UNITS] ⚠️ Failed to decode as BubbleWorkflowResponse: \(error)")
        }

        // Try 2: Response with nested "response.inventoryUnits" (Bubble's standard workflow format)
        do {
            let response: InventoryUnitsWorkflowResponse = try await executeRequest(
                endpoint: "api/1.1/wf/create_default_inventory_units",
                method: "POST",
                body: bodyData,
                requiresAuth: false
            )
            print("[API_INVENTORY_UNITS] ✅ Decoded with nested inventoryUnits: \(response.response?.inventoryUnits?.count ?? 0) units")
            if let units = response.response?.inventoryUnits, !units.isEmpty {
                return units
            }
        } catch {
            print("[API_INVENTORY_UNITS] ⚠️ Failed to decode with nested inventoryUnits: \(error)")
        }

        // Try 3: Empty response wrapper (workflow ran but returned status only)
        do {
            let response: EmptyWorkflowResponse = try await executeRequest(
                endpoint: "api/1.1/wf/create_default_inventory_units",
                method: "POST",
                body: bodyData,
                requiresAuth: false
            )
            print("[API_INVENTORY_UNITS] 📥 Empty workflow response - status: \(response.status ?? "nil")")
            // Workflow executed but returned no data - fetch units separately
            print("[API_INVENTORY_UNITS] 🔄 Fetching units after workflow...")
            return try await fetchCompanyInventoryUnits(companyId: companyId)
        } catch {
            print("[API_INVENTORY_UNITS] ⚠️ Failed to decode as empty response: \(error)")
        }

        print("[API_INVENTORY_UNITS] ❌ Could not decode response - check Bubble workflow return value")
        return []
    }

    // MARK: - InventoryUnit Updates

    /// Update an inventory unit
    /// - Parameters:
    ///   - id: The inventory unit ID
    ///   - display: New display name (optional)
    ///   - sortOrder: New sort order (optional)
    func updateInventoryUnit(id: String, display: String? = nil, sortOrder: Int? = nil) async throws {
        print("[UPDATE_INVENTORY_UNIT] 📝 Updating inventory unit: \(id)")

        var updateData: [String: Any] = [:]

        if let display = display {
            updateData[BubbleFields.InventoryUnit.display] = display
            print("[UPDATE_INVENTORY_UNIT] Display: \(display)")
        }

        if let sortOrder = sortOrder {
            updateData[BubbleFields.InventoryUnit.sortOrder] = sortOrder
            print("[UPDATE_INVENTORY_UNIT] Sort Order: \(sortOrder)")
        }

        guard !updateData.isEmpty else {
            print("[UPDATE_INVENTORY_UNIT] ⚠️ No updates to send")
            return
        }

        let bodyData = try JSONSerialization.data(withJSONObject: updateData)

        print("[UPDATE_INVENTORY_UNIT] 📡 Sending PATCH request to Bubble...")
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.inventoryUnit.lowercased())/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )

        print("[UPDATE_INVENTORY_UNIT] ✅ Inventory unit successfully updated in Bubble")
    }

    // MARK: - InventoryUnit Deletion

    /// Delete an inventory unit (soft delete)
    /// - Parameter id: The inventory unit ID to delete
    func deleteInventoryUnit(id: String) async throws {
        print("[API] Deleting inventory unit: \(id)")

        // Soft delete by setting deletedAt
        let updateData: [String: Any] = [
            BubbleFields.InventoryUnit.deletedAt: ISO8601DateFormatter().string(from: Date())
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: updateData)

        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.inventoryUnit.lowercased())/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )

        print("[API] ✅ Inventory unit soft deleted successfully")
    }

    // MARK: - InventoryItem Fetching

    /// Fetch all inventory items for a company
    /// - Parameter companyId: The company ID
    /// - Returns: Array of inventory item DTOs
    func fetchCompanyInventoryItems(companyId: String) async throws -> [InventoryItemDTO] {
        print("[API_INVENTORY_ITEMS] 📦 Fetching inventory items for company: \(companyId)")

        let constraints: [[String: Any]] = [
            [
                "key": BubbleFields.InventoryItem.company,
                "constraint_type": "equals",
                "value": companyId
            ],
            [
                "key": BubbleFields.InventoryItem.deletedAt,
                "constraint_type": "is_empty"
            ]
        ]

        // Use detached task to prevent cancellation from parent task (SwiftUI refreshable)
        // This isolates the network request from the parent's cancellation scope
        let apiService = self
        let items: [InventoryItemDTO] = try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let result: [InventoryItemDTO] = try await apiService.fetchBubbleObjectsWithArrayConstraintsPaginated(
                        objectType: BubbleFields.Types.inventoryItem,
                        constraints: constraints,
                        sortField: BubbleFields.InventoryItem.name
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        print("[API_INVENTORY_ITEMS] ✅ Fetched \(items.count) inventory items")
        return items
    }

    /// Fetch a single inventory item by ID
    /// - Parameter id: The inventory item ID
    /// - Returns: InventoryItem DTO
    func fetchInventoryItem(id: String) async throws -> InventoryItemDTO {
        return try await fetchBubbleObject(
            objectType: BubbleFields.Types.inventoryItem,
            id: id
        )
    }

    // MARK: - InventoryItem Creation

    /// Create a new inventory item
    /// - Parameter item: The inventory item DTO to create
    /// - Returns: The created inventory item DTO with server-assigned ID
    func createInventoryItem(_ item: InventoryItemDTO) async throws -> InventoryItemDTO {
        print("[API_INVENTORY_ITEM_CREATE] 🔵 Starting inventory item creation")
        print("[API_INVENTORY_ITEM_CREATE] Name: \(item.name ?? "unnamed")")

        let itemData = item.toDictionary()
        let bodyData = try JSONSerialization.data(withJSONObject: itemData)

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[API_INVENTORY_ITEM_CREATE] 📤 Request body: \(jsonString)")
        }

        print("[API_INVENTORY_ITEM_CREATE] 📡 Sending POST request to Bubble...")
        let response: InventoryItemCreationResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.inventoryItem)",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )

        print("[API_INVENTORY_ITEM_CREATE] ✅ Bubble returned ID: \(response.id)")

        return InventoryItemDTO(
            id: response.id,
            name: item.name,
            description: item.description,
            quantity: item.quantity,
            unit: item.unit,
            tags: item.tags,
            company: item.company,
            sku: item.sku,
            notes: item.notes,
            imageUrl: item.imageUrl,
            createdDate: nil,
            modifiedDate: nil
        )
    }

    // MARK: - InventoryItem Updates

    /// Update an inventory item
    /// - Parameters:
    ///   - id: The inventory item ID
    ///   - updates: Dictionary of fields to update
    func updateInventoryItem(id: String, updates: [String: Any]) async throws {
        print("[UPDATE_INVENTORY_ITEM] 📝 Updating inventory item: \(id)")
        print("[UPDATE_INVENTORY_ITEM] 📋 Updates keys: \(updates.keys.joined(separator: ", "))")

        // Debug: Log each value type to catch non-serializable objects
        for (key, value) in updates {
            let valueType = type(of: value)
            print("[UPDATE_INVENTORY_ITEM] 🔍 \(key): \(valueType) = \(value)")
        }

        guard !updates.isEmpty else {
            print("[UPDATE_INVENTORY_ITEM] ⚠️ No updates to send")
            return
        }

        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: updates)
        } catch {
            print("[UPDATE_INVENTORY_ITEM] ❌ JSON serialization failed: \(error)")
            print("[UPDATE_INVENTORY_ITEM] ❌ Updates that failed: \(updates)")
            throw error
        }

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[UPDATE_INVENTORY_ITEM] 📤 Request body: \(jsonString)")
        }

        print("[UPDATE_INVENTORY_ITEM] 📡 Sending PATCH request to Bubble...")
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.inventoryItem.lowercased())/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )

        print("[UPDATE_INVENTORY_ITEM] ✅ Inventory item successfully updated in Bubble")
    }

    /// Update inventory item quantity
    /// - Parameters:
    ///   - id: The inventory item ID
    ///   - newQuantity: The new quantity value
    func updateInventoryItemQuantity(id: String, newQuantity: Double) async throws {
        print("[UPDATE_INVENTORY_ITEM] 📝 Updating quantity for item: \(id) to \(newQuantity)")

        let updates: [String: Any] = [
            BubbleFields.InventoryItem.quantity: newQuantity
        ]

        try await updateInventoryItem(id: id, updates: updates)
    }

    // MARK: - InventoryItem Deletion

    /// Delete an inventory item (soft delete)
    /// - Parameter id: The inventory item ID to delete
    func deleteInventoryItem(id: String) async throws {
        print("[API] Deleting inventory item: \(id)")

        // Soft delete by setting deletedAt
        let updateData: [String: Any] = [
            BubbleFields.InventoryItem.deletedAt: ISO8601DateFormatter().string(from: Date())
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: updateData)

        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.inventoryItem.lowercased())/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )

        print("[API] ✅ Inventory item soft deleted successfully")
    }

    // MARK: - InventorySnapshot Fetching

    /// Fetch all inventory snapshots for a company
    /// - Parameter companyId: The company ID
    /// - Returns: Array of inventory snapshot DTOs
    func fetchCompanySnapshots(companyId: String) async throws -> [InventorySnapshotDTO] {
        print("[API_SNAPSHOTS] 📸 Fetching snapshots for company: \(companyId)")

        let constraints: [[String: Any]] = [
            [
                "key": BubbleFields.InventorySnapshot.company,
                "constraint_type": "equals",
                "value": companyId
            ]
        ]

        let snapshots: [InventorySnapshotDTO] = try await fetchBubbleObjectsWithArrayConstraintsPaginated(
            objectType: BubbleFields.Types.inventorySnapshot,
            constraints: constraints,
            sortField: "Created Date",  // Use Bubble's default field, not custom createdAt
            sortOrder: "desc"
        )

        print("[API_SNAPSHOTS] ✅ Fetched \(snapshots.count) snapshots")
        return snapshots
    }

    /// Fetch snapshot items for a specific snapshot
    /// - Parameter snapshotId: The snapshot ID
    /// - Returns: Array of snapshot item DTOs
    func fetchSnapshotItems(snapshotId: String) async throws -> [InventorySnapshotItemDTO] {
        print("[API_SNAPSHOTS] 📦 Fetching items for snapshot: \(snapshotId)")

        let constraints: [[String: Any]] = [
            [
                "key": BubbleFields.InventorySnapshotItem.snapshot,
                "constraint_type": "equals",
                "value": snapshotId
            ]
        ]

        let items: [InventorySnapshotItemDTO] = try await fetchBubbleObjectsWithArrayConstraintsPaginated(
            objectType: BubbleFields.Types.inventorySnapshotItem,
            constraints: constraints,
            sortField: BubbleFields.InventorySnapshotItem.name
        )

        print("[API_SNAPSHOTS] ✅ Fetched \(items.count) snapshot items")
        return items
    }

    // MARK: - InventorySnapshot Creation

    /// Create a new inventory snapshot
    /// - Parameters:
    ///   - companyId: The company ID
    ///   - createdById: The user ID who created it (nil if automatic)
    ///   - isAutomatic: Whether this is an automatic snapshot
    ///   - itemCount: Number of items in the snapshot
    ///   - notes: Optional notes
    /// - Returns: The created snapshot DTO with server-assigned ID
    func createSnapshot(
        companyId: String,
        createdById: String?,
        isAutomatic: Bool,
        itemCount: Int,
        notes: String?
    ) async throws -> InventorySnapshotDTO {
        print("[API_SNAPSHOT_CREATE] 📸 Creating snapshot for company: \(companyId)")

        // Note: Don't set createdAt or createdBy - Bubble auto-manages these system fields
        var snapshotData: [String: Any] = [
            BubbleFields.InventorySnapshot.company: companyId,
            BubbleFields.InventorySnapshot.isAutomatic: isAutomatic,
            BubbleFields.InventorySnapshot.itemCount: itemCount
        ]

        if let notes = notes {
            snapshotData[BubbleFields.InventorySnapshot.notes] = notes
        }

        let bodyData = try JSONSerialization.data(withJSONObject: snapshotData)

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[API_SNAPSHOT_CREATE] 📤 Request body: \(jsonString)")
        }

        print("[API_SNAPSHOT_CREATE] 📡 Sending POST request to Bubble...")
        print("[API_SNAPSHOT_CREATE] 📡 Endpoint: api/1.1/obj/\(BubbleFields.Types.inventorySnapshot)")

        do {
            let response: InventorySnapshotCreationResponse = try await executeRequest(
                endpoint: "api/1.1/obj/\(BubbleFields.Types.inventorySnapshot)",
                method: "POST",
                body: bodyData,
                requiresAuth: false
            )

            print("[API_SNAPSHOT_CREATE] ✅ Bubble returned ID: \(response.id)")

            return InventorySnapshotDTO(
                id: response.id,
                company: companyId,
                createdAt: nil,  // Set by Bubble ("Created Date")
                createdBy: nil,  // Set by Bubble ("Created By")
                isAutomatic: isAutomatic,
                itemCount: itemCount,
                notes: notes
            )
        } catch {
            print("[API_SNAPSHOT_CREATE] ❌ Failed to create snapshot: \(error)")
            throw error
        }
    }

    /// Create a snapshot item
    /// - Parameter item: The snapshot item DTO to create
    /// - Returns: The created snapshot item DTO with server-assigned ID
    func createSnapshotItem(_ item: InventorySnapshotItemDTO) async throws -> InventorySnapshotItemDTO {
        let itemData = item.toDictionary()
        let bodyData = try JSONSerialization.data(withJSONObject: itemData)

        let response: InventorySnapshotItemCreationResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.inventorySnapshotItem)",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )

        return InventorySnapshotItemDTO(
            id: response.id,
            snapshot: item.snapshot,
            originalItemId: item.originalItemId,
            name: item.name,
            quantity: item.quantity,
            unitDisplay: item.unitDisplay,
            sku: item.sku,
            tags: item.tags,
            description: item.description
        )
    }

    /// Create a full inventory snapshot with all current items
    /// - Parameters:
    ///   - companyId: The company ID
    ///   - userId: The user creating the snapshot (nil if automatic)
    ///   - isAutomatic: Whether this is an automatic snapshot
    ///   - items: Current inventory items to snapshot
    ///   - notes: Optional notes
    /// - Returns: The created snapshot ID
    func createFullSnapshot(
        companyId: String,
        userId: String?,
        isAutomatic: Bool,
        items: [InventoryItem],
        notes: String? = nil
    ) async throws -> String {
        print("[API_SNAPSHOT] 📸 Creating full snapshot with \(items.count) items")

        // 1. Create the snapshot record
        let snapshot = try await createSnapshot(
            companyId: companyId,
            createdById: userId,
            isAutomatic: isAutomatic,
            itemCount: items.count,
            notes: notes
        )

        print("[API_SNAPSHOT] 📸 Snapshot created: \(snapshot.id)")

        // 2. Create snapshot items for each inventory item
        for item in items {
            let snapshotItemDTO = InventorySnapshotItemDTO.from(item: item, snapshotId: snapshot.id)
            _ = try await createSnapshotItem(snapshotItemDTO)
        }

        print("[API_SNAPSHOT] ✅ Full snapshot created with \(items.count) items")
        return snapshot.id
    }

    // MARK: - Tag Fetching

    /// Fetch all tags for a company
    /// - Parameter companyId: The company ID
    /// - Returns: Array of tag DTOs
    func fetchCompanyTags(companyId: String) async throws -> [InventoryTagDTO] {
        print("[API_TAGS] 🏷️ Fetching tags for company: \(companyId)")

        let constraints: [[String: Any]] = [
            [
                "key": BubbleFields.Tag.company,
                "constraint_type": "equals",
                "value": companyId
            ],
            [
                "key": BubbleFields.Tag.deletedAt,
                "constraint_type": "is_empty"
            ]
        ]

        let apiService = self
        let tags: [InventoryTagDTO] = try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let result: [InventoryTagDTO] = try await apiService.fetchBubbleObjectsWithArrayConstraintsPaginated(
                        objectType: BubbleFields.Types.tag,
                        constraints: constraints,
                        sortField: BubbleFields.Tag.name
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        print("[API_TAGS] ✅ Fetched \(tags.count) tags")
        return tags
    }

    // MARK: - Tag Creation

    /// Create a new tag
    /// - Parameter tag: The tag DTO to create
    /// - Returns: The created tag DTO with server-assigned ID
    func createTag(_ tag: InventoryTagDTO) async throws -> InventoryTagDTO {
        print("[API_TAG_CREATE] 🔵 Creating tag: \(tag.name ?? "unknown")")

        var tagData: [String: Any] = [
            BubbleFields.Tag.name: tag.name ?? "",
            BubbleFields.Tag.company: tag.company ?? ""
        ]

        if let warning = tag.warningThreshold {
            tagData[BubbleFields.Tag.warningThreshold] = warning
        }

        if let critical = tag.criticalThreshold {
            tagData[BubbleFields.Tag.criticalThreshold] = critical
        }

        let bodyData = try JSONSerialization.data(withJSONObject: tagData)

        print("[API_TAG_CREATE] 📡 Sending POST request to Bubble...")
        let response: InventoryTagCreationResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.tag)",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )

        print("[API_TAG_CREATE] ✅ Bubble returned ID: \(response.id)")

        return InventoryTagDTO(
            id: response.id,
            name: tag.name,
            warningThreshold: tag.warningThreshold,
            criticalThreshold: tag.criticalThreshold,
            company: tag.company
        )
    }

    // MARK: - Tag Updates

    /// Update a tag
    /// - Parameters:
    ///   - id: The tag ID
    ///   - updates: Dictionary of fields to update
    func updateTag(id: String, updates: [String: Any]) async throws {
        print("[UPDATE_TAG] 📝 Updating tag: \(id)")

        guard !updates.isEmpty else {
            print("[UPDATE_TAG] ⚠️ No updates to send")
            return
        }

        let bodyData = try JSONSerialization.data(withJSONObject: updates)

        print("[UPDATE_TAG] 📡 Sending PATCH request to Bubble...")
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.tag)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )

        print("[UPDATE_TAG] ✅ Tag successfully updated in Bubble")
    }

    // MARK: - Tag Deletion

    /// Delete a tag (soft delete)
    /// - Parameter id: The tag ID to delete
    func deleteTag(id: String) async throws {
        print("[API] Deleting tag: \(id)")

        let updateData: [String: Any] = [
            BubbleFields.Tag.deletedAt: ISO8601DateFormatter().string(from: Date())
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: updateData)

        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.tag)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )

        print("[API] ✅ Tag soft deleted successfully")
    }
}

/// Response wrapper for Bubble workflow responses
struct BubbleWorkflowResponse<T: Decodable>: Decodable {
    let status: String?
    let response: T?
}

/// Response wrapper for inventory units workflow - Bubble nests return values inside "response" object
struct InventoryUnitsWorkflowResponse: Decodable {
    let status: String?
    let response: InventoryUnitsResponseData?

    struct InventoryUnitsResponseData: Decodable {
        let inventoryUnits: [InventoryUnitDTO]?
    }
}

/// Empty workflow response (status only, no data)
struct EmptyWorkflowResponse: Decodable {
    let status: String?
}
