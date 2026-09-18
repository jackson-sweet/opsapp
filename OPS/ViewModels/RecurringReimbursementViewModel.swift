//
//  RecurringReimbursementViewModel.swift
//  OPS
//
//  One company's recurring reimbursements and the commands that change them.
//  Owned by each surface that manages them (batch review, expense settings,
//  the line sheet) and reloaded on the expense signals, so every surface shows
//  the database's current truth.
//
//  Every command states its outcome once, as a toast, and broadcasts
//  `.opsExpensesDidChange` so batch totals and line lists refresh — the
//  database moved money, not just this record.
//

import Foundation
import SwiftUI
import Supabase

@MainActor
final class RecurringReimbursementViewModel: ObservableObject {

    /// The command in flight. One at a time: every command serializes on the
    /// company's expense lock server-side anyway.
    enum Command: Equatable {
        case create
        case update(String)
        case end(String)
        case delete(String)
        case skip(String)
        case restore(String)
    }

    /// What a command came to. A refusal has already been told to the operator.
    enum Outcome: Equatable {
        case done
        case refused(ExpenseRecurring.Refusal)
        /// Nothing was sent — another command was already running.
        case ignored

        /// The form the operator is looking at no longer matches the database:
        /// close it so reopening shows the current truth.
        var invalidatesForm: Bool {
            switch self {
            case .refused(.changed), .refused(.removed): return true
            default: return false
            }
        }
    }

    @Published private(set) var snapshot: RecurringReimbursementsSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    @Published private(set) var inFlight: Command?

    private let makeRepository: (String) -> RecurringReimbursementRepository
    private let toasts: @MainActor (Toast) -> Void
    private var repository: RecurringReimbursementRepository?
    private var companyId: String?
    private var loadGeneration = 0
    private var refreshTask: Task<Void, Never>?

    init(
        makeRepository: @escaping (String) -> RecurringReimbursementRepository = {
            ExpenseRecurringReimbursementRepository(companyId: $0)
        },
        toasts: @escaping @MainActor (Toast) -> Void = { ToastCenter.shared.present($0) }
    ) {
        self.makeRepository = makeRepository
        self.toasts = toasts
    }

    // MARK: - Setup & reads

    func setup(companyId: String) {
        let normalized = companyId.lowercased()
        guard normalized != self.companyId else { return }
        self.companyId = normalized
        repository = makeRepository(companyId)
        loadGeneration += 1
        snapshot = nil
        loadFailed = false
    }

    /// This month on the company calendar (UTC until the calendar loads).
    var currentMonth: String {
        ExpenseRecurring.currentMonth(in: snapshot?.timeZone)
    }

    /// Company currency new setups are filed in.
    var currency: String {
        snapshot?.currency ?? "USD"
    }

    var setups: [ExpenseRecurringReimbursementDTO] {
        snapshot?.setups ?? []
    }

    /// The setup that filed `expense`, when loaded.
    func setup(for expense: ExpenseDTO) -> ExpenseRecurringReimbursementDTO? {
        snapshot?.setup(id: expense.recurringReimbursementId)
    }

    func setup(id: String) -> ExpenseRecurringReimbursementDTO? {
        snapshot?.setup(id: id)
    }

    func load() async {
        guard let repository else { return }
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer {
            if generation == loadGeneration { isLoading = false }
        }
        do {
            let fresh = try await repository.fetchSnapshot()
            guard generation == loadGeneration else { return }
            snapshot = fresh
            loadFailed = false
        } catch {
            guard generation == loadGeneration, !error.isCancellation else { return }
            loadFailed = true
        }
    }

    /// Coalesces a burst of expense signals (a command touches the setup, its
    /// lines and their batches) into one read.
    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    // MARK: - Commands

    func create(userId: String, name: String, amount: Double, firstPeriod: String) async -> Outcome {
        await run(.create) { repository in
            try await repository.create(CreateRecurringReimbursementParams(
                userId: userId,
                name: name,
                amount: amount,
                firstPeriod: firstPeriod,
                categoryId: nil
            ))
        } success: { setup in
            Feedback.Recurring.added(amount: BooksFormat.exact(setup.amount, code: setup.currency))
        }
    }

    /// Unpaid months follow the change; paid months keep what was paid.
    func update(_ setup: ExpenseRecurringReimbursementDTO, name: String, amount: Double) async -> Outcome {
        await run(.update(setup.id)) { repository in
            try await repository.update(UpdateRecurringReimbursementParams(
                id: setup.id,
                name: name,
                amount: amount,
                categoryId: setup.categoryId,
                expectedUpdatedAt: setup.updatedAt
            ))
        } success: { _ in
            Feedback.Recurring.updated
        }
    }

