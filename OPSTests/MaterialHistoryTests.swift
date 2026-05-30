//
//  MaterialHistoryTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

final class MaterialHistoryTests: XCTestCase {
    func testMaterialHistoryDTOsDecodeLiveP6Rows() throws {
        let demandPayload = """
        {
          "id": "demand-1",
          "company_id": "company-1",
          "project_id": "project-1",
          "task_id": "task-1",
          "estimate_id": "estimate-1",
          "line_item_id": "line-1",
          "product_id": "product-1",
          "product_material_id": "recipe-1",
          "catalog_variant_id": "variant-1",
          "unit_id": "unit-1",
          "demand_key": "estimate:estimate-1:line:line-1:product_material:recipe-1:variant:variant-1",
          "source": "estimate_acceptance",
          "status": "warning",
          "required_quantity": 12.5,
          "available_quantity_at_booking": 4.0,
          "projected_overrun_quantity": 8.5,
          "resolver_payload": {
            "availability": {
              "effective_available_quantity": 4.0,
              "availability_basis": "length:ft"
            }
          },
          "warning_payload": {
            "warning_count": 1
          },
          "created_at": "2026-05-28T12:00:00Z",
          "updated_at": "2026-05-28T12:01:00Z",
          "deleted_at": null
        }
        """
        let allocationPayload = """
        {
          "id": "allocation-1",
          "company_id": "company-1",
          "task_material_id": null,
          "demand_id": "demand-1",
          "catalog_variant_id": "variant-1",
          "catalog_stock_unit_id": "stock-1",
          "inventory_deduction_id": "deduction-1",
          "allocation_key": "estimate:estimate-1:line:line-1:product_material:recipe-1:variant:variant-1:stock:stock-1",
          "allocation_status": "consumed",
          "allocated_quantity": 4.0,
          "consumed_quantity": 4.0,
          "overrun_quantity": 8.5,
          "stock_unit_snapshot": {
            "catalog_stock_unit_id": "stock-1",
            "unit_kind": "roll",
            "label": "ROLL A",
            "lot_code": "LOT-42",
            "remaining_length_value": 18,
            "length_unit": "ft",
            "quantity_value": 1,
            "location": "SHOP RACK",
            "status": "partial",
            "captured_at": "2026-05-28T12:02:00Z"
          },
          "created_at": "2026-05-28T12:00:00Z",
          "updated_at": "2026-05-28T12:02:00Z",
          "deleted_at": null
        }
        """
        let snapshotItemPayload = """
        {
          "id": "snapshot-item-1",
          "company_id": "company-1",
          "snapshot_id": "snapshot-1",
          "demand_id": "demand-1",
          "task_material_id": null,
          "allocation_id": "allocation-1",
          "inventory_deduction_id": "deduction-1",
          "catalog_variant_id": "variant-1",
          "catalog_stock_unit_id": "stock-1",
          "source_event_id": "event-1",
          "unit_id": "unit-1",
          "quantity": 4.0,
          "projected_overrun_quantity": 8.5,
          "stock_unit_snapshot": {
            "catalog_stock_unit_id": "stock-1",
            "label": "ROLL A",
            "location": "SHOP RACK",
            "status": "partial"
          },
          "created_at": "2026-05-28T12:02:00Z"
        }
        """
        let deductionPayload = """
        {
          "id": "deduction-1",
          "company_id": "company-1",
          "inventory_item_id": null,
          "project_id": "project-1",
          "task_id": "task-1",
          "line_item_id": "line-1",
          "quantity_deducted": 4.0,
          "previous_quantity": 10.0,
          "new_quantity": 6.0,
          "reason": "task_completion",
          "deducted_by": "user-1",
          "deducted_at": "2026-05-28T12:02:00Z",
          "notes": "task completion",
          "catalog_variant_id": "variant-1"
        }
        """

        let decoder = JSONDecoder()
        let demand = try decoder.decode(ProjectMaterialDemandDTO.self, from: Data(demandPayload.utf8))
        let allocation = try decoder.decode(TaskMaterialAllocationDTO.self, from: Data(allocationPayload.utf8))
        let snapshotItem = try decoder.decode(ProjectMaterialSnapshotItemDTO.self, from: Data(snapshotItemPayload.utf8))
        let deduction = try decoder.decode(MaterialInventoryDeductionDTO.self, from: Data(deductionPayload.utf8))

        XCTAssertEqual(demand.requiredQuantity, 12.5)
        XCTAssertEqual(demand.projectedOverrunQuantity, 8.5)
        XCTAssertEqual(allocation.stockUnitSnapshot?.location, "SHOP RACK")
        XCTAssertEqual(allocation.stockUnitSnapshot?.status, "partial")
        XCTAssertEqual(snapshotItem.inventoryDeductionId, "deduction-1")
        XCTAssertEqual(deduction.quantityDeducted, 4.0)
    }

