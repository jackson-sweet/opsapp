import Foundation

enum ExpenseCorrectionPolicy {
    /// UI affordance only; the RPC rechecks permissions, row revision, all
    /// lifecycle evidence and accounting history in its transaction.
    static func canCorrect(
        expense: ExpenseDTO, batch: ExpenseBatchDTO?, actorId: String?, companyId: String?,
        canApproveAll: Bool, canViewAll: Bool
    ) -> Bool {
        guard canApproveAll, canViewAll,
              let actorId, UUID(uuidString: actorId) != nil,
              let companyId, expense.companyId.lowercased() == companyId.lowercased(),
              expense.submittedBy.lowercased() != actorId.lowercased(),
              // Recurring reimbursement lines change only from their setup.
              !expense.isRecurringReimbursement,
              ["submitted", "rejected"].contains(expense.status), expense.deletedAt == nil,
              expense.approvedBy == nil, expense.approvedAt == nil,
              expense.accountingSyncId == nil, expense.accountingSyncedAt == nil,
              expense.accountingSyncStatus == nil || expense.accountingSyncStatus == "pending" else { return false }
        guard let batchId = expense.batchId else { return true }
        guard let batch, batch.id.lowercased() == batchId.lowercased(),
              batch.companyId.lowercased() == companyId.lowercased(),
              batch.submittedBy?.lowercased() == expense.submittedBy.lowercased(),
              batch.paidAt == nil, batch.paidBy == nil, batch.reviewedAt == nil, batch.reviewedBy == nil,
              ["open", "pending_review", "submitted", "rejected"].contains(batch.status) else { return false }
        return true
    }
}

struct ExpenseCorrectionChange: Identifiable, Equatable {
    let id: String
    let label: String
    let before: String
    let after: String

    static func changes(in correction: ExpenseCorrectionDTO) -> [Self] {
        let old = correction.before, new = correction.after
        var changes: [Self] = []
        func add<T: Equatable>(_ key: String, _ label: String, _ a: T, _ b: T, display: (T) -> String) {
            guard a != b else { return }
            changes.append(Self(id: key, label: label, before: display(a), after: display(b)))
        }
        func text(_ value: String?) -> String { value?.isEmpty == false ? value! : "—" }
        add("merchant_name", "MERCHANT", old.merchantName, new.merchantName, display: text)
        add("description", "NOTES", old.description, new.description, display: text)
        if old.categoryId != new.categoryId {
            changes.append(Self(id: "category_id", label: "CATEGORY", before: text(old.categoryName), after: text(new.categoryName)))
        }
        if old.amount != new.amount || old.currency != new.currency {
            changes.append(Self(id: "amount", label: "AMOUNT", before: BooksFormat.exact(old.amount, code: old.currency ?? "USD"), after: BooksFormat.exact(new.amount, code: new.currency ?? "USD")))
        }
        if old.taxAmount != new.taxAmount || (old.currency != new.currency && (old.taxAmount != nil || new.taxAmount != nil)) {
            changes.append(Self(id: "tax_amount", label: "TAX", before: old.taxAmount.map { BooksFormat.exact($0, code: old.currency ?? "USD") } ?? "—", after: new.taxAmount.map { BooksFormat.exact($0, code: new.currency ?? "USD") } ?? "—"))
        }
        add("expense_date", "DATE", old.expenseDate, new.expenseDate, display: text)
        add("payment_method", "PAID WITH", old.paymentMethod, new.paymentMethod) {
            $0.flatMap(ExpensePaymentMethod.init(rawValue:))?.displayName ?? text($0)
        }
        add("project_missing_reason", "NO PROJECT REASON", old.projectMissingReason, new.projectMissingReason) {
            NoProjectReason(code: $0)?.label ?? text($0)
        }
        add("project_missing_note", "PROJECT NOTE", old.projectMissingNote, new.projectMissingNote, display: text)
        let beforeAllocations = old.allocations.sorted { $0.projectId < $1.projectId }
        let afterAllocations = new.allocations.sorted { $0.projectId < $1.projectId }
        // Names are audit labels, not editable fields. A later rename alone is
        // not presented as an allocation correction.
        let beforeValues = beforeAllocations.map { "\($0.projectId.lowercased()):\($0.percentage):\(String(describing: $0.amount))" }
        let afterValues = afterAllocations.map { "\($0.projectId.lowercased()):\($0.percentage):\(String(describing: $0.amount))" }
        if beforeValues != afterValues {
            func allocations(_ values: [ExpenseCorrectionSnapshot.Allocation], currency: String?) -> String {
                guard !values.isEmpty else { return "—" }
                return values.map {
                    let percentage = $0.percentage.formatted(.number.precision(.fractionLength(0...2)))
                    let allocationAmount = $0.amount.map { " · " + BooksFormat.exact($0, code: currency ?? "USD") } ?? ""
                    return "\(text($0.projectTitle)) · \(percentage)%\(allocationAmount)"
                }.joined(separator: "\n")
            }
            changes.append(Self(id: "allocations", label: "PROJECT SPLIT", before: allocations(beforeAllocations, currency: old.currency), after: allocations(afterAllocations, currency: new.currency)))
        }
        return changes
    }
}
