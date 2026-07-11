//
//  ExpenseViewModel.swift
//  OPS
//
//  ViewModel for Expenses — manages expense list, filtering, categories, batches, and approval actions.
//

import SwiftUI

@MainActor
class ExpenseViewModel: ObservableObject {
    @Published var expenses: [ExpenseDTO] = []
    @Published var categories: [ExpenseCategoryDTO] = []
    @Published var batches: [ExpenseBatchDTO] = []
    /// The current user's own batches — drives the My Expenses filling-total
    /// strip and each card's envelope-phase line.
    @Published var myBatches: [ExpenseBatchDTO] = []
    @Published var settings: ExpenseSettingsDTO? = nil
    @Published var selectedFilter: ExpenseFilter = .all
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var autoApproveRules: [AutoApproveRuleDTO] = []
    @Published var reviewBatches: [ExpenseBatchDTO] = []
    @Published var selectedBatchExpenses: [ExpenseDTO] = []
    @Published var flaggedExpenseIds: Set<String> = []
    @Published var flagComments: [String: String] = [:]

    private var repository: ExpenseRepository?
    private var storedCompanyId: String?
    private var storedUserId: String?
    private var storedUserName: String?
    private let ocrService: ExpenseOCRServiceProtocol = AppleVisionOCRService()
    private let notificationRepo = NotificationRepository()
    /// Debounce for realtime-driven console reloads (`.expenseUpdated` bursts).
    private var realtimeRefreshTask: Task<Void, Never>?

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
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let isoFull = ISO8601DateFormatter()

        // Parse date for each expense, group by month key
        var monthBuckets: [String: (label: String, expenses: [ExpenseDTO])] = [:]
        for expense in source {
            let dateString = expense.expenseDate ?? expense.createdAt
            var date: Date?
            date = iso.date(from: dateString)
            if date == nil { date = isoFull.date(from: dateString) }
            let resolvedDate = date ?? Date()

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
                ProjectExpenseGroup(id: projectId, expenses: projectDict[projectId]!)
            }