    func testMaterialHistoryStateCombinesBookedConsumedOverrunAndStockSnapshot() {
        let demand = ProjectMaterialDemandDTO.fixture(
            id: "demand-1",
            demandKey: "demand-key-1",
            requiredQuantity: 12.5,
            availableQuantityAtBooking: 4.0,
            projectedOverrunQuantity: 8.5
        )
        let allocation = TaskMaterialAllocationDTO.fixture(
            id: "allocation-1",
            demandId: "demand-1",
            consumedQuantity: 4.0,
            overrunQuantity: 8.5,
            stockUnitSnapshot: MaterialStockUnitSnapshot(
                catalogStockUnitId: "stock-1",
                unitKind: "roll",
                label: "ROLL A",
                lotCode: "LOT-42",
                widthValue: nil,
                widthUnit: nil,
                originalLengthValue: nil,
                remainingLengthValue: 18,
                lengthUnit: "ft",
                quantityValue: 1,
                location: "SHOP RACK",
                status: "partial",
                capturedAt: "2026-05-28T12:02:00Z"
            )
        )
        let deduction = MaterialInventoryDeductionDTO.fixture(
            id: "deduction-1",
            taskId: "task-1",
            quantityDeducted: 4.0
        )

        let history = TaskMaterialHistory.make(
            demands: [demand],
            allocations: [allocation],
            snapshotItems: [],
            deductions: [deduction]
        )

        XCTAssertEqual(history.totalBookedQuantity, 12.5)
        XCTAssertEqual(history.totalConsumedQuantity, 4.0)
        XCTAssertEqual(history.totalOverrunQuantity, 8.5)
        XCTAssertEqual(history.lines.first?.stockLocation, "SHOP RACK")
        XCTAssertEqual(history.lines.first?.stockStatus, "partial")
        XCTAssertEqual(history.lines.first?.stockLabel, "ROLL A")
    }

    func testMaterialHistoryPreservesEachStockUnitEvidenceForSplitDemand() {
        let demand = ProjectMaterialDemandDTO.fixture(
            id: "demand-1",
            demandKey: "demand-key-1",
            requiredQuantity: 14,
            availableQuantityAtBooking: 12,
            projectedOverrunQuantity: 2
        )
        let rollA = TaskMaterialAllocationDTO.fixture(
            id: "allocation-roll-a",
            demandId: "demand-1",
            consumedQuantity: 7,
            overrunQuantity: 0,
            stockUnitSnapshot: MaterialStockUnitSnapshot(
                catalogStockUnitId: "stock-roll-a",
                label: "ROLL A",
                remainingLengthValue: 18,
                lengthUnit: "ft",
                location: "SHOP RACK",
                status: "partial"
            )
        )
        let rollB = TaskMaterialAllocationDTO.fixture(
            id: "allocation-roll-b",
            demandId: "demand-1",
            consumedQuantity: 5,
            overrunQuantity: 0,
            stockUnitSnapshot: MaterialStockUnitSnapshot(
                catalogStockUnitId: "stock-roll-b",
                label: "ROLL B",
                remainingLengthValue: 11,
                lengthUnit: "ft",
                location: "TRUCK 2",
                status: "full"
            )
        )
        let unavailableSnapshot = ProjectMaterialSnapshotItemDTO.fixture(
            id: "snapshot-unavailable",
            demandId: "demand-1",
            allocationId: nil,
            quantity: 0,
            projectedOverrunQuantity: 2,
            stockUnitSnapshot: MaterialStockUnitSnapshot(
                catalogStockUnitId: "stock-unavailable",
                label: "ALLOCATED SHORT",
                quantityValue: 0,
                location: "NO STOCK",
                status: "unavailable"
            )
        )

        let history = TaskMaterialHistory.make(
            demands: [demand],
            allocations: [rollA, rollB],
            snapshotItems: [unavailableSnapshot],
            deductions: []
        )

        XCTAssertEqual(history.totalBookedQuantity, 14)
        XCTAssertEqual(history.totalConsumedQuantity, 12)
        XCTAssertEqual(history.totalOverrunQuantity, 2)
        XCTAssertEqual(history.lines.map(\.stockLabel), ["ROLL A", "ROLL B", "ALLOCATED SHORT"])
        XCTAssertEqual(history.lines.map(\.stockLocation), ["SHOP RACK", "TRUCK 2", "NO STOCK"])
        XCTAssertEqual(history.lines.map(\.stockStatus), ["partial", "full", "unavailable"])
        XCTAssertEqual(history.lines.map(\.consumedQuantity), [7, 5, 0])
        XCTAssertEqual(history.lines.map(\.overrunQuantity), [0, 0, 2])
    }

