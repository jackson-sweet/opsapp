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

    private var repository: ExpenseRepository?
    private let ocrService: ExpenseOCRServiceProtocol = AppleVisionOCRService()

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
}
