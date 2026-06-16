//
//  TaskSuggestionEngine.swift
//  OPS
//
//  On-device suggestion engine for the Quick Add rail on Project Details.
//  Computes top-N (taskType, crew) combinations the company uses frequently
//  and recently. Pure SwiftData read — no network. Pure recency × frequency,
//  no ML.
//
//  Spec: docs/superpowers/specs/2026-05-10-quick-add-task-chips-design.md
//  Bug:  e3996ac3-4180-4bdf-9423-f1d3b0c7b6de
//

import Foundation
import SwiftData
import CryptoKit

/// One row in the Quick Add rail.
struct TaskSuggestion: Identifiable, Hashable {
    let taskTypeId: String
    /// Sorted ascending — the canonical form used for keying.
    let teamMemberIds: [String]
    /// Sum of `exp(-daysAgo / 30)` across all occurrences in the window.
    let score: Double
    let mostRecentAt: Date

    var id: String { keyHash }

    /// SHA-256 base64 of `taskTypeId + ":" + teamMemberIds.joined(",")`.
    /// Stable across renders, used as the dismissal-storage key.
    var keyHash: String {
        Self.hash(taskTypeId: taskTypeId, teamIds: teamMemberIds)
    }

    static func hash(taskTypeId: String, teamIds: [String]) -> String {
        let raw = "\(taskTypeId):\(teamIds.joined(separator: ","))"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return Data(digest).base64EncodedString()
    }
}

enum TaskSuggestionEngine {
    /// Days of history to consider.
    static let windowDays: Int = 60

    /// Minimum number of tasks of a given type within the window for that type
    /// to qualify as a suggestion.
    static let minOccurrences: Int = 2

    /// Maximum suggestions returned after ranking + dedup.
    static let maxResults: Int = 3

    /// Most members a single chip ever suggests/commits. The chip renders
    /// `prefix(2)` avatars (QuickAddSuggestionsRail.metaRow), so a wider crew
    /// would silently assign members the user never saw. Cap to what the chip
    /// shows.
    static let maxCrew: Int = 2

    /// Compute top suggestions for a company, excluding any keys already on
    /// the given project. Reads from the provided SwiftData context.
    ///
    /// Suggestion model — recency-weighted task type, crewed with that type's
    /// most-recent ACTIVE members (mirrors the task form's recency model in
    /// `DataController+Recency.swift`):
    ///   1. Rank task types by `sum(exp(-daysAgo / 30))` over the window,
    ///      using each task's stable creation stamp (`createdAt`, falling back
    ///      to `lastSyncedAt`), requiring at least `minOccurrences` tasks.
    ///   2. For each surfaced type, derive the crew as the top `maxCrew`
    ///      members by most-recent assignment to THAT type, keeping only
    ///      members in `activeMemberIds` (the caller's current-company,
    ///      non-deleted, active set). Each task's crew is deduped before it
    ///      contributes, so a row that repeats the same id N times can't pad
    ///      the signal.
    ///   3. The keyHash / on-project dedup / dismissal store all key off the
    ///      FINAL (active-filtered, deduped, sorted) crew, so dismissals stay
    ///      stable.
    ///
    /// `activeMemberIds` must be lowercased to match the lowercased ids stored
    /// in `ProjectTask.teamMemberIdsString`.
    ///
    /// Caller is responsible for being on @MainActor — `ModelContext` is not
    /// Sendable. Returns at most `maxResults`.
    static func suggestions(
        context: ModelContext,
        companyId: String,
        activeMemberIds: Set<String>,
        for project: Project
    ) -> [TaskSuggestion] {
        guard !companyId.isEmpty else { return [] }

        let cutoff = Calendar.current.date(
            byAdding: .day, value: -windowDays, to: Date()
        ) ?? .distantPast

        let predicate = #Predicate<ProjectTask> { task in
            task.companyId == companyId &&
            task.deletedAt == nil
        }
        let descriptor = FetchDescriptor<ProjectTask>(predicate: predicate)
        guard let tasks = try? context.fetch(descriptor) else { return [] }

