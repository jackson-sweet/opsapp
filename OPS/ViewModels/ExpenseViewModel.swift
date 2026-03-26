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

    func setup(companyId: String) {
        storedCompanyId = companyId
        repository = ExpenseRepository(companyId: companyId)
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

    func submitExpense(_ expenseId: String) async {
        guard let repo = repository else { return }
        do {
            // Check auto-approve threshold
            if let settings = settings,
               let threshold = settings.autoApproveThreshold,
               let expense = expenses.first(where: { $0.id == expenseId }),
               expense.amount < threshold {
                // Auto-approve
                let updated = try await repo.approve(expenseId, approvedBy: "auto")
                if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                    expenses[idx] = updated
                }
                // Fire-and-forget: trigger accounting sync for auto-approved expense
                Task { await repo.triggerAccountingSync(expenseId: expenseId) }
            } else {
                let updated = try await repo.updateStatus(expenseId, status: .submitted)
                if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                    expenses[idx] = updated
                }
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

    // MARK: - Invoice Bundling

    func bundleInvoice(userId: String, userName: String, periodStart: Date, periodEnd: Date) async throws {
        guard let repo = repository else { return }
        let iso = ISO8601DateFormatter()
        let startStr = iso.string(from: periodStart)
        let endStr = iso.string(from: periodEnd)

        let unbatched = try await repo.fetchUnbatchedExpenses(
            userId: userId, periodStart: startStr, periodEnd: endStr
        )
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
        }

        // Fire-and-forget: create in-app notification + push for admin/office users
        let capturedCompanyId = unbatched[0].companyId
        let capturedBatchId = batch.id
        let capturedBatchNumber = batchNumber
        let capturedUserName = userName
        let capturedNotificationRepo = notificationRepo
        Task {
            // Find admin/office users to notify
            struct UserIdRow: Codable { let id: String }
            let admins = (try? await SupabaseService.shared.client
                .from("users")
                .select("id")
                .eq("company_id", value: capturedCompanyId)
                .in("role", values: ["admin", "owner", "office"])
                .execute()
                .value as [UserIdRow]) ?? []

            // Create in-app notification for each admin
            for admin in admins {
                let dto = NotificationRepository.CreateNotificationDTO(
                    userId: admin.id,
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

            // Send push to admins
            let adminIds = admins.map(\.id)
            if !adminIds.isEmpty {
                try? await OneSignalService.shared.notifyExpenseSubmitted(
                    adminUserIds: adminIds,
                    submitterName: capturedUserName,
                    batchNumber: capturedBatchNumber,
                    batchId: capturedBatchId
                )
            }
        }

        await loadBatches()
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
