import Foundation

@MainActor
protocol ExpenseCorrectionRepository {
    func correctForReview(_ command: ExpenseCorrectionCommand) async throws -> ExpenseCorrectionReceipt
    func fetchCorrections(expenseId: String) async throws -> [ExpenseCorrectionDTO]
    func fetchOne(_ expenseId: String) async throws -> ExpenseDTO
    func fetchBatch(_ batchId: String) async throws -> ExpenseBatchDTO
}

extension ExpenseRepository: ExpenseCorrectionRepository {}

struct ExpenseCorrectionSaveResult {
    let receipt: ExpenseCorrectionReceipt
    let refreshed: Bool
}

enum ExpenseCorrectionError: LocalizedError {
    case serviceUnavailable, accountChanged, invalidReceipt
    var errorDescription: String? {
        switch self {
        case .serviceUnavailable: return "Expense service isn't ready. Close the form and try again."
        case .accountChanged: return "Your account changed. Reopen expenses in the correct company."
        case .invalidReceipt: return "The correction wasn't confirmed. Retry the same correction."
        }
    }
}
