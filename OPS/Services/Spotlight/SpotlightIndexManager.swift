//
//  SpotlightIndexManager.swift
//  OPS
//
//  Central entry point for Core Spotlight indexing. Permission-gated,
//  hooked into InboundProcessor for sync-driven updates.
//
//  Delete-propagation: the re-index pass in `backfill` naturally drops
//  soft-deleted entities via `deletedAt == nil` filters on each fetch.
//  Incremental updates use `SpotlightSyncTracker` for targeted updates.
//

import Foundation
import CoreSpotlight
import SwiftData

@MainActor
final class SpotlightIndexManager {
    static let shared = SpotlightIndexManager()

    private let index = CSSearchableIndex.default()
    private var isIndexing = false

    private init() {}

    // MARK: - Permission Gates

    /// Determines which entity types the current user is allowed to have indexed.
    ///
    /// Core CRUD entities (projects, clients, tasks) are indexable for every
    /// authenticated company member — fine-grained visibility is handled below
    /// by passesProjectScopeFilter / passesClientScopeFilter / passesTaskScopeFilter,
    /// which already enforce company scope, team assignment, and status gates.
    /// Gating the whole domain on `projects.view` / `clients.view` caused clients
    /// to silently disappear for roles whose permission dict does not define
    /// those keys (the codebase elsewhere uses `scope(for:) ?? "all"` with a
    /// safe default — see SyncEngine, InboundProcessor).
    ///
    /// Money-tab entities (invoices, estimates) keep their explicit gate because
    /// that mirrors the Money tab's own visibility contract.
    private func allowedDomains() -> Set<String> {
        let perms = PermissionStore.shared
        var allowed: Set<String> = [
            SpotlightDomain.project,
            SpotlightDomain.client,
            // Bug G4 — SubClients (site/billing contacts) inherit the same
            // visibility contract as their parent Client entity, so they
            // piggyback on the client domain gating below.
            SpotlightDomain.subClient,
            SpotlightDomain.task
        ]

        if perms.can("pipeline.view") {
            allowed.insert(SpotlightDomain.invoice)
            allowed.insert(SpotlightDomain.estimate)
        }
        if perms.can("estimates.view") {
            allowed.insert(SpotlightDomain.estimate)
        }

        return allowed
    }

    // MARK: - Full Backfill

    /// Per-user backfill flag. Scoped to the current user so a shared device
    /// (manager logging in on a field worker's phone) triggers a fresh backfill
    /// for each account. Falls back to a legacy key if no user is available.
    private func backfillFlagKey(forUserId userId: String? = nil) -> String {
        let id = userId ?? UserDefaults.standard.string(forKey: "currentUserId") ?? ""
        return id.isEmpty
            ? "spotlight.initialBackfillComplete"
            : "spotlight.initialBackfillComplete.\(id)"
    }

    /// Index all allowed entities from SwiftData. Called on first launch after
    /// feature deployment, or after major permission/role changes.
    func backfill(context: ModelContext, progress: ((Double, String) -> Void)? = nil) async {
        guard !isIndexing else { return }
        isIndexing = true
        defer { isIndexing = false }

        let allowed = allowedDomains()
        let steps = Double(max(allowed.count, 1))
        var current = 0.0

        if allowed.contains(SpotlightDomain.project) {
            await indexAllProjects(context: context)
            current += 1
            progress?(current / steps, "Projects")
        }
        if allowed.contains(SpotlightDomain.client) {
            await indexAllClients(context: context)
            current += 1
            progress?(current / steps, "Clients")
        }
        // Bug G4 — backfill sub-clients right after clients so the parent
        // lookup used to resolve parentClientName hits the just-written
        // client rows in SwiftData.
        if allowed.contains(SpotlightDomain.subClient) {
            await indexAllSubClients(context: context)
            current += 1
            progress?(current / steps, "Contacts")
        }
        if allowed.contains(SpotlightDomain.task) {
            await indexAllTasks(context: context)
            current += 1
            progress?(current / steps, "Tasks")
        }
        if allowed.contains(SpotlightDomain.invoice) {
            await indexAllInvoices(context: context)
            current += 1
            progress?(current / steps, "Invoices")
        }
        if allowed.contains(SpotlightDomain.estimate) {
            await indexAllEstimates(context: context)
            current += 1
            progress?(current / steps, "Estimates")
        }

        UserDefaults.standard.set(true, forKey: backfillFlagKey())
    }

