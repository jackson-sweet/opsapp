//
//  ExpenseViewModel.swift
//  OPS
//
//  ViewModel for Expenses — manages expense list, filtering, categories, batches, and approval actions.
//

import SwiftUI
import Combine

enum ExpenseSettingsLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

private enum ExpenseViewModelError: LocalizedError {
    case repositoryUnavailable

    var errorDescription: String? {
        "Expense service isn't ready. Close the form and try again."
    }
}

/// Seam for the expense batch-decision rail row. Conformed to by
/// `NotificationRepository` (the `notify_expense_batch_decision` RPC); tests
/// substitute a spy.
///
/// Direct `notifications` inserts have failed 42501 for app roles since the
/// 2026-07-15 notification-creation hardening, so the server owns everything
/// the row says: it validates the actor holds `expenses.approve`, validates the
/// decision is actually recorded on the batch row, derives the submitter
/// recipient from that row, renders the batch-vocabulary copy and deep link,
/// and dedupes per batch + decision.
protocol ExpenseDecisionNotifying {
    /// `decision` is one of `approved` / `sent_back` / `paid`; `count` is the
    /// sent-back line count, ignored for the other two. The server reads the
    /// RECORDED decision, so this may only be called once the decision's own
    /// write has landed.
    @discardableResult
    func notifyExpenseBatchDecision(batchId: String, decision: String, count: Int?) async throws -> String
}

extension NotificationRepository: ExpenseDecisionNotifying {}

/// The approval transaction and its affected-row readback. The database queues
/// accounting work atomically; this seam never substitutes local state for a save.
@MainActor
protocol ExpenseBatchApprovalRepository {
    func approveBatchAtomic(_ batchId: String) async throws
    func fetchBatch(_ batchId: String) async throws -> ExpenseBatchDTO
    func fetchBatchExpenses(_ batchId: String) async throws -> [ExpenseDTO]
}

@MainActor
protocol ExpenseConsoleRepository {
    func fetchBatches() async throws -> [ExpenseBatchDTO]
    func fetchAll() async throws -> [ExpenseDTO]
    func fetchSettings() async throws -> ExpenseSettingsDTO?
}

extension ExpenseRepository: ExpenseBatchApprovalRepository, ExpenseConsoleRepository {}

/// Process-wide financial receipts outlive any particular console. Claims
/// protect pending work; accepted receipts protect stale/reopened consoles
/// after the original operation releases its claim.
@MainActor
final class ExpenseBatchApprovalState: ObservableObject {
    static let shared = ExpenseBatchApprovalState()

    struct Key: Hashable {
        let companyId: String
        let batchId: String

        init(_ batch: ExpenseBatchDTO) {
            companyId = batch.companyId.lowercased()
            batchId = batch.id.lowercased()
        }
    }

    @Published private(set) var accepted: [Key: Int] = [:]
    @Published private(set) var claims: Set<Key> = []
    private(set) var receiptVersion = 0

    func claim(_ batches: [ExpenseBatchDTO]) -> Set<Key> {
        let keys = Set(batches.map(Key.init))
        claims.formUnion(keys)
        return keys
    }

    func release(_ keys: Set<Key>) {
        claims.subtract(keys)
    }

    func recordAccepted(_ batch: ExpenseBatchDTO) {
        receiptVersion += 1
        accepted[Key(batch)] = receiptVersion
    }

    func reconcile(_ batches: [ExpenseBatchDTO], readStartedAt version: Int) {
        // A previously-started read cannot undo a newer receipt. An explicit
        // later server transition back to review remains authoritative.
        let retired = batches.compactMap { batch -> Key? in
            let key = Key(batch)
            guard let acceptedAt = accepted[key], acceptedAt <= version,
                  !claims.contains(key),
                  ExpenseBatchStatus(rawValue: batch.status)?.needsReview == true else { return nil }
            return key
        }
        guard !retired.isEmpty else { return }
        var remaining = accepted
        for key in retired { remaining.removeValue(forKey: key) }
        accepted = remaining
    }
}

struct ExpenseBatchApprovalResult: Equatable {
    let savedCount: Int
    let requestedCount: Int
    let refreshRequired: Bool

    var toastLabel: String {
        if refreshRequired {
            return "// \(savedCount) OF \(requestedCount) APPROVED · REFRESH NEEDED"
        }
        return "// \(savedCount) OF \(requestedCount) BATCHES APPROVED"
    }
}

@MainActor
class ExpenseViewModel: ObservableObject {
    @Published var expenses: [ExpenseDTO] = []
    @Published var categories: [ExpenseCategoryDTO] = []
    @Published var batches: [ExpenseBatchDTO] = []
    /// The current user's own batches — drives the My Expenses filling-total
    /// strip and each card's envelope-phase line.
    @Published var myBatches: [ExpenseBatchDTO] = []
    @Published var settings: ExpenseSettingsDTO? = nil
    @Published private(set) var settingsLoadState: ExpenseSettingsLoadState = .idle
    @Published var selectedFilter: ExpenseFilter = .all
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var autoApproveRules: [AutoApproveRuleDTO] = []
    @Published var reviewBatches: [ExpenseBatchDTO] = []
    @Published var selectedBatchExpenses: [ExpenseDTO] = []
    @Published var flaggedExpenseIds: Set<String> = []
    @Published var flagComments: [String: String] = [:]

    @Published private(set) var isApprovingBatches = false
    @Published private(set) var hasSavedCurrentApproval = false
    @Published private(set) var approvalBatchNumber = 0
    @Published private(set) var approvalBatchCount = 0
    @Published private(set) var approvalRefreshRequired = false
    @Published private(set) var lastBatchApprovalResult: ExpenseBatchApprovalResult?

