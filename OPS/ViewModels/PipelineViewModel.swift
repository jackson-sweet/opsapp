//
//  PipelineViewModel.swift
//  OPS
//
//  Loads opportunities for a company, groups by stage, sorts within each
//  stage (stale first, then lastActivityAt desc).
//

import SwiftUI
import SwiftData

@MainActor
class PipelineViewModel: ObservableObject {

    @Published var allOpportunities: [Opportunity] = []
    @Published var isLoading: Bool = false
    @Published var loadError: String? = nil
    @Published var selectedStage: PipelineStage = .newLead

    /// Identity of the operator whose pipeline this is. Used by in-court
    /// computations to scope "ball in your court" leads to the current user.
    /// nil → in-court counts return 0.
    @Published var currentUserId: String?

    private var repository: OpportunityRepository?
    private var companyId: String?

    // MARK: - Setup

    func setup(companyId: String, currentUserId: String? = nil) {
        self.companyId = companyId
        self.currentUserId = currentUserId
        self.repository = OpportunityRepository(companyId: companyId)
    }

    // MARK: - Load

    func loadData() async {
        guard let repo = repository else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let dtos = try await repo.fetchAll()
            allOpportunities = dtos.map { $0.toModel() }
        } catch {
            if !error.isCancellation {
                print("[Pipeline] Load failed: \(error)")
                loadError = error.localizedDescription
            }
        }
    }

    // MARK: - Derivations

    /// Opportunities in the given stage, sorted: stale first, then lastActivityAt desc, then createdAt desc.
    func opportunities(in stage: PipelineStage) -> [Opportunity] {
        allOpportunities
            .filter { $0.stage == stage && !$0.isDeleted && !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.isStale != rhs.isStale { return lhs.isStale }
                let lDate = lhs.lastActivityAt ?? lhs.createdAt
                let rDate = rhs.lastActivityAt ?? rhs.createdAt
                if lDate != rDate { return lDate > rDate }
                return lhs.createdAt > rhs.createdAt
            }
    }

    /// Count per stage for the strip.
    func count(in stage: PipelineStage) -> Int {
        allOpportunities.filter { $0.stage == stage && !$0.isDeleted && !$0.isArchived }.count
    }

    /// Pipeline-wide counts for dashboard carousel.
    var activeLeadCount: Int {
        allOpportunities.filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived }.count
    }

    var weightedForecastValue: Double {
        allOpportunities
            .filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived }
            .reduce(0) { $0 + $1.weightedValue }
    }

    var staleLeadsCount: Int {
        allOpportunities.filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived && $0.isStale }.count
    }

    var nextFollowUpDue: Date? {
        allOpportunities
            .compactMap { $0.nextFollowUpAt }
            .filter { $0 >= Date() }
            .min()
    }

    /// True when no opportunities exist at all (any stage).
    var isPipelineEmpty: Bool {
        allOpportunities.allSatisfy { $0.isDeleted || $0.isArchived }
    }

    // MARK: - Ball-in-court derivations

    /// Severity buckets — each in-court lead lands in exactly one bucket,
    /// highest severity wins. `followUp`-stage-only signal rolls into stale.
    struct InCourtBuckets: Equatable {
        var overdue: Int
        var stale: Int
        var untouched: Int

        var total: Int { overdue + stale + untouched }
    }

    /// Filtered list — leads where the next move is the current user's.
    /// Returns empty when `currentUserId == nil`.
    private var inCourtOpportunities: [Opportunity] {
        guard let me = currentUserId else { return [] }
        let now = Date()
        return allOpportunities.filter { opp in
            guard opp.assignedTo == me else { return false }
            guard !opp.stage.isTerminal else { return false }
            guard !opp.isDeleted, !opp.isArchived else { return false }

            let isOverdue = (opp.nextFollowUpAt.map { $0 <= now }) ?? false
            let isStale = opp.isStale
            let isFollowUpStage = opp.stage == .followUp
            let isUntouched = (opp.stage == .newLead && opp.lastActivityAt == nil)

            return isOverdue || isStale || isFollowUpStage || isUntouched
        }
    }

    var inCourtCount: Int {
        inCourtOpportunities.count
    }

    var inCourtBuckets: InCourtBuckets {
        let now = Date()
        var b = InCourtBuckets(overdue: 0, stale: 0, untouched: 0)
        for opp in inCourtOpportunities {
            let isOverdue = (opp.nextFollowUpAt.map { $0 <= now }) ?? false
            if isOverdue {
                b.overdue += 1
            } else if opp.isStale || opp.stage == .followUp {
                b.stale += 1
            } else if opp.stage == .newLead && opp.lastActivityAt == nil {
                b.untouched += 1
            }
        }
        return b
    }

    var inCourtTotalValue: Double {
        inCourtOpportunities.reduce(0) { $0 + ($1.estimatedValue ?? 0) }
    }

    var inCourtOpportunityIds: Set<String> {
        Set(inCourtOpportunities.map { $0.id })
    }

    // MARK: - Stat-card computeds

    var staleLeadsTotalValue: Double {
        allOpportunities
            .filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived && $0.isStale }
            .reduce(0) { $0 + ($1.estimatedValue ?? 0) }
    }

    /// Summary string for the STALE RISK card sub-line, or nil when no stale leads.
    /// Format: `"12D IN QUOTING"` — oldest stale lead's days-in-stage and stage display name.
    var oldestStaleDescription: String? {
        let stale = allOpportunities
            .filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived && $0.isStale }
        guard let oldest = stale.max(by: { $0.daysInStage < $1.daysInStage }) else { return nil }
        return "\(oldest.daysInStage)D IN \(oldest.stage.displayName)"
    }

    /// Win rate over the given period. Returns nil if fewer than 5 closes in the window.
    /// Period bounded by `actualCloseDate`. Closed = won OR lost.
    func closeRate(periodDays: Int) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -periodDays, to: Date()) ?? Date.distantPast
        let closed = allOpportunities.filter { opp in
            guard !opp.isDeleted else { return false }
            guard let closeDate = opp.actualCloseDate else { return false }
            return closeDate >= cutoff && (opp.stage == .won || opp.stage == .lost)
        }
        guard closed.count >= 5 else { return nil }
        let wonCount = closed.filter { $0.stage == .won }.count
        return Double(wonCount) / Double(closed.count)
    }

    // MARK: - Mutations

    func moveToStage(opportunityId: String, to stage: PipelineStage, userId: String?) async throws {
        guard let repo = repository else { return }
        let updatedDTO = try await repo.moveToStage(opportunityId: opportunityId, to: stage, userId: userId)
        if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
            let updated = updatedDTO.toModel()
            allOpportunities[idx] = updated
        }
    }

    func markWon(opportunityId: String, actualValue: Double?, projectId: String?, userId: String?) async throws {
        guard let repo = repository else { return }
        let updatedDTO = try await repo.markWon(opportunityId: opportunityId, actualValue: actualValue, projectId: projectId, userId: userId)
        if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
            allOpportunities[idx] = updatedDTO.toModel()
        }
    }

    func markLost(opportunityId: String, reason: LossReason, notes: String?, userId: String?) async throws {
        guard let repo = repository else { return }
        let updatedDTO = try await repo.markLost(opportunityId: opportunityId, reason: reason, notes: notes, userId: userId)
        if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
            allOpportunities[idx] = updatedDTO.toModel()
        }
    }

    func addLead(_ dto: CreateOpportunityDTO) async throws -> Opportunity {
        guard let repo = repository else { throw NSError(domain: "Pipeline", code: 0) }
        let resultDTO = try await repo.create(dto)
        let model = resultDTO.toModel()
        allOpportunities.append(model)
        return model
    }

    func archive(opportunityId: String) async throws {
        guard let repo = repository else { return }
        try await repo.archive(opportunityId)
        if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
            allOpportunities[idx].archivedAt = Date()
        }
    }

    func softDelete(opportunityId: String) async throws {
        guard let repo = repository else { return }
        try await repo.softDelete(opportunityId)
        if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
            allOpportunities[idx].deletedAt = Date()
        }
    }
}
