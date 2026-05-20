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
    /// Full stage_transitions history for the company. Drives the hero widget's
    /// forecast-delta baseline (30D-ago pipeline reconstruction) and the
    /// avg-velocity computation. Loaded in parallel with opportunities.
    @Published var allStageTransitions: [StageTransition] = []
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
            async let oppsTask  = repo.fetchAll()
            async let txTask    = repo.fetchAllStageTransitions()
            let (oppDtos, txDtos) = try await (oppsTask, txTask)
            allOpportunities    = oppDtos.map { $0.toModel() }
            allStageTransitions = txDtos.map { $0.toModel() }
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

    // MARK: - Close-rate (consumed by MoneyDashboardViewModel for BOOKS tab)
    //
    // The 2026-05-19 LEADS rebuild removed the in-court derivations, the
    // STALE RISK stat card, and the oldest-stale summary string — see the
    // new triage bucketize section below. `closeRate` survived because
    // BOOKS still calls it.

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

    // MARK: - Triage queue (2026-05-19 rebuild)
    //
    // The new LEADS surface is a triage queue, not a stage browser. Each open
    // lead lands in exactly one urgency bucket; the operator filters by bucket.
    // Mirrors the prototype's `bucketize()` in shared.jsx.

    enum TriageBucket: String, CaseIterable, Identifiable {
        case all
        case overdue        // nextFollowUpAt <= now
        case dueToday       // nextFollowUpAt == today
        case waitingOnYou   // last message was inbound (lastMessageDirection == "in")
        case fresh          // newLead stage with no activity yet
        case waitingOnThem  // catch-all for non-urgent open leads

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:           return "ALL"
            case .overdue:       return "OVERDUE"
            case .dueToday:      return "DUE TODAY"
            case .waitingOnYou:  return "REPLY DUE"
            case .fresh:         return "NEW"
            case .waitingOnThem: return "WAITING"
            }
        }
    }

    enum UrgencyTone {
        case rose, tan, steel, neutral
    }

    struct TriageBuckets: Equatable {
        var overdue:       [Opportunity]
        var dueToday:      [Opportunity]
        var waitingOnYou:  [Opportunity]
        var fresh:         [Opportunity]
        var waitingOnThem: [Opportunity]
        /// Won leads with no projectId yet — drive the WON · CONVERT carousel.
        var unconvertedWon: [Opportunity]

        /// Every actionable open lead in urgency order. Used when the operator
        /// picks the ALL chip — keeps rose / tan rows at the top.
        var all: [Opportunity] {
            overdue + dueToday + waitingOnYou + fresh + waitingOnThem
        }

        func leads(for bucket: TriageBucket) -> [Opportunity] {
            switch bucket {
            case .all:           return all
            case .overdue:       return overdue
            case .dueToday:      return dueToday
            case .waitingOnYou:  return waitingOnYou
            case .fresh:         return fresh
            case .waitingOnThem: return waitingOnThem
            }
        }
    }

    /// Bucketize every open lead. Won leads route to `unconvertedWon`; lost
    /// leads are excluded entirely.
    var triageBuckets: TriageBuckets {
        var overdue: [Opportunity]       = []
        var dueToday: [Opportunity]      = []
        var waitingOnYou: [Opportunity]  = []
        var fresh: [Opportunity]         = []
        var waitingOnThem: [Opportunity] = []
        var unconvertedWon: [Opportunity] = []

        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now

        for opp in allOpportunities where !opp.isDeleted && !opp.isArchived {
            if opp.stage == .won {
                if opp.projectId == nil { unconvertedWon.append(opp) }
                continue
            }
            if opp.stage == .lost { continue }

            if let due = opp.nextFollowUpAt {
                if due < startOfToday {
                    overdue.append(opp)
                    continue
                }
                if due < startOfTomorrow {
                    dueToday.append(opp)
                    continue
                }
            }

            // "Waiting on you" — last inbound activity unanswered.
            // Skip for newLead (those route to .fresh).
            if opp.stage != .newLead, opp.lastMessageDirection == "in" {
                waitingOnYou.append(opp)
                continue
            }

            if opp.stage == .newLead {
                fresh.append(opp)
                continue
            }

            waitingOnThem.append(opp)
        }

        // Sort overdue most-overdue-first; others by stale-then-lastActivity desc.
        overdue.sort {
            ($0.nextFollowUpAt ?? .distantFuture) < ($1.nextFollowUpAt ?? .distantFuture)
        }
        let staleFirst: (Opportunity, Opportunity) -> Bool = { a, b in
            if a.isStale != b.isStale { return a.isStale }
            let aDate = a.lastActivityAt ?? a.createdAt
            let bDate = b.lastActivityAt ?? b.createdAt
            return aDate > bDate
        }
        dueToday.sort(by: staleFirst)
        waitingOnYou.sort(by: staleFirst)
        fresh.sort(by: staleFirst)
        waitingOnThem.sort(by: staleFirst)

        return TriageBuckets(
            overdue: overdue,
            dueToday: dueToday,
            waitingOnYou: waitingOnYou,
            fresh: fresh,
            waitingOnThem: waitingOnThem,
            unconvertedWon: unconvertedWon
        )
    }

    /// Returns the bucket a single lead belongs to. Used by the ALL view so the
    /// row can derive its own urgency tone independent of the active filter.
    func bucketOf(_ lead: Opportunity) -> TriageBucket {
        let now = Date()
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now

        if let due = lead.nextFollowUpAt {
            if due < startOfToday    { return .overdue }
            if due < startOfTomorrow { return .dueToday }
        }
        if lead.stage != .newLead, lead.lastMessageDirection == "in" {
            return .waitingOnYou
        }
        if lead.stage == .newLead { return .fresh }
        return .waitingOnThem
    }

    /// Tone for the chip dot + row verb. In ALL view the tone is derived from
    /// the lead's own bucket; in any other bucket the tone is the bucket's.
    func toneFor(_ bucket: TriageBucket, lead: Opportunity? = nil) -> UrgencyTone {
        let effective = (bucket == .all && lead != nil) ? bucketOf(lead!) : bucket
        switch effective {
        case .overdue:       return .rose
        case .dueToday:      return .tan
        case .waitingOnYou:  return .steel
        case .fresh:         return .neutral
        case .waitingOnThem: return .neutral
        case .all:           return .neutral
        }
    }

    /// One-word action verb the row leads with. Per direction-triage.jsx
    /// lines 478–494. In ALL view the verb derives from the lead's effective
    /// bucket.
    func verbFor(_ lead: Opportunity, bucket: TriageBucket) -> String {
        let effective = bucket == .all ? bucketOf(lead) : bucket
        switch effective {
        case .overdue:
            switch lead.stage {
            case .quoted:      return "CHASE QUOTE"
            case .negotiation: return "CLOSE"
            default:           return "FOLLOW UP"
            }
        case .dueToday:
            switch lead.stage {
            case .negotiation: return "CLOSE"
            case .quoted:      return "CONFIRM"
            default:           return "CALL"
            }
        case .waitingOnYou:
            return lead.stage == .qualifying ? "QUALIFY" : "REPLY"
        case .fresh:
            return "TRIAGE"
        case .waitingOnThem:
            return "CHECK IN"
        case .all:
            return "REVIEW"
        }
    }

    /// The bucket to land on at app-open: highest-urgency that has leads.
    /// Falls back to .overdue if everything's empty (so the empty-state copy
    /// still reads coherently).
    var defaultBucket: TriageBucket {
        let order: [TriageBucket] = [.overdue, .dueToday, .waitingOnYou, .fresh, .waitingOnThem]
        let b = triageBuckets
        return order.first { !b.leads(for: $0).isEmpty } ?? .overdue
    }

    // MARK: - Hero-widget computeds (2026-05-19 rebuild)

    /// Active leads — non-terminal, non-deleted, non-archived.
    var openLeadCount: Int {
        allOpportunities.filter {
            !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived
        }.count
    }

    /// "Waiting" sub-line on the OPEN hero sub-metric — both buckets that
    /// represent waiting (you owe a reply + they owe you a reply).
    var waitingCount: Int {
        let b = triageBuckets
        return b.waitingOnYou.count + b.waitingOnThem.count
    }

    // MARK: - Forecast delta (vs 30 days ago)
    //
    // Reconstructs the pipeline state 30 days ago using `allStageTransitions`
    // and re-runs the weighted-forecast sum against that historical state.
    // Approach = Option A ("what it would have been") from the LEADS polish
    // P1-3 brief: every opp gets its stage-as-of-T queried via the latest
    // transition with `transitionedAt <= T`. When an opp has no transition
    // on or before T, the fallback is `.newLead` (the schema's implicit
    // initial stage) provided `createdAt <= T`.
    //
    // Caveats:
    //  - Opps created directly in a non-newLead stage via the API would be
    //    misclassified as newLead at the priorDate baseline. Rare; baseline
    //    is approximate by design.
    //  - Won/lost opps as of priorDate contribute zero to the baseline
    //    (terminal stages are excluded from weighted forecast).

    /// Percent change in weighted forecast value vs 30 days ago. nil when
    /// the prior baseline is zero (no opportunities existed 30D ago) or when
    /// stage transitions haven't been fetched yet.
    var forecastDeltaPct: Double? {
        guard !allStageTransitions.isEmpty else { return nil }
        let priorDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let current = weightedForecastValue
        let priorBaseline = weightedForecast(asOf: priorDate)
        guard priorBaseline > 0 else { return nil }
        return ((current - priorBaseline) / priorBaseline) * 100.0
    }

    /// Sum of (estimatedValue × stage.winProbability) across opportunities
    /// that existed and were non-terminal on the given date. Used to
    /// reconstruct historical baselines for the forecast-delta chip.
    private func weightedForecast(asOf date: Date) -> Double {
        let txByOpp = Dictionary(grouping: allStageTransitions, by: \.opportunityId)
        var baseline: Double = 0
        for opp in allOpportunities {
            guard !opp.isDeleted else { continue }
            guard opp.createdAt <= date else { continue }
            if let archived = opp.archivedAt, archived <= date { continue }
            if let deleted  = opp.deletedAt,  deleted  <= date { continue }
            let priorStage = stage(for: opp, asOf: date, transitions: txByOpp[opp.id] ?? [])
            if priorStage.isTerminal { continue }
            let est = opp.estimatedValue ?? 0
            baseline += est * Double(priorStage.winProbability) / 100.0
        }
        return baseline
    }

    /// The stage an opportunity occupied on a given date. Returns the latest
    /// `toStage` from a transition with `transitionedAt <= date`; falls back
    /// to `.newLead` when no such transition exists (the schema's implicit
    /// initial stage for any opportunity).
    private func stage(for opp: Opportunity, asOf date: Date, transitions: [StageTransition]) -> PipelineStage {
        let priors = transitions.filter { $0.transitionedAt <= date }
        if let last = priors.max(by: { $0.transitionedAt < $1.transitionedAt }) {
            return last.toStage
        }
        return .newLead
    }

    // MARK: - Velocity (avg newLead → won, last 90D)
    //
    // Mirrors the closeRate(periodDays:) nil-on-low-N idiom — returns nil
    // when fewer than 5 wins land in the window. Per-opp duration =
    // (won-transition time) − (newLead-transition time), with fallbacks to
    // `actualCloseDate` and `createdAt` when transition rows are missing
    // (older / migrated opps).

    /// Average days from `newLead` entry to `won` entry across opportunities
    /// won in the last `periodDays`. nil when fewer than 5 qualifying wins.
    func avgVelocityDays(periodDays: Int = 90) -> Int? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -periodDays, to: Date()) ?? Date.distantPast
        let recentWins = allOpportunities.filter { opp in
            guard !opp.isDeleted, opp.stage == .won else { return false }
            guard let close = opp.actualCloseDate else { return false }
            return close >= cutoff
        }
        guard recentWins.count >= 5 else { return nil }

        let txByOpp = Dictionary(grouping: allStageTransitions, by: \.opportunityId)
        var totalDays: Double = 0
        var counted = 0
        for opp in recentWins {
            let transitions = txByOpp[opp.id] ?? []
            let newLeadStart: Date = transitions
                .filter { $0.toStage == .newLead }
                .map(\.transitionedAt)
                .min()
                ?? opp.createdAt
            let wonAt: Date? = transitions
                .filter { $0.toStage == .won }
                .map(\.transitionedAt)
                .min()
                ?? opp.actualCloseDate
            guard let wonAt else { continue }
            let days = wonAt.timeIntervalSince(newLeadStart) / 86_400
            guard days >= 0 else { continue }
            totalDays += days
            counted += 1
        }
        guard counted >= 5 else { return nil }
        return Int((totalDays / Double(counted)).rounded())
    }
}
