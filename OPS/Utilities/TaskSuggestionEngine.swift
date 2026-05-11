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

    /// Minimum number of occurrences within the window for a key to qualify.
    static let minOccurrences: Int = 2

    /// Maximum suggestions returned after ranking + dedup.
    static let maxResults: Int = 3

    /// Compute top suggestions for a company, excluding any keys already on
    /// the given project. Reads from the provided SwiftData context.
    ///
    /// Caller is responsible for being on @MainActor — `ModelContext` is not
    /// Sendable. Returns at most `maxResults`.
    static func suggestions(
        context: ModelContext,
        companyId: String,
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

        // Build dedup set of keys already present on the current project so
        // we never suggest a setup the user has already added here.
        let existingKeys: Set<String> = Set(
            project.tasks
                .filter { $0.deletedAt == nil }
                .map { key(taskTypeId: $0.taskTypeId, teamIds: $0.getTeamMemberIds().sorted()) }
        )

        struct Agg {
            var score: Double = 0
            var occurrences: Int = 0
            var mostRecent: Date = .distantPast
            var taskTypeId: String = ""
            var teamMemberIds: [String] = []
        }
        var bucket: [String: Agg] = [:]

        let now = Date()
        for task in tasks {
            // Recency stamp: `lastSyncedAt` is the only timestamp guaranteed
            // to exist on every synced row today. If the parallel
            // recency-suggestions work lands `ProjectTask.createdAt`, swap
            // the next line to `task.createdAt ?? task.lastSyncedAt`.
            let stamp = task.lastSyncedAt ?? .distantPast
            guard stamp >= cutoff else { continue }

            let sortedIds = task.getTeamMemberIds().sorted()
            let k = key(taskTypeId: task.taskTypeId, teamIds: sortedIds)
            if existingKeys.contains(k) { continue }

            let daysAgo = Calendar.current.dateComponents(
                [.day], from: stamp, to: now
            ).day ?? 0
            let weight = exp(-Double(max(0, daysAgo)) / 30.0)

            var agg = bucket[k] ?? Agg()
            agg.score += weight
            agg.occurrences += 1
            if stamp > agg.mostRecent { agg.mostRecent = stamp }
            agg.taskTypeId = task.taskTypeId
            agg.teamMemberIds = sortedIds
            bucket[k] = agg
        }

        let dismissed = dismissedKeyHashes(forProjectId: project.id)

        let suggestions: [TaskSuggestion] = bucket.values.compactMap { agg -> TaskSuggestion? in
            guard agg.occurrences >= minOccurrences else { return nil }
            let candidate = TaskSuggestion(
                taskTypeId: agg.taskTypeId,
                teamMemberIds: agg.teamMemberIds,
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