    func testTaskDetailsMaterialHistoryDoesNotCapEvidenceAtFourLines() throws {
        let demand = ProjectMaterialDemandDTO.fixture(
            id: "demand-1",
            demandKey: "demand-key-1",
            requiredQuantity: 30,
            availableQuantityAtBooking: 24,
            projectedOverrunQuantity: 6
        )
        let allocations = (1...5).map { index in
            TaskMaterialAllocationDTO.fixture(
                id: "allocation-roll-\(index)",
                demandId: "demand-1",
                consumedQuantity: Double(index),
                overrunQuantity: 0,
                stockUnitSnapshot: MaterialStockUnitSnapshot(
                    catalogStockUnitId: "stock-roll-\(index)",
                    label: "ROLL \(index)",
                    remainingLengthValue: Double(30 - index),
                    lengthUnit: "ft",
                    location: "RACK \(index)",
                    status: index.isMultiple(of: 2) ? "full" : "partial"
                )
            )
        }
        let overrunSnapshot = ProjectMaterialSnapshotItemDTO.fixture(
            id: "snapshot-overrun",
            demandId: "demand-1",
            allocationId: nil,
            quantity: 0,
            projectedOverrunQuantity: 6,
            stockUnitSnapshot: MaterialStockUnitSnapshot(
                catalogStockUnitId: "stock-overrun",
                label: "ALLOCATED SHORT",
                quantityValue: 0,
                location: "NO STOCK",
                status: "unavailable"
            )
        )

        let history = TaskMaterialHistory.make(
            demands: [demand],
            allocations: allocations,
            snapshotItems: [overrunSnapshot],
            deductions: []
        )

        XCTAssertEqual(history.lines.count, 6)
        XCTAssertEqual(history.lines.map(\.stockLabel), [
            "ROLL 1",
            "ROLL 2",
            "ROLL 3",
            "ROLL 4",
            "ROLL 5",
            "ALLOCATED SHORT"
        ])

        let taskDetailsSource = try String(
            contentsOf: taskDetailsViewSourceURL,
            encoding: .utf8
        )
        XCTAssertFalse(
            taskDetailsSource.contains("materialHistory.lines.prefix(4)"),
            "TaskDetailsView must expose all \(history.lines.count) material evidence lines."
        )
    }

    func testMaterialHistoryRepositoryQueryUsesP6TablesAndSkipsDeprecatedInventoryDeductedFlag() {
        let queryShape = TaskMaterialHistoryRepository.QueryShape(
            projectId: "project-1",
            taskId: "task-1"
        )

        XCTAssertEqual(
            Set(TaskMaterialHistoryRepository.QueryShape.tableNames),
            [
                "project_material_demands",
                "task_material_allocations",
                "project_material_snapshot_items",
                "inventory_deductions"
            ]
        )
        XCTAssertTrue(queryShape.demandFilters.contains(.eq("project_id", "project-1")))
        XCTAssertTrue(queryShape.demandFilters.contains(.eq("task_id", "task-1")))
        XCTAssertFalse(TaskMaterialHistoryRepository.QueryShape.usesDeprecatedInventoryDeductedFlag)
    }