    /// Sets the last month paid, or removes the end (`lastPeriod == nil`).
    func end(_ setup: ExpenseRecurringReimbursementDTO, lastPeriod: String?) async -> Outcome {
        await run(.end(setup.id)) { repository in
            try await repository.end(EndRecurringReimbursementParams(
                id: setup.id,
                lastPeriod: lastPeriod,
                expectedUpdatedAt: setup.updatedAt
            ))
        } success: { _ in
            lastPeriod.map { Feedback.Recurring.ended(month: ExpenseRecurring.formatMonth($0)) }
                ?? Feedback.Recurring.resumed
        }
    }

    /// For a setup made in error — the database refuses once a month is paid.
    func delete(_ setup: ExpenseRecurringReimbursementDTO) async -> Outcome {
        await run(.delete(setup.id)) { repository in
            try await repository.delete(DeleteRecurringReimbursementParams(
                id: setup.id,
                expectedUpdatedAt: setup.updatedAt
            ))
        } success: { _ in
            Feedback.Recurring.deleted
        }
    }

    /// Leaves one unpaid month out. The toast's UNDO restores it and then runs
    /// `onChanged` again, so the surface that skipped refreshes either way.
    @discardableResult
    func skip(_ line: ExpenseDTO, onChanged: @escaping () -> Void = {}) async -> Outcome {
        let month = line.recurringPeriod.map(ExpenseRecurring.formatMonth) ?? "MONTH"
        let expenseId = line.id
        let period = line.recurringPeriod
        let outcome = await run(.skip(expenseId)) { repository in
            try await repository.skipLine(expenseId: expenseId)
        } success: { _ in
            // Strong capture on purpose: UNDO must work after the surface that
            // skipped has closed. The toast releases it when it dismisses.
            Feedback.Recurring.skipped(month: month, expenseId: expenseId) {
                Task { @MainActor in
                    if await self.restore(expenseId: expenseId, period: period) == .done {
                        onChanged()
                    }
                }
            }
        }
        if outcome == .done { onChanged() }
        return outcome
    }

    /// Puts a skipped month back at the current amount.
    @discardableResult
    func restore(expenseId: String, period: String?) async -> Outcome {
        let month = period.map(ExpenseRecurring.formatMonth) ?? "MONTH"
        return await run(.restore(expenseId)) { repository in
            try await repository.restoreLine(expenseId: expenseId)
        } success: { _ in
            Feedback.Recurring.restored(month: month, expenseId: expenseId)
        }
    }

    // MARK: - Command plumbing

    private func run(
        _ command: Command,
        _ send: (RecurringReimbursementRepository) async throws -> ExpenseRecurringReimbursementDTO,
        success: (ExpenseRecurringReimbursementDTO) -> Toast
    ) async -> Outcome {
        guard let repository else {
            toasts(Feedback.Recurring.refused(.failed))
            return .refused(.failed)
        }
        guard inFlight == nil else {
            toasts(Feedback.Recurring.refused(.busy))
            return .ignored
        }
        inFlight = command
        defer { inFlight = nil }

        do {
            let setup = try await send(repository)
            merge(setup)
            toasts(success(setup))
            NotificationCenter.default.post(name: .opsExpensesDidChange, object: nil)
            // A command moves months, batches and totals beyond the one setup it
            // answers with; a follow-up read settles every surface on them.
            scheduleRefresh()
            return .done
        } catch {
            let refusal = Self.refusal(for: error)
            toasts(Feedback.Recurring.refused(refusal))
            // Settle on the current truth — a refusal often means something
            // changed underneath the operator.
            await load()
            return .refused(refusal)
        }
    }

    /// Replaces the setup with the command's answer. A deleted setup leaves the
    /// list. Any read already in flight is older than this answer, so it is
    /// discarded — unless nothing has loaded yet, in which case that first read
    /// must still land (the follow-up refresh settles it on the answer).
    private func merge(_ setup: ExpenseRecurringReimbursementDTO) {
        guard var current = snapshot else { return }
        loadGeneration += 1
        isLoading = false
        current.setups.removeAll { $0.id.lowercased() == setup.id.lowercased() }
        if setup.deletedAt == nil {
            current.setups.append(setup)
            current.setups.sort { $0.createdAt < $1.createdAt }
        }
        snapshot = current
    }

    /// Transport failure → offline; a PostgREST refusal → its mapped reason.
    nonisolated static func refusal(for error: Error) -> ExpenseRecurring.Refusal {
        if let urlError = error as? URLError {
            let offline: Set<URLError.Code> = [
                .notConnectedToInternet, .networkConnectionLost, .timedOut,
                .dataNotAllowed, .cannotFindHost, .cannotConnectToHost,
            ]
            return offline.contains(urlError.code) ? .offline : .failed
        }
        if let postgrest = error as? PostgrestError {
            return ExpenseRecurring.refusal(forMessage: postgrest.message)
        }
        return ExpenseRecurring.refusal(forMessage: String(describing: error))
    }
}
