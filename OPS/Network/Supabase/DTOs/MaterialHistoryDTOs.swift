//
//  MaterialHistoryDTOs.swift
//  OPS
//
//  Server-authoritative material history from Phase 6 demand, allocation,
//  snapshot, and deduction tables.
//

import Foundation

struct MaterialStockUnitSnapshot: Codable, Equatable {
    let catalogStockUnitId: String?
    let catalogVariantId: String?
    let unitKind: String?
    let label: String?
    let lotCode: String?
    let widthValue: Double?
    let widthUnit: String?
    let originalLengthValue: Double?
    let remainingLengthValue: Double?
    let lengthUnit: String?
    let quantityValue: Double?
    let location: String?
    let status: String?
    let capturedAt: String?

    init(
        catalogStockUnitId: String? = nil,
        catalogVariantId: String? = nil,
        unitKind: String? = nil,
        label: String? = nil,
        lotCode: String? = nil,
        widthValue: Double? = nil,
        widthUnit: String? = nil,
        originalLengthValue: Double? = nil,
        remainingLengthValue: Double? = nil,
        lengthUnit: String? = nil,
        quantityValue: Double? = nil,
        location: String? = nil,
        status: String? = nil,
        capturedAt: String? = nil
    ) {
        self.catalogStockUnitId = catalogStockUnitId
        self.catalogVariantId = catalogVariantId
        self.unitKind = unitKind
        self.label = label
        self.lotCode = lotCode
        self.widthValue = widthValue
        self.widthUnit = widthUnit
        self.originalLengthValue = originalLengthValue
        self.remainingLengthValue = remainingLengthValue
        self.lengthUnit = lengthUnit
        self.quantityValue = quantityValue
        self.location = location
        self.status = status
        self.capturedAt = capturedAt
    }

    enum CodingKeys: String, CodingKey {
        case catalogStockUnitId = "catalog_stock_unit_id"
        case catalogVariantId = "catalog_variant_id"
        case unitKind = "unit_kind"
        case label
        case lotCode = "lot_code"
        case widthValue = "width_value"
        case widthUnit = "width_unit"
        case originalLengthValue = "original_length_value"
        case remainingLengthValue = "remaining_length_value"
        case lengthUnit = "length_unit"
        case quantityValue = "quantity_value"
        case location
        case status
        case capturedAt = "captured_at"
    }

    var displayLabel: String {
        if let label = nonEmpty(label) {
            return label
        }
        if let lotCode = nonEmpty(lotCode) {
            return lotCode
        }
        if let catalogStockUnitId = nonEmpty(catalogStockUnitId) {
            return shortId(catalogStockUnitId)
        }
        return "—"
    }
}

struct ProjectMaterialDemandDTO: Codable, Equatable {
    let id: String
    let companyId: String
    let projectId: String
    let taskId: String?
    let estimateId: String?
    let lineItemId: String?
    let productId: String?
    let productMaterialId: String?
    let catalogVariantId: String?
    let unitId: String?
    let demandKey: String
    let source: String?
    let status: String?
    let requiredQuantity: Double
    let availableQuantityAtBooking: Double?
    let projectedOverrunQuantity: Double
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId = "company_id"
        case projectId = "project_id"
        case taskId = "task_id"
        case estimateId = "estimate_id"
        case lineItemId = "line_item_id"
        case productId = "product_id"
        case productMaterialId = "product_material_id"
        case catalogVariantId = "catalog_variant_id"
        case unitId = "unit_id"
        case demandKey = "demand_key"
        case source
        case status
        case requiredQuantity = "required_quantity"
        case availableQuantityAtBooking = "available_quantity_at_booking"
        case projectedOverrunQuantity = "projected_overrun_quantity"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct TaskMaterialAllocationDTO: Codable, Equatable {
    let id: String
    let companyId: String
    let taskMaterialId: String?
    let demandId: String?
    let catalogVariantId: String?
    let catalogStockUnitId: String?
    let inventoryDeductionId: String?
    let allocationKey: String?
    let allocationStatus: String?
    let allocatedQuantity: Double
    let consumedQuantity: Double
    let overrunQuantity: Double
    let stockUnitSnapshot: MaterialStockUnitSnapshot?
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId = "company_id"
        case taskMaterialId = "task_material_id"
        case demandId = "demand_id"
        case catalogVariantId = "catalog_variant_id"
        case catalogStockUnitId = "catalog_stock_unit_id"
        case inventoryDeductionId = "inventory_deduction_id"
        case allocationKey = "allocation_key"
        case allocationStatus = "allocation_status"
        case allocatedQuantity = "allocated_quantity"
        case consumedQuantity = "consumed_quantity"
        case overrunQuantity = "overrun_quantity"
        case stockUnitSnapshot = "stock_unit_snapshot"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct ProjectMaterialSnapshotItemDTO: Codable, Equatable {
    let id: String
    let companyId: String
    let snapshotId: String
    let demandId: String?
    let taskMaterialId: String?
    let allocationId: String?
    let inventoryDeductionId: String?
    let catalogVariantId: String?
    let catalogStockUnitId: String?
    let sourceEventId: String?
    let unitId: String?
    let quantity: Double
    let projectedOverrunQuantity: Double
    let stockUnitSnapshot: MaterialStockUnitSnapshot?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId = "company_id"
        case snapshotId = "snapshot_id"
        case demandId = "demand_id"
        case taskMaterialId = "task_material_id"
        case allocationId = "allocation_id"
        case inventoryDeductionId = "inventory_deduction_id"
        case catalogVariantId = "catalog_variant_id"
        case catalogStockUnitId = "catalog_stock_unit_id"
        case sourceEventId = "source_event_id"
        case unitId = "unit_id"
        case quantity
        case projectedOverrunQuantity = "projected_overrun_quantity"
        case stockUnitSnapshot = "stock_unit_snapshot"
        case createdAt = "created_at"
    }
}

struct MaterialInventoryDeductionDTO: Codable, Equatable {
    let id: String
    let companyId: String
    let inventoryItemId: String?
    let projectId: String?
    let taskId: String?
    let lineItemId: String?
    let quantityDeducted: Double
    let previousQuantity: Double?
    let newQuantity: Double?
    let reason: String?
    let deductedBy: String?
    let deductedAt: String?
    let notes: String?
    let catalogVariantId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId = "company_id"
        case inventoryItemId = "inventory_item_id"
        case projectId = "project_id"
        case taskId = "task_id"
        case lineItemId = "line_item_id"
        case quantityDeducted = "quantity_deducted"
        case previousQuantity = "previous_quantity"
        case newQuantity = "new_quantity"
        case reason
        case deductedBy = "deducted_by"
        case deductedAt = "deducted_at"
        case notes
        case catalogVariantId = "catalog_variant_id"
    }
}

