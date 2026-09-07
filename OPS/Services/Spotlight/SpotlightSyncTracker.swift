//
//  SpotlightSyncTracker.swift
//  OPS
//
//  Collects per-sync-pass dirty / deleted entity IDs so Spotlight receives
//  targeted, minimal updates after each sync instead of a full re-index.
//  Owned by InboundProcessor; reset at sync start, dispatched in linkAllRelationships.
//

import Foundation
import SwiftData

@MainActor
final class SpotlightSyncTracker {

    private let manager: SpotlightIndexManager

    init(manager: SpotlightIndexManager? = nil) { self.manager = manager ?? .shared }

    private var dirtyByDomain: [String: Set<String>] = [:]
    private var deletedByDomain: [String: Set<String>] = [:]

    // MARK: - Marking

    func markDirty(domain: String, id: String) {
        // If we're marking something dirty that was previously marked deleted in
        // this same sync pass, the latest signal wins — clear the deletion.
        deletedByDomain[domain]?.remove(id)
        dirtyByDomain[domain, default: []].insert(id)
    }

    func markDeleted(domain: String, id: String) {
        // Deletion supersedes any prior dirty marking.
        dirtyByDomain[domain]?.remove(id)
        deletedByDomain[domain, default: []].insert(id)
    }

    // MARK: - Lifecycle

    func reset() {
        dirtyByDomain.removeAll()
        deletedByDomain.removeAll()
    }

    var isEmpty: Bool {
        dirtyByDomain.values.allSatisfy { $0.isEmpty } &&
        deletedByDomain.values.allSatisfy { $0.isEmpty }
    }

    // MARK: - Dispatch