        // Stable creation stamp — `createdAt` doesn't drift on edit-sync the
        // way `lastSyncedAt` does. Falls back to `lastSyncedAt`, then
        // `.distantPast` for rows synced before the column existed. Matches
        // DataController+Recency.swift.
        func stamp(for task: ProjectTask) -> Date {
            task.createdAt ?? task.lastSyncedAt ?? .distantPast
        }

        // Active, deduped, lowercased crew for a single task.
        func activeCrew(for task: ProjectTask) -> [String] {
            let lowered = task.getTeamMemberIds()
                .map { $0.lowercased() }
                .filter { !$0.isEmpty && activeMemberIds.contains($0) }
            return Array(Set(lowered)).sorted()
        }

        let now = Date()

        // MARK: Aggregate per task type.
        struct TypeAgg {
            var score: Double = 0
            var occurrences: Int = 0
            var mostRecent: Date = .distantPast
            /// memberId -> most-recent assignment stamp on this type.
            var memberLatest: [String: Date] = [:]
        }
        var byType: [String: TypeAgg] = [:]

        for task in tasks where !task.taskTypeId.isEmpty {
            let s = stamp(for: task)
            guard s >= cutoff else { continue }

            let daysAgo = Calendar.current.dateComponents(
                [.day], from: s, to: now
            ).day ?? 0
            let weight = exp(-Double(max(0, daysAgo)) / 30.0)

            var agg = byType[task.taskTypeId] ?? TypeAgg()
            agg.score += weight
            agg.occurrences += 1
            if s > agg.mostRecent { agg.mostRecent = s }
            for memberId in activeCrew(for: task) {
                if (agg.memberLatest[memberId] ?? .distantPast) < s {
                    agg.memberLatest[memberId] = s
                }
            }
            byType[task.taskTypeId] = agg
        }

        // Build dedup set of keys already present on the current project so we
        // never suggest a setup the user has already added here. Normalize the
        // existing crews the SAME way (active-filtered, deduped, sorted) so the
        // comparison matches the final suggested crew.
        let existingKeys: Set<String> = Set(
            project.tasks
                .filter { $0.deletedAt == nil }
                .map { key(taskTypeId: $0.taskTypeId, teamIds: activeCrew(for: $0)) }
        )

        let dismissed = dismissedKeyHashes(forProjectId: project.id)

        let suggestions: [TaskSuggestion] = byType.compactMap { (taskTypeId, agg) -> TaskSuggestion? in
            guard agg.occurrences >= minOccurrences else { return nil }

            // Top-`maxCrew` active members by most-recent assignment to this
            // type. Tie-break on member id for determinism.
            let crew: [String] = agg.memberLatest
                .sorted { lhs, rhs in
                    if lhs.value != rhs.value { return lhs.value > rhs.value }
                    return lhs.key < rhs.key
                }
                .prefix(maxCrew)
                .map { $0.key }
                .sorted()

            let k = key(taskTypeId: taskTypeId, teamIds: crew)
            guard !existingKeys.contains(k) else { return nil }

            let candidate = TaskSuggestion(
                taskTypeId: taskTypeId,
                teamMemberIds: crew,
                score: agg.score,
                mostRecentAt: agg.mostRecent
            )
            guard !dismissed.contains(candidate.keyHash) else { return nil }
            return candidate
        }
        .sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.mostRecentAt > b.mostRecentAt
        }

        return Array(suggestions.prefix(maxResults))
    }

    // MARK: - Dismissal storage (per-project, local-only, never synced)

    static func dismissedKeyHashes(forProjectId projectId: String) -> Set<String> {
        let raw = UserDefaults.standard.stringArray(
            forKey: dismissDefaultsKey(projectId: projectId)
        ) ?? []
        return Set(raw)
    }

    static func dismiss(_ suggestion: TaskSuggestion, forProjectId projectId: String) {
        let defaultsKey = dismissDefaultsKey(projectId: projectId)
        var current = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        if !current.contains(suggestion.keyHash) {
            current.append(suggestion.keyHash)
            UserDefaults.standard.set(current, forKey: defaultsKey)
        }
    }

    // MARK: - Helpers

    private static func key(taskTypeId: String, teamIds: [String]) -> String {
        "\(taskTypeId):\(teamIds.joined(separator: ","))"
    }

    private static func dismissDefaultsKey(projectId: String) -> String {
        "quickadd.dismissed.\(projectId)"
    }
}