struct TaskMaterialHistory: Equatable {
    struct Line: Identifiable, Equatable {
        let id: String
        let demandKey: String
        let catalogVariantId: String?
        let bookedQuantity: Double
        let consumedQuantity: Double
        let overrunQuantity: Double
        let availableQuantityAtBooking: Double?
        let stockLabel: String
        let stockLocation: String?
        let stockStatus: String?
        let stockQuantity: Double?
        let stockQuantityUnit: String?
    }

    static let empty = TaskMaterialHistory(
        totalBookedQuantity: 0,
        totalConsumedQuantity: 0,
        totalOverrunQuantity: 0,
        lines: []
    )

    let totalBookedQuantity: Double
    let totalConsumedQuantity: Double
    let totalOverrunQuantity: Double
    let lines: [Line]

    var isEmpty: Bool {
        lines.isEmpty && totalBookedQuantity == 0 && totalConsumedQuantity == 0 && totalOverrunQuantity == 0
    }

    var hasOverrun: Bool {
        totalOverrunQuantity > 0 || lines.contains { $0.overrunQuantity > 0 }
    }

    static func make(
        demands: [ProjectMaterialDemandDTO],
        allocations: [TaskMaterialAllocationDTO],
        snapshotItems: [ProjectMaterialSnapshotItemDTO],
        deductions: [MaterialInventoryDeductionDTO]
    ) -> TaskMaterialHistory {
        let allocationsByDemandId = Dictionary(grouping: allocations, by: { $0.demandId ?? "" })
        let snapshotItemsByDemandId = Dictionary(grouping: snapshotItems, by: { $0.demandId ?? "" })
        let deductionsById = Dictionary(uniqueKeysWithValues: deductions.map { ($0.id, $0) })

        let lines = demands.flatMap { demand -> [Line] in
            let demandAllocations = allocationsByDemandId[demand.id] ?? []
            let demandSnapshotItems = snapshotItemsByDemandId[demand.id] ?? []
            return evidenceLines(
                demand: demand,
                allocations: demandAllocations,
                snapshotItems: demandSnapshotItems,
                deductionsById: deductionsById
            )
        }

        let consumedFromAllocations = allocations.map(\.consumedQuantity).reduce(0, +)
        let fallbackConsumed = deductions.map(\.quantityDeducted).reduce(0, +)
        let totalOverrun = demands.map { demand in
            overrunQuantity(
                demand: demand,
                allocations: allocationsByDemandId[demand.id] ?? [],
                snapshotItems: snapshotItemsByDemandId[demand.id] ?? []
            )
        }.reduce(0, +)

        return TaskMaterialHistory(
            totalBookedQuantity: demands.map(\.requiredQuantity).reduce(0, +),
            totalConsumedQuantity: positive(consumedFromAllocations, fallback: fallbackConsumed),
            totalOverrunQuantity: totalOverrun,
            lines: lines.sorted {
                if $0.demandKey == $1.demandKey {
                    return $0.id < $1.id
                }
                return $0.demandKey < $1.demandKey
            }
        )
    }

