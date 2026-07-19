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

    var id: String { clientId.lowercased() }

    init(client: Client, companyId: String, createdAt: Date = Date()) {
        self.clientId = client.id
        self.companyId = companyId
        self.name = client.name
        self.email = client.email
        self.phoneNumber = client.phoneNumber
        self.address = client.address
        self.notes = client.notes
        self.createdAt = createdAt
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

        let requests = pending
        for request in requests {
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
                // Leave this request durably queued. A later timer, foreground,
                // authentication, or connectivity-restored drain will retry it.
                print(
                    "[LEAD_AUTOCREATE_QUEUE] Delivery deferred for client "
                        + "\(request.clientId): \(error)"
                )
            }
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
