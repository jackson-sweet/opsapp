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
        ocrConfidence: Double?
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
            ocrRawData: ocrRawData,
            ocrConfidence: ocrConfidence
        )
        do {
            let created = try await repo.create(dto)
            expenses.insert(created, at: 0)
            return created
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func updateExpense(_ expenseId: String, fields: UpdateExpenseDTO) async {
        guard let repo = repository else { return }
        do {
            let updated = try await repo.update(expenseId, fields: fields)
            if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                expenses[idx] = updated
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
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Allocations

    func setAllocations(_ expenseId: String, allocations: [CreateExpenseAllocationDTO]) async {
        guard let repo = repository else { return }
        do {
            try await repo.setAllocations(expenseId, allocations: allocations)
            // Refresh the expense to get updated allocations
            let updated = try await repo.fetchOne(expenseId)
            if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                expenses[idx] = updated
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
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleCategory(_ categoryId: String, isActive: Bool) async {
        guard let repo = repository else { return }
        do {
            try await repo.updateCategory(categoryId, name: nil, icon: nil, isActive: isActive)
            categories = try await repo.fetchCategories()
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


    // MARK: - Invoice Review

    func loadBatchesForReview() async {
        guard let repo = repository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            reviewBatches = try await repo.fetchBatches()
        } catch {
            self.error = error.localizedDescription
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
        } catch {
            self.error = error.localizedDescription
        }
    }

    func unflagExpense(_ expenseId: String) async {
        guard let repo = repository else { return }
        do {
            let updated = try await repo.unflagExpense(expenseId)
            flaggedExpenseIds.remove(expenseId)
            flagComments.removeValue(forKey: expenseId)
            if let idx = selectedBatchExpenses.firstIndex(where: { $0.id == expenseId }) {
                selectedBatchExpenses[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func unflagAllExpenses() async {
        let ids = Array(flaggedExpenseIds)
        for id in ids {
            await unflagExpense(id)
        }
    }

    func approveInvoice(_ batchId: String, reviewedBy: String) async {
        guard let repo = repository else { return }
        do {
            let approvedAmount = selectedBatchExpenses.reduce(0.0) { $0 + $1.amount }
            _ = try await repo.updateBatchStatus(
                batchId,
                status: ExpenseBatchStatus.approved.rawValue,
                reviewedBy: reviewedBy,
                approvedAmount: approvedAmount
            )
            for expense in selectedBatchExpenses {
                _ = try await repo.approve(expense.id, approvedBy: reviewedBy)
                await repo.triggerAccountingSync(expenseId: expense.id)
            }

            // Notify the crew member who submitted the invoice
            let matchingBatch = reviewBatches.first(where: { $0.id == batchId })
            if let submittedBy = matchingBatch?.submittedBy,
               let companyId = storedCompanyId {
                let capturedNotificationRepo = notificationRepo
                let capturedBatchNumber = matchingBatch?.batchNumber ?? batchId
                Task {
                    // Create in-app notification
                    let dto = NotificationRepository.CreateNotificationDTO(
                        userId: submittedBy,
                        companyId: companyId,
                        type: "invoice_approved",
                        title: "Invoice Approved",
                        body: "Your invoice \(capturedBatchNumber) has been approved",
                        projectId: nil,
                        noteId: nil,
                        expenseId: nil,
                        batchId: batchId,
                        deepLinkType: "invoice_detail"
                    )
                    try? await capturedNotificationRepo.createNotification(dto)
                    // Send push
                    try? await OneSignalService.shared.notifyInvoiceApproved(
                        userId: submittedBy,
                        batchNumber: capturedBatchNumber,
                        batchId: batchId
                    )
                }

                // Schedule local notification for immediate feedback
                NotificationManager.shared.scheduleExpenseNotification(
                    category: .invoiceApproved,
                    title: "Invoice Approved",
                    body: "Your invoice \(capturedBatchNumber) has been approved",
                    batchId: batchId
                )
            }

            await loadBatchesForReview()
        } catch {
            self.error = error.localizedDescription
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

            // Notify the crew member about revisions needed
            if let submittedBy = batch.submittedBy,
               let companyId = storedCompanyId {
                let capturedNotificationRepo = notificationRepo
                let capturedBatchNumber = batch.batchNumber
                let flaggedCount = flagged.count
                Task {
                    // Create in-app notification
                    let dto = NotificationRepository.CreateNotificationDTO(
                        userId: submittedBy,
                        companyId: companyId,
                        type: "invoice_revisions",
                        title: "Invoice Revisions Needed",
                        body: "\(flaggedCount) expense\(flaggedCount == 1 ? "" : "s") on \(capturedBatchNumber) need\(flaggedCount == 1 ? "s" : "") revision",
                        projectId: nil,
                        noteId: nil,
                        expenseId: nil,
                        batchId: batchId,
                        deepLinkType: "invoice_detail"
                    )
                    try? await capturedNotificationRepo.createNotification(dto)
                    // Send push
                    try? await OneSignalService.shared.notifyInvoiceRevisions(
                        userId: submittedBy,
                        batchNumber: capturedBatchNumber,
                        batchId: batchId,
                        flaggedCount: flaggedCount
                    )
                }

                // Schedule local notification for immediate feedback
                NotificationManager.shared.scheduleExpenseNotification(
                    category: .invoiceRevisions,
                    title: "Invoice Revisions Needed",
                    body: "\(flaggedCount) expense\(flaggedCount == 1 ? "" : "s") on \(capturedBatchNumber) need\(flaggedCount == 1 ? "s" : "") revision",
                    batchId: batchId
                )
            }

            await loadBatchesForReview()
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
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleAutoApproveRule(_ ruleId: String, isActive: Bool) async {
        guard let repo = repository else { return }
        do {
            try await repo.updateAutoApproveRule(ruleId, isActive: isActive)
            await loadAutoApproveRules()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteAutoApproveRule(_ ruleId: String) async {
        guard let repo = repository else { return }
        do {
            try await repo.deleteAutoApproveRule(ruleId)
            await loadAutoApproveRules()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
