//
//  DaySheetViewModel.swift
//  OPS
//
//  The delegate day sheet. `PipelineViewModel` stays the data engine — fetch,
//  realtime debounce, triage bucketing — and this is presentation only: the
//  console's five buckets collapsed into the three groups an operator actually
//  sorts their day by (whose move is it), each row carrying the one urgency
//  caption and the one milestone verb it is allowed to show. No second fetch,
//  no second cadence.
//
//  `groups(from:policy:now:)` is a pure function of its inputs — same buckets,
//  same policy, same clock, same output — so it is exercised directly by
//  DaySheetViewModelTests without any network or SwiftData.
//
//  Spec: docs/superpowers/specs/2026-07-27-my-leads-day-sheet-design.md §3.2
//

import Foundation
import Combine

@MainActor
final class DaySheetViewModel: ObservableObject {

    // MARK: - Presentation types

    /// Why this lead is on today's sheet. One value per source bucket, so a
    /// row's tone and its caption can never disagree about the same lead.
    enum Urgency: Equatable {
        /// Missed follow-up — whole days past its due date (always ≥ 1).
        case late(days: Int)
        /// Follow-up lands today.
        case today
        /// Correspondence or a manual signal is waiting on the operator.
        case yourMove
        /// Untouched new lead, captioned with how long it has been sitting.
        case newLead(age: String)
        /// Handled — back to the operator on the stamped date, if there is one.
        case waiting(back: String?)
    }

    /// One lead as the sheet renders it.
    ///
    /// `Opportunity` is a reference type the console mutates in place across a
    /// refresh, so equality is declared over the values this row actually
    /// presents rather than synthesized from the model object.
    struct Row: Identifiable, Equatable {
        let lead: Opportunity
        let urgency: Urgency
        let milestone: LeadMilestone?

        var id: String { lead.id }

        static func == (lhs: Row, rhs: Row) -> Bool {
            lhs.lead.id == rhs.lead.id
            && lhs.urgency == rhs.urgency
            && lhs.milestone == rhs.milestone
        }
    }

    /// The day, in the order it gets worked: what needs the operator now, what
    /// just landed, and what is parked with someone else.
    struct Groups: Equatable {
        var yourMove: [Row]
        var new: [Row]
        var waiting: [Row]

        var total: Int { yourMove.count + new.count + waiting.count }
        var yourMoveCount: Int { yourMove.count }
    }

    // MARK: - Transform

    /// Collapse the console's triage buckets into the day sheet's three groups.
    ///
    /// Row-filters with `can(.view, assignedTo:)` even though RLS already scopes
    /// the fetch server-side — the sheet must never widen what the operator is
    /// allowed to see, whatever a cached or stale payload happens to contain.
    /// `unconvertedWon` is deliberately ignored: won leads are a conversion
    /// queue, not today's work.
    static func groups(from buckets: PipelineViewModel.TriageBuckets,
                       policy: LeadAccessPolicy,
                       now: Date) -> Groups {
        let calendar = Calendar.current

        // Defensive on every count: the buckets already exclude deleted,
        // archived, and terminal leads, and RLS already scopes the fetch.
        func visible(_ leads: [Opportunity]) -> [Opportunity] {
            leads.filter {
                policy.can(.view, assignedTo: $0.assignedTo)
                && !$0.isDeleted
                && !$0.isArchived
                && !$0.stage.isTerminal
            }
        }

        // The milestone button is an edit. Without the grant the row still
        // shows — read-only — so a viewer sees the day, just can't stamp it.
        func row(_ lead: Opportunity, _ urgency: Urgency) -> Row {
            Row(lead: lead,
                urgency: urgency,
                milestone: policy.can(.edit, assignedTo: lead.assignedTo)
                    ? LeadMilestone.milestone(for: lead.stage)
                    : nil)
        }

        // YOUR MOVE — the console's three act-now buckets, in the order it
        // already sorted them: most-late first, then today's, then the rest.
        var yourMove: [Row] = []
        yourMove += visible(buckets.overdue).map {
            row($0, .late(days: daysLate($0.nextFollowUpAt, now: now, calendar: calendar)))
        }
        yourMove += visible(buckets.dueToday).map { row($0, .today) }
        yourMove += visible(buckets.waitingOnYou).map { row($0, .yourMove) }

        // NEW — newest first. The lead that just landed is the one worth
        // opening, regardless of how the console ordered the bucket.
        let new = stableSorted(visible(buckets.fresh)) { $0.createdAt > $1.createdAt }
            .map { row($0, .newLead(age: age(from: $0.createdAt, to: now))) }

        // WAITING — soonest comeback first. Leads with no comeback date sink
        // below, keeping the console's last-activity-descending order.
        let parked = visible(buckets.waitingOnThem)
        let dated = stableSorted(parked.filter { $0.nextFollowUpAt != nil }) {
            ($0.nextFollowUpAt ?? .distantFuture) < ($1.nextFollowUpAt ?? .distantFuture)
        }
        let undated = parked.filter { $0.nextFollowUpAt == nil }
        let waiting = (dated + undated).map {
            row($0, .waiting(back: comeback(for: $0.nextFollowUpAt, now: now, calendar: calendar)))
        }

        return Groups(yourMove: yourMove, new: new, waiting: waiting)
    }

    // MARK: - Vocabulary

    /// Whole days between a missed follow-up and today. Clamped to 1 — a lead
    /// only reaches the overdue bucket once its date is behind today's start.
    private static func daysLate(_ due: Date?, now: Date, calendar: Calendar) -> Int {
        guard let due else { return 1 }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: due),
                                           to: calendar.startOfDay(for: now)).day ?? 1
        return max(1, days)
    }

    /// NOW / 3H AGO / 2D AGO — how long an untouched new lead has been sitting.
    private static func age(from created: Date, to now: Date) -> String {
        let hours = Int(now.timeIntervalSince(created) / 3600)
        if hours < 1 { return "NOW" }
        if hours < 24 { return "\(hours)H AGO" }
        return "\(hours / 24)D AGO"
    }

    /// BACK TMRW / BACK FRI / BACK AUG 4 — the day sheet's comeback vocabulary.
    ///
    /// Deliberately NOT `LeadChaseStrip.comebackLabel`: the chase strip reads
    /// TODAY / TMRW / FRI / IN 9D, while the day sheet leads with the verb and
    /// spells the date out past the current week. Same data, different sentence.
    private static func comeback(for due: Date?, now: Date, calendar: Calendar) -> String? {
        guard let due else { return nil }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: due)).day ?? 0
        if days <= 0 { return "BACK TODAY" }
        if days == 1 { return "BACK TMRW" }
        if days < 7 { return "BACK \(weekdayFormatter.string(from: due).uppercased())" }
        return "BACK \(monthDayFormatter.string(from: due).uppercased())"
    }

    // en_US_POSIX so the sheet reads the same on every device locale — these
    // are OPS labels, not localized dates.
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    // MARK: - Ordering

    /// `Array.sorted` is not a stable sort. The sheet's tie-breaks must be, or
    /// equal-keyed rows swap places between two identical refreshes.
    private static func stableSorted(
        _ leads: [Opportunity],
        by areInIncreasingOrder: (Opportunity, Opportunity) -> Bool
    ) -> [Opportunity] {
        leads.enumerated().sorted { left, right in
            if areInIncreasingOrder(left.element, right.element) { return true }
            if areInIncreasingOrder(right.element, left.element) { return false }
            return left.offset < right.offset
        }.map(\.element)
    }
}
