//
//  ClientLeadsViewModel.swift
//  OPS
//
//  Loads and shapes a client's pipeline leads for the client-profile Leads
//  section (ContactDetailView). Leads are not SwiftData-synced, so this
//  fetches via OpportunityRepository and holds results in memory. `apply` is
//  a pure transform (view-scope filter → open/closed split → sort → tally),
//  exposed for tests.
//
//  Spec: docs/superpowers/specs/2026-07-21-ios-client-leads-section-design.md
//

import Foundation
import Combine

@MainActor
final class ClientLeadsViewModel: ObservableObject {

    enum LoadState: Equatable { case idle, loading, loaded, error }

    struct OutcomeTally: Equatable {
        var won = 0
        var lost = 0
        var discarded = 0
        var hasAny: Bool { won + lost + discarded > 0 }
    }

    @Published private(set) var openLeads: [Opportunity] = []
    @Published private(set) var closedLeads: [Opportunity] = []
    @Published private(set) var tally = OutcomeTally()
    @Published private(set) var loadState: LoadState = .idle

    /// Test seam — inject a fixed lead set. Nil in production (uses the repository).
    var loaderOverride: ((_ companyId: String, _ clientId: String) async throws -> [Opportunity])?

    /// Pure transform: keep only viewable / non-deleted / non-archived leads for
    /// this client; split open vs. terminal; sort; tally the closed outcomes.
    func apply(_ leads: [Opportunity], clientId: String, policy: LeadAccessPolicy) {
        let visible = leads.filter {
            !$0.isDeleted
            && !$0.isArchived
            && $0.clientId == clientId
            && policy.can(.view, assignedTo: $0.assignedTo)
        }

        openLeads = visible
            .filter { !$0.stage.isTerminal }
            .sorted { openSortKey($0) > openSortKey($1) }

        closedLeads = visible
            .filter { $0.stage.isTerminal }
            .sorted { closedSortKey($0) > closedSortKey($1) }

        var t = OutcomeTally()
        for lead in closedLeads {
            switch lead.stage {
            case .won:       t.won += 1
            case .lost:      t.lost += 1
            case .discarded: t.discarded += 1
            default:         break
            }
        }
        tally = t
    }

    func load(companyId: String, clientId: String, policy: LeadAccessPolicy) async {
        loadState = .loading
        do {
            let leads: [Opportunity]
            if let loaderOverride {
                leads = try await loaderOverride(companyId, clientId)
            } else {
                let repo = OpportunityRepository(companyId: companyId)
                leads = try await repo.fetchAllLinked(toClientId: clientId).map { $0.toModel() }
            }
            apply(leads, clientId: clientId, policy: policy)
            loadState = .loaded
        } catch {
            loadState = .error
        }
    }

    // Open: most-recent activity first. `updatedAt` is non-optional, so this
    // always resolves to a concrete date.
    private func openSortKey(_ o: Opportunity) -> Date {
        o.lastActivityAt ?? o.updatedAt
    }

    // Closed: most-recently closed first.
    private func closedSortKey(_ o: Opportunity) -> Date {
        o.actualCloseDate ?? o.updatedAt
    }
}
