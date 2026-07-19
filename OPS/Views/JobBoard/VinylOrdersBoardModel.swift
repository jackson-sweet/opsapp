//
//  VinylOrdersBoardModel.swift
//  OPS
//
//  Pure population, grouping, and sort logic for the VINYL ORDERS board
//  (spec § 4). The board is a live procurement console: won, active jobs
//  whose vinyl phase is still open — quotes are not procurement, finished
//  jobs are history, and a job whose vinyl tasks are all complete has left
//  the vinyl phase whether or not it was ever marked. Kept free of SwiftData
//  (mirrors VinylTaskFilter's testability pattern) — the view assembles
//  plain inputs from its queries.
//

import Foundation

/// One project's glance-level facts, assembled by the caller from markers +
/// tasks. `vinylTaskStartDates` carries ONLY incomplete, non-deleted vinyl
/// tasks (the caller pre-filters by `TaskStatus != .completed`).
struct VinylBoardRowInput: Equatable, Identifiable {
    var projectId: String
    var title: String
    var status: Status
    var vinylTaskStartDates: [Date?]
    var hasIncompleteVinylTask: Bool
    var createdAt: Date?
    var ordered: Bool
    var orderedAt: Date?

    var id: String { projectId }
}

enum VinylOrdersBoardModel {

    /// Population + grouping + sort in one pass.
    ///
    /// - TO ORDER: earliest scheduled vinyl need first; unscheduled jobs after
    ///   scheduled ones, newest-created first (a fresh unscheduled job is the
    ///   likeliest to need attention); title as the final stable tiebreak.
    /// - ORDERED: most recently ordered first (nil `orderedAt` last).
    static func rows(
        from inputs: [VinylBoardRowInput]
    ) -> (toOrder: [VinylBoardRowInput], ordered: [VinylBoardRowInput]) {
        let populated = inputs.filter { input in
            (input.status == .accepted || input.status == .inProgress)
                && input.hasIncompleteVinylTask
        }

        let toOrder = populated
            .filter { !$0.ordered }
            .sorted { lhs, rhs in
                switch (earliestStart(lhs), earliestStart(rhs)) {
                case let (l?, r?) where l != r:
                    return l < r
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    let lCreated = lhs.createdAt ?? .distantPast
                    let rCreated = rhs.createdAt ?? .distantPast
                    if lCreated != rCreated { return lCreated > rCreated }
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }

        let ordered = populated
            .filter(\.ordered)
            .sorted { lhs, rhs in
                switch (lhs.orderedAt, rhs.orderedAt) {
                case let (l?, r?) where l != r:
                    return l > r
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }

        return (toOrder, ordered)
    }

    /// The soonest scheduled incomplete vinyl task, or nil when none carry a
    /// date (unscheduled).
    private static func earliestStart(_ input: VinylBoardRowInput) -> Date? {
        input.vinylTaskStartDates.compactMap { $0 }.min()
    }
}
