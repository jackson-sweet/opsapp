//
//  PaymentReviewRepository.swift
//  OPS
//
//  Authoritative Payment Review reads and mutations. Close/write-off resolve
//  in Postgres before the card advances; reminders enter the existing web
//  approval queue and are never represented as already sent.
//

import Foundation
import Supabase

struct PaymentReviewCloseResult: Decodable, Sendable {
    let projectID: String
    let status: String
    let alreadyClosed: Bool

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case status
        case alreadyClosed = "already_closed"
    }
}

struct PaymentReviewWriteOffResult: Decodable, Sendable {
    let projectID: String
    let status: String
    let writtenOffInvoiceCount: Int
    let writtenOffBalance: Double

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case status
        case writtenOffInvoiceCount = "written_off_invoice_count"
        case writtenOffBalance = "written_off_balance"
    }
}

struct PaymentReminderQueueResult: Decodable, Sendable {
    let eligibleCount: Int
    let queuedCount: Int
    let alreadyQueuedCount: Int
    let failedCount: Int?
}

enum PaymentReminderBlockedReason: String, Decodable, Sendable {
    case featureDisabled = "feature_disabled"
    case remindersDisabled = "reminders_disabled"
    case mailboxRequired = "mailbox_required"
    case clientEmailRequired = "client_email_required"
}

enum PaymentReviewRepositoryError: LocalizedError {
    case invalidResponse
    case noReminderDue
    case forbidden
    case companySettingsUnavailable
    case reminderBlocked(PaymentReminderBlockedReason)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response"
        case .noReminderDue:
            return "No reminder is due"
        case .forbidden:
            return "Permission denied"
        case .companySettingsUnavailable:
            return "Company payment settings unavailable"
        case .reminderBlocked(let reason):
            return reason.rawValue
        case .server(let message):
            return message
        }
    }
}

final class PaymentReviewRepository {
    private struct CompanyPaymentSettingsRow: Decodable {
        let timeZoneIdentifier: String
        let currencyCode: String

        enum CodingKeys: String, CodingKey {
            case timeZoneIdentifier = "timezone"
            case currencyCode = "currency_code"
        }
    }

    private struct InvoiceFinancialRow: Decodable {
        let projectID: String?
        let projectRef: String?
        let status: String
        let balanceDue: Double
        let dueDate: String?
        let quickBooksID: String?
        let sageID: String?

        enum CodingKeys: String, CodingKey {
            case projectID = "project_id"
            case projectRef = "project_ref"
            case status
            case balanceDue = "balance_due"
            case dueDate = "due_date"
            case quickBooksID = "qb_id"
            case sageID = "sage_id"
        }
    }

    private struct ReminderErrorBody: Decodable {
        let error: String?
        let eligibleCount: Int?
        let queuedCount: Int?
        let alreadyQueuedCount: Int?
        let blockedReason: PaymentReminderBlockedReason?
    }

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    @MainActor
    convenience init() {
        self.init(client: SupabaseService.shared.client)
    }