            return ExpenseMonthGroup(
                id: key,
                monthLabel: bucket.label,
                projectGroups: projectGroups,
                unallocated: unallocated
            )
        }
    }

    func setup(companyId: String, currentUserId: String? = nil, currentUserName: String? = nil) {
        storedCompanyId = companyId
        storedUserId = currentUserId
        storedUserName = currentUserName
        repository = ExpenseRepository(companyId: companyId)
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

    func loadSettings() async {
        guard let repo = repository else { return }
        do {
            settings = try await repo.fetchSettings()
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }

    func loadAll() async {
        async let expensesTask: () = loadExpenses()
        async let categoriesTask: () = loadCategories()
        async let settingsTask: () = loadSettings()
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

    // MARK: - CRUD

    func createExpense(
        companyId: String,
        submittedBy: String,
        categoryId: String?,
        merchantName: String?,
        description: String?,
        amount: Double,
        taxAmount: Double?,
        currency: String?,
        expenseDate: String?,
        paymentMethod: String?,
        receiptImageUrl: String?,
        receiptThumbnailUrl: String?,
        ocrRawData: [String: String]?,
        ocrConfidence: Double?,
        receiptMissingReason: String? = nil,
        receiptMissingNote: String? = nil,
        projectMissingReason: String? = nil,
        projectMissingNote: String? = nil
    ) async -> ExpenseDTO? {
        guard let repo = repository else { return nil }
        let dto = CreateExpenseDTO(
            companyId: companyId,
            submittedBy: submittedBy,
            status: "draft",
            categoryId: categoryId,
            merchantName: merchantName,
            description: description,
            amount: amount,
            taxAmount: taxAmount,
            currency: currency,
            expenseDate: expenseDate,
            paymentMethod: paymentMethod,
            receiptImageUrl: receiptImageUrl,
            receiptThumbnailUrl: receiptThumbnailUrl,
            receiptMissingReason: receiptMissingReason,
            receiptMissingNote: receiptMissingNote,
            projectMissingReason: projectMissingReason,
            projectMissingNote: projectMissingNote,
            ocrRawData: ocrRawData,
            ocrConfidence: ocrConfidence
        )
        do {
            let created = try await repo.create(dto)
            expenses.insert(created, at: 0)
            ToastCenter.shared.present(Feedback.Expense.saved)
            return created
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// `silent: true` suppresses the success toast — use for background
    /// follow-up writes (e.g. receipt URL after upload) that are invisible to
    /// the user as a distinct save action.
    func updateExpense(_ expenseId: String, fields: UpdateExpenseDTO, silent: Bool = false) async {
        guard let repo = repository else { return }
        do {
            let updated = try await repo.update(expenseId, fields: fields)
            if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                expenses[idx] = updated
            }
            if !silent {
                ToastCenter.shared.present(Feedback.Expense.changesSaved)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Re-file + recompute totals after editing a line that is already in an
    /// envelope. Clearing batch_id makes the server `place_expense` trigger
    /// re-file it by its (possibly changed) date and recompute the destination
    /// envelope total; the previous envelope is recomputed too if the line
    /// moved. The line keeps its status — no revert to draft, no manual resubmit.
    func refileEditedExpense(_ expenseId: String, previousBatchId: String?) async {
        guard let repo = repository else { return }
        do {
            try await repo.clearBatchId(expenseId)            // → trigger re-files + recalcs destination
            let updated = try await repo.fetchOne(expenseId)
            if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                expenses[idx] = updated
            }
            if let prev = previousBatchId, prev != updated.batchId {
                _ = try? await repo.recalculateBatchTotal(prev)   // old envelope lost a line
            }
            ToastCenter.shared.present(Feedback.Expense.changesSaved)
        } catch {
            self.error = error.localizedDescription
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

    /// Mark a completed expense as submitted. The server `place_expense` trigger
    /// files it into the right envelope by date; the daily sweep notifies the
    /// office once per envelope when it sends, and auto-clears under-threshold
    /// lines. The client no longer batches, notifies per-expense, or
    /// auto-approves — the server is authoritative.
    func submitExpense(_ expenseId: String) async {
        guard let repo = repository else { return }
        do {
            let updated = try await repo.updateStatus(expenseId, status: .submitted)
            if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                expenses[idx] = updated
            }
            ToastCenter.shared.present(Feedback.Expense.submitted)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func approveExpense(_ expenseId: String, approvedBy: String) async {
        guard let repo = repository else { return }
        do {
            let updated = try await repo.approve(expenseId, approvedBy: approvedBy)
            if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                expenses[idx] = updated
            }
            // Fire-and-forget: trigger accounting sync if company has a connected provider
            Task { await repo.triggerAccountingSync(expenseId: expenseId) }
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

    // MARK: - Allocations

    /// `silent: true` suppresses the success toast — use when allocation
    /// writes are part of a larger save flow that already toasts its outcome.
    func setAllocations(_ expenseId: String, allocations: [CreateExpenseAllocationDTO], silent: Bool = false) async {
        guard let repo = repository else { return }
        do {
            try await repo.setAllocations(expenseId, allocations: allocations)
            // Refresh the expense to get updated allocations
            let updated = try await repo.fetchOne(expenseId)
            if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                expenses[idx] = updated
            }
            if !silent {
                ToastCenter.shared.present(Feedback.Expense.allocationsSaved)
            }
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
        guard let repo = repository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let batchesTask = repo.fetchBatches()
            async let linesTask = repo.fetchAll()
            async let settingsTask = repo.fetchSettings()
            let (batches, lines, loadedSettings) = try await (batchesTask, linesTask, settingsTask)
            reviewBatches = batches
            expenses = lines
            settings = loadedSettings
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }

    /// Debounced realtime refresh. RealtimeProcessor posts `.expenseUpdated`
    /// for every `expenses` / `expense_batches` change — coalesce bursts
    /// (an approval flips a batch plus each of its lines) into one reload.
    func scheduleRealtimeRefresh() {
        realtimeRefreshTask?.cancel()
        realtimeRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.loadConsole()
        }
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

    /// Atomic whole-batch approve — `approve_expense_batch` sets the batch and
    /// its non-rejected lines approved and recalculates in one transaction,
    /// then accounting sync fires best-effort per approved line (web parity).
    /// `silent` suppresses the per-batch toast for bulk runs.
    @discardableResult
    func approveBatch(_ batch: ExpenseBatchDTO, silent: Bool = false) async -> Bool {
        guard let repo = repository else { return false }
        do {
            try await repo.approveBatchAtomic(batch.id)
            let lines = (try? await repo.fetchBatchExpenses(batch.id)) ?? []
            for line in lines where ExpenseStatus(rawValue: line.status) == .approved {
                await repo.triggerAccountingSync(expenseId: line.id)
            }
            notifySubmitter(of: batch, notice: .approved)
            if !silent {
                ToastCenter.shared.present(Feedback.Batch.approved)
                await loadConsole()
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Bulk approve — sequential atomic RPCs (each batch approves whole or
    /// not at all). Stops on the first failure; everything already approved
    /// stays approved. Returns how many went through.
    @discardableResult
    func approveBatches(_ batches: [ExpenseBatchDTO]) async -> Int {
        var approvedCount = 0
        for batch in batches {
            let ok = await approveBatch(batch, silent: true)
            if !ok { break }
            approvedCount += 1
        }
        if approvedCount > 0 {
            ToastCenter.shared.present(Feedback.Batch.allApproved)
        }
        await loadConsole()
        return approvedCount
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

    private enum BatchNotice {
        case approved
        case sentBack(count: Int)
        case paid
    }

    /// In-app row + push to the batch's submitter. Skips self-notification
    /// (the acting approver's feedback is the toast).
    private func notifySubmitter(of batch: ExpenseBatchDTO, notice: BatchNotice) {
        guard let submitterId = batch.submittedBy, !submitterId.isEmpty,
              let companyId = storedCompanyId, !companyId.isEmpty,
              submitterId != storedUserId else { return }
        let capturedRepo = notificationRepo
        let batchNumber = batch.batchNumber
        let batchId = batch.id
        Task {
            let type: String
            let title: String
            let body: String
            switch notice {
            case .approved:
                type = "expense_approved"
                title = "Expenses Approved"
                body = "Your batch \(batchNumber) was approved"
            case .sentBack(let count):
                type = "expense_rejected"
                title = "Expenses Sent Back"
                body = "\(count) expense\(count == 1 ? "" : "s") on \(batchNumber) need\(count == 1 ? "s" : "") fixes"
            case .paid:
                type = "expense_paid"
                title = "Expenses Paid Out"
                body = "Your expense batch \(batchNumber) has been paid out"
            }
            let dto = NotificationRepository.CreateNotificationDTO(
                userId: submitterId,
                companyId: companyId,
                type: type,
                title: title,
                body: body,
                batchId: batchId,
                deepLinkType: "expense"
            )
            try? await capturedRepo.createNotification(dto)
            switch notice {
            case .approved:
                try? await OneSignalService.shared.notifyBatchApproved(
                    userId: submitterId, batchNumber: batchNumber, batchId: batchId)
            case .sentBack(let count):
                try? await OneSignalService.shared.notifyBatchSentBack(
                    userId: submitterId, batchNumber: batchNumber, batchId: batchId, flaggedCount: count)
            case .paid:
                try? await OneSignalService.shared.notifyBatchPaid(
                    userId: submitterId, batchNumber: batchNumber, batchId: batchId)
            }
        }
    }

    func loadBatchExpenses(_ batchId: String) async {
        guard let repo = repository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            selectedBatchExpenses = try await repo.fetchBatchExpenses(batchId)
            flaggedExpenseIds = Set(selectedBatchExpenses.compactMap { $0.flaggedBy != nil ? $0.id : nil })
            flagComments = Dictionary(uniqueKeysWithValues:
                selectedBatchExpenses.compactMap { expense in
                    guard let comment = expense.flagComment else { return nil }
                    return (expense.id, comment)
                }
            )
        } catch {
            self.error = error.localizedDescription
        }
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
                await repo.triggerAccountingSync(expenseId: expense.id)
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
