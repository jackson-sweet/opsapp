//
//  TaskMaterialHistoryRepository.swift
//  OPS
//
//  Reads Phase 6 material demand, booking snapshot, allocation, and deduction
//  history without consulting deprecated task flags.
//

import Foundation
import Supabase

final class TaskMaterialHistoryRepository {
    struct QueryShape: Equatable {
        enum Filter: Equatable {
            case eq(String, String)
        }

        static let tableNames = [
            "project_material_demands",
            "task_material_allocations",
            "project_material_snapshot_items",
            "inventory_deductions"
        ]
        static let usesDeprecatedInventoryDeductedFlag = false
        static let demandSelect = """
            id,company_id,project_id,task_id,estimate_id,line_item_id,product_id,product_material_id,catalog_variant_id,unit_id,demand_key,source,status,required_quantity,available_quantity_at_booking,projected_overrun_quantity,created_at,updated_at,deleted_at
            """
        static let allocationSelect = """
            id,company_id,task_material_id,demand_id,catalog_variant_id,catalog_stock_unit_id,inventory_deduction_id,allocation_key,allocation_status,allocated_quantity,consumed_quantity,overrun_quantity,stock_unit_snapshot,created_at,updated_at,deleted_at
            """
        static let snapshotItemSelect = """
            id,company_id,snapshot_id,demand_id,task_material_id,allocation_id,inventory_deduction_id,catalog_variant_id,catalog_stock_unit_id,source_event_id,unit_id,quantity,projected_overrun_quantity,stock_unit_snapshot,created_at
            """
        static let deductionSelect = """
            id,company_id,inventory_item_id,project_id,task_id,line_item_id,quantity_deducted,previous_quantity,new_quantity,reason,deducted_by,deducted_at,notes,catalog_variant_id
            """

        let projectId: String
        let taskId: String

        var demandFilters: [Filter] {
            [
                .eq("project_id", projectId),
                .eq("task_id", taskId)
            ]
        }
    }

    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchTaskHistory(projectId: String, taskId: String) async throws -> TaskMaterialHistory {
        let demands: [ProjectMaterialDemandDTO] = try await client
            .from("project_material_demands")
            .select(QueryShape.demandSelect)
            .eq("company_id", value: companyId)
            .eq("project_id", value: projectId)
            .eq("task_id", value: taskId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: true)
            .execute()
            .value

        let demandIds = demands.map(\.id)
        let allocations = try await fetchAllocations(demandIds: demandIds)
        let snapshotItems = try await fetchSnapshotItems(demandIds: demandIds)

        let deductions: [MaterialInventoryDeductionDTO] = try await client
            .from("inventory_deductions")
            .select(QueryShape.deductionSelect)
            .eq("company_id", value: companyId)
            .eq("project_id", value: projectId)
            .eq("task_id", value: taskId)
            .order("deducted_at", ascending: true)
            .execute()
            .value

        return TaskMaterialHistory.make(
            demands: demands,
            allocations: allocations,
            snapshotItems: snapshotItems,
            deductions: deductions
        )
    }

    private func fetchAllocations(demandIds: [String]) async throws -> [TaskMaterialAllocationDTO] {
        guard !demandIds.isEmpty else { return [] }
        return try await client
            .from("task_material_allocations")
            .select(QueryShape.allocationSelect)
            .eq("company_id", value: companyId)
            .in("demand_id", values: demandIds)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    private func fetchSnapshotItems(demandIds: [String]) async throws -> [ProjectMaterialSnapshotItemDTO] {
        guard !demandIds.isEmpty else { return [] }
        return try await client
            .from("project_material_snapshot_items")
            .select(QueryShape.snapshotItemSelect)
            .eq("company_id", value: companyId)
            .in("demand_id", values: demandIds)
            .order("created_at", ascending: true)
            .execute()
            .value
    }
}
