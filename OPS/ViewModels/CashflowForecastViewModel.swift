//
//  CashflowForecastViewModel.swift
//  OPS
//
//  Assembles inputs from repositories, calls CashflowForecastEngine, publishes
//  ForecastResult. Persists layer toggles per-user via @AppStorage.
//
//  Notes on data-layer adaptations vs the plan:
//    - EstimateDTO has no `approvedAt` column; we use `updatedAt` as the
//      approval proxy for `approved`/`converted` estimates.
//    - SupabaseDate.parseDateOnly is used for `date` columns (yyyy-MM-dd);
//      SupabaseDate.parse for `timestamptz`.
//

import Foundation
import SwiftUI

@MainActor
final class CashflowForecastViewModel: ObservableObject {

    @Published var result: ForecastResult?
    @Published var isLoading: Bool = false
    @Published var loadError: String?

    @AppStorage("cashflow.layers.committed")  private var includeCommitted  = true
    @AppStorage("cashflow.layers.contracted") private var includeContracted = true
    @AppStorage("cashflow.layers.pipeline")   private var includePipeline   = true
    @AppStorage("cashflow.layers.recurring")  private var includeRecurring  = true
    @AppStorage("cashflow.horizonWeeks")      private var horizonWeeks      = 13

    // Injected dependencies. companyId may be empty at construction and set
    // later via setup(companyId:dashboardVM:) — matches the dashboardVM pattern
    // in BooksTabView where companyId arrives after view init.
    private(set) var companyId: String
    private var dashboardVM: MoneyDashboardViewModel
    private var invoiceRepo: InvoiceRepository
    private var estimateRepo: EstimateRepository
    private var opportunityRepo: OpportunityRepository
    private var milestoneRepo: PaymentMilestoneRepository
    private var recurringRepo: RecurringExpenseRepository
    private var settingsRepo: ForecastSettingsRepository
    private var alertRepo: ForecastAlertRepository
    private var dispatcher: ForecastNotificationDispatcher

    init(
        companyId: String = "",
        dashboardVM: MoneyDashboardViewModel? = nil
    ) {
        self.companyId = companyId
        self.dashboardVM = dashboardVM ?? MoneyDashboardViewModel()
        self.invoiceRepo    = InvoiceRepository(companyId: companyId)
        self.estimateRepo   = EstimateRepository(companyId: companyId)
        self.opportunityRepo = OpportunityRepository(companyId: companyId)
        self.milestoneRepo  = PaymentMilestoneRepository(companyId: companyId)
        self.recurringRepo  = RecurringExpenseRepository(companyId: companyId)
        self.settingsRepo   = ForecastSettingsRepository(companyId: companyId)
        self.alertRepo      = ForecastAlertRepository(companyId: companyId)
        self.dispatcher     = ForecastNotificationDispatcher(companyId: companyId)
    }

    /// Late-binding companyId + dashboardVM. Called from BooksTabView once
    /// the data controller exposes the current user's company.
    func setup(companyId: String, dashboardVM: MoneyDashboardViewModel) {
        guard !companyId.isEmpty else { return }
        self.companyId = companyId
        self.dashboardVM = dashboardVM
        self.invoiceRepo    = InvoiceRepository(companyId: companyId)
        self.estimateRepo   = EstimateRepository(companyId: companyId)
        self.opportunityRepo = OpportunityRepository(companyId: companyId)
        self.milestoneRepo  = PaymentMilestoneRepository(companyId: companyId)
        self.recurringRepo  = RecurringExpenseRepository(companyId: companyId)
        self.settingsRepo   = ForecastSettingsRepository(companyId: companyId)
        self.alertRepo      = ForecastAlertRepository(companyId: companyId)
        self.dispatcher     = ForecastNotificationDispatcher(companyId: companyId)
    }

    /// Exposed for child sheets that need to instantiate repositories tied
    /// to the same company context.
    var companyIdForExternalUse: String { companyId }

    var layerSet: Set<ForecastLayer> {
        var s: Set<ForecastLayer> = []
        if includeCommitted  { s.insert(.committed) }
        if includeContracted { s.insert(.contracted) }
        if includePipeline   { s.insert(.pipeline) }
        if includeRecurring  { s.insert(.recurring) }
        return s
    }

    func setLayer(_ layer: ForecastLayer, included: Bool) {
        switch layer {
        case .committed:  includeCommitted  = included
        case .contracted: includeContracted = included
        case .pipeline:   includePipeline   = included
        case .recurring:  includeRecurring  = included
        }
    }

    func setHorizon(weeks: Int) { horizonWeeks = weeks }

