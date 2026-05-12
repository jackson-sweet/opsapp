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

    /// Fetches every `expense_project_allocations` row whose parent expense
    /// belongs to this company and is not soft-deleted. Used by the Books
    /// Phase 2 Jobs card to compute per-project cost rollups without
    /// re-hydrating every expense's nested allocation array.
    func fetchAllAllocations() async throws -> [ExpenseAllocationDTO] {
        try await client
            .from("expense_project_allocations")
            .select("*, expense:expenses!inner(company_id, deleted_at)")
            .eq("expense.company_id", value: companyId)
            .is("expense.deleted_at", value: nil)
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
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    // MARK: - Invoice Batches

    func createBatch(_ dto: CreateExpenseBatchDTO) async throws -> ExpenseBatchDTO {
        try await client
            .from("expense_batches")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func updateBatchStatus(_ batchId: String, status: String, reviewedBy: String? = nil, reviewNotes: String? = nil, approvedAmount: Double? = nil) async throws -> ExpenseBatchDTO {
        var fields: [String: String] = ["status": status]
        if let reviewedBy {
            fields["reviewed_by"] = reviewedBy
            fields["reviewed_at"] = ISO8601DateFormatter().string(from: Date())
        }
        if let reviewNotes {
            fields["review_notes"] = reviewNotes
        }
        if let approvedAmount {
            fields["approved_amount"] = String(approvedAmount)
        }
        return try await client
            .from("expense_batches")
            .update(fields)
            .eq("id", value: batchId)
            .select()
            .single()
            .execute()
            .value
    }

    func assignExpensesToBatch(_ expenseIds: [String], batchId: String) async throws {
        for id in expenseIds {
            try await client
                .from("expenses")
                .update(["batch_id": batchId])
                .eq("id", value: id)
                .execute()
        }
    }

    /// Clear the batch assignment for an expense (set batch_id to null)
    func clearBatchId(_ expenseId: String) async throws {
        struct NullBatch: Encodable {
            let batch_id: String? = nil
        }
        try await client
            .from("expenses")
            .update(NullBatch())
            .eq("id", value: expenseId)
            .execute()
    }

    // MARK: - Always-Bundle Helpers

    /// Returns the user's open expense_batch for the given period scope, or
    /// creates one atomically. For per_job review_frequency pass the
    /// expense's project as `scopeProjectId` so multiple expenses for the
    /// same project accumulate into the same batch. Period modes pass nil.
    ///
    /// Wraps the public.get_or_create_open_batch RPC.
    func getOrCreateOpenBatch(
        submittedBy: String,
        periodStart: String,
        periodEnd: String,
        scopeProjectId: String? = nil
    ) async throws -> ExpenseBatchDTO {
        try await client
            .rpc("get_or_create_open_batch", params: GetOrCreateOpenBatchParams(
                p_company_id: companyId,
                p_submitted_by: submittedBy,
                p_period_start: periodStart,
                p_period_end: periodEnd,
                p_scope_project_id: scopeProjectId
            ))
            .single()
            .execute()
            .value
    }

    /// Recompute and persist a batch's total_amount from its non-deleted
    /// expenses. Returns the new total. Use after attaching expenses so
    /// auto-approve threshold checks see the right value.
    @discardableResult
    func recalculateBatchTotal(_ batchId: String) async throws -> Double {
        let total: Double = try await client
            .rpc("recalculate_expense_batch_total", params: ["p_batch_id": batchId])
            .execute()
            .value
        return total
    }

    private struct GetOrCreateOpenBatchParams: Encodable {
        let p_company_id: String
        let p_submitted_by: String
        let p_period_start: String
        let p_period_end: String
        let p_scope_project_id: String?
    }

    /// Fetch all "orphan" expenses for the company — submitted but never
    /// attached to a batch. These exist only because of pre-fix client
    /// versions or interrupted submissions; recovery re-bundles them.
    func fetchOrphanExpenses() async throws -> [ExpenseDTO] {
        try await client
            .from("expenses")
            .select("*, expense_project_allocations(*), expense_categories(*)")
            .eq("company_id", value: companyId)
            .eq("status", value: ExpenseStatus.submitted.rawValue)
            .is("batch_id", value: nil)
            .is("deleted_at", value: nil)
            .order("expense_date", ascending: true)
            .execute()
            .value
    }

    func fetchBatchesByUser(_ userId: String) async throws -> [ExpenseBatchDTO] {
        try await client
            .from("expense_batches")
            .select()
            .eq("company_id", value: companyId)
            .eq("submitted_by", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchBatchesByPeriod(start: String, end: String) async throws -> [ExpenseBatchDTO] {
        try await client
            .from("expense_batches")
            .select()
            .eq("company_id", value: companyId)
            .gte("period_start", value: start)
            .lte("period_end", value: end)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    // MARK: - Expense Flagging

    func flagExpense(_ expenseId: String, flaggedBy: String, comment: String) async throws -> ExpenseDTO {
        try await client
            .from("expenses")
            .update([
                "flag_comment": comment,
                "flagged_by": flaggedBy,
                "flagged_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: expenseId)
            .select("*, expense_project_allocations(*), expense_categories(*)")
            .single()
            .execute()
            .value
    }

    func unflagExpense(_ expenseId: String) async throws -> ExpenseDTO {
        // Use AnyJSON.null to explicitly send JSON null values — Swift optionals
        // set to nil are skipped by Codable's encodeIfPresent, producing an empty
        // update body that PostgREST rejects with "cannot coerce to single json object".
        return try await client
            .from("expenses")
            .update([
                "flag_comment": AnyJSON.null,
                "flagged_by": AnyJSON.null,
                "flagged_at": AnyJSON.null
            ] as [String: AnyJSON])
            .eq("id", value: expenseId)
            .select("*, expense_project_allocations(*), expense_categories(*)")
            .single()
            .execute()
            .value
    }

    func fetchUnbatchedExpenses(userId: String, periodStart: String, periodEnd: String) async throws -> [ExpenseDTO] {
        try await client
            .from("expenses")
            .select("*, expense_project_allocations(*), expense_categories(*)")
            .eq("company_id", value: companyId)
            .eq("submitted_by", value: userId)
            .is("batch_id", value: nil)
            .is("deleted_at", value: nil)
            .in("status", values: [ExpenseStatus.draft.rawValue])
            .gte("expense_date", value: periodStart)
            .lte("expense_date", value: periodEnd)
            .order("expense_date", ascending: true)
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

    // MARK: - Auto-Approve Rules

    func fetchAutoApproveRules() async throws -> [AutoApproveRuleDTO] {
        try await client
            .from("expense_auto_approve_rules")
            .select("*, expense_auto_approve_rule_members(*)")
            .eq("company_id", value: companyId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createAutoApproveRule(_ dto: CreateAutoApproveRuleDTO) async throws -> AutoApproveRuleDTO {
        try await client
            .from("expense_auto_approve_rules")
            .insert(dto)
            .select("*, expense_auto_approve_rule_members(*)")
            .single()
            .execute()
            .value
    }

    func updateAutoApproveRule(_ ruleId: String, thresholdAmount: Double? = nil, appliesToAll: Bool? = nil, isActive: Bool? = nil) async throws {
        struct RuleUpdate: Encodable {
            var threshold_amount: Double?
            var applies_to_all: Bool?
            var is_active: Bool?
            var updated_at: String

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                if let threshold_amount { try container.encode(threshold_amount, forKey: .threshold_amount) }
                if let applies_to_all { try container.encode(applies_to_all, forKey: .applies_to_all) }
                if let is_active { try container.encode(is_active, forKey: .is_active) }
                try container.encode(updated_at, forKey: .updated_at)
            }

            enum CodingKeys: String, CodingKey {
                case threshold_amount, applies_to_all, is_active, updated_at
            }
        }

        let update = RuleUpdate(threshold_amount: thresholdAmount, applies_to_all: appliesToAll, is_active: isActive, updated_at: ISO8601DateFormatter().string(from: Date()))
        try await client
            .from("expense_auto_approve_rules")
            .update(update)
            .eq("id", value: ruleId)
            .execute()
    }

    func deleteAutoApproveRule(_ ruleId: String) async throws {
        try await client
            .from("expense_auto_approve_rules")
            .delete()
            .eq("id", value: ruleId)
            .execute()
    }

    func setAutoApproveRuleMembers(_ ruleId: String, userIds: [String]) async throws {
        // Delete existing members
        try await client
            .from("expense_auto_approve_rule_members")
            .delete()
            .eq("rule_id", value: ruleId)
            .execute()

        // Insert new members
        if !userIds.isEmpty {
            let dtos = userIds.map { CreateAutoApproveRuleMemberDTO(ruleId: ruleId, userId: $0) }
            try await client
                .from("expense_auto_approve_rule_members")
                .insert(dtos)
                .execute()
        }
    }

    func checkAutoApproveLineItem(userId: String, amount: Double) async throws -> Bool {
        let rules: [AutoApproveRuleDTO] = try await client
            .from("expense_auto_approve_rules")
            .select("*, expense_auto_approve_rule_members(*)")
            .eq("company_id", value: companyId)
            .eq("rule_type", value: "line_item")
            .eq("is_active", value: true)
            .execute()
            .value

        for rule in rules {
            guard amount < rule.thresholdAmount else { continue }
            if rule.appliesToAll { return true }
            if let members = rule.members, members.contains(where: { $0.userId == userId }) {
                return true
            }
        }
        return false
    }

    func checkAutoApproveInvoice(userId: String, totalAmount: Double) async throws -> Bool {
        let rules: [AutoApproveRuleDTO] = try await client
            .from("expense_auto_approve_rules")
            .select("*, expense_auto_approve_rule_members(*)")
            .eq("company_id", value: companyId)
            .eq("rule_type", value: "invoice")
            .eq("is_active", value: true)
            .execute()
            .value

        for rule in rules {
            guard totalAmount < rule.thresholdAmount else { continue }
            if rule.appliesToAll { return true }
            if let members = rule.members, members.contains(where: { $0.userId == userId }) {
                return true
            }
        }
        return false
    }
}
