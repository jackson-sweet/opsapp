//
//  ExpenseRecurringReimbursementRepository.swift
//  OPS
//
//  Reads a company's recurring reimbursements and calls their commands. The
//  database owns the whole lifecycle: it files one pre-approved line per month
//  into the person's envelope, and every change goes through a SECURITY
//  DEFINER command that checks `expenses.approve` (scope all), serializes with
//  every other expense write, and notifies the crew member. Each command takes
//  the setup's `updated_at` as an optimistic-concurrency token, so a stale form
//  is refused instead of overwriting newer work.
//

import Foundation
import Supabase

/// Seam for `RecurringReimbursementViewModel`; tests substitute a fake.
protocol RecurringReimbursementRepository {
    func fetchSnapshot() async throws -> RecurringReimbursementsSnapshot
    func create(_ params: CreateRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO
    func update(_ params: UpdateRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO
    func end(_ params: EndRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO
    func delete(_ params: DeleteRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO
    func skipLine(expenseId: String) async throws -> ExpenseRecurringReimbursementDTO
    func restoreLine(expenseId: String) async throws -> ExpenseRecurringReimbursementDTO
}

final class ExpenseRecurringReimbursementRepository: RecurringReimbursementRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Read

    private struct CompanyCalendarRow: Decodable {
        let currencyCode: String?
        let timezone: String?

        enum CodingKeys: String, CodingKey {
            case currencyCode = "currency_code"
            case timezone
        }
    }

    /// Live setups with every month's line, plus the company calendar they run on.
    func fetchSnapshot() async throws -> RecurringReimbursementsSnapshot {
        async let companyRow: CompanyCalendarRow = client
            .from("companies")
            .select("currency_code,timezone")
            .eq("id", value: companyId)
            .is("deleted_at", value: nil)
            .single()
            .execute()
            .value
        async let setupRows: [ExpenseRecurringReimbursementDTO] = client
            .from("expense_recurring_reimbursements")
            .select()
            .eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: true)
            .execute()
            .value
        let (company, setups) = try await (companyRow, setupRows)

        let currency = Self.normalizedCurrency(company.currencyCode)
        guard !setups.isEmpty else {
            return RecurringReimbursementsSnapshot(setups: [], currency: currency, timeZone: company.timezone)
        }

        let lineRows: [RecurringLineRowDTO] = try await client
            .from("expenses")
            .select(RecurringLineRowDTO.selectColumns)
            .in("recurring_reimbursement_id", values: setups.map(\.id))
            .execute()
            .value
        let linesBySetup = Dictionary(grouping: lineRows) { $0.recurringReimbursementId.lowercased() }

        return RecurringReimbursementsSnapshot(
            setups: setups.map { setup in
                setup.withLines((linesBySetup[setup.id.lowercased()] ?? []).map(\.summary))
            },
            currency: currency,
            timeZone: company.timezone
        )
    }

    /// The database files new setups in the company currency, defaulting to USD.
    static func normalizedCurrency(_ raw: String?) -> String {
        let code = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let letters: ClosedRange<Unicode.Scalar> = "A"..."Z"
        guard code.unicodeScalars.count == 3,
              code.unicodeScalars.allSatisfy({ letters.contains($0) }) else { return "USD" }
        return code
    }

    // MARK: - Commands

    func create(_ params: CreateRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO {
        try await client
            .rpc("create_expense_recurring_reimbursement", params: params)
            .execute()
            .value
    }

    func update(_ params: UpdateRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO {
        try await client
            .rpc("update_expense_recurring_reimbursement", params: params)
            .execute()
            .value
    }

    /// Sets the last month paid, or clears it (nil) so it runs again from this month.
    func end(_ params: EndRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO {
        try await client
            .rpc("end_expense_recurring_reimbursement", params: params)
            .execute()
            .value
    }

    /// Removes a setup made in error with every month. Refused once a month is paid.
    func delete(_ params: DeleteRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO {
        try await client
            .rpc("delete_expense_recurring_reimbursement", params: params)
            .execute()
            .value
    }

    /// Leaves one unpaid month out.
    func skipLine(expenseId: String) async throws -> ExpenseRecurringReimbursementDTO {
        try await client
            .rpc("skip_expense_recurring_reimbursement_line", params: RecurringLineCommandParams(expenseId: expenseId))
            .execute()
            .value
    }

    /// Puts a skipped month back at the current amount.
    func restoreLine(expenseId: String) async throws -> ExpenseRecurringReimbursementDTO {
        try await client
            .rpc("restore_expense_recurring_reimbursement_line", params: RecurringLineCommandParams(expenseId: expenseId))
            .execute()
            .value
    }
}