    func load() async {
        guard !companyId.isEmpty else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            async let settings  = settingsRepo.fetch()
            async let invoices  = invoiceRepo.fetchAll()
            async let estimates = estimateRepo.fetchAll()
            async let opps      = opportunityRepo.fetchAll()
            async let milestones = milestoneRepo.fetchAll()
            async let recurring  = recurringRepo.fetchAll()

            let (s, inv, est, opp, ms, rec) = try await (
                settings, invoices, estimates, opps, milestones, recurring
            )

            let inputs = buildInputs(
                settings: s,
                invoices: inv,
                estimates: est,
                opportunities: opp,
                milestones: ms,
                recurring: rec
            )

            let engineResult = CashflowForecastEngine().compute(inputs: inputs)
            self.result = engineResult

            // Fire notification path (anti-spam handled inside dispatcher).
            await dispatcher.reactTo(result: engineResult)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func buildInputs(
        settings: ForecastSettingsDTO,
        invoices: [InvoiceDTO],
        estimates: [EstimateDTO],
        opportunities: [OpportunityDTO],
        milestones: [PaymentMilestoneDTO],
        recurring: [RecurringExpenseDTO]
    ) -> ForecastInputs {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday

        let avgDays = dashboardVM.avgDaysToPayment > 0 ? dashboardVM.avgDaysToPayment : 14
        let startingBalance = settings.currentBalance ?? 0
        let threshold = settings.lowWaterThreshold ?? 5000

        // Committed: sent / viewed / partially-paid / past-due invoices with
        // a remaining balance. Drop drafts, voided, written-off, paid.
        let invoiceInputs: [ForecastInvoiceInput] = invoices.compactMap { dto in
            guard let dueStr = dto.dueDate,
                  let due = SupabaseDate.parseDateOnly(dueStr) ?? SupabaseDate.parse(dueStr),
                  let rawStatus = dto.status,
                  let status = ForecastInvoiceStatus(rawValue: rawStatus),
                  (dto.balanceDue ?? 0) > 0
            else { return nil }
            return ForecastInvoiceInput(
                id: dto.id,
                balanceDue: dto.balanceDue ?? 0,
                dueDate: due,
                status: status,
                clientLabel: dto.invoiceNumber ?? "INV"
            )
        }

        // Estimate→milestoneSet map for `hasMilestones` lookup. Excluded
        // estimates without milestones get treated as a lump sum below.
        let estimateIdsWithMilestones = Set(milestones.map { $0.estimateId })

        let estimateInputs: [ForecastEstimateInput] = estimates.compactMap { dto in
            let status = EstimateStatus(rawValue: dto.status)
            guard status == .approved || status == .converted else { return nil }
            // EstimateDTO has no `approvedAt` column; `updatedAt` is the closest
            // proxy for approval timestamp (status flips touch updated_at).
            let approvedProxy = SupabaseDate.parse(dto.updatedAt)
            // Project end-date hookup deferred — Estimate has no embedded
            // project span. Engine falls back to approvedAt + 30 days.
            return ForecastEstimateInput(
                id: dto.id,
                total: dto.total,
                approvedAt: approvedProxy,
                projectEndDate: nil,
                clientLabel: dto.estimateNumber ?? "EST",
                hasMilestones: estimateIdsWithMilestones.contains(dto.id)
            )
        }

        let milestoneInputs: [ForecastMilestoneInput] = milestones.compactMap { dto in
            return ForecastMilestoneInput(
                id: dto.id,
                estimateId: dto.estimateId,
                amount: dto.amount,
                expectedDate: dto.expectedDate.flatMap { SupabaseDate.parseDateOnly($0) },
                fallbackDate: nil,
                isPaid: dto.paidAt != nil,
                label: dto.name
            )
        }

        let oppInputs: [ForecastOpportunityInput] = opportunities.compactMap { dto in
            guard let ecdStr = dto.expectedCloseDate,
                  let ecd = SupabaseDate.parseDateOnly(ecdStr) ?? SupabaseDate.parse(ecdStr)
            else { return nil }
            let stage = PipelineStage(rawValue: dto.stage) ?? .newLead
            let prob = dto.winProbability ?? stage.winProbability
            return ForecastOpportunityInput(
                id: dto.id,
                estimatedValue: dto.estimatedValue ?? 0,
                winProbability: prob,
                expectedCloseDate: ecd,
                label: dto.title ?? dto.contactName ?? "Lead"
            )
        }

        let recurringInputs: [ForecastRecurringInput] = recurring.compactMap { dto in
            guard let cadence = RecurringCadence(rawValue: dto.cadence),
                  let due = SupabaseDate.parseDateOnly(dto.nextDueDate)
            else { return nil }
            return ForecastRecurringInput(
                id: dto.id,
                amount: dto.amount,
                cadence: cadence,
                nextDueDate: due,
                endDate: dto.endDate.flatMap { SupabaseDate.parseDateOnly($0) },
                label: dto.name
            )
        }

        return ForecastInputs(
            today: Date(),
            horizonWeeks: horizonWeeks,
            startingBalance: startingBalance,
            lowWaterThreshold: threshold,
            avgDaysToPayment: avgDays,
            layers: layerSet,
            invoices: invoiceInputs,
            milestones: milestoneInputs,
            estimates: estimateInputs,
            opportunities: oppInputs,
            recurringExpenses: recurringInputs,
            calendar: cal,
            startingBalanceAsOf: settings.balanceUpdatedAt.flatMap { SupabaseDate.parse($0) }
        )
    }
}