    func testCatalogSetupNotificationRouteRefreshesRailAfterMappingSave() {
        let route = CatalogSetupNotificationRoute.route(
            type: "catalog_mapping_needed",
            deepLinkType: "catalogSetup",
            actionUrl: "ops://catalog/setup?missingMapping=catalog_mapping_needed%3Aproduct%3Aproduct-1%3Alinked_catalog_item",
            actionLabel: "FIX MAPPING",
            dedupeKey: nil
        )

        XCTAssertEqual(route?.missingMappingKey, "catalog_mapping_needed:product:product-1:linked_catalog_item")
        XCTAssertTrue(route?.refreshesNotificationRailAfterCommit == true)
    }
}

private var taskDetailsViewSourceURL: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("OPS/Views/Components/Project/TaskDetailsView.swift")
}

private extension ProjectMaterialDemandDTO {
    static func fixture(
        id: String,
        demandKey: String,
        requiredQuantity: Double,
        availableQuantityAtBooking: Double?,
        projectedOverrunQuantity: Double
    ) -> ProjectMaterialDemandDTO {
        ProjectMaterialDemandDTO(
            id: id,
            companyId: "company-1",
            projectId: "project-1",
            taskId: "task-1",
            estimateId: "estimate-1",
            lineItemId: "line-1",
            productId: "product-1",
            productMaterialId: "recipe-1",
            catalogVariantId: "variant-1",
            unitId: "unit-1",
            demandKey: demandKey,
            source: "estimate_acceptance",
            status: "warning",
            requiredQuantity: requiredQuantity,
            availableQuantityAtBooking: availableQuantityAtBooking,
            projectedOverrunQuantity: projectedOverrunQuantity,
            createdAt: "2026-05-28T12:00:00Z",
            updatedAt: "2026-05-28T12:01:00Z",
            deletedAt: nil
        )
    }
}

private extension TaskMaterialAllocationDTO {
    static func fixture(
        id: String,
        demandId: String,
        consumedQuantity: Double,
        overrunQuantity: Double,
        stockUnitSnapshot: MaterialStockUnitSnapshot?
    ) -> TaskMaterialAllocationDTO {
        TaskMaterialAllocationDTO(
            id: id,
            companyId: "company-1",
            taskMaterialId: nil,
            demandId: demandId,
            catalogVariantId: "variant-1",
            catalogStockUnitId: stockUnitSnapshot?.catalogStockUnitId,
            inventoryDeductionId: "deduction-1",
            allocationKey: "\(demandId):allocation",
            allocationStatus: "consumed",
            allocatedQuantity: consumedQuantity,
            consumedQuantity: consumedQuantity,
            overrunQuantity: overrunQuantity,
            stockUnitSnapshot: stockUnitSnapshot,
            createdAt: "2026-05-28T12:00:00Z",
            updatedAt: "2026-05-28T12:02:00Z",
            deletedAt: nil
        )
    }
}

private extension MaterialInventoryDeductionDTO {
    static func fixture(
        id: String,
        taskId: String,
        quantityDeducted: Double
    ) -> MaterialInventoryDeductionDTO {
        MaterialInventoryDeductionDTO(
            id: id,
            companyId: "company-1",
            inventoryItemId: nil,
            projectId: "project-1",
            taskId: taskId,
            lineItemId: "line-1",
            quantityDeducted: quantityDeducted,
            previousQuantity: 10,
            newQuantity: 6,
            reason: "task_completion",
            deductedBy: "user-1",
            deductedAt: "2026-05-28T12:02:00Z",
            notes: "task completion",
            catalogVariantId: "variant-1"
        )
    }
}

private extension ProjectMaterialSnapshotItemDTO {
    static func fixture(
        id: String,
        demandId: String,
        allocationId: String?,
        quantity: Double,
        projectedOverrunQuantity: Double,
        stockUnitSnapshot: MaterialStockUnitSnapshot?
    ) -> ProjectMaterialSnapshotItemDTO {
        ProjectMaterialSnapshotItemDTO(
            id: id,
            companyId: "company-1",
            snapshotId: "snapshot-1",
            demandId: demandId,
            taskMaterialId: nil,
            allocationId: allocationId,
            inventoryDeductionId: nil,
            catalogVariantId: "variant-1",
            catalogStockUnitId: stockUnitSnapshot?.catalogStockUnitId,
            sourceEventId: nil,
            unitId: "unit-1",
            quantity: quantity,
            projectedOverrunQuantity: projectedOverrunQuantity,
            stockUnitSnapshot: stockUnitSnapshot,
            createdAt: "2026-05-28T12:02:00Z"
        )
    }
}
