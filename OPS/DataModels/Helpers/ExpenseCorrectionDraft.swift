import Foundation

/// Editable values only. A stale reload carries deliberate edits forward and
/// adopts newer server values for fields the reviewer never changed.
struct ExpenseCorrectionDraft: Equatable {
    var merchant: String
    var description: String
    var amount: String
    var tax: String
    var currency: String
    var date: String
    var categoryId: String?
    var paymentMethod: String
    var projectReason: String?
    var projectNote: String
    var allocations: [ExpenseAtomicAllocationCommand]

    init(expense: ExpenseDTO) {
        merchant = expense.merchantName ?? ""
        description = expense.description ?? ""
        amount = String(format: "%.2f", expense.amount)
        tax = expense.taxAmount.map { String(format: "%.2f", $0) } ?? ""
        currency = expense.currency?.uppercased() ?? "USD"
        date = expense.expenseDate.map { String($0.prefix(10)) } ?? ""
        categoryId = expense.categoryId?.lowercased()
        paymentMethod = expense.paymentMethod ?? "personal_card"
        projectReason = expense.projectMissingReason
        projectNote = expense.projectMissingNote ?? ""
        allocations = (expense.allocations ?? []).map {
            ExpenseAtomicAllocationCommand(projectId: $0.projectId.lowercased(), percentage: $0.percentage, amount: nil)
        }.sorted { $0.projectId < $1.projectId }
    }

    func rebased(from previous: Self, onto fresh: Self) -> (draft: Self, conflicts: [String]) {
        var draft = self
        var conflicts: [String] = []
        func merge<T: Equatable>(_ key: WritableKeyPath<Self, T>, _ label: String) {
            let entered = self[keyPath: key], old = previous[keyPath: key], latest = fresh[keyPath: key]
            if entered == old { draft[keyPath: key] = latest }
            else if latest != old && latest != entered { conflicts.append(label) }
        }
        merge(\.merchant, "merchant")
        merge(\.description, "notes")
        merge(\.amount, "amount")
        merge(\.tax, "tax")
        merge(\.currency, "currency")
        merge(\.date, "date")
        merge(\.categoryId, "category")
        merge(\.paymentMethod, "payment method")
        // Project split and no-project explanation form one intent; they must
        // not be independently merged into contradictory assignments.
        let unchangedProject = allocations == previous.allocations
            && projectReason == previous.projectReason && projectNote == previous.projectNote
        if unchangedProject {
            draft.allocations = fresh.allocations
            draft.projectReason = fresh.projectReason
            draft.projectNote = fresh.projectNote
        } else if fresh.allocations != previous.allocations || fresh.projectReason != previous.projectReason || fresh.projectNote != previous.projectNote {
            if allocations != fresh.allocations || projectReason != fresh.projectReason || projectNote != fresh.projectNote {
                conflicts.append("project split")
            }
        }
        return (draft, conflicts)
    }
}
