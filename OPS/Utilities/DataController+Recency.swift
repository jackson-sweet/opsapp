//
//  DataController+Recency.swift
//  OPS
//
//  Recency helpers for the project/task creation flows. Powers the
//  "start from recent" suggestion strip on the project form and the
//  recency-sorted task type + team member pickers on the task form.
//
//  Bug 9d5c2535-8cf3-4ea0-9e41-948066392be9 — added 2026-05-10.
//

import Foundation
import SwiftData

extension DataController {

    /// Returns up to `limit` projects most recently created by `userId`, newest
    /// first. Filters out soft-deleted rows and rows synced down before the
    /// `created_at` / `created_by` columns existed (those are `nil` locally
    /// and won't appear in the per-user recency strip).
    ///
    /// Tutorial mode is the caller's concern — pass the already-filtered set
    /// of projects via `allProjects` if you want only `DEMO_` rows.
    func recentlyCreatedProjects(
        by userId: String,
        from allProjects: [Project],
        limit: Int = 5
    ) -> [Project] {
        allProjects
            .filter { project in
                project.deletedAt == nil &&
                project.createdAt != nil &&
                project.createdBy == userId
            }
            .sorted { (lhs: Project, rhs: Project) -> Bool in
                let lDate = lhs.createdAt ?? .distantPast
                let rDate = rhs.createdAt ?? .distantPast
                return lDate > rDate
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Returns team-member IDs sorted by most recent assignment to the given
    /// task type. Members never assigned to this type are omitted — the
    /// caller appends them at the bottom alphabetically.
    ///
    /// Stable signal: prefers `task.createdAt`, falls back to
    /// `task.lastSyncedAt`, finally `.distantPast`.
    func recentTeamMemberIds(
        forTaskType taskTypeId: String,
        companyId: String
    ) -> [String] {
        guard let context = modelContext, !taskTypeId.isEmpty, !companyId.isEmpty else {
            return []
        }

        let predicate = #Predicate<ProjectTask> { task in
            task.taskTypeId == taskTypeId &&
            task.companyId == companyId &&
            task.deletedAt == nil
        }
        let descriptor = FetchDescriptor<ProjectTask>(predicate: predicate)

        guard let tasks = try? context.fetch(descriptor) else { return [] }

        var latest: [String: Date] = [:]
        for task in tasks {
            let stamp = task.createdAt ?? task.lastSyncedAt ?? .distantPast
            for memberId in task.getTeamMemberIds() where !memberId.isEmpty {
                if (latest[memberId] ?? .distantPast) < stamp {
                    latest[memberId] = stamp
                }
            }
        }

        return latest
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }

    /// Returns task-type IDs sorted by most recent use across all tasks in
    /// the company. Unused types are omitted — the caller appends them at
    /// the bottom alphabetically.
    func recentTaskTypeIds(companyId: String) -> [String] {
        guard let context = modelContext, !companyId.isEmpty else { return [] }

        let predicate = #Predicate<ProjectTask> { task in
            task.companyId == companyId &&
            task.deletedAt == nil
        }
        let descriptor = FetchDescriptor<ProjectTask>(predicate: predicate)

        guard let tasks = try? context.fetch(descriptor) else { return [] }

        var latest: [String: Date] = [:]
        for task in tasks where !task.taskTypeId.isEmpty {
            let stamp = task.createdAt ?? task.lastSyncedAt ?? .distantPast
            if (latest[task.taskTypeId] ?? .distantPast) < stamp {
                latest[task.taskTypeId] = stamp
            }
        }

        return latest
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }

    /// Ranks `candidates` for the team-member picker by affinity to the given
    /// task type — the crew you routinely put on this kind of work first
    /// (ranked by how often, ties broken by recency), then everyone else by
    /// most-recent overall use, then alphabetically. Returns the ordered users
    /// and the set that qualifies as the "usual crew" for the type (for the
    /// picker's section header + badge). Single source of truth: replaces the
    /// recency-only ordering that was duplicated across every picker caller.
    ///
    /// An empty `taskTypeId` (picker opened before a type is chosen) yields no
    /// type affinity, so the list falls back to recently-used-then-alphabetical.
    func rankedTeamMembers(
        forTaskType taskTypeId: String,
        companyId: String,
        candidates: [User]
    ) -> (ordered: [User], usualCrewIds: Set<String>) {
        guard !candidates.isEmpty else { return ([], []) }

        // De-dupe by id, keeping first occurrence — defends the ranking against
        // a caller that passes a list with repeats.
        var byId: [String: User] = [:]
        for user in candidates where byId[user.id] == nil { byId[user.id] = user }

        func alphabetical() -> [User] {
            byId.values.sorted {
                $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }
        }

        guard let context = modelContext, !companyId.isEmpty else {
            return (alphabetical(), [])
        }

        // One fetch of the company's live tasks; tally assignment history per
        // member in a single pass.
        let predicate = #Predicate<ProjectTask> { task in
            task.companyId == companyId && task.deletedAt == nil
        }
        let tasks = (try? context.fetch(FetchDescriptor<ProjectTask>(predicate: predicate))) ?? []

        var typeCount: [String: Int] = [:]
        var lastForType: [String: Date] = [:]
        var lastOverall: [String: Date] = [:]

        for task in tasks {
            let stamp = task.createdAt ?? task.lastSyncedAt ?? .distantPast
            let isTargetType = !taskTypeId.isEmpty && task.taskTypeId == taskTypeId
            for memberId in task.getTeamMemberIds() where !memberId.isEmpty {
                if (lastOverall[memberId] ?? .distantPast) < stamp { lastOverall[memberId] = stamp }
                if isTargetType {
                    typeCount[memberId, default: 0] += 1
                    if (lastForType[memberId] ?? .distantPast) < stamp { lastForType[memberId] = stamp }
                }
            }
        }

        let stats = byId.values.map { user in
            CrewAffinityStats(
                memberId: user.id,
                fullName: user.fullName,
                typeAssignmentCount: typeCount[user.id] ?? 0,
                lastAssignedToType: lastForType[user.id] ?? .distantPast,
                lastAssignedOverall: lastOverall[user.id] ?? .distantPast
            )
        }

        let ranking = CrewAffinityRanker.rank(stats)
        let ordered = ranking.orderedIds.compactMap { byId[$0] }
        return (ordered, ranking.usualCrewIds)
    }
}