    func fetchFinancialSummaries(
        projectIDs: [String],
        companyID: String?,
        now: Date = Date()
    ) async throws -> [String: PaymentReviewFinancialSummary] {
        guard !projectIDs.isEmpty else { return [:] }
        guard let companyID = companyID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !companyID.isEmpty else {
            throw PaymentReviewRepositoryError.companySettingsUnavailable
        }

        async let companySettingsRow: CompanyPaymentSettingsRow = client
            .from("companies")
            .select("timezone,currency_code")
            .eq("id", value: companyID)
            .is("deleted_at", value: nil)
            .single()
            .execute()
            .value
        async let canonicalRows: [InvoiceFinancialRow] = client
            .from("invoices")
            .select("project_id,project_ref,status,balance_due,due_date,qb_id,sage_id")
            .eq("company_id", value: companyID)
            .in("project_ref", values: projectIDs)
            .is("deleted_at", value: nil)
            .execute()
            .value
        async let legacyRows: [InvoiceFinancialRow] = client
            .from("invoices")
            .select("project_id,project_ref,status,balance_due,due_date,qb_id,sage_id")
            .eq("company_id", value: companyID)
            .in("project_id", values: projectIDs)
            .is("project_ref", value: nil)
            .is("deleted_at", value: nil)
            .execute()
            .value
        let (settingsRow, canonical, legacy) = try await (
            companySettingsRow,
            canonicalRows,
            legacyRows
        )
        let timeZone = try Self.companyTimeZone(
            identifier: settingsRow.timeZoneIdentifier
        )
        let currencyCode = try Self.normalizedCurrencyCode(
            settingsRow.currencyCode
        )
        let rows = canonical + legacy

        let outstandingStatuses: Set<String> = [
            InvoiceStatus.sent.rawValue,
            InvoiceStatus.awaitingPayment.rawValue,
            InvoiceStatus.partiallyPaid.rawValue,
            InvoiceStatus.pastDue.rawValue,
        ]
        let resolvedStatuses: Set<String> = [
            InvoiceStatus.paid.rawValue,
            InvoiceStatus.void.rawValue,
            InvoiceStatus.writtenOff.rawValue,
        ]
        let grouped = Dictionary(grouping: rows) { $0.projectRef ?? $0.projectID ?? "" }

        var summaries = Dictionary(
            uniqueKeysWithValues: projectIDs.map {
                ($0, PaymentReviewFinancialSummary.empty(currencyCode: currencyCode))
            }
        )
        grouped.forEach { entry in
            guard !entry.key.isEmpty else { return }
            let outstanding = entry.value.filter {
                $0.balanceDue > 0 && outstandingStatuses.contains($0.status)
            }
            let unresolved = entry.value.filter {
                $0.balanceDue > 0 && !resolvedStatuses.contains($0.status)
            }
            let externallyManagedOutstanding = outstanding.filter {
                $0.quickBooksID != nil || $0.sageID != nil
            }
            let overdueCount = outstanding.filter { row in
                guard let value = row.dueDate else { return false }
                return Self.isOverdue(
                    dueDate: value,
                    now: now,
                    timeZone: timeZone
                )
            }.count
            summaries[entry.key] = PaymentReviewFinancialSummary(
                invoiceCount: entry.value.count,
                unresolvedInvoiceCount: unresolved.count,
                outstandingInvoiceCount: outstanding.count,
                externallyManagedOutstandingInvoiceCount: externallyManagedOutstanding.count,
                overdueInvoiceCount: overdueCount,
                unresolvedBalance: unresolved.reduce(0) { $0 + $1.balanceDue },
                outstandingBalance: outstanding.reduce(0) { $0 + $1.balanceDue },
                currencyCode: currencyCode
            )
        }
        return summaries
    }

    static func companyTimeZone(identifier: String) throws -> TimeZone {
        let identifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              let timeZone = TimeZone(identifier: identifier) else {
            throw PaymentReviewRepositoryError.companySettingsUnavailable
        }
        return timeZone
    }

    static func normalizedCurrencyCode(_ value: String) throws -> String {
        let currencyCode = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let isASCIIAlpha = currencyCode.unicodeScalars.allSatisfy {
            (65...90).contains($0.value)
        }
        guard currencyCode.unicodeScalars.count == 3, isASCIIAlpha else {
            throw PaymentReviewRepositoryError.companySettingsUnavailable
        }
        return currencyCode
    }

    static func isOverdue(
        dueDate value: String,
        now: Date,
        timeZone: TimeZone
    ) -> Bool {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let parsedDate = SupabaseDate.parseDateOnly(value) else { return false }

        let dateComponents = utc.dateComponents(
            [.year, .month, .day],
            from: parsedDate
        )
        var companyCalendar = Calendar(identifier: .gregorian)
        companyCalendar.timeZone = timeZone
        guard let companyDueDate = companyCalendar.date(from: dateComponents) else {
            return false
        }
        return companyDueDate < companyCalendar.startOfDay(for: now)
    }

    func closeProject(_ projectID: String) async throws -> PaymentReviewCloseResult {
        try await client
            .rpc(
                "close_project_from_payment_review",
                params: ["p_project_id": projectID]
            )
            .execute()
            .value
    }

    func writeOffProject(
        _ projectID: String,
        idempotencyKey: String
    ) async throws -> PaymentReviewWriteOffResult {
        try await client
            .rpc(
                "write_off_project_from_payment_review",
                params: [
                    "p_project_id": projectID,
                    "p_idempotency_key": idempotencyKey,
                ]
            )
            .execute()
            .value
    }

    func queueReminder(_ projectID: String) async throws -> PaymentReminderQueueResult {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let url = AppConfiguration.apiBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("review")
            .appendingPathComponent("payment")
            .appendingPathComponent("reminder")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["projectId": projectID])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw PaymentReviewRepositoryError.invalidResponse
        }

        if response.statusCode == 200 || response.statusCode == 201 {
            return try JSONDecoder().decode(PaymentReminderQueueResult.self, from: data)
        }
        if response.statusCode == 409 {
            throw PaymentReviewRepositoryError.noReminderDue
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw PaymentReviewRepositoryError.forbidden
        }

        let body = try? JSONDecoder().decode(ReminderErrorBody.self, from: data)
        if response.statusCode == 422, let reason = body?.blockedReason {
            throw PaymentReviewRepositoryError.reminderBlocked(reason)
        }
        throw PaymentReviewRepositoryError.server(
            body?.error ?? "Unable to queue reminder"
        )
    }
}
