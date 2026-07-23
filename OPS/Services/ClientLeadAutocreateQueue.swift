//
//  ClientLeadAutocreateQueue.swift
//  OPS
//
//  Durable delivery for the pipeline lead that follows a client create.
//  The client is the authoritative save; lead delivery retries independently.
//

import Foundation
import SwiftData

struct PendingClientLeadAutocreate: Codable, Equatable, Identifiable {
    let clientId: String
    let companyId: String
    let name: String
    let email: String?
    let phoneNumber: String?
    let address: String?
    let notes: String?
    let createdAt: Date

    // Retry-policy state (SYNC RECOVERY spec §3). Every field is OPTIONAL and
    // strictly additive: JSON persisted by the shipped v1 shape (which carries
    // none of these keys) still decodes — the synthesized Decodable uses
    // `decodeIfPresent` for optionals, so a missing key resolves to nil rather
    // than throwing. Declared `var` WITHOUT a default (never a defaulted `let`,
    // which Swift would drop from `CodingKeys` and fail to round-trip) so the
    // synthesized Codable keeps them and persists them.
    var attempts: Int?
    var lastAttemptAt: Date?
    var lastError: String?
    var parkedAt: Date?

    var id: String { clientId.lowercased() }

    /// Delivery attempts made so far (0 when the request has never been tried).
    var effectiveAttempts: Int { attempts ?? 0 }

    /// A parked request is a permanent server rejection: excluded from the
    /// automatic drain until a user Retry / unpark clears `parkedAt`.
    var isParked: Bool { parkedAt != nil }

    init(client: Client, companyId: String, createdAt: Date = Date()) {
        self.clientId = client.id
        self.companyId = companyId
        self.name = client.name
        self.email = client.email
        self.phoneNumber = client.phoneNumber
        self.address = client.address
        self.notes = client.notes
        self.createdAt = createdAt
        self.attempts = nil
        self.lastAttemptAt = nil
        self.lastError = nil
        self.parkedAt = nil
    }
}

struct ClientLeadAutocreateDelivery {
    let opportunityId: String
    let opportunityDTO: OpportunityDTO?
    let createdNow: Bool
}

@MainActor
protocol ClientLeadAutocreateQueueing: AnyObject {
    func enqueueAndDrainInBackground(_ client: Client, companyId: String)
}

@MainActor
final class ClientLeadAutocreateQueue: ClientLeadAutocreateQueueing {
    typealias Attempt = (PendingClientLeadAutocreate) async throws -> ClientLeadAutocreateDelivery
    typealias ActiveCompanyIdProvider = () -> String?

    // Deny live delivery until OPSApp supplies the authenticated company scope.
    // Test queues may omit a provider to exercise the pure delivery state machine.
    static let shared = ClientLeadAutocreateQueue(activeCompanyId: { nil })

    private let defaults: UserDefaults
    private let defaultsKey: String
    private let attempt: Attempt
    /// Injectable clock. Production reads the wall clock; tests substitute a
    /// controllable `now` to exercise the exponential backoff windows
    /// deterministically without sleeping.
    var now: () -> Date = { Date() }
    private var activeCompanyIdProvider: ActiveCompanyIdProvider?
    private var pending: [PendingClientLeadAutocreate]
    private var isDraining = false
    private var drainRequestedWhileRunning = false
    private var deliveryScopeGeneration = 0
    private var retryTimer: Timer?
    private weak var modelContext: ModelContext?

    init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = "pendingClientLeadAutocreates.v1",
        automaticRetry: Bool = true,
        activeCompanyId: ActiveCompanyIdProvider? = nil,
        attempt: Attempt? = nil
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        self.activeCompanyIdProvider = activeCompanyId
        self.attempt = attempt ?? Self.performLiveAttempt

        if let data = defaults.data(forKey: defaultsKey) {
            do {
                pending = try JSONDecoder().decode([PendingClientLeadAutocreate].self, from: data)
            } catch {
                pending = []
                print("[LEAD_AUTOCREATE_QUEUE] Could not decode pending deliveries: \(error)")
            }
        } else {
            pending = []
        }