    private static func evidenceLines(
        demand: ProjectMaterialDemandDTO,
        allocations: [TaskMaterialAllocationDTO],
        snapshotItems: [ProjectMaterialSnapshotItemDTO],
        deductionsById: [String: MaterialInventoryDeductionDTO]
    ) -> [Line] {
        let snapshotItemsByAllocationId = Dictionary(
            grouping: snapshotItems.filter { nonEmpty($0.allocationId) != nil },
            by: { $0.allocationId ?? "" }
        )
        let allocationIds = Set(allocations.map(\.id))
        var lines = allocations.map { allocation -> Line in
            let fallbackSnapshot = allocation.id.isEmpty ? nil : snapshotItemsByAllocationId[allocation.id]?.first?.stockUnitSnapshot
            let stockSnapshot = allocation.stockUnitSnapshot ?? fallbackSnapshot
            let consumed = consumedQuantity(
                allocation: allocation,
                deductionsById: deductionsById
            )

            return Line(
                id: "\(demand.id):allocation:\(allocation.id)",
                demandKey: demand.demandKey,
                catalogVariantId: demand.catalogVariantId,
                bookedQuantity: demand.requiredQuantity,
                consumedQuantity: consumed,
                overrunQuantity: max(allocation.overrunQuantity, 0),
                availableQuantityAtBooking: demand.availableQuantityAtBooking,
                stockLabel: stockSnapshot?.displayLabel ?? "—",
                stockLocation: nonEmpty(stockSnapshot?.location),
                stockStatus: nonEmpty(stockSnapshot?.status),
                stockQuantity: stockQuantity(stockSnapshot),
                stockQuantityUnit: stockQuantityUnit(stockSnapshot)
            )
        }

        let snapshotOnlyLines = snapshotItems
            .filter { item in
                guard let allocationId = nonEmpty(item.allocationId) else { return true }
                return !allocationIds.contains(allocationId)
            }
            .map { item -> Line in
                let stockSnapshot = item.stockUnitSnapshot
                return Line(
                    id: "\(demand.id):snapshot:\(item.id)",
                    demandKey: demand.demandKey,
                    catalogVariantId: demand.catalogVariantId,
                    bookedQuantity: demand.requiredQuantity,
                    consumedQuantity: 0,
                    overrunQuantity: max(item.projectedOverrunQuantity, 0),
                    availableQuantityAtBooking: demand.availableQuantityAtBooking,
                    stockLabel: stockSnapshot?.displayLabel ?? "—",
                    stockLocation: nonEmpty(stockSnapshot?.location),
                    stockStatus: nonEmpty(stockSnapshot?.status),
                    stockQuantity: stockQuantity(stockSnapshot) ?? max(item.quantity, 0),
                    stockQuantityUnit: stockQuantityUnit(stockSnapshot)
                )
            }

        lines.append(contentsOf: snapshotOnlyLines)
        if lines.isEmpty {
            lines.append(
                Line(
                    id: demand.id,
                    demandKey: demand.demandKey,
                    catalogVariantId: demand.catalogVariantId,
                    bookedQuantity: demand.requiredQuantity,
                    consumedQuantity: 0,
                    overrunQuantity: max(demand.projectedOverrunQuantity, 0),
                    availableQuantityAtBooking: demand.availableQuantityAtBooking,
                    stockLabel: "—",
                    stockLocation: nil,
                    stockStatus: nil,
                    stockQuantity: nil,
                    stockQuantityUnit: nil
                )
            )
        }
        return lines
    }

    private static func overrunQuantity(
        demand: ProjectMaterialDemandDTO,
        allocations: [TaskMaterialAllocationDTO],
        snapshotItems: [ProjectMaterialSnapshotItemDTO]
    ) -> Double {
        let allocationOverrun = allocations.map(\.overrunQuantity).reduce(0, +)
        guard allocationOverrun == 0 else { return allocationOverrun }
        let snapshotOverrun = snapshotItems.map(\.projectedOverrunQuantity).reduce(0, +)
        return positive(snapshotOverrun, fallback: demand.projectedOverrunQuantity)
    }

    private static func consumedQuantity(
        allocation: TaskMaterialAllocationDTO,
        deductionsById: [String: MaterialInventoryDeductionDTO]
    ) -> Double {
        guard allocation.consumedQuantity == 0 else { return allocation.consumedQuantity }
        return allocation.inventoryDeductionId.flatMap { deductionsById[$0]?.quantityDeducted } ?? 0
    }

    private static func stockQuantity(_ snapshot: MaterialStockUnitSnapshot?) -> Double? {
        if let remainingLengthValue = snapshot?.remainingLengthValue {
            return remainingLengthValue
        }
        return snapshot?.quantityValue
    }

    private static func stockQuantityUnit(_ snapshot: MaterialStockUnitSnapshot?) -> String? {
        if snapshot?.remainingLengthValue != nil {
            return nonEmpty(snapshot?.lengthUnit)
        }
        return nil
    }

    private static func positive(_ value: Double, fallback: Double) -> Double {
        value > 0 ? value : max(fallback, 0)
    }
}

private func nonEmpty(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

private func shortId(_ value: String) -> String {
    String(value.prefix(8)).uppercased()
}
