//
//  ActivityTargetLoader.swift
//  OPS
//
//  Loads the cross-source candidate list (leads + clients + jobs) that backs
//  ActivityTargetPickerView. Fetches each SwiftData model with a bare
//  FetchDescriptor and filters in memory — #Predicate against enum-backed
//  properties (PipelineStage, Project.Status) is unreliable, so every other
//  cross-source picker in this codebase (LogActivityViewModel.loadActiveOpportunities,
//  SiteVisitIdentityPanel.loadSearchSources) does the same thing. Mirrored here.
//

import Foundation
import SwiftData

/// Loads the unified `ActivityTarget` candidate list for a company: open
/// leads, active clients, and open jobs — the three surfaces an activity can
/// be logged against.
enum ActivityTargetLoader {

    /// Fetch and filter all three sources for `companyId`, returning them as
    /// one flat `[ActivityTarget]`. Callers (the picker view) own sorting the
    /// combined list for display / search filtering; the per-source order
    /// here just keeps each source's own natural order before merge.
    static func load(companyId: String, modelContext: ModelContext) -> [ActivityTarget] {
        var targets: [ActivityTarget] = []
        targets.append(contentsOf: loadOpportunities(companyId: companyId, modelContext: modelContext))
        targets.append(contentsOf: loadClients(companyId: companyId, modelContext: modelContext))
        targets.append(contentsOf: loadProjects(companyId: companyId, modelContext: modelContext))
        return targets
    }

    // MARK: - Leads

    private static func loadOpportunities(companyId: String, modelContext: ModelContext) -> [ActivityTarget] {
        let descriptor = FetchDescriptor<Opportunity>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all
            .filter { $0.companyId == companyId && !$0.stage.isTerminal && $0.deletedAt == nil }
            .sorted { ($0.lastActivityAt ?? $0.createdAt) > ($1.lastActivityAt ?? $1.createdAt) }
            .map { .opportunity($0) }
    }

    // MARK: - Clients

    /// Top-level clients only for v1 — `Client.subClients` are not surfaced as
    /// separately-selectable rows here (SiteVisitIdentityPanel, the reference
    /// cross-source picker, does the same: only top-level `Client` rows are
    /// matchable, sub-clients are contact details on the parent, not distinct
    /// targets). An activity logged against a client always attaches to the
    /// parent client id.
    private static func loadClients(companyId: String, modelContext: ModelContext) -> [ActivityTarget] {
        let descriptor = FetchDescriptor<Client>(sortBy: [SortDescriptor(\.name)])
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all
            .filter { ($0.companyId == nil || $0.companyId == companyId) && $0.deletedAt == nil }
            .map { .client($0) }
    }

    // MARK: - Jobs

    private static func loadProjects(companyId: String, modelContext: ModelContext) -> [ActivityTarget] {
        let descriptor = FetchDescriptor<Project>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all
            .filter { $0.companyId == companyId && $0.deletedAt == nil && !$0.status.isCompleted }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { .project($0) }
    }
}