    /// Apply the collected diff to Core Spotlight. Removes come first (so Spotlight
    /// doesn't briefly show stale data during the upsert pass), then upserts are
    /// dispatched by domain.
    ///
    /// For each dirty domain, we compare the requested ID set against what the fetch
    /// returns. If the entity was marked dirty but is no longer in SwiftData (deleted
    /// outside our tracked path — e.g. via an external cleanup), we issue an explicit
    /// remove so the index doesn't keep orphan entries.
    func dispatch(
        context: ModelContext,
        isCurrent: @MainActor () -> Bool = { true }
    ) async {
        guard !Task.isCancelled, isCurrent(), !isEmpty else { return }
        // Claim this batch before suspending. Marks received while it is in
        // flight belong to the next dispatch and must never be reset by it.
        let dirtyBatch = dirtyByDomain
        let deletedBatch = deletedByDomain
        reset()
        let container = context.container
        defer { withExtendedLifetime(container) {} }
        let mgr = manager

        // 1. Deletions — fire these first
        for (domain, ids) in deletedBatch where !ids.isEmpty {
            for id in ids {
                await mgr.remove(domain: domain, id: id, isCurrent: isCurrent)
                guard !Task.isCancelled, isCurrent() else { return }
            }
        }

        // 2. Upserts — per domain, with orphan cleanup
        if let ids = dirtyBatch[SpotlightDomain.project], !ids.isEmpty {
            let projects = fetchProjects(ids: ids, context: context)
            let foundIds = Set(projects.map { $0.id })
            for project in projects {
                await mgr.indexProject(project, isCurrent: isCurrent)
                guard !Task.isCancelled, isCurrent() else { return }
            }
            for missing in ids.subtracting(foundIds) {
                await mgr.remove(domain: SpotlightDomain.project, id: missing, isCurrent: isCurrent)
                guard !Task.isCancelled, isCurrent() else { return }
            }
        }

        if let ids = dirtyBatch[SpotlightDomain.client], !ids.isEmpty {
            let clients = fetchClients(ids: ids, context: context)
            let foundIds = Set(clients.map { $0.id })
            for client in clients {
                await mgr.indexClient(client, isCurrent: isCurrent)
                guard !Task.isCancelled, isCurrent() else { return }
            }
            for missing in ids.subtracting(foundIds) {
                await mgr.remove(domain: SpotlightDomain.client, id: missing, isCurrent: isCurrent)
                guard !Task.isCancelled, isCurrent() else { return }
            }
        }

        // Bug G4 — delta-update pass for sub-clients. Orphan cleanup mirrors the
        // client path: any id marked dirty that no longer has a SwiftData row
        // gets an explicit remove so Spotlight never shows phantom contacts.
        if let ids = dirtyBatch[SpotlightDomain.subClient], !ids.isEmpty {
            let subClients = fetchSubClients(ids: ids, context: context)
            let foundIds = Set(subClients.map { $0.id })
            for subClient in subClients {
                await mgr.indexSubClient(subClient, isCurrent: isCurrent)
                guard !Task.isCancelled, isCurrent() else { return }
            }
            for missing in ids.subtracting(foundIds) {
                await mgr.remove(domain: SpotlightDomain.subClient, id: missing, isCurrent: isCurrent)
                guard !Task.isCancelled, isCurrent() else { return }
            }
        }

        if let ids = dirtyBatch[SpotlightDomain.task], !ids.isEmpty {
            let tasks = fetchTasks(ids: ids, context: context)
            let foundIds = Set(tasks.map { $0.id })
            for task in tasks {
                await mgr.indexTask(task, isCurrent: isCurrent)
                guard !Task.isCancelled, isCurrent() else { return }
            }
            for missing in ids.subtracting(foundIds) {
                await mgr.remove(domain: SpotlightDomain.task, id: missing, isCurrent: isCurrent)
                guard !Task.isCancelled, isCurrent() else { return }
            }
        }

        if let ids = dirtyBatch[SpotlightDomain.invoice], !ids.isEmpty {
            let invoices = fetchInvoices(ids: ids, context: context)
            let foundIds = Set(invoices.map { $0.id })
            let clientIds = Set(invoices.compactMap { $0.clientId })
            let clientsById = fetchClientMap(ids: clientIds, context: context)
            for invoice in invoices {
                let clientName = invoice.clientId.flatMap { clientsById[$0]?.name }
                await mgr.indexInvoice(invoice, clientName: clientName, isCurrent: isCurrent)
                guard !Task.isCancelled, isCurrent() else { return }
            }
            for missing in ids.subtracting(foundIds) {
                await mgr.remove(domain: SpotlightDomain.invoice, id: missing, isCurrent: isCurrent)
                guard !Task.isCancelled, isCurrent() else { return }
            }
        }

        if let ids = dirtyBatch[SpotlightDomain.estimate], !ids.isEmpty {
            let estimates = fetchEstimates(ids: ids, context: context)
            let foundIds = Set(estimates.map { $0.id })
            let clientIds = Set(estimates.compactMap { $0.clientId })
            let clientsById = fetchClientMap(ids: clientIds, context: context)
            for estimate in estimates {
                let clientName = estimate.clientId.flatMap { clientsById[$0]?.name }
                await mgr.indexEstimate(estimate, clientName: clientName, isCurrent: isCurrent)
                guard !Task.isCancelled, isCurrent() else { return }
            }
            for missing in ids.subtracting(foundIds) {
                await mgr.remove(domain: SpotlightDomain.estimate, id: missing, isCurrent: isCurrent)
                guard !Task.isCancelled, isCurrent() else { return }
            }
        }

        let dirtyCount = dirtyBatch.values.reduce(0) { $0 + $1.count }
        let deletedCount = deletedBatch.values.reduce(0) { $0 + $1.count }
        print("[SpotlightSyncTracker] Dispatched \(dirtyCount) upserts, \(deletedCount) removals")

    }

    // MARK: - Typed fetch helpers

    private func fetchProjects(ids: Set<String>, context: ModelContext) -> [Project] {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchClients(ids: Set<String>, context: ModelContext) -> [Client] {
        let descriptor = FetchDescriptor<Client>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchSubClients(ids: Set<String>, context: ModelContext) -> [SubClient] {
        let descriptor = FetchDescriptor<SubClient>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchTasks(ids: Set<String>, context: ModelContext) -> [ProjectTask] {
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchInvoices(ids: Set<String>, context: ModelContext) -> [Invoice] {
        let descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchEstimates(ids: Set<String>, context: ModelContext) -> [Estimate] {
        let descriptor = FetchDescriptor<Estimate>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchClientMap(ids: Set<String>, context: ModelContext) -> [String: Client] {
        guard !ids.isEmpty else { return [:] }
        let descriptor = FetchDescriptor<Client>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        let clients = (try? context.fetch(descriptor)) ?? []
        return Dictionary(clients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
