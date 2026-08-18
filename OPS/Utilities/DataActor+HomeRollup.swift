//
//  DataActor+HomeRollup.swift
//  OPS
//
//  Home's billable-this-week rollup, computed off the main thread
//  (bug 3d9ead2f follow-up: HomeView is MainActor-inferred, so its
//  loadTodaysProjects Task faulted project.tasks for every live project
//  on the main thread on mount, tab return, foreground, and sync).
//
//  Scoping contract: the CALLER decides which projects the card counts.
//  HomeView passes the ids of the same list it feeds the map
//  (getProjectsForCurrentUser + scheduled-task merge + tutorial filter);
//  this actor fetches exactly those rows in its own context and never
//  re-derives visibility, so the rollup cannot disagree with the map.
//  HomeRollupDataActorTests locks the parity.
//

import Foundation
import SwiftData

/// Everything Home needs back from the background rollup pass.
struct HomeRollupSnapshot: Sendable {
    let rollup: HomeBillableThisWeekRollup
    let projectsNeedingTasksCount: Int
}

extension DataActor {

    /// Compute the billable-this-week rollup and the needs-tasks count for
    /// exactly the given projects, faulting `project.tasks` on the actor's
    /// context instead of the main thread.
    ///
    /// Mirrors the legacy HomeView.computeBillableRollup gates exactly:
    /// invoices/estimates are company-scoped at the fetch when a company id
    /// exists ("no company id means no filter"), tombstones never materialize.
    func computeHomeRollup(
        projectIds: [String],
        companyId: String?,
        today: Date = Date()
    ) -> HomeRollupSnapshot {
        let projects = fetchProjects(ids: projectIds)

        var invoiceDescriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate<Invoice> { $0.deletedAt == nil }
        )
        var estimateDescriptor = FetchDescriptor<Estimate>(
            predicate: #Predicate<Estimate> { $0.deletedAt == nil }
        )
        if let companyId {
            invoiceDescriptor.predicate = #Predicate<Invoice> {
                $0.deletedAt == nil && $0.companyId == companyId
            }
            estimateDescriptor.predicate = #Predicate<Estimate> {
                $0.deletedAt == nil && $0.companyId == companyId
            }
        }
        let invoices = (try? modelContext.fetch(invoiceDescriptor)) ?? []
        let estimates = (try? modelContext.fetch(estimateDescriptor)) ?? []

        return HomeRollupSnapshot(
            rollup: HomeBillableThisWeekRollupEngine.compute(
                projects: projects,
                invoices: invoices,
                estimates: estimates,
                today: today
            ),
            projectsNeedingTasksCount: ProjectsWithoutTasksDetector
                .projectsWithoutTasks(from: projects)
                .count
        )
    }

    /// Needs-tasks count alone — the review-sheet-dismiss recompute needs the
    /// count without paying for the invoice/estimate fetches.
    func projectsNeedingTasksCount(projectIds: [String]) -> Int {
        ProjectsWithoutTasksDetector
            .projectsWithoutTasks(from: fetchProjects(ids: projectIds))
            .count
    }

    private func fetchProjects(ids: [String]) -> [Project] {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { ids.contains($0.id) }
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("[DataActor] Home rollup project fetch failed: \(error)")
            return []
        }
    }
}
