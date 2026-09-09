//
//  NotificationThreadLeadCache.swift
//  OPS
//
//  The rail's email-thread → lead lookup: one batched request, once per thread
//  id, cached for the life of the list.
//
//  Bug 589e3b1e — the rail can hold 50 inbox rows citing 50 distinct threads.
//  Resolving them one at a time (the shape the single-row tap path uses) is a
//  network storm on a truck's connection, and re-resolving on every filter flip
//  would repeat it. This cache is the seam: it asks only for ids it has never
//  seen, in one `.in("id", …)` select, and keeps the answers.
//
//  Failure is silent on purpose. A thrown read leaves the cache untouched, so
//  the rows stay ungrouped and behave exactly as they did before — the app
//  never claims "no lead" on the strength of a request that did not complete.
//

import Foundation

/// The one read the rail needs from `email_threads`. A protocol so the rail's
/// grouping can be exercised without a Supabase client.
protocol EmailThreadLeadResolving {
    /// Opportunity id per thread id, with an entry for every id asked for.
    func opportunityIds(forEmailThreadIds ids: [String]) async throws -> [String: String?]
}

extension OpportunityRepository: EmailThreadLeadResolving {}

@MainActor
final class NotificationThreadLeadCache {
    /// Thread id → opportunity id. A key present with a nil value means
    /// "looked up, no lead". A key absent means "never looked up".
    private(set) var resolved: [String: String?] = [:]

    init(resolved: [String: String?] = [:]) {
        self.resolved = resolved
    }

    /// Resolve every thread id these notifications need and that the cache does
    /// not already hold. Performs no request when there is nothing new to ask.
    func resolve(
        for notifications: [NotificationDTO],
        using resolver: EmailThreadLeadResolving
    ) async {
        let pending = NotificationInboxGrouping.threadIdsNeedingResolution(
            in: notifications,
            alreadyResolved: Set(resolved.keys)
        )
        guard !pending.isEmpty else { return }

        do {
            let answers = try await resolver.opportunityIds(forEmailThreadIds: pending)
            for (threadId, opportunityId) in answers {
                resolved[threadId] = opportunityId
            }
        } catch {
            // Leave the cache alone: unresolved rows render exactly as before.
            print("[NOTIFICATIONS] Thread→lead resolution failed: \(error)")
        }
    }
}