    var confirmedApprovedBatchIds: Set<String> {
        Set(reviewBatches.compactMap { batch in
            guard belongsToCurrentCompany(batch),
                  approvalState.accepted[ExpenseBatchApprovalState.Key(batch)] != nil else { return nil }
            return batch.id
        })
    }

    var approvalInFlightBatchIds: Set<String> {
        Set(reviewBatches.compactMap { batch in
            guard belongsToCurrentCompany(batch),
                  approvalState.claims.contains(ExpenseBatchApprovalState.Key(batch)) else { return nil }
            return batch.id
        })
    }

    /// Shared by list and reopened detail views; not tied to sheet lifetime.
    var batchApprovalRepository: ExpenseBatchApprovalRepository?
    var consoleRepository: ExpenseConsoleRepository?
    private var consoleLoadGeneration = 0
    private var batchLineLoadGeneration = 0
    private var selectedBatchId: String?
    private var needsConsoleRefreshAfterApproval = false
    private let approvalState: ExpenseBatchApprovalState
    private var approvalStateObservation: AnyCancellable?
    private var ownedBatchApprovalClaims: Set<ExpenseBatchApprovalState.Key> = []
    private var batchApprovalFailure: String?

    init(approvalState: ExpenseBatchApprovalState? = nil) {
        self.approvalState = approvalState ?? .shared
        approvalStateObservation = self.approvalState.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var approvalProgressLabel: String {
        if approvalBatchCount > 1 {
            return hasSavedCurrentApproval
                ? "SAVED \(approvalBatchNumber) OF \(approvalBatchCount) · FINISHING"
                : "APPROVING \(approvalBatchNumber) OF \(approvalBatchCount)"
        }
        return hasSavedCurrentApproval ? "APPROVED · FINISHING" : "APPROVING…"
    }

    func canApproveBatch(_ batch: ExpenseBatchDTO) -> Bool {
        let key = ExpenseBatchApprovalState.Key(batch)
        guard belongsToCurrentCompany(batch), !isApprovingBatches,
              approvalState.accepted[key] == nil,
              !approvalState.claims.contains(key) else { return false }
        let current = reviewBatches.first(where: { $0.id == batch.id }) ?? batch
        return ExpenseBatchStatus(rawValue: current.status)?.needsReview == true
    }

    private func belongsToCurrentCompany(_ batch: ExpenseBatchDTO) -> Bool {
        storedCompanyId == nil || storedCompanyId?.lowercased() == batch.companyId.lowercased()
    }

    var correctionRepository: ExpenseCorrectionRepository?
    /// The open form supplies its live account source so an account switch is
    /// caught even before this view model receives its next setup call.
    var correctionCurrentIdentity: (() -> (companyId: String?, userId: String?))?
    private var repository: ExpenseRepository?
    private var storedCompanyId: String?
    private var storedUserId: String?
    private var storedUserName: String?
    private let ocrService: ExpenseOCRServiceProtocol = AppleVisionOCRService()
    /// Seam for the submitter's decision rail row. A defaulted property rather
    /// than an init parameter: the view model is constructed at call sites that
    /// have no business knowing the notification seam exists.
    var decisionNotifier: ExpenseDecisionNotifying = NotificationRepository()
    /// Debounce for realtime-driven console reloads (`.expenseUpdated` bursts).
    private var realtimeRefreshTask: Task<Void, Never>?

    var hasLoadedSettings: Bool { settingsLoadState == .loaded }

    var submissionRequirements: ExpenseSubmissionRequirements {
        ExpenseSubmissionRequirements(settings: settings)
    }

    enum ExpenseFilter: String, CaseIterable {
        case all      = "ALL"
        case pending  = "PENDING"
        case approved = "APPROVED"
        case rejected = "REJECTED"
    }

    var filteredExpenses: [ExpenseDTO] {
        var result = expenses
        switch selectedFilter {
        case .all:      break
        case .pending:  result = result.filter { $0.status == "submitted" || $0.status == "draft" }
        case .approved: result = result.filter { $0.status == "approved" || $0.status == "reimbursed" }
        case .rejected: result = result.filter { $0.status == "rejected" }
        }
        if !searchText.isEmpty {
            result = result.filter {
                ($0.merchantName ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.description ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    // MARK: - Grouped Expenses

    struct ExpenseMonthGroup: Identifiable {
        let id: String                            // "2026-03"
        let monthLabel: String                    // "MARCH 2026"
        let projectGroups: [ProjectExpenseGroup]
        let unallocated: [ExpenseDTO]
        var totalCount: Int { projectGroups.reduce(0) { $0 + $1.expenses.count } + unallocated.count }
    }

    struct ProjectExpenseGroup: Identifiable {
        let id: String          // projectId
        var projectId: String { id }
        let expenses: [ExpenseDTO]
    }

    var groupedExpenses: [ExpenseMonthGroup] {
        let source = filteredExpenses

        let monthKeyFormatter = DateFormatter()
        monthKeyFormatter.dateFormat = "yyyy-MM"
        let monthLabelFormatter = DateFormatter()
        monthLabelFormatter.dateFormat = "MMMM yyyy"

        // Parse date for each expense, group by month key. Date-only strings
        // anchor to LOCAL midnight (ExpenseBuckets.parseDate) so a line from
        // the 1st never groups under the previous month west of Greenwich.
        var monthBuckets: [String: (label: String, expenses: [ExpenseDTO])] = [:]
        for expense in source {
            let dateString = expense.expenseDate ?? expense.createdAt
            let resolvedDate = ExpenseBuckets.parseDate(dateString) ?? Date()

            let key = monthKeyFormatter.string(from: resolvedDate)
            let label = monthLabelFormatter.string(from: resolvedDate).uppercased()
            var bucket = monthBuckets[key] ?? (label: label, expenses: [])
            bucket.expenses.append(expense)
            monthBuckets[key] = bucket
        }

        // Sort months descending
        let sortedKeys = monthBuckets.keys.sorted(by: >)

        return sortedKeys.map { key in
            let bucket = monthBuckets[key]!
            var projectDict: [String: [ExpenseDTO]] = [:]
            var unallocated: [ExpenseDTO] = []

            for expense in bucket.expenses {
                if let allocations = expense.allocations, let first = allocations.first {
                    projectDict[first.projectId, default: []].append(expense)
                } else {
                    unallocated.append(expense)
                }
            }

            let projectGroups = projectDict.keys.sorted().map { projectId in
                ProjectExpenseGroup(
                    id: projectId,
                    expenses: ExpenseBuckets.attentionOrdered(projectDict[projectId]!)
                )
            }

            return ExpenseMonthGroup(
                id: key,
                monthLabel: bucket.label,
                projectGroups: projectGroups,
                unallocated: ExpenseBuckets.attentionOrdered(unallocated)
            )
        }
    }

    func setup(companyId: String, currentUserId: String? = nil, currentUserName: String? = nil) {
        let companyChanged = storedCompanyId != companyId
        storedCompanyId = companyId
        storedUserId = currentUserId
        storedUserName = currentUserName
        repository = ExpenseRepository(companyId: companyId)
        batchApprovalRepository = repository
        consoleRepository = repository
        correctionRepository = repository
        if companyChanged {
            approvalRefreshRequired = false
            consoleLoadGeneration += 1
            settings = nil
            settingsLoadState = .idle
        }
    }

    /// Update the cached current-user context (used for notification dispatch
    /// — submitter name in body, exclude-self in recipients). Safe to call
    /// after setup once the DataController has loaded the user.
    func setCurrentUser(id: String?, name: String?) {
        storedUserId = id
        storedUserName = name
    }

    // MARK: - Load Data

    func loadExpenses() async {
        guard let repo = repository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            expenses = try await repo.fetchAll()
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }

    func loadCategories() async {
        guard let repo = repository else { return }
        do {
            categories = try await repo.fetchCategories()
            // If no categories exist, seed defaults
            if categories.isEmpty {
                try await repo.seedDefaultCategories()
                categories = try await repo.fetchCategories()
            }
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }

    func loadBatches() async {
        guard let repo = repository else { return }
        do {
            batches = try await repo.fetchBatches()
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }

    /// Load the current user's own batches (for the crew filling total + the
    /// per-card envelope phase). RLS scopes reads to the company; we keep just
    /// this user's so the strip/phase math stays cheap and correct.
    func loadMyBatches() async {
        guard let repo = repository, let uid = storedUserId else { return }
        do {
            myBatches = try await repo.fetchBatchesByUser(uid)
        } catch {
            // Observability only — the list still works without the phase line.
        }
    }

    /// Resolved envelope status for an expense's batch (nil when the line is a
    /// draft / unbatched, or its batch isn't loaded yet).
    func batchStatus(for expense: ExpenseDTO) -> ExpenseBatchStatus? {
        guard let bid = expense.batchId,
              let batch = myBatches.first(where: { $0.id == bid }) else { return nil }
        return ExpenseBatchStatus(rawValue: batch.status)
    }

    /// The current filling envelope(s) total + period label for the low-key
    /// running-total strip. Nil when nothing is filling this period.
    var currentFilling: (total: Double, periodLabel: String)? {
        let open = myBatches.filter { ExpenseBatchStatus(rawValue: $0.status) == .open }
        guard !open.isEmpty else { return nil }
        let total = open.compactMap(\.totalAmount).reduce(0, +)
        let label: String = {
            let latest = open
                .sorted { ($0.periodStart ?? "") > ($1.periodStart ?? "") }
                .first?.periodStart
            guard let start = latest else { return "" }
            let iso = ISO8601DateFormatter(); iso.formatOptions = [.withFullDate]
            guard let d = iso.date(from: start) else { return "" }
            let f = DateFormatter(); f.dateFormat = "MMMM"
            return f.string(from: d).uppercased()
        }()
        return (total, label)
    }

    @discardableResult
    func loadSettings() async -> Bool {
        guard let repo = repository else {
            settingsLoadState = .failed
            return false
        }
        settingsLoadState = .loading
        do {
            settings = try await repo.fetchSettings()
            settingsLoadState = .loaded
            self.error = nil
            return true
        } catch {
            settingsLoadState = .failed
            if !error.isCancellation { self.error = error.localizedDescription }
            return false
        }
    }

    /// Resolve company submission policy before a final submit. A missing row
    /// is a successful load and uses database defaults; a network failure is
    /// not treated as permission to submit.
    func ensureSettingsLoaded() async -> Bool {
        if hasLoadedSettings { return true }
        return await loadSettings()
    }

    func loadAll() async {
        async let expensesTask: () = loadExpenses()
        async let categoriesTask: () = loadCategories()
        async let settingsTask: Bool = loadSettings()
        async let batchesTask: () = loadBatches()
        async let myBatchesTask: () = loadMyBatches()
        _ = await (expensesTask, categoriesTask, settingsTask, batchesTask, myBatchesTask)
    }

    // MARK: - OCR

    func scanReceipt(image: UIImage) async -> OCRResult? {
        do {
            return try await ocrService.extractData(from: image)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    // MARK: - Corrections

    /// The receipt confirms the command, while an independent read supplies
    /// current data. A replay receipt must never roll back a later crew edit.
    func correctExpenseForReview(_ command: ExpenseCorrectionCommand) async throws -> ExpenseCorrectionSaveResult {
        guard let repo = correctionRepository else { throw ExpenseCorrectionError.serviceUnavailable }
        guard correctionIdentityMatches(companyId: command.content.companyId, actorId: command.actorId) else {
            throw ExpenseCorrectionError.accountChanged
        }
        let receipt = try await repo.correctForReview(command)
        guard receipt.matches(command) else { throw ExpenseCorrectionError.invalidReceipt }
        guard correctionIdentityMatches(companyId: command.content.companyId, actorId: command.actorId) else {
            throw ExpenseCorrectionError.accountChanged
        }
        // Invalidate older reads, then capture this refresh's generation.
        // Newer console/detail reads supersede it while network awaits yield.
        batchLineLoadGeneration += 1
        consoleLoadGeneration += 1
        let lineGeneration = batchLineLoadGeneration
        let consoleGeneration = consoleLoadGeneration
        do {
            let row = try await repo.fetchOne(command.content.expenseId)
            guard correctionIdentityMatches(companyId: command.content.companyId, actorId: command.actorId) else {
                throw ExpenseCorrectionError.accountChanged
            }
            guard row.id.lowercased() == command.content.expenseId.lowercased(),
                  row.companyId.lowercased() == command.content.companyId.lowercased(),
                  row.submittedBy.lowercased() == command.content.submittedBy.lowercased() else {
                throw ExpenseCorrectionError.invalidReceipt
            }
            var batch: ExpenseBatchDTO?
            if let batchId = row.batchId {
                batch = try await repo.fetchBatch(batchId)
                guard batch?.id.lowercased() == batchId.lowercased(),
                      batch?.companyId.lowercased() == row.companyId.lowercased() else {
                    throw ExpenseCorrectionError.invalidReceipt
                }
            }
            guard correctionIdentityMatches(companyId: command.content.companyId, actorId: command.actorId) else {
                throw ExpenseCorrectionError.accountChanged
            }
            guard lineGeneration == batchLineLoadGeneration, consoleGeneration == consoleLoadGeneration else {
                return ExpenseCorrectionSaveResult(receipt: receipt, refreshed: false)
            }
            // Publish row and envelope together, only after every read matches.
            if let index = expenses.firstIndex(where: { $0.id.lowercased() == row.id.lowercased() }) {
                if row.deletedAt != nil { expenses.remove(at: index) } else { expenses[index] = row }
            }
            if let index = selectedBatchExpenses.firstIndex(where: { $0.id.lowercased() == row.id.lowercased() }) {
                var lines = selectedBatchExpenses
                if row.batchId?.lowercased() == selectedBatchId?.lowercased(), row.deletedAt == nil {
                    lines[index] = row
                } else {
                    lines.remove(at: index)
                }
                applySelectedBatchExpenses(lines)
            }
            if let batch {
                if let index = batches.firstIndex(where: { $0.id.lowercased() == batch.id.lowercased() }) { batches[index] = batch }
                if let index = reviewBatches.firstIndex(where: { $0.id.lowercased() == batch.id.lowercased() }) { reviewBatches[index] = batch }
                if let index = myBatches.firstIndex(where: { $0.id.lowercased() == batch.id.lowercased() }) { myBatches[index] = batch }
            }
            return ExpenseCorrectionSaveResult(receipt: receipt, refreshed: true)
        } catch {
            guard correctionIdentityMatches(companyId: command.content.companyId, actorId: command.actorId) else {
                throw ExpenseCorrectionError.accountChanged
            }
            // The immutable receipt is already proof. Failure to refresh is
            // reported separately; never resend a new correction to refresh.
            return ExpenseCorrectionSaveResult(receipt: receipt, refreshed: false)
        }
    }

    func loadExpenseCorrections(expenseId: String, companyId: String, actorId: String) async throws -> [ExpenseCorrectionDTO] {
        guard let repo = correctionRepository else { throw ExpenseCorrectionError.serviceUnavailable }
        guard correctionIdentityMatches(companyId: companyId, actorId: actorId) else { throw ExpenseCorrectionError.accountChanged }
        let rows = try await repo.fetchCorrections(expenseId: expenseId)
        guard correctionIdentityMatches(companyId: companyId, actorId: actorId) else { throw ExpenseCorrectionError.accountChanged }
        guard rows.allSatisfy({ $0.companyId.lowercased() == companyId.lowercased() && $0.expenseId.lowercased() == expenseId.lowercased() }) else {
            throw ExpenseCorrectionError.invalidReceipt
        }
        return rows
    }

    func reloadExpenseCorrectionBaseline(expenseId: String, companyId: String, actorId: String) async throws -> (ExpenseDTO, ExpenseBatchDTO?) {
        guard let repo = correctionRepository else { throw ExpenseCorrectionError.serviceUnavailable }
        guard correctionIdentityMatches(companyId: companyId, actorId: actorId) else { throw ExpenseCorrectionError.accountChanged }
        let row = try await repo.fetchOne(expenseId)
        guard correctionIdentityMatches(companyId: companyId, actorId: actorId) else { throw ExpenseCorrectionError.accountChanged }
        guard row.id.lowercased() == expenseId.lowercased(), row.companyId.lowercased() == companyId.lowercased() else {
            throw ExpenseCorrectionError.invalidReceipt
        }
        var batch: ExpenseBatchDTO?
        if let batchId = row.batchId {
            batch = try await repo.fetchBatch(batchId)
            guard correctionIdentityMatches(companyId: companyId, actorId: actorId) else { throw ExpenseCorrectionError.accountChanged }
            guard batch?.id.lowercased() == batchId.lowercased(), batch?.companyId.lowercased() == companyId.lowercased() else {
                throw ExpenseCorrectionError.invalidReceipt
            }
        }
        return (row, batch)
    }

    private func correctionIdentityMatches(companyId: String, actorId: String) -> Bool {
        if let current = correctionCurrentIdentity?() {
            guard current.companyId?.lowercased() == companyId.lowercased(),
                  current.userId?.lowercased() == actorId.lowercased() else { return false }
        }
        return storedCompanyId?.lowercased() == companyId.lowercased() && storedUserId?.lowercased() == actorId.lowercased()
    }

    // MARK: - CRUD

    /// Save one complete expense snapshot. The server returns the canonical
    /// row only after content, allocations, exception metadata, placement, and
    /// affected batch totals have all committed.
    @discardableResult
    func saveExpenseAtomically(_ command: ExpenseAtomicSaveCommand) async throws -> ExpenseDTO {
        guard let repo = repository else { throw ExpenseViewModelError.repositoryUnavailable }
        do {
            let updated = try await repo.saveAtomically(command)
            if let index = expenses.firstIndex(where: { $0.id == updated.id }) {
                expenses[index] = updated
            } else {
                expenses.insert(updated, at: 0)
            }
            self.error = nil
            return updated
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    /// Read back one expense after an ambiguous network result. This is used to
    /// distinguish a lost response from a write that never committed.
    func fetchExpense(_ expenseId: String) async -> ExpenseDTO? {
        guard let repo = repository else { return nil }
        do {
            let expense = try await repo.fetchOne(expenseId)
            if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                expenses[idx] = expense
            }
            self.error = nil
            return expense
        } catch {
            return nil
        }
    }

    /// Fetch expenses for a specific batch from the network (used by admin review)
    func fetchBatchExpenses(batchId: String) async -> [ExpenseDTO] {
        guard let repo = repository else { return [] }
        do {
            return try await repo.fetchBatchExpenses(batchId)
        } catch {
            self.error = "Failed to load batch expenses: \(error.localizedDescription)"
            return []
        }
    }

    func deleteExpense(_ expenseId: String) async {
        guard let repo = repository else { return }
        do {
            try await repo.softDelete(expenseId)
            expenses.removeAll { $0.id == expenseId }
            // Broadcast so every visible expense list refreshes — notably the
            // project expenses tab, which renders a separate cache and otherwise
            // keeps showing the deleted line until reopened.
            NotificationCenter.default.post(name: .opsExpensesDidChange, object: nil)
            ToastCenter.shared.present(Feedback.Expense.deleted)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Status Actions

    func approveExpense(_ expenseId: String, approvedBy: String) async {
        guard let repo = repository else { return }
        do {
            let updated = try await repo.approve(expenseId, approvedBy: approvedBy)
            if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                expenses[idx] = updated
            }
            // The saved status transition already queued its accounting work.
            ToastCenter.shared.present(Feedback.Expense.approved)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func rejectExpense(_ expenseId: String, rejectedBy: String, reason: String) async {
        guard let repo = repository else { return }
        do {
            let updated = try await repo.reject(expenseId, rejectedBy: rejectedBy, reason: reason)
            if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                expenses[idx] = updated
            }
            ToastCenter.shared.present(Feedback.Expense.rejected)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Categories

    func createCategory(companyId: String, name: String, icon: String?) async {
        guard let repo = repository else { return }
        let dto = CreateExpenseCategoryDTO(
            companyId: companyId,
            name: name,
            icon: icon,
            sortOrder: categories.count
        )
        do {
            let created = try await repo.createCategory(dto)
            categories.append(created)
            ToastCenter.shared.present(Feedback.Expense.categoryCreated)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleCategory(_ categoryId: String, isActive: Bool) async {
        guard let repo = repository else { return }
        do {
            try await repo.updateCategory(categoryId, name: nil, icon: nil, isActive: isActive)
            categories = try await repo.fetchCategories()
            ToastCenter.shared.present(Feedback.Expense.categoryUpdated)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Settings

    func saveSettings(_ dto: ExpenseSettingsDTO) async {
        guard let repo = repository else { return }
        do {
            try await repo.upsertSettings(dto)
            settings = dto
            settingsLoadState = .loaded
            self.error = nil
            ToastCenter.shared.present(Feedback.Expense.settingsSaved)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Project-scoped

    func loadExpensesForProject(_ projectId: String) async {
        guard let repo = repository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            expenses = try await repo.fetchByProject(projectId)
        } catch {
            self.error = error.localizedDescription
        }
    }


    // MARK: - Batch Console (four-bucket review)

    /// One console load: every company batch + every company line + settings,
    /// in parallel. The strip and the queue derive from the SAME two datasets
    /// so the numbers can never disagree with the list beneath them.
    func loadConsole() async {
        guard let repo = consoleRepository else { return }
        consoleLoadGeneration += 1
        let generation = consoleLoadGeneration
        let receiptVersion = approvalState.receiptVersion
        isLoading = true
        defer { isLoading = false }
        do {
            async let batchesTask = repo.fetchBatches()
            async let linesTask = repo.fetchAll()
            async let settingsTask = repo.fetchSettings()
            let (batches, lines, loadedSettings) = try await (batchesTask, linesTask, settingsTask)
            // A response started before an approval committed cannot put the
            // old review row back over its authoritative affected-row readback.
            guard generation == consoleLoadGeneration else { return }
            reviewBatches = batches
            approvalState.reconcile(batches, readStartedAt: receiptVersion)
            expenses = lines
            settings = loadedSettings
            settingsLoadState = .loaded
            approvalRefreshRequired = false
            self.error = nil
        } catch {
            guard generation == consoleLoadGeneration else { return }
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }

    /// Debounced realtime refresh. RealtimeProcessor posts `.expenseUpdated`
    /// for every `expenses` / `expense_batches` change — coalesce bursts
    /// (an approval flips a batch plus each of its lines) into one reload.
    @discardableResult
    func scheduleRealtimeRefresh() -> Task<Void, Never>? {
        // Own approval events can be one event per line. Preserve a refresh for
        // unrelated changes too, but do not refetch the whole company mid-run.
        if isApprovingBatches {
            needsConsoleRefreshAfterApproval = true
            return nil
        }
        realtimeRefreshTask?.cancel()
        realtimeRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            // The operation may have started while this debounce was asleep.
            // Keep one deferred reload instead of launching three full reads.
            if self.isApprovingBatches {
                self.needsConsoleRefreshAfterApproval = true
                return
            }
            await self.loadConsole()
        }
        return realtimeRefreshTask
    }

    /// Per-batch line counts + flag counts for the loaded company lines.
    var consoleLineStats: [String: ExpenseBatchLineStats] {
        ExpenseBuckets.lineStats(expenses)
    }

    /// The four working sets, each in its canonical order.
    var consoleSplit: ExpenseBucketSplit {
        ExpenseBuckets.split(reviewBatches, lineStats: consoleLineStats)
    }

    /// Everything the instrument strip shows.
    var consoleMetrics: ExpenseConsoleMetrics {
        ExpenseBuckets.computeMetrics(batches: reviewBatches, expenses: expenses, now: Date())
    }

    // MARK: - Batch actions (RPC-backed)

    /// Only the server RPC decides whether approval succeeded. A shared guard
    /// covers the entire awaited operation, including accounting and readback.
    @discardableResult
    func approveBatch(_ batch: ExpenseBatchDTO, silent: Bool = false) async -> Bool {
        guard let repo = batchApprovalRepository, canApproveBatch(batch) else { return false }
        claimBatchApprovals([batch])
        batchApprovalFailure = nil
        lastBatchApprovalResult = nil
        isApprovingBatches = true
        approvalBatchNumber = 1
        approvalBatchCount = 1
        hasSavedCurrentApproval = false
        defer { finishBatchApproval() }
        let saved = await persistBatchApproval(batch, repository: repo)
        let result = ExpenseBatchApprovalResult(
            savedCount: saved ? 1 : 0, requestedCount: 1, refreshRequired: approvalRefreshRequired)
        lastBatchApprovalResult = result
        if saved && !silent { presentApprovalResult(result) }
        if !saved { self.error = batchApprovalFailure }
        return saved
    }

    /// Each batch remains one atomic RPC. Deduplicate the frozen selection,
    /// skip flagged/already-approved rows, and stop at the first failed write.
    @discardableResult
    func approveBatches(_ batches: [ExpenseBatchDTO]) async -> Int {
        guard let repo = batchApprovalRepository, !isApprovingBatches else { return 0 }
        var seen: Set<ExpenseBatchApprovalState.Key> = []
        let lineStats = consoleLineStats
        let requested = batches.filter {
            seen.insert(ExpenseBatchApprovalState.Key($0)).inserted && canApproveBatch($0) && (lineStats[$0.id]?.flagged ?? 0) == 0
        }
        guard !requested.isEmpty else { return 0 }
        claimBatchApprovals(requested)
        batchApprovalFailure = nil
        lastBatchApprovalResult = nil
        isApprovingBatches = true
        approvalBatchCount = requested.count
        defer { finishBatchApproval() }
        var approvedCount = 0
        for batch in requested {
            approvalBatchNumber = approvedCount + 1
            hasSavedCurrentApproval = false
            guard await persistBatchApproval(batch, repository: repo) else { break }
            approvedCount += 1
        }
        let result = ExpenseBatchApprovalResult(
            savedCount: approvedCount, requestedCount: requested.count, refreshRequired: approvalRefreshRequired)
        lastBatchApprovalResult = result
        if approvedCount > 0 {
            // One result owns both partial success and refresh trouble; a
            // generic failure toast must not displace its saved/requested count.
            self.error = nil
            presentApprovalResult(result)
        } else {
            self.error = batchApprovalFailure
        }
        return approvedCount
    }

    private func claimBatchApprovals(_ batches: [ExpenseBatchDTO]) {
        ownedBatchApprovalClaims = approvalState.claim(batches)
    }

    private func finishBatchApproval() {
        approvalState.release(ownedBatchApprovalClaims)
        ownedBatchApprovalClaims.removeAll()
        isApprovingBatches = false
        hasSavedCurrentApproval = false
        if needsConsoleRefreshAfterApproval {
            needsConsoleRefreshAfterApproval = false
            scheduleRealtimeRefresh()
        }
    }

    private func persistBatchApproval(
        _ batch: ExpenseBatchDTO,
        repository repo: ExpenseBatchApprovalRepository
    ) async -> Bool {
        do {
            try await repo.approveBatchAtomic(batch.id)
        } catch {
            batchApprovalFailure = error.localizedDescription
            return false
        }

        // This is a receipt of the completed RPC, never an optimistic status.
        // Keep it even when a subsequent read fails, so retrying a stale detail
        // cannot submit the same decision or accounting work again.
        approvalState.recordAccepted(batch)
        hasSavedCurrentApproval = true
        consoleLoadGeneration += 1
        self.error = nil
        notifySubmitter(of: batch, notice: .approved)

        // Two affected-row reads replace the previous company-wide batches +
        // expenses + settings reload. Read independently so either successful
        // response can refresh its canonical cache after the decision is saved.
        async let batchRead = repo.fetchBatch(batch.id)
        async let lineRead = repo.fetchBatchExpenses(batch.id)
        do {
            let lines = try await lineRead
            expenses.removeAll { $0.batchId == batch.id }
            expenses.append(contentsOf: lines)
            if selectedBatchId == batch.id {
                batchLineLoadGeneration += 1
                applySelectedBatchExpenses(lines)
            }
        } catch {
            approvalRefreshRequired = true
        }
        do {
            let updated = try await batchRead
            if let index = reviewBatches.firstIndex(where: { $0.id == updated.id }) {
                reviewBatches[index] = updated
            } else {
                reviewBatches.append(updated)
            }
            if let index = batches.firstIndex(where: { $0.id == updated.id }) { batches[index] = updated }
            if let index = myBatches.firstIndex(where: { $0.id == updated.id }) { myBatches[index] = updated }
        } catch {
            approvalRefreshRequired = true
        }
        consoleLoadGeneration += 1

        // Provider delivery belongs to the durable database queue created by
        // the decision transaction; it never extends this client operation.
        return true
    }

    private func presentApprovalResult(_ result: ExpenseBatchApprovalResult) {
        if result.refreshRequired {
            ToastCenter.shared.present(Toast(
                label: result.toastLabel, tone: .warning,
                action: ToastAction(label: "REFRESH") { [weak self] in
                    Task { await self?.loadConsole() }
                }))
        } else if result.savedCount < result.requestedCount {
            ToastCenter.shared.present(Toast(label: result.toastLabel, tone: .warning))
        } else if result.requestedCount > 1 {
            ToastCenter.shared.present(Feedback.Batch.allApproved)
        } else {
            ToastCenter.shared.present(Feedback.Batch.approved)
        }
    }

    /// Record a payout — `mark_expense_batch_paid` stamps paid_at/paid_by and
    /// flips the batch's approved lines to `reimbursed` ("paid" in the app).
    /// The toast carries UNDO (mis-tap recovery, web parity).
    @discardableResult
    func markPaid(_ batch: ExpenseBatchDTO, silent: Bool = false) async -> Bool {
        guard let repo = repository else { return false }
        do {
            try await repo.markBatchPaid(batch.id)
            notifySubmitter(of: batch, notice: .paid)
            if !silent {
                ToastCenter.shared.present(Toast(
                    label: "// PAID OUT · \(batch.batchNumber)",
                    tone: .success,
                    action: ToastAction(label: "UNDO") { [weak self] in
                        Task { await self?.unmarkPaid(batch) }
                    }
                ))
                await loadConsole()
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Bulk payout — sequential RPCs, one summary toast (no bulk undo; each
    /// batch's detail keeps UNDO). Returns how many went through.
    @discardableResult
    func markPaidBatches(_ batches: [ExpenseBatchDTO]) async -> Int {
        var paidCount = 0
        for batch in batches {
            let ok = await markPaid(batch, silent: true)
            if !ok { break }
            paidCount += 1
        }
        if paidCount > 0 {
            ToastCenter.shared.present(Feedback.Batch.allPaid)
        }
        await loadConsole()
        return paidCount
    }

    /// Reverse a payout recording — clears paid_at/paid_by and returns the
    /// lines to `approved`. No notification (web parity).
    func unmarkPaid(_ batch: ExpenseBatchDTO) async {
        guard let repo = repository else { return }
        do {
            try await repo.unmarkBatchPaid(batch.id)
            ToastCenter.shared.present(Feedback.Batch.paidUndone)
            await loadConsole()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Early-clear one line while its envelope is still filling. The server
    /// approves the line, leaves the envelope open, recalculates, and
    /// notifies the submitter itself.
    func earlyClearLine(_ expenseId: String, batchId: String) async {
        guard let repo = repository else { return }
        do {
            try await repo.earlyClearLine(expenseId)
            ToastCenter.shared.present(Feedback.Batch.lineCleared)
            await loadBatchExpenses(batchId)
            await loadConsole()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Submitter notifications (batch vocabulary)

    /// Internal so the decision tests can drive each case directly — the
    /// decision -> RPC mapping is this path's entire contract.
    enum BatchNotice {
        case approved
        case sentBack(count: Int)
        case paid
    }

    /// In-app row + push to the batch's submitter. Skips self-notification
    /// (the acting approver's feedback is the toast).
    ///
    /// The rail row crosses `notify_expense_batch_decision`, which refuses a
    /// decision that is not already recorded on the batch row — so every caller
    /// must await its own status / paid_at / amendment write first (they all
    /// do). Copy, recipient, and deep link are server-side; the client only
    /// names the decision.
    ///
    /// Best-effort by design: the decision itself is already persisted, so a
    /// transport failure here must never fail the caller.
    ///
    /// - Returns: the dispatch task, or `nil` when nothing is dispatched.
    @discardableResult
    func notifySubmitter(of batch: ExpenseBatchDTO, notice: BatchNotice) -> Task<Void, Never>? {
        guard let submitterId = batch.submittedBy, !submitterId.isEmpty,
              let companyId = storedCompanyId, !companyId.isEmpty,
              submitterId != storedUserId else { return nil }
        let notifier = decisionNotifier
        let batchNumber = batch.batchNumber
        let batchId = batch.id
        return Task {
            let decision: String
            let sentBackCount: Int?
            switch notice {
            case .approved:
                decision = "approved"
                sentBackCount = nil
            case .sentBack(let count):
                decision = "sent_back"
                sentBackCount = count
            case .paid:
                decision = "paid"
                sentBackCount = nil
            }
            _ = try? await notifier.notifyExpenseBatchDecision(
                batchId: batchId, decision: decision, count: sentBackCount)
            // The companion push carries the rail row's own copy, so the
            // decision alone picks the row type to match.
            switch notice {
            case .approved:
                try? await OneSignalService.shared.notifyBatchApproved(userId: submitterId)
            case .sentBack:
                try? await OneSignalService.shared.notifyBatchSentBack(userId: submitterId)
            case .paid:
                try? await OneSignalService.shared.notifyBatchPaid(userId: submitterId)
            }
        }
    }

    func loadBatchExpenses(_ batchId: String) async {
        guard let repo = repository else { return }
        if selectedBatchId != batchId {
            applySelectedBatchExpenses([])
        }
        selectedBatchId = batchId
        batchLineLoadGeneration += 1
        let generation = batchLineLoadGeneration
        isLoading = true
        defer { isLoading = false }
        do {
            // Undecided lines lead, settled money follows, newest first
            // inside each group — the reviewer's eye lands on the work.
            let lines = try await repo.fetchBatchExpenses(batchId)
            guard selectedBatchId == batchId, generation == batchLineLoadGeneration else { return }
            applySelectedBatchExpenses(lines)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func applySelectedBatchExpenses(_ lines: [ExpenseDTO]) {
        selectedBatchExpenses = ExpenseBuckets.attentionOrdered(lines)
        flaggedExpenseIds = Set(selectedBatchExpenses.compactMap { $0.flaggedBy != nil ? $0.id : nil })
        flagComments = Dictionary(uniqueKeysWithValues:
            selectedBatchExpenses.compactMap { expense in
                guard let comment = expense.flagComment else { return nil }
                return (expense.id, comment)
            }
        )
    }

    func flagExpense(_ expenseId: String, comment: String, flaggedBy: String) async {
        guard let repo = repository else { return }
        do {
            let updated = try await repo.flagExpense(expenseId, flaggedBy: flaggedBy, comment: comment)
            flaggedExpenseIds.insert(expenseId)
            flagComments[expenseId] = comment
            if let idx = selectedBatchExpenses.firstIndex(where: { $0.id == expenseId }) {
                selectedBatchExpenses[idx] = updated
            }
            ToastCenter.shared.present(Feedback.Expense.flagged)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// `silent: true` suppresses the per-item toast — used by `unflagAllExpenses`
    /// which emits a single summary toast after the loop.
    func unflagExpense(_ expenseId: String, silent: Bool = false) async {
        guard let repo = repository else { return }
        do {
            let updated = try await repo.unflagExpense(expenseId)
            flaggedExpenseIds.remove(expenseId)
            flagComments.removeValue(forKey: expenseId)
            if let idx = selectedBatchExpenses.firstIndex(where: { $0.id == expenseId }) {
                selectedBatchExpenses[idx] = updated
            }
            if !silent {
                ToastCenter.shared.present(Feedback.Expense.flagCleared)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func unflagAllExpenses() async {
        let ids = Array(flaggedExpenseIds)
        for id in ids {
            await unflagExpense(id, silent: true)
        }
        if !ids.isEmpty {
            ToastCenter.shared.present(Feedback.Expense.flagCleared)
        }
    }

    func sendRevisions(batchId: String, batch: ExpenseBatchDTO, reviewedBy: String, reviewNotes: String?) async {
        guard let repo = repository else { return }
        do {
            let clean = selectedBatchExpenses.filter { !flaggedExpenseIds.contains($0.id) }
            let flagged = selectedBatchExpenses.filter { flaggedExpenseIds.contains($0.id) }

            for expense in clean {
                _ = try await repo.approve(expense.id, approvedBy: reviewedBy)
            }

            let cleanAmount = clean.reduce(0.0) { $0 + $1.amount }

            _ = try await repo.updateBatchStatus(
                batchId,
                status: ExpenseBatchStatus.partiallyApproved.rawValue,
                reviewedBy: reviewedBy,
                reviewNotes: reviewNotes,
                approvedAmount: cleanAmount
            )

            let amendmentNumber = (batch.amendmentNumber ?? 0) + 1
            let amendmentBatchNumber = "\(batch.batchNumber)-A\(amendmentNumber)"
            let flaggedTotal = flagged.reduce(0.0) { $0 + $1.amount }

            let amendmentDTO = CreateExpenseBatchDTO(
                companyId: batch.companyId,
                batchNumber: amendmentBatchNumber,
                periodStart: batch.periodStart,
                periodEnd: batch.periodEnd,
                status: ExpenseBatchStatus.rejected.rawValue,
                submittedBy: batch.submittedBy,
                totalAmount: flaggedTotal,
                parentBatchId: batchId,
                amendmentNumber: amendmentNumber
            )

            let amendmentBatch = try await repo.createBatch(amendmentDTO)

            let flaggedIds = flagged.map { $0.id }
            try await repo.assignExpensesToBatch(flaggedIds, batchId: amendmentBatch.id)

            for expense in flagged {
                let comment = flagComments[expense.id] ?? "Flagged for revision"
                _ = try await repo.reject(expense.id, rejectedBy: reviewedBy, reason: comment)
            }

            flaggedExpenseIds.removeAll()
            flagComments.removeAll()

            // Tell the submitter their flagged lines came back (in-app + push).
            notifySubmitter(of: batch, notice: .sentBack(count: flagged.count))

            ToastCenter.shared.present(Feedback.Batch.sentBack)
            await loadConsole()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Auto-Approve Rules

    func loadAutoApproveRules() async {
        guard let repo = repository else { return }
        do {
            autoApproveRules = try await repo.fetchAutoApproveRules()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createAutoApproveRule(ruleType: AutoApproveRuleType, threshold: Double, appliesToAll: Bool, memberIds: [String], createdBy: String) async {
        guard let repo = repository else { return }
        do {
            let dto = CreateAutoApproveRuleDTO(
                companyId: storedCompanyId ?? "",
                createdBy: createdBy,
                ruleType: ruleType.rawValue,
                thresholdAmount: threshold,
                appliesToAll: appliesToAll
            )
            let rule = try await repo.createAutoApproveRule(dto)
            if !appliesToAll && !memberIds.isEmpty {
                try await repo.setAutoApproveRuleMembers(rule.id, userIds: memberIds)
            }
            await loadAutoApproveRules()
            ToastCenter.shared.present(Feedback.Expense.ruleCreated)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleAutoApproveRule(_ ruleId: String, isActive: Bool) async {
        guard let repo = repository else { return }
        do {
            try await repo.updateAutoApproveRule(ruleId, isActive: isActive)
            await loadAutoApproveRules()
            ToastCenter.shared.present(Feedback.Expense.ruleUpdated)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteAutoApproveRule(_ ruleId: String) async {
        guard let repo = repository else { return }
        do {
            try await repo.deleteAutoApproveRule(ruleId)
            await loadAutoApproveRules()
            ToastCenter.shared.present(Feedback.Expense.ruleDeleted)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
