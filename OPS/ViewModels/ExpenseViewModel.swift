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
        _ = await (expensesTask, categoriesTask, settingsTask, batchesTask)
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

    /// Reset an expense's batch assignment (used when editing a submitted expense)
    func resetExpenseBatch(_ expenseId: String) async {
        guard let repo = repository else { return }
        do {
            try await repo.clearBatchId(expenseId)
            // Refresh the expense in our local list
            let updated = try await repo.fetchOne(expenseId)
            if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                expenses[idx] = updated
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

    /// Submit a single expense for review.
    ///
    /// - If the expense's amount is below `expense_settings.auto_approve_threshold`,
    ///   it auto-approves on the spot (status -> approved, accounting sync fires).
    ///   No batch is attached and no review notification is sent — matches the
    ///   pre-existing per-expense auto-approve semantics.
    /// - Otherwise: the expense is attached to the user's open batch for the
    ///   appropriate scope (per `review_frequency`), status -> submitted, batch
    ///   total recalculated, and approvers (anyone with `expenses.approve`) are
    ///   notified. Always-bundle: every above-threshold submission ends up in
    ///   a batch — no orphans.
    func submitExpense(_ expenseId: String) async {
        guard let repo = repository,
              let companyId = storedCompanyId,
              let expense = expenses.first(where: { $0.id == expenseId }) else { return }

        // Auto-approve path (per-expense, threshold-based) — preserved.
        if let threshold = settings?.autoApproveThreshold,
           expense.amount < threshold {
            do {
                let updated = try await repo.approve(expenseId, approvedBy: "auto")
                if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                    expenses[idx] = updated
                }
                Task { await repo.triggerAccountingSync(expenseId: expenseId) }
            } catch {
                self.error = error.localizedDescription
            }
            return
        }

        // Always-bundle path.
        do {
            let frequency = settings?.reviewFrequency ?? "monthly"
            let scopeProjectId: String? = (frequency == "per_job")
                ? expense.allocations?.first?.projectId
                : nil

            let period = ExpenseBatchPeriod.forExpense(
                expenseDate: expense.expenseDate,
                createdAt: expense.createdAt,
                reviewFrequency: frequency
            )

            let batch = try await repo.getOrCreateOpenBatch(
                submittedBy: expense.submittedBy,
                periodStart: period.start,
                periodEnd: period.end,
                scopeProjectId: scopeProjectId
            )

            try await repo.assignExpensesToBatch([expenseId], batchId: batch.id)
            let updated = try await repo.updateStatus(expenseId, status: .submitted)
            if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                expenses[idx] = updated
            }

            try? await repo.recalculateBatchTotal(batch.id)

            // Fire-and-forget: notify approvers via permission lookup.
            let capturedCompanyId = companyId
            let capturedBatch = batch
            let capturedExpense = updated
            let capturedSubmitterId = storedUserId ?? expense.submittedBy
            let capturedSubmitterName = storedUserName ?? "A crew member"
            let capturedNotificationRepo = notificationRepo
            Task {
                await Self.dispatchExpenseSubmittedNotifications(
                    companyId: capturedCompanyId,
                    submitterId: capturedSubmitterId,
                    submitterName: capturedSubmitterName,
                    batch: capturedBatch,
                    expense: capturedExpense,
                    notificationRepo: capturedNotificationRepo
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Static helper: posts in-app + push notifications to everyone in the
    /// company with `expenses.approve`, excluding the submitter. Fire-and-forget
    /// at the call site; failures are logged but don't propagate.
    private static func dispatchExpenseSubmittedNotifications(
        companyId: String,
        submitterId: String,
        submitterName: String,
        batch: ExpenseBatchDTO,
        expense: ExpenseDTO,
        notificationRepo: NotificationRepository
    ) async {
        let approverIds = (try? await RecipientLookupService.usersWithPermission(
            companyId: companyId,
            permission: "expenses.approve"
        )) ?? []
        let recipients = approverIds.filter { $0 != submitterId.lowercased() }
        guard !recipients.isEmpty else { return }

        let merchant = expense.merchantName?.isEmpty == false ? expense.merchantName! : "Expense"
        let amountStr = String(format: "$%.2f", expense.amount)
        let title = "Expense Submitted"
        let body = "\(submitterName) submitted \(merchant) (\(amountStr)) for review"

        for recipient in recipients {
            let dto = NotificationRepository.CreateNotificationDTO(
                userId: recipient,
                companyId: companyId,
                type: "expense_submitted",
                title: title,
                body: body,
                projectId: nil,
                noteId: nil,
                expenseId: expense.id,
                batchId: batch.id,
                deepLinkType: "expense"
            )
            try? await notificationRepo.createNotification(dto)
        }

        try? await OneSignalService.shared.notifyExpenseSubmitted(
            adminUserIds: recipients,
            submitterName: submitterName,
            batchNumber: batch.batchNumber,
            batchId: batch.id
        )
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

    // MARK: - Invoice Bundling

    func bundleInvoice(userId: String, userName: String, periodStart: Date, periodEnd: Date, selectedExpenseIds: Set<String>? = nil) async throws {
        guard let repo = repository else { return }
        // Use date-only format (YYYY-MM-DD) to match the expense_date column type in Postgres
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let startStr = dateFmt.string(from: periodStart)
        let endStr = dateFmt.string(from: periodEnd)

        var unbatched = try await repo.fetchUnbatchedExpenses(
            userId: userId, periodStart: startStr, periodEnd: endStr
        )

        // Filter to only selected expenses if a selection was provided
        if let selectedIds = selectedExpenseIds {
            unbatched = unbatched.filter { selectedIds.contains($0.id) }
        }

        guard !unbatched.isEmpty else { return }

        let total = unbatched.reduce(0.0) { $0 + $1.amount }

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        let monthKey = monthFormatter.string(from: periodStart)
        let lastName = userName.split(separator: " ").last.map(String.init) ?? userName
        let batchNumber = "EXP-\(monthKey)-\(lastName.uppercased())"

        let createDTO = CreateExpenseBatchDTO(
            companyId: unbatched[0].companyId,
            batchNumber: batchNumber,
            periodStart: startStr,
            periodEnd: endStr,
            status: ExpenseBatchStatus.submitted.rawValue,
            submittedBy: userId,
            totalAmount: total,
            parentBatchId: nil,
            amendmentNumber: nil
        )

        let batch = try await repo.createBatch(createDTO)
        let expenseIds = unbatched.map { $0.id }
        try await repo.assignExpensesToBatch(expenseIds, batchId: batch.id)

        // Check auto-approve
        let shouldAutoApprove = try await repo.checkAutoApproveInvoice(userId: userId, totalAmount: total)
        if shouldAutoApprove {
            _ = try await repo.updateBatchStatus(
                batch.id,
                status: ExpenseBatchStatus.autoApproved.rawValue,
                reviewedBy: nil,
                reviewNotes: "Auto-approved by rule"
            )
            for expense in unbatched {
                _ = try await repo.approve(expense.id, approvedBy: "auto")
                await repo.triggerAccountingSync(expenseId: expense.id)
            }
        } else {
            // Mark each expense as "submitted" so the UI reflects the correct state
            for expense in unbatched {
                _ = try await repo.updateStatus(expense.id, status: .submitted)
            }
        }

        // Fire-and-forget: notify everyone with expenses.approve permission.
        // NEVER filter by users.role — gate by granular permission so custom
        // roles and per-user overrides are honored.
        let capturedCompanyId = unbatched[0].companyId
        let capturedBatchId = batch.id
        let capturedBatchNumber = batchNumber
        let capturedUserName = userName
        let capturedSubmitterId = userId
        let capturedNotificationRepo = notificationRepo
        Task {
            let approverIds = (try? await RecipientLookupService.usersWithPermission(
                companyId: capturedCompanyId,
                permission: "expenses.approve"
            )) ?? []
            let recipients = approverIds.filter { $0 != capturedSubmitterId }

            for recipient in recipients {
                let dto = NotificationRepository.CreateNotificationDTO(
                    userId: recipient,
                    companyId: capturedCompanyId,
                    type: "expense_submitted",
                    title: "Invoice Submitted",
                    body: "\(capturedUserName) submitted invoice \(capturedBatchNumber) for review",
                    projectId: nil,
                    noteId: nil,
                    expenseId: nil,
                    batchId: capturedBatchId,
                    deepLinkType: "invoice_detail"
                )
                try? await capturedNotificationRepo.createNotification(dto)
            }

            if !recipients.isEmpty {
                try? await OneSignalService.shared.notifyExpenseSubmitted(
                    adminUserIds: recipients,
                    submitterName: capturedUserName,
                    batchNumber: capturedBatchNumber,
                    batchId: capturedBatchId
                )
            }
        }

        await loadBatches()
        await loadExpenses()
    }

    // MARK: - Orphan Recovery

    /// Count of expenses stuck in the orphan state for this company.
    /// Drives the orphan-recovery banner in ExpensesListView.
    @Published var orphanCount: Int = 0

    func loadOrphanCount() async {
        guard let repo = repository else { return }
        do {
            let orphans = try await repo.fetchOrphanExpenses()
            orphanCount = orphans.count
        } catch {
            // Silently swallow — this is observability, not a user action.
            // Refreshing the screen will retry.
            orphanCount = 0
        }
    }

    /// Re-bundle every orphan expense into the appropriate open batch and
    /// notify approvers once per resulting batch. Idempotent: re-running is
    /// safe; already-bundled expenses are filtered out by fetchOrphanExpenses.
    func recoverOrphans() async {
        guard let repo = repository,
              let companyId = storedCompanyId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let orphans = try await repo.fetchOrphanExpenses()
            guard !orphans.isEmpty else {
                orphanCount = 0
                return
            }

            let frequency = settings?.reviewFrequency ?? "monthly"

            // Resolve batches per orphan, group expense IDs by batch so we
            // assign + recompute once per batch.
            var attachmentsByBatch: [String: (batch: ExpenseBatchDTO, expenses: [ExpenseDTO])] = [:]
            for expense in orphans {
                let scopeProjectId: String? = (frequency == "per_job")
                    ? expense.allocations?.first?.projectId
                    : nil
                let period = ExpenseBatchPeriod.forExpense(
                    expenseDate: expense.expenseDate,
                    createdAt: expense.createdAt,
                    reviewFrequency: frequency
                )
                let batch = try await repo.getOrCreateOpenBatch(
                    submittedBy: expense.submittedBy,
                    periodStart: period.start,
                    periodEnd: period.end,
                    scopeProjectId: scopeProjectId
                )
                var bucket = attachmentsByBatch[batch.id] ?? (batch: batch, expenses: [])
                bucket.expenses.append(expense)
                attachmentsByBatch[batch.id] = bucket
            }

            for (_, bucket) in attachmentsByBatch {
                let ids = bucket.expenses.map { $0.id }
                try await repo.assignExpensesToBatch(ids, batchId: bucket.batch.id)
                try? await repo.recalculateBatchTotal(bucket.batch.id)

                // One in-app + push notification per batch (not per expense)
                // so admins aren't spammed during recovery.
                let firstExpense = bucket.expenses.first!
                let submitterId = firstExpense.submittedBy.lowercased()
                let submitterName = storedUserName ?? "A crew member"
                let captured = (
                    cid: companyId,
                    sid: submitterId,
                    sname: submitterName,
                    batch: bucket.batch,
                    expense: firstExpense
                )
                let capturedNotificationRepo = notificationRepo
                Task {
                    await Self.dispatchExpenseSubmittedNotifications(
                        companyId: captured.cid,
                        submitterId: captured.sid,
                        submitterName: captured.sname,
                        batch: captured.batch,
                        expense: captured.expense,
                        notificationRepo: capturedNotificationRepo
                    )
                }
            }

            await loadOrphanCount()
            await loadBatchesForReview()
            await loadExpenses()
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