        if automaticRetry {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.drain()
                }
            }
        }
    }

    deinit {
        retryTimer?.invalidate()
    }

    var pendingCount: Int { pending.count }

    /// Permanent server rejections awaiting a user decision (Retry / Discard).
    /// Consumed by the PENDING WORK recovery screen's NEEDS ATTENTION section.
    var parkedRequests: [PendingClientLeadAutocreate] { pending.filter { $0.isParked } }

    /// Requests still eligible for automatic delivery (never parked). Consumed
    /// by the recovery screen's in-flight section.
    var activeRequests: [PendingClientLeadAutocreate] { pending.filter { !$0.isParked } }

    func contains(clientId: String) -> Bool {
        let normalizedId = clientId.lowercased()
        return pending.contains { $0.id == normalizedId }
    }

    func configure(
        modelContext: ModelContext,
        activeCompanyId: @escaping ActiveCompanyIdProvider
    ) {
        self.modelContext = modelContext
        activeCompanyIdProvider = activeCompanyId
        invalidateDeliveryScope()
    }

    /// Invalidates every in-flight delivery result across logout, login, or
    /// company switches. A server write that completed during the transition
    /// stays queued and is reconciled by its idempotency key in the right scope.
    func invalidateDeliveryScope() {
        deliveryScopeGeneration &+= 1
        if isDraining {
            drainRequestedWhileRunning = true
        }
    }

    func enqueue(_ client: Client, companyId: String) {
        let request = PendingClientLeadAutocreate(client: client, companyId: companyId)
        if let index = pending.firstIndex(where: { $0.id == request.id }) {
            pending[index] = request
        } else {
            pending.append(request)
        }
        persist()
    }

    func enqueueAndDrainInBackground(_ client: Client, companyId: String) {
        enqueue(client, companyId: companyId)
        Task { @MainActor [weak self] in
            await self?.drain()
        }
    }

    /// User Retry on a single parked request: clear the park + retry state so it
    /// re-enters the automatic drain immediately, then drain.
    func retryParked(clientId: String) {
        let normalizedId = clientId.lowercased()
        guard let index = pending.firstIndex(where: { $0.id == normalizedId }) else { return }
        clearRetryState(at: index)
        persist()
        Task { @MainActor [weak self] in
            await self?.drain()
        }
    }

    /// RETRY ALL on the recovery screen: clear every parked request's park +
    /// retry state, then drain.
    func unparkAll() {
        var mutated = false
        for index in pending.indices where pending[index].isParked {
            clearRetryState(at: index)
            mutated = true
        }
        guard mutated else { return }
        persist()
        Task { @MainActor [weak self] in
            await self?.drain()
        }
    }

    /// Discard: drop a request entirely (parked or active). The authoritative
    /// local client stays; only the durable lead-delivery receipt is removed.
    func removeRequest(clientId: String) {
        let normalizedId = clientId.lowercased()
        guard pending.contains(where: { $0.id == normalizedId }) else { return }
        pending.removeAll { $0.id == normalizedId }
        persist()
    }

    /// Resets a request to a fresh delivery budget. Clears `parkedAt`,
    /// `attempts`, `lastAttemptAt`, and `lastError` together — a user-initiated
    /// retry means "try now", so the whole backoff pair is cleared, not just the
    /// park flag (a reset `attempts` beside a stale `lastAttemptAt` would impose
    /// a phantom backoff on work the operator just asked to send).
    private func clearRetryState(at index: Int) {
        pending[index].parkedAt = nil
        pending[index].attempts = nil
        pending[index].lastAttemptAt = nil
        pending[index].lastError = nil
    }

    func drain() async {
        if isDraining {
            drainRequestedWhileRunning = true
            return
        }
        guard !pending.isEmpty else { return }
        isDraining = true
        defer {
            isDraining = false
            if drainRequestedWhileRunning {
                drainRequestedWhileRunning = false
                Task { @MainActor [weak self] in
                    await self?.drain()
                }
            }
        }

        // Snapshot the ids, then re-read each request's live state every
        // iteration — a prior iteration may have parked, backed off, delivered,
        // or removed it.
        let requestIds = pending.map { $0.id }
        for requestId in requestIds {
            guard let request = pending.first(where: { $0.id == requestId }) else { continue }

            // A permanent rejection is parked until the operator Retries — never
            // auto-retried. This is the guard that stops the class of bug that
            // burned the retry budget on a hopeless 400 from ever recurring.
            if request.isParked { continue }

            // Respect the exponential backoff window since the last attempt.
            guard isEligibleForDrain(request) else { continue }

            guard deliveryScopeAllows(request) else { continue }
            let attemptScopeGeneration = deliveryScopeGeneration

            do {
                let delivery = try await attempt(request)

                guard attemptScopeGeneration == deliveryScopeGeneration,
                      deliveryScopeAllows(request) else {
                    // The account/company changed while the request was in
                    // flight. Never inject the old result into the new scope or
                    // clear its durable receipt. The correct scope will read it
                    // back later by the unique idempotency key.
                    print(
                        "[LEAD_AUTOCREATE_QUEUE] Scope changed during delivery for client "
                            + request.clientId
                    )
                    continue
                }

                applyLocalDelivery(delivery)
                bindSiteVisitDrafts(forClientId: request.clientId, delivery: delivery)
                pending.removeAll { $0.id == request.id }
                persist()

                NotificationCenter.default.post(name: .opsLeadsDidChange, object: nil)

                if delivery.createdNow {
                    NotificationCenter.default.post(
                        name: Notification.Name("LeadCreatedSuccess"),
                        object: nil,
                        userInfo: ["leadId": delivery.opportunityId]
                    )
                }

                print(
                    "[LEAD_AUTOCREATE_QUEUE] Delivered client \(request.clientId) "
                        + "to opportunity \(delivery.opportunityId)"
                )
            } catch {
                // Classify the failure identically to the outbound sync engine:
                // permanent rejections park (no further auto-retry, ever),
                // transient/auth failures increment attempts and back off. Either
                // way the request stays durably queued.
                recordAttemptFailure(clientId: requestId, error: error)
            }
        }
    }

    /// A request is eligible for a fresh attempt when it has never been tried
    /// (`lastAttemptAt == nil`) or the exponential backoff window since its last
    /// attempt has elapsed. Parked requests are excluded before this runs.
    private func isEligibleForDrain(_ request: PendingClientLeadAutocreate) -> Bool {
        guard let lastAttemptAt = request.lastAttemptAt else { return true }
        let window = Self.backoffInterval(attempts: request.effectiveAttempts)
        return now() >= lastAttemptAt.addingTimeInterval(window)
    }

    /// Exponential backoff between delivery attempts: 60s base, doubling per
    /// attempt, capped at 900s (15 min) — `min(60 · 2^min(attempts,4), 900)`.
    /// The slow drain timer plus this backoff make an attempt cap unnecessary; a
    /// permanent rejection parks (never retries) rather than burning a budget.
    static func backoffInterval(attempts: Int) -> TimeInterval {
        min(60 * pow(2.0, Double(min(attempts, 4))), 900)
    }

    /// Applies the shared sync failure disposition to a queued request. Permanent
    /// rejections park immediately (no further auto-retry, ever); transient and
    /// auth failures increment the attempt count and stamp the backoff clock.
    /// Mirrors `SyncOperationFailurePolicy` so the queue and the outbound sync
    /// engine react to a failed push identically.
    private func recordAttemptFailure(clientId: String, error: Error) {
        guard let index = pending.firstIndex(where: { $0.id == clientId }) else { return }
        let disposition = SyncErrorClassifier.disposition(for: error)
        let description = String(describing: error)
        let stampedAt = now()

        switch disposition {
        case .permanent:
            pending[index].parkedAt = stampedAt
            pending[index].lastError = description
            persist()
            AnalyticsService.shared.track(
                eventType: .error,
                eventName: "lead_autocreate_parked",
                properties: [
                    "error_type": description,
                    "attempts": pending[index].effectiveAttempts,
                    "entity_type": "opportunity",
                    "operation_type": "autocreate"
                ]
            )
            print(
                "[LEAD_AUTOCREATE_QUEUE] Parked client \(pending[index].clientId) — "
                    + "server rejected it (permanent); will not auto-retry: \(description)"
            )

        case .transient, .auth:
            pending[index].attempts = pending[index].effectiveAttempts + 1
            pending[index].lastAttemptAt = stampedAt
            pending[index].lastError = description
            persist()
            print(
                "[LEAD_AUTOCREATE_QUEUE] Delivery deferred for client "
                    + "\(pending[index].clientId) (attempt \(pending[index].effectiveAttempts)): "
                    + "\(description)"
            )
        }
    }

    private func deliveryScopeAllows(_ request: PendingClientLeadAutocreate) -> Bool {
        guard let activeCompanyIdProvider else { return true }
        guard let activeCompanyId = activeCompanyIdProvider(),
              !activeCompanyId.isEmpty else { return false }
        return activeCompanyId.caseInsensitiveCompare(request.companyId) == .orderedSame
    }

    private func applyLocalDelivery(_ delivery: ClientLeadAutocreateDelivery) {
        guard let dto = delivery.opportunityDTO,
              let modelContext else { return }

        let opportunityId = dto.id
        let descriptor = FetchDescriptor<Opportunity>(
            predicate: #Predicate<Opportunity> { $0.id == opportunityId }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        modelContext.insert(dto.toModel())
        do {
            try modelContext.save()
        } catch {
            // The server delivery already succeeded. Realtime / the next REST
            // refresh remains the source of truth if this local cache write fails.
            print("[LEAD_AUTOCREATE_QUEUE] Local opportunity cache deferred: \(error)")
        }
    }

    /// Binds any local site-visit identity drafts (and their visits) that were
    /// waiting on THIS client's lead. A durable queue delivery is the moment the
    /// lead becomes real, so the visit capture that started the client finally
    /// receives its `opportunityId` — closing RC4 (the one-shot site-visit lead
    /// create). Only unbound drafts (nil `opportunityId`) matching the delivered
    /// client are touched; an operator's later hand-binding is never clobbered.
    private func bindSiteVisitDrafts(
        forClientId clientId: String,
        delivery: ClientLeadAutocreateDelivery
    ) {
        guard let modelContext else { return }
        let normalizedClientId = clientId.lowercased()

        // `#Predicate` can't express a reliable case-insensitive String equality,
        // so fetch the unbound drafts and match the clientId in memory.
        let draftDescriptor = FetchDescriptor<SiteVisitIdentityDraft>(
            predicate: #Predicate<SiteVisitIdentityDraft> { $0.opportunityId == nil }
        )
        guard let unboundDrafts = try? modelContext.fetch(draftDescriptor) else { return }
        let matches = unboundDrafts.filter {
            ($0.clientId ?? "").lowercased() == normalizedClientId
        }
        guard !matches.isEmpty else { return }

        let boundAt = now()
        for draft in matches {
            draft.opportunityId = delivery.opportunityId
            draft.lastCommittedAt = boundAt
            draft.touch()

            let visitId = draft.siteVisitId
            let visitDescriptor = FetchDescriptor<SiteVisit>(
                predicate: #Predicate<SiteVisit> { $0.id == visitId }
            )
            if let visit = (try? modelContext.fetch(visitDescriptor))?.first,
               visit.opportunityId == nil {
                visit.opportunityId = delivery.opportunityId
            }
        }

        do {
            try modelContext.save()
        } catch {
            // The lead already exists server-side; a deferred local bind reconciles
            // on the next inbound refresh. Never fail the delivery over the cache.
            print("[LEAD_AUTOCREATE_QUEUE] Site-visit binding save deferred: \(error)")
        }

        // Nudge any open capture UI to refresh its binding — one signal per visit.
        for draft in matches {
            NotificationCenter.default.post(
                name: Notification.Name("SiteVisitLeadBound"),
                object: nil,
                userInfo: ["siteVisitId": draft.siteVisitId]
            )
        }
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(pending), forKey: defaultsKey)
        } catch {
            print("[LEAD_AUTOCREATE_QUEUE] Could not persist pending deliveries: \(error)")
        }
    }

    private static func performLiveAttempt(
        _ request: PendingClientLeadAutocreate
    ) async throws -> ClientLeadAutocreateDelivery {
        // DataController creates clients local-first. Do not attempt the child
        // opportunity until the parent client is visible to this authenticated
        // Supabase session.
        _ = try await ClientRepository(companyId: request.companyId).fetchOne(request.clientId)

        let repository = OpportunityRepository(companyId: request.companyId)
        if let existing = try await repository.fetchFirstActiveLinked(toClientId: request.clientId) {
            return ClientLeadAutocreateDelivery(
                opportunityId: existing.id,
                opportunityDTO: existing,
                createdNow: false
            )
        }

        let sourceThreadKey = ClientLeadAutocreate.sourceThreadKey(forClientId: request.clientId)
        if let existing = try await repository.fetchBySourceThreadKey(sourceThreadKey) {
            return ClientLeadAutocreateDelivery(
                opportunityId: existing.id,
                opportunityDTO: existing,
                createdNow: false
            )
        }

        guard let dto = ClientLeadAutocreate.makeOpportunityDTO(for: request) else {
            throw ClientLeadAutocreateError.missingClientName
        }

        do {
            let created = try await repository.create(dto)
            return ClientLeadAutocreateDelivery(
                opportunityId: created.id,
                opportunityDTO: created,
                createdNow: true
            )
        } catch {
            let createError = error

            // The insert response may have failed after the database committed.
            // The unique source key prevents a second insert; immediate readback
            // lets this attempt clear the receipt without waiting for the timer.
            if let existing = try? await repository.fetchBySourceThreadKey(sourceThreadKey) {
                return ClientLeadAutocreateDelivery(
                    opportunityId: existing.id,
                    opportunityDTO: existing,
                    createdNow: false
                )
            }
            throw createError
        }
    }
}
