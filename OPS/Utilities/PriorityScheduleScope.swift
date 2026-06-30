//
//  PriorityScheduleScope.swift
//  OPS
//
//  Pure scope resolution for the priority-queue scheduler. Split out from
//  PriorityQueueViewModel so the "what gets scheduled" decision — and the run
//  buttons' enabled state — can be unit-tested without standing up a
//  DataController / ModelContext.
//

import Foundation

/// Which projects a priority-queue "Schedule" run targets.
enum PriorityScheduleScope {
    /// Only the ranked (prioritized) projects, in priority order. Unranked work
    /// is left untouched — the user deliberately deferred it.
    case ranked
    /// Every active project — ranked first (in priority order), then the rest.
    /// Works even when nothing has been ranked yet, which is the common case.
    case all
}

/// Pure helpers shared by the view model's run buttons and the scheduler. Kept
/// free of SwiftData / DataController so the targeting rules can be exercised
/// directly in tests, and so the UI and the engine can never disagree about
/// what "schedulable" means.
enum PriorityScheduleScoping {

    /// A project still has work to auto-schedule: an active, non-deleted task
    /// missing a start or end date. This is the single source of truth for
    /// "schedulable" — the run buttons' enabled state and the scope candidate
    /// lists both go through it, so a button can never sit live over an empty
    /// plan (the old bug where tapping produced nothing).
    static func hasSchedulableTask(_ project: Project) -> Bool {
        project.tasks.contains {
            $0.deletedAt == nil && $0.status == .active && ($0.startDate == nil || $0.endDate == nil)
        }
    }

    /// The ordered project list a run of `scope` feeds to the scheduler.
    /// `.all` keeps ranked projects first so priority order is still honored
    /// even when the unranked tail is swept in behind them.
    static func candidates(
        for scope: PriorityScheduleScope,
        ranked: [Project],
        unranked: [Project]
    ) -> [Project] {
        switch scope {
        case .ranked: return ranked
        case .all:    return ranked + unranked
        }
    }

    /// A run of `scope` is live only when at least one candidate actually has
    /// work to place. Without this the "Schedule" buttons sit enabled over an
    /// empty plan and do nothing on tap.
    static func canSchedule(
        scope: PriorityScheduleScope,
        ranked: [Project],
        unranked: [Project]
    ) -> Bool {
        candidates(for: scope, ranked: ranked, unranked: unranked).contains(where: hasSchedulableTask)
    }
}
