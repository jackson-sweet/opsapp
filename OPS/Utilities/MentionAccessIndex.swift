//
//  MentionAccessIndex.swift
//  OPS
//
//  In-memory index of project IDs the current user has mention-based view
//  access to. Derived from live (non-soft-deleted) ProjectNote rows on-device.
//  Bug G9 — tag-based project view permission.
//
//  Rule (locked, 2026-04-20):
//    - Mention in any live note on a project grants view access.
//    - Revoked when all mentions removed OR all containing notes soft-deleted.
//    - Mention grant does NOT add the user to team_member_ids.
//    - Mention-granted projects DO NOT appear in: Job Board "My Projects",
//      Calendar, Schedule, or Map. They ARE searchable via Universal Search
//      and iOS Spotlight, and reachable via push-notification deep link.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class MentionAccessIndex: ObservableObject {
    static let shared = MentionAccessIndex()

    @Published private(set) var mentionedProjectIds: Set<String> = []

    private init() {}

    /// Rebuild the index from SwiftData. O(notes) — safe to call often; notes
    /// fit easily in memory at OPS's data volumes (tens of thousands max).
    func rebuild(context: ModelContext, userId: String) {
        let descriptor = FetchDescriptor<ProjectNote>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        guard let notes = try? context.fetch(descriptor) else {
            mentionedProjectIds = []
            return
        }
        var ids: Set<String> = []
        for note in notes where note.mentionedUserIds.contains(userId) {
            ids.insert(note.projectId)
        }
        mentionedProjectIds = ids
    }

    /// O(1) membership check.
    func contains(_ projectId: String) -> Bool {
        mentionedProjectIds.contains(projectId)
    }

    /// Clear on logout.
    func clear() {
        mentionedProjectIds = []
    }
}
