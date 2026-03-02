//
//  ExpenseRepository.swift
//  OPS
//
//  Repository for Expense operations via Supabase.
//

import Foundation
import Supabase

class ExpenseRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Expenses

    func fetchAll() async throws -> [ExpenseDTO] {
        try await client
            .from("expenses")
            .select("*, expense_project_allocations(*), expense_categories(*)")
            .eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchOne(_ expenseId: String) async throws -> ExpenseDTO {
        try await client
            .from("expenses")
            .select("*, expense_project_allocations(*), expense_categories(*)")
            .eq("id", value: expenseId)
            .single()
            .execute()
            .value
    }

    func create(_ dto: CreateExpenseDTO) async throws -> ExpenseDTO {
        try await client
            .from("expenses")
            .insert(dto)
            .select("*, expense_project_allocations(*), expense_categories(*)")
            .single()
            .execute()
            .value
    }

    func update(_ expenseId: String, fields: UpdateExpenseDTO) async throws -> ExpenseDTO {
        try await client
            .from("expenses")
            .update(fields)
            .eq("id", value: expenseId)
            .select("*, expense_project_allocations(*), expense_categories(*)")
            .single()
            .execute()
            .value
    }

    func updateStatus(_ expenseId: String, status: ExpenseStatus) async throws -> ExpenseDTO {
        try await client
            .from("expenses")
            .update(["status": status.rawValue])
            .eq("id", value: expenseId)
            .select("*, expense_project_allocations(*), expense_categories(*)")
            .single()
            .execute()
            .value
    }

    func approve(_ expenseId: String, approvedBy: String) async throws -> ExpenseDTO {
        try await client
            .from("expenses")
            .update([
                "status": "approved",
                "approved_by": approvedBy,
                "approved_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: expenseId)
            .select("*, expense_project_allocations(*), expense_categories(*)")
            .single()
            .execute()
            .value
    }

    func reject(_ expenseId: String, rejectedBy: String, reason: String) async throws -> ExpenseDTO {
        try await client
            .from("expenses")
            .update([
                "status": "rejected",
                "rejected_by": rejectedBy,
                "rejected_at": ISO8601DateFormatter().string(from: Date()),
                "rejection_reason": reason
            ])
            .eq("id", value: expenseId)
            .select("*, expense_project_allocations(*), expense_categories(*)")
            .single()
            .execute()
            .value
    }

    func softDelete(_ expenseId: String) async throws {
        try await client
            .from("expenses")
            .update(["deleted_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: expenseId)
            .execute()
    }

    // MARK: - Accounting Sync

    /// Triggers the accounting-sync-expense Edge Function for an approved expense.
    /// Fire-and-forget — logs errors but does not throw, so approval is not blocked.
    func triggerAccountingSync(expenseId: String) async {
        do {
            try await client.functions.invoke(
                "accounting-sync-expense",
                options: .init(body: ["expense_id": expenseId])
            )
        } catch {
            print("[ExpenseRepository] Accounting sync trigger failed for \(expenseId): \(error.localizedDescription)")
        }
    }

    // MARK: - Allocations

    func setAllocations(_ expenseId: String, allocations: [CreateExpenseAllocationDTO]) async throws {
        // Delete existing allocations
        try await client
            .from("expense_project_allocations")
            .delete()
            .eq("expense_id", value: expenseId)
            .execute()

        // Insert new allocations
        if !allocations.isEmpty {
            try await client
                .from("expense_project_allocations")
                .insert(allocations)
                .execute()
        }
    }

    // MARK: - Categories

    func fetchCategories() async throws -> [ExpenseCategoryDTO] {
        try await client
            .from("expense_categories")
            .select()
            .eq("company_id", value: companyId)
            .eq("is_active", value: true)
            .order("sort_order", ascending: true)
            .execute()
            .value
    }

    func createCategory(_ dto: CreateExpenseCategoryDTO) async throws -> ExpenseCategoryDTO {
        try await client
            .from("expense_categories")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func updateCategory(_ id: String, name: String?, icon: String?, isActive: Bool?) async throws {
        struct CategoryUpdate: Encodable {
            var name: String?
            var icon: String?
            var is_active: Bool?

            enum CodingKeys: String, CodingKey {
                case name, icon, is_active
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                if let name = name { try container.encode(name, forKey: .name) }
                if let icon = icon { try container.encode(icon, forKey: .icon) }
                if let is_active = is_active { try container.encode(is_active, forKey: .is_active) }
            }
        }

        let update = CategoryUpdate(name: name, icon: icon, is_active: isActive)
        try await client
            .from("expense_categories")
            .update(update)
            .eq("id", value: id)
            .execute()
    }

    func seedDefaultCategories() async throws {
        let defaults: [(String, String, Int)] = [
            ("Materials", "shippingbox.fill", 0),
            ("Labor", "person.fill", 1),
            ("Equipment / Tools", "wrench.and.screwdriver.fill", 2),
            ("Fuel / Mileage", "fuelpump.fill", 3),
            ("Per Diem", "bed.double.fill", 4),
            ("Subcontractor", "person.2.fill", 5),
            ("Permits / Fees", "doc.text.fill", 6),
            ("Office Supplies", "paperclip", 7),
            ("Other", "ellipsis.circle.fill", 8)
        ]
        let dtos = defaults.map { name, icon, order in
            [
                "company_id": companyId,
                "name": name,
                "icon": icon,
                "is_default": "true",
                "is_active": "true",
                "sort_order": "\(order)"
            ]
        }
        try await client
            .from("expense_categories")
            .insert(dtos)
            .execute()
    }

    // MARK: - Batches

    func fetchBatches() async throws -> [ExpenseBatchDTO] {
        try await client
            .from("expense_batches")
            .select()
            .eq("company_id", value: companyId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchBatchExpenses(_ batchId: String) async throws -> [ExpenseDTO] {
        try await client
            .from("expenses")
            .select("*, expense_project_allocations(*), expense_categories(*)")
            .eq("batch_id", value: batchId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    // MARK: - Settings

    func fetchSettings() async throws -> ExpenseSettingsDTO? {
        let results: [ExpenseSettingsDTO] = try await client
            .from("expense_settings")
            .select()
            .eq("company_id", value: companyId)
            .execute()
            .value
        return results.first
    }

    func upsertSettings(_ dto: ExpenseSettingsDTO) async throws {
        var settingsDTO = dto
        settingsDTO.companyId = companyId
        try await client
            .from("expense_settings")
            .upsert(settingsDTO, onConflict: "company_id")
            .execute()
    }

    // MARK: - Expenses by Project

    func fetchByProject(_ projectId: String) async throws -> [ExpenseDTO] {
        // Fetch expense IDs that have allocations to this project
        let allocations: [ExpenseAllocationDTO] = try await client
            .from("expense_project_allocations")
            .select()
            .eq("project_id", value: projectId)
            .execute()
            .value

        let expenseIds = allocations.map { $0.expenseId }
        guard !expenseIds.isEmpty else { return [] }

        return try await client
            .from("expenses")
            .select("*, expense_project_allocations(*), expense_categories(*)")
            .in("id", values: expenseIds)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    // MARK: - Accounting Category Mappings

    func fetchCategoryMappings(provider: String) async throws -> [AccountingCategoryMappingDTO] {
        try await client
            .from("accounting_category_mappings")
            .select()
            .eq("company_id", value: companyId)
            .eq("provider", value: provider)
            .execute()
            .value
    }

    func upsertCategoryMapping(_ dto: CreateAccountingCategoryMappingDTO) async throws {
        try await client
            .from("accounting_category_mappings")
            .upsert(dto, onConflict: "company_id,expense_category_id,provider")
            .execute()
    }

    func deleteCategoryMapping(_ id: String) async throws {
        try await client
            .from("accounting_category_mappings")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
