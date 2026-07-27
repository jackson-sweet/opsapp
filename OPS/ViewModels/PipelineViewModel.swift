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
    @Published private(set) var followUpInFlightLeadIDs: Set<String> = []
    @Published private(set) var followUpReconcilingLeadIDs: Set<String> = []
    @Published private(set) var followUpUnknownLeadIDs: Set<String> = []
    @Published private(set) var followUpUnavailableLeadIDs: Set<String> = []

    /// Identity of the operator whose pipeline this is. Used by in-court
    /// computations to scope "ball in your court" leads to the current user.
    /// nil → in-court counts return 0.
    @Published var currentUserId: String?

    private var repository: OpportunityRepository?
    private var companyId: String?
    private let followUpService: LeadFollowUpServiceProtocol

    enum FollowUpProgress: Equatable {
        case idle
        case sending
        case syncing
        case unknown
    }

    enum FollowUpActionOutcome {
        case sent(comebackAt: Date?)
        case syncing
        case unknown
        case unavailable
        case rejected
        case busy
        case signatureRequired
        case permissionDenied
        case networkError
    }

    init(followUpService: LeadFollowUpServiceProtocol? = nil) {
        self.followUpService = followUpService ?? LeadFollowUpService.shared
    }

    // MARK: - Setup

    func setup(companyId: String, currentUserId: String? = nil) {
        self.companyId = companyId
        self.currentUserId = currentUserId
        self.repository = OpportunityRepository(companyId: companyId)
    }

    // MARK: - Remote-change refresh (debounced, coalesced, merge-based)
    //
    // Leads are deliberately outside the SwiftData sync engine (see bug
    // 0b7e9b17): three freshness triggers — Supabase Realtime events, a
    // foreground-resume catch-up, and pull-to-refresh — all funnel through
    // one debounced, coalesced reload that MERGES server rows into the
    // existing Opportunity instances by id (reference semantics keep the
    // pushed LeadDetailView live and list identity stable).

    /// True once the initial `.task` load has populated the surface. Remote /
    /// foreground triggers before that are no-ops — the initial load owns cold
    /// start (avoids a debounced fetch racing the first `.task` load).
    private(set) var hasLoadedOnce = false
    private var pendingRefreshTask: Task<Void, Never>?
    private var isLoadInFlight = false
    private var needsFollowUpLoad = false

    /// Single funnel for every automatic trigger (realtime burst, foreground).
    /// The trailing debounce collapses event storms into one fetch; the
    /// in-flight coalescer guarantees a fetch STARTED before the last event
    /// completes re-runs once more, so no change is missed.
    func scheduleRefresh(debounce: Duration = .milliseconds(1500)) {
        guard hasLoadedOnce else { return }
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.refreshCoalesced()
        }
    }

    private func refreshCoalesced() async {
        if isLoadInFlight { needsFollowUpLoad = true; return }
        isLoadInFlight = true
        await loadData(silent: true)
        isLoadInFlight = false
        if needsFollowUpLoad {
            needsFollowUpLoad = false
            await refreshCoalesced()
        }
    }

    /// Identity-preserving merge. Existing instances are mutated via `apply`
    /// (reference semantics keep the pushed detail screen live); result order
    /// follows `incoming` (server sort = created_at desc); ids absent from
    /// `incoming` drop out (server-deleted / merged leads disappear).
    ///
    /// `nonisolated` — a pure transform over its arguments that touches no
    /// actor-isolated state, so it is safe to call off the main actor (and
    /// from synchronous test code).
    nonisolated static func merge(existing: [Opportunity], incoming: [Opportunity]) -> [Opportunity] {
        let byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return incoming.map { fresh in
            if let current = byId[fresh.id] {
                current.apply(fresh)
                return current
            }
            return fresh
        }
    }

    // MARK: - Load

    /// Loads opportunities + stage transitions for the company.
    ///
    /// - `silent == false` (initial `.task` load and the nine `Lead*Success`
    ///   listeners): the loading spinner flips as before.
    /// - `silent == true` (realtime / foreground / pull-to-refresh): skips the
    ///   `isLoading` writes so no skeleton flashes over live content — the
    ///   surface stays put while rows update in place — but still records
    ///   `loadError`.
    func loadData(silent: Bool = false) async {
        guard let repo = repository else { return }
        if !silent { isLoading = true }
        loadError = nil
        defer { if !silent { isLoading = false } }

        do {
            let oppDtos = try await repo.fetchAll()
            allOpportunities = Self.merge(existing: allOpportunities,
                                          incoming: oppDtos.map { $0.toModel() })
            // A canonical refresh is the retry boundary for transient
            // mailbox/thread/signature availability. The durable request key
            // still prevents a second provider send if the prior result was
            // ambiguous.
            followUpUnavailableLeadIDs.removeAll()
            reconcileFollowUpProgressWithLoadedLeads()
            hasLoadedOnce = true
            // Keep the incoming-call caller-ID directory fresh (154cb8a3).
            // No-op unless the operator has the toggle on.
            CallDirectoryRefresher.refresh(from: oppDtos)
            // Keep iPhone Spotlight's LEAD index in lockstep with the surface.
            // Every lead change (create / edit / archive / delete / stage move,
            // plus realtime + foreground) funnels through this load, so a single
            // reconcile here keeps system-wide search current. No-op without
            // pipeline access or before the initial Spotlight backfill. Detached
            // so index writes never delay the visible refresh.
            let leadsSnapshot = allOpportunities
            Task { @MainActor in
                await SpotlightIndexManager.shared.reconcileLeads(leadsSnapshot)
            }
        } catch {
            if !error.isCancellation {
                print("[Pipeline] Load failed: \(error)")
                loadError = error.localizedDescription
            }
        }
    }

    deinit {
        pendingRefreshTask?.cancel()
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

    // MARK: - Chase flip (Leads redesign 2026-07, spec §2.2)

    /// Comeback rule (spec §2.2): default now+3d; a sooner FUTURE follow-up is
    /// kept; past-due dates are always replaced or an overdue lead could never
    /// leave OVERDUE.
    nonisolated static func comebackDate(existing: Date?, from now: Date = Date()) -> Date {
        let proposed = now.addingTimeInterval(3 * 86_400)
        if let existing, existing > now, existing < proposed { return existing }
        return proposed
    }

    /// HANDLED ✓ — declare the ball back in their court and schedule the comeback.
    /// Returns the comeback date so the caller can voice the toast.
    func markHandled(opportunityId: String) async throws -> Date {
        guard let repo = repository,
              let opp = allOpportunities.first(where: { $0.id == opportunityId }) else {
            throw NSError(domain: "Pipeline", code: 0)
        }
        let now = Date()
        let comeback = Self.comebackDate(existing: opp.nextFollowUpAt, from: now)
        let dto = try await repo.update(opportunityId, patch: MarkHandledPatch(
            handledAt: SupabaseDate.format(now),
            nextFollowUpAt: SupabaseDate.format(comeback)
        ))
        // apply (NOT element replacement) — keeps reference identity so a
        // pushed detail stays live, mirroring the merge contract.
        if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
            allOpportunities[idx].apply(dto.toModel())
        }
        NotificationCenter.default.post(name: Notification.Name("LeadUpdatedSuccess"),
                                        object: nil, userInfo: ["leadId": opportunityId])
        return comeback
    }

    // MARK: - One-tap follow-up

    /// Local eligibility controls whether a due/overdue strip offers the
    /// server-backed stock reply or falls back to HANDLED. The server remains
    /// authoritative for mailbox, thread, recipient, signature, and newest
    /// message safety.
    func canSendFollowUp(for opportunity: Opportunity) -> Bool {
        guard [.quoted, .followUp, .negotiation].contains(opportunity.stage),
              !Self.isAwaitingReply(opportunity),
              !followUpUnavailableLeadIDs.contains(opportunity.id),
              companyId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              currentUserId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              let email = opportunity.contactEmail else {
            return false
        }
        return !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func followUpProgress(for opportunityId: String) -> FollowUpProgress {
        if followUpInFlightLeadIDs.contains(opportunityId) { return .sending }
        if followUpUnknownLeadIDs.contains(opportunityId) { return .unknown }
        if followUpReconcilingLeadIDs.contains(opportunityId) { return .syncing }
        return .idle
    }

    /// Sends the standardized reply through the connected mailbox. No local
    /// lead state advances until the API returns the canonical opportunity
    /// after provider-confirmed delivery and lifecycle reconciliation.
    func sendFollowUp(opportunityId: String) async -> FollowUpActionOutcome {
        guard let opportunity = allOpportunities.first(where: { $0.id == opportunityId }),
              canSendFollowUp(for: opportunity) else {
            followUpUnavailableLeadIDs.insert(opportunityId)
            return .unavailable
        }

        switch followUpProgress(for: opportunityId) {
        case .sending:
            return .busy
        case .syncing:
            return .syncing
        case .unknown:
            return .unknown
        case .idle:
            break
        }

        followUpInFlightLeadIDs.insert(opportunityId)
        defer { followUpInFlightLeadIDs.remove(opportunityId) }

        guard let companyId, let currentUserId else {
            followUpUnavailableLeadIDs.insert(opportunityId)
            return .unavailable
        }
        let scope = LeadFollowUpAttemptScope(
            companyId: companyId,
            actorUserId: currentUserId,
            nextFollowUpAt: opportunity.nextFollowUpAt,
            handledAt: opportunity.handledAt,
            lastOutboundAt: opportunity.lastOutboundAt
        )

        switch await followUpService.sendFollowUp(
            opportunityId: opportunityId,
            scope: scope
        ) {
        case .reconciled(let canonicalDTO, let comebackAt):
            if let index = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
                allOpportunities[index].apply(canonicalDTO.toModel())
            }
            followUpReconcilingLeadIDs.remove(opportunityId)
            followUpUnknownLeadIDs.remove(opportunityId)
            followUpUnavailableLeadIDs.remove(opportunityId)
            NotificationCenter.default.post(
                name: Notification.Name("LeadUpdatedSuccess"),
                object: nil,
                userInfo: ["leadId": opportunityId]
            )
            return .sent(comebackAt: comebackAt)

        case .reconciledReceipt(let comebackAt):
            followUpReconcilingLeadIDs.remove(opportunityId)
            followUpUnknownLeadIDs.remove(opportunityId)
            followUpUnavailableLeadIDs.remove(opportunityId)
            scheduleRefresh(debounce: .zero)
            NotificationCenter.default.post(
                name: Notification.Name("LeadUpdatedSuccess"),
                object: nil,
                userInfo: ["leadId": opportunityId]
            )
            return .sent(comebackAt: comebackAt)

        case .providerAcceptedPending:
            followUpUnknownLeadIDs.remove(opportunityId)
            followUpReconcilingLeadIDs.insert(opportunityId)
            return .syncing

        case .deliveryUnknown:
            followUpReconcilingLeadIDs.remove(opportunityId)
            followUpUnknownLeadIDs.insert(opportunityId)
            return .unknown

        case .alreadyInProgress:
            followUpReconcilingLeadIDs.remove(opportunityId)
            followUpUnknownLeadIDs.insert(opportunityId)
            scheduleRefresh(debounce: .zero)
            return .unknown

        case .unavailable:
            followUpUnavailableLeadIDs.insert(opportunityId)
            return .unavailable

        case .rejected:
            return .rejected

        case .busy:
            return .busy

        case .signatureRequired:
            followUpUnavailableLeadIDs.insert(opportunityId)
            return .signatureRequired

        case .permissionDenied:
            followUpUnavailableLeadIDs.insert(opportunityId)
            return .permissionDenied

        case .networkError:
            return .networkError
        }
    }

    /// A realtime/foreground refresh clears a pending indicator only after the
    /// canonical row proves that the lead moved forward. This avoids treating
    /// a transport timeout as delivery while still letting background
    /// reconciliation finish the interaction without reopening the screen.
    func reconcileFollowUpProgressWithLoadedLeads(now: Date = Date()) {
        let unresolved = followUpReconcilingLeadIDs.union(followUpUnknownLeadIDs)
        for opportunityId in unresolved {
            guard let opportunity = allOpportunities.first(where: { $0.id == opportunityId }) else {
                continue
            }

            // A newer inbound message is canonical even when the send receipt
            // is still reconciling. Yield to YOUR MOVE immediately so stale
            // transport state never masks the customer's reply.
            if Self.isAwaitingReply(opportunity) {
                followUpReconcilingLeadIDs.remove(opportunityId)
                followUpUnknownLeadIDs.remove(opportunityId)
                continue
            }

            guard opportunity.lastMessageDirection == "out",
                  opportunity.handledAt != nil,
                  let comeback = opportunity.nextFollowUpAt,
                  comeback > now else {
                continue
            }
            followUpReconcilingLeadIDs.remove(opportunityId)
            followUpUnknownLeadIDs.remove(opportunityId)
        }
    }

    /// YOUR MOVE — correct ownership without rewriting correspondence history.
    func markOperatorActionRequired(opportunityId: String) async throws {
        guard let repo = repository else {
            throw NSError(domain: "Pipeline", code: 0)
        }
        // The database trigger replaces this sentinel with its own clock and
        // returns the authoritative row, preventing device skew from corrupting
        // newest-event ordering.
        let dto = try await repo.update(
            opportunityId,
            patch: MarkOperatorActionRequiredPatch(
                operatorActionRequiredAt: SupabaseDate.format(Date())
            )
        )
        if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
            allOpportunities[idx].apply(dto.toModel())
        }
        NotificationCenter.default.post(
            name: Notification.Name("LeadUpdatedSuccess"),
            object: nil,
            userInfo: ["leadId": opportunityId]
        )
    }

    /// ADJUST — reschedule when this lead resurfaces.
    func adjustComeback(opportunityId: String, to date: Date) async throws {
        guard let repo = repository else { return }
        let dto = try await repo.update(opportunityId, patch: AdjustComebackPatch(
            nextFollowUpAt: SupabaseDate.format(date)
        ))
        if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
            allOpportunities[idx].apply(dto.toModel())
        }
        NotificationCenter.default.post(name: Notification.Name("LeadUpdatedSuccess"),
                                        object: nil, userInfo: ["leadId": opportunityId])
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
        case waitingOnYou   // their touch is last AND not declared handled (isAwaitingReply)
        case fresh          // newLead stage with no activity yet
        case waitingOnThem  // catch-all for non-urgent open leads

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:           return "ALL"
            case .overdue:       return "OVERDUE"
            case .dueToday:      return "DUE TODAY"
            case .waitingOnYou:  return "YOUR MOVE"
            case .fresh:         return "NEW"
            case .waitingOnThem: return "WAITING"
            }
        }
    }

    /// YOUR MOVE is resolved from the newest correspondence or manual ownership
    /// signal. Manual corrections win exact ties; when inbound and outbound
    /// timestamps tie, the server's direction breaks the tie.
    nonisolated static func isAwaitingReply(_ opp: Opportunity) -> Bool {
        guard opp.stage != .newLead else { return false }

        let timestamps = [
            opp.lastInboundAt,
            opp.lastOutboundAt,
            opp.handledAt,
            opp.operatorActionRequiredAt
        ].compactMap { $0 }
        guard let latest = timestamps.max() else {
            return opp.lastMessageDirection == "in"
        }

        if opp.operatorActionRequiredAt == latest { return true }
        if opp.handledAt == latest { return false }

        let inboundIsLatest = opp.lastInboundAt == latest
        let outboundIsLatest = opp.lastOutboundAt == latest
        if inboundIsLatest && outboundIsLatest {
            return opp.lastMessageDirection == "in"
        }
        return inboundIsLatest
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
    /// and discarded leads are excluded entirely (all terminal stages).
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
                if opp.projectId == nil,
                   !LeadConversionVisibilityStore.shared.contains(opp.id) {
                    unconvertedWon.append(opp)
                }
                continue
            }
            // Drop every terminal stage from the triage queue. .won is handled
            // above (it can surface in the convert carousel); .lost and the
            // server-only .discarded state are excluded entirely.
            if opp.stage.isTerminal { continue }

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

            // YOUR MOVE — newest correspondence/manual signal requires action.
            // newLead routes to .fresh instead.
            if Self.isAwaitingReply(opp) {
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
        if Self.isAwaitingReply(lead) {
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

    // MARK: - Work-first summary (Leads redesign 2026-07, spec §7)
    //
    // Weighted probability is fully retired from lead surfaces — the summary
    // reads work (NEED ACTION) and real dollars (unweighted open pipeline,
    // won-this-month), never estimatedValue × winProbability.

    /// The number the operator answers to: overdue + due today + your move.
    var needActionCount: Int {
        let b = triageBuckets
        return b.overdue.count + b.dueToday.count + b.waitingOnYou.count
    }

    /// UNWEIGHTED sum of open leads' estimated value.
    var openPipelineValue: Double {
        allOpportunities.filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived }
            .reduce(0) { $0 + ($1.estimatedValue ?? 0) }
    }

    /// Won leads with an actualCloseDate in the current calendar month —
    /// actual value when recorded, estimated otherwise.
    var wonThisMonthValue: Double {
        let cal = Calendar.current
        return allOpportunities.filter { o in
            guard o.stage == .won, !o.isDeleted, let d = o.actualCloseDate else { return false }
            return cal.isDate(d, equalTo: Date(), toGranularity: .month)
        }.reduce(0) { $0 + ($1.actualValue ?? $1.estimatedValue ?? 0) }
    }
}