    var hasCompletedInitialBackfill: Bool {
        UserDefaults.standard.bool(forKey: backfillFlagKey())
    }

    // MARK: - Clear

    /// Clear the entire OPS Spotlight index. Called on logout and role change.
    ///
    /// Callers from logout paths must pass `forUserId` explicitly because
    /// `currentUserId` in `UserDefaults` may already be cleared by the time
    /// the async body runs (logout tears down auth state synchronously, then
    /// the `Task { await clearAll() }` wakes up on a later tick). Without an
    /// explicit user id, the backfill flag for the logged-out user would leak
    /// in `UserDefaults` indefinitely.
    func clearAll(forUserId explicitUserId: String? = nil) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            index.deleteSearchableItems(withDomainIdentifiers: SpotlightDomain.all) { error in
                if let error = error {
                    print("[Spotlight] Failed to clear: \(error)")
                }
                continuation.resume()
            }
        }
        UserDefaults.standard.removeObject(forKey: backfillFlagKey(forUserId: explicitUserId))
        print("[Spotlight] Cleared all indexed items")
    }

    // MARK: - Bulk index methods

    private func indexAllProjects(context: ModelContext) async {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        guard let projects = try? context.fetch(descriptor) else { return }

        let filtered = projects.filter { passesProjectScopeFilter($0) }
        let sorted = filtered.sorted { ($0.lastSyncedAt ?? .distantPast) > ($1.lastSyncedAt ?? .distantPast) }
        let items = sorted.map { SpotlightItemBuilder.buildProject($0) }
        await indexInBatches(items)
        print("[Spotlight] Indexed \(items.count) projects")
    }

    private func indexAllClients(context: ModelContext) async {
        guard let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") else { return }
        let descriptor = FetchDescriptor<Client>(
            predicate: #Predicate { $0.deletedAt == nil && $0.companyId == companyId }
        )
        guard let clients = try? context.fetch(descriptor) else { return }

        // Pre-download avatars for thumbnails
        await preloadAvatars(for: clients)

        let sorted = clients.sorted { ($0.lastSyncedAt ?? .distantPast) > ($1.lastSyncedAt ?? .distantPast) }
        let items = sorted.map { SpotlightItemBuilder.buildClient($0) }
        await indexInBatches(items)
        print("[Spotlight] Indexed \(items.count) clients")
    }

    /// Bug G4 — bulk-index all sub-clients for the current company. Sub-clients
    /// don't have their own companyId column; scope is enforced through the
    /// parent client relationship (parent.companyId == currentUserCompanyId).
    private func indexAllSubClients(context: ModelContext) async {
        guard let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") else { return }
        let descriptor = FetchDescriptor<SubClient>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        guard let subClients = try? context.fetch(descriptor) else { return }

        // Filter by parent client's company + soft-delete; drop orphans (parent missing).
        let filtered = subClients.filter { sub in
            guard let parent = sub.client,
                  parent.deletedAt == nil,
                  parent.companyId == companyId else { return false }
            return true
        }
        let sorted = filtered.sorted { ($0.lastSyncedAt ?? .distantPast) > ($1.lastSyncedAt ?? .distantPast) }
        let items = sorted.map { SpotlightItemBuilder.buildSubClient($0, parentClientName: $0.client?.name) }
        await indexInBatches(items)
        print("[Spotlight] Indexed \(items.count) sub-clients")
    }

    private func indexAllTasks(context: ModelContext) async {
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        guard let tasks = try? context.fetch(descriptor) else { return }

        let filtered = tasks.filter { passesTaskScopeFilter($0) }
        let sorted = filtered.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        let items = sorted.map { SpotlightItemBuilder.buildTask($0) }
        await indexInBatches(items)
        print("[Spotlight] Indexed \(items.count) tasks")
    }

    private func indexAllInvoices(context: ModelContext) async {
        guard let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") else { return }
        let descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate { $0.deletedAt == nil && $0.companyId == companyId }
        )
        guard let invoices = try? context.fetch(descriptor) else { return }

        let clientsById = fetchClientMap(context: context)
        let sorted = invoices.sorted { $0.updatedAt > $1.updatedAt }
        let items = sorted.map { invoice -> CSSearchableItem in
            let clientName = invoice.clientId.flatMap { clientsById[$0]?.name }
            return SpotlightItemBuilder.buildInvoice(invoice, clientName: clientName)
        }
        await indexInBatches(items)
        print("[Spotlight] Indexed \(items.count) invoices")
    }

    private func indexAllEstimates(context: ModelContext) async {
        guard let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") else { return }
        let descriptor = FetchDescriptor<Estimate>(
            predicate: #Predicate { $0.deletedAt == nil && $0.companyId == companyId }
        )
        guard let estimates = try? context.fetch(descriptor) else { return }

        let clientsById = fetchClientMap(context: context)
        let sorted = estimates.sorted { $0.updatedAt > $1.updatedAt }
        let items = sorted.map { estimate -> CSSearchableItem in
            let clientName = estimate.clientId.flatMap { clientsById[$0]?.name }
            return SpotlightItemBuilder.buildEstimate(estimate, clientName: clientName)
        }
        await indexInBatches(items)
        print("[Spotlight] Indexed \(items.count) estimates")
    }

    // MARK: - Incremental Updates

    /// Index a single project. If the project no longer passes the scope filter
    /// (e.g. user's role changed, project is deleted), REMOVE it from the index.
    /// Never a no-op — stale data in Spotlight is a bug.
    func indexProject(_ project: Project) async {
        guard allowedDomains().contains(SpotlightDomain.project),
              project.deletedAt == nil,
              passesProjectScopeFilter(project) else {
            await remove(domain: SpotlightDomain.project, id: project.id)
            return
        }
        let item = SpotlightItemBuilder.buildProject(project)
        await indexInBatches([item])
    }

    func indexClient(_ client: Client) async {
        guard allowedDomains().contains(SpotlightDomain.client),
              client.deletedAt == nil,
              passesClientScopeFilter(client) else {
            await remove(domain: SpotlightDomain.client, id: client.id)
            return
        }
        if let url = client.profileImageURL, !url.isEmpty,
           !ClientAvatarCache.shared.exists(remoteURL: url) {
            _ = await ClientAvatarCache.shared.ensureCached(remoteURL: url)
        }
        let item = SpotlightItemBuilder.buildClient(client)
        await indexInBatches([item])
    }

    /// Bug G4 — incremental upsert for a single sub-client. Mirrors `indexClient`:
    /// removes the entry outright if scope no longer passes (parent gone /
    /// soft-deleted / company mismatch) so stale data doesn't linger.
    func indexSubClient(_ subClient: SubClient) async {
        guard allowedDomains().contains(SpotlightDomain.subClient),
              subClient.deletedAt == nil,
              passesSubClientScopeFilter(subClient) else {
            await remove(domain: SpotlightDomain.subClient, id: subClient.id)
            return
        }
        let item = SpotlightItemBuilder.buildSubClient(subClient, parentClientName: subClient.client?.name)
        await indexInBatches([item])
    }

    func indexTask(_ task: ProjectTask) async {
        guard allowedDomains().contains(SpotlightDomain.task),
              task.deletedAt == nil,
              passesTaskScopeFilter(task) else {
            await remove(domain: SpotlightDomain.task, id: task.id)
            return
        }
        let item = SpotlightItemBuilder.buildTask(task)
        await indexInBatches([item])
    }

    func indexInvoice(_ invoice: Invoice, clientName: String?) async {
        guard allowedDomains().contains(SpotlightDomain.invoice),
              invoice.deletedAt == nil else {
            await remove(domain: SpotlightDomain.invoice, id: invoice.id)
            return
        }
        let item = SpotlightItemBuilder.buildInvoice(invoice, clientName: clientName)
        await indexInBatches([item])
    }

    func indexEstimate(_ estimate: Estimate, clientName: String?) async {
        guard allowedDomains().contains(SpotlightDomain.estimate),
              estimate.deletedAt == nil else {
            await remove(domain: SpotlightDomain.estimate, id: estimate.id)
            return
        }
        let item = SpotlightItemBuilder.buildEstimate(estimate, clientName: clientName)
        await indexInBatches([item])
    }

    /// Remove a specific entity from the index.
    func remove(domain: String, id: String) async {
        let itemId = SpotlightItemId.make(domain: domain, id: id)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            index.deleteSearchableItems(withIdentifiers: [itemId]) { error in
                if let error = error {
                    print("[Spotlight] Remove error: \(error)")
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Scope Filters

    private func passesProjectScopeFilter(_ project: Project) -> Bool {
        let perms = PermissionStore.shared
        let userId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
        let isFieldCrew = !perms.hasFullAccess("projects.view")
        let hasPipelineAccess = perms.can("pipeline.view")
        // Bug G9 — Spotlight is a wide surface (reachable via system search);
        // mention-granted projects must be indexed so tagged users can find them.
        if isFieldCrew && !ProjectAccessHelper.wideVisible(project, userId: userId) { return false }
        if !hasPipelineAccess && (project.status == .rfq || project.status == .estimated) { return false }
        return true
    }

    private func passesClientScopeFilter(_ client: Client) -> Bool {
        guard let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") else { return false }
        return client.companyId == companyId
    }

    /// Bug G4 — sub-client scope mirrors client scope via the parent relationship.
    /// Orphans (parent deleted or missing) are excluded so Spotlight doesn't
    /// surface contacts whose client has been removed.
    private func passesSubClientScopeFilter(_ subClient: SubClient) -> Bool {
        guard let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId"),
              let parent = subClient.client,
              parent.deletedAt == nil,
              parent.companyId == companyId else { return false }
        return true
    }

    private func passesTaskScopeFilter(_ task: ProjectTask) -> Bool {
        guard let project = task.project, project.deletedAt == nil else { return false }
        let perms = PermissionStore.shared
        let userId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
        let isFieldCrew = !perms.hasFullAccess("projects.view")
        // Bug G9 — tasks on mention-granted projects are searchable.
        if isFieldCrew && !ProjectAccessHelper.wideVisible(project, userId: userId) { return false }
        return true
    }

    // MARK: - Batching

    private func indexInBatches(_ items: [CSSearchableItem], batchSize: Int = 100) async {
        guard !items.isEmpty else { return }
        var offset = 0
        while offset < items.count {
            let end = min(offset + batchSize, items.count)
            let batch = Array(items[offset..<end])
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                index.indexSearchableItems(batch) { error in
                    if let error = error {
                        print("[Spotlight] Batch index error: \(error)")
                    }
                    continuation.resume()
                }
            }
            offset = end
        }
    }

    // MARK: - Avatar preload

    private func preloadAvatars(for clients: [Client]) async {
        await withTaskGroup(of: Void.self) { group in
            for client in clients {
                guard let url = client.profileImageURL, !url.isEmpty,
                      !ClientAvatarCache.shared.exists(remoteURL: url) else { continue }
                group.addTask {
                    _ = await ClientAvatarCache.shared.ensureCached(remoteURL: url)
                }
            }
        }
    }

    private func fetchClientMap(context: ModelContext) -> [String: Client] {
        let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        return Dictionary(clients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
