//
//  CrewAffinityRanker.swift
//  OPS
//
//  Pure ranking for the team-member picker. Orders crew by AFFINITY to the
//  task at hand: the people you routinely put on this kind of work (vinyl,
//  rail, framing, …) rise to the top, ranked by how often they've done it,
//  ties broken by who did it most recently. Everyone else falls below, ordered
//  by who you've assigned most recently across any work, then alphabetically.
//
//  This replaces the recency-only ordering that was copy-pasted across the
//  task form, project form, and the review pickers — one source of truth so
//  every "select team members" surface ranks identically.
//
//  Pure and deterministic by design (no SwiftData / Date.now inside) so the
//  ranking is unit-testable; the DataController extension does the fetch and
//  feeds stats in.
//

import Foundation

/// Per-candidate assignment history, relative to one target task type.
struct CrewAffinityStats: Equatable {
    let memberId: String
    let fullName: String
    /// Number of (non-deleted) tasks of the TARGET task type this member has
    /// been assigned to. The "usual crew for vinyl" signal.
    let typeAssignmentCount: Int
    /// Most recent assignment to the TARGET task type (`.distantPast` if none).
    let lastAssignedToType: Date
    /// Most recent assignment to ANY task type (`.distantPast` if never
    /// assigned). The fallback ordering when there's no type precedent.
    let lastAssignedOverall: Date
}

enum CrewAffinityRanker {

    /// Ordered candidate IDs plus the set that qualifies as the "usual crew"
    /// for the target type (those with at least one prior assignment to it).
    struct Ranking: Equatable {
        let orderedIds: [String]
        let usualCrewIds: Set<String>
    }

    /// Rank candidates for a task type.
    ///
    /// Tier 1 — usual crew (`typeAssignmentCount > 0`): most-assigned to this
    /// type first; ties broken by most-recent assignment to this type, then
    /// name. This is the "commonly assigned to vinyl" ordering.
    ///
    /// Tier 2 — everyone else: most-recently-used overall first (the "no
    /// precedent → recently used" fallback), then name. Members never assigned
    /// to anything sort to the bottom alphabetically.
    static func rank(_ stats: [CrewAffinityStats]) -> Ranking {
        let usual = stats
            .filter { $0.typeAssignmentCount > 0 }
            .sorted(by: usualTierOrder)
        let rest = stats
            .filter { $0.typeAssignmentCount == 0 }
            .sorted(by: restTierOrder)

        return Ranking(
            orderedIds: (usual + rest).map(\.memberId),
            usualCrewIds: Set(usual.map(\.memberId))
        )
    }

    // MARK: - Tier ordering

    private static func usualTierOrder(_ a: CrewAffinityStats, _ b: CrewAffinityStats) -> Bool {
        if a.typeAssignmentCount != b.typeAssignmentCount {
            return a.typeAssignmentCount > b.typeAssignmentCount
        }
        if a.lastAssignedToType != b.lastAssignedToType {
            return a.lastAssignedToType > b.lastAssignedToType
        }
        return nameOrder(a, b)
    }

    private static func restTierOrder(_ a: CrewAffinityStats, _ b: CrewAffinityStats) -> Bool {
        if a.lastAssignedOverall != b.lastAssignedOverall {
            return a.lastAssignedOverall > b.lastAssignedOverall
        }
        return nameOrder(a, b)
    }

    private static func nameOrder(_ a: CrewAffinityStats, _ b: CrewAffinityStats) -> Bool {
        a.fullName.localizedCaseInsensitiveCompare(b.fullName) == .orderedAscending
    }
}
