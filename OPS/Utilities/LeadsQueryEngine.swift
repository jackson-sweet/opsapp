//
//  LeadsQueryEngine.swift
//  OPS
//
//  The LEADS console's query engine (console redesign 2026-08-05, spec §5–§6,
//  §10). Search, sort, crew filtering, roster resolution and band-state
//  selection live here — pure, nonisolated, view-free — so the console renders
//  one tested truth instead of scattering predicates through its body.
//
//  Nothing in this file may import SwiftUI. Deployment floor is iOS 17.6.
//

import Foundation

// MARK: - Controls

/// How the queue is ordered. URGENCY is the console default and the only mode
/// that groups; NEWEST and VALUE flatten the queue.
enum LeadSort: String, CaseIterable {
    case urgency
    case newest
    case value
}

/// The assignment slice the operator is looking at. `member` carries a
/// lowercased user id: `UUID().uuidString` is uppercase while Postgres stores
/// uuids lowercased, so every comparison in this file folds case.
enum CrewFilter: Equatable {
    case all
    case mine
    case unassigned
    case member(String)
}

/// The console's session controls. A plain value type held as `@State`, so a
/// tab remount resets the operator to URGENCY / ALL CREW / no query — opening
/// LEADS always answers "what needs me" first (spec §5.2).
struct LeadsListControls: Equatable {
    var query: String = ""
    var sort: LeadSort = .urgency
    var crew: CrewFilter = .all

    /// Search is live per keystroke, but a whitespace-only field is not a
    /// search — it must not suspend the browse filters (spec §5.4).
    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Result

/// What the queue renders. URGENCY with no bucket chip and no query is the one
/// grouped mode; every other combination — another sort, an active chip, any
/// search — flattens.
enum LeadsQueryResult: Equatable {
    case grouped([(bucket: PipelineViewModel.TriageBucket, leads: [Opportunity])])
    case flat([Opportunity])

    /// Hand-written: a tuple cannot conform to `Equatable`, so the compiler
    /// cannot synthesise this for the `.grouped` payload.
    static func == (lhs: LeadsQueryResult, rhs: LeadsQueryResult) -> Bool {
        switch (lhs, rhs) {
        case let (.grouped(left), .grouped(right)):
            guard left.count == right.count else { return false }
            return zip(left, right).allSatisfy { $0.bucket == $1.bucket && $0.leads == $1.leads }
        case let (.flat(left), .flat(right)):
            return left == right
        default:
            return false
        }
    }
}

// MARK: - Engine

enum LeadsQueryEngine {

    // MARK: Browse order

    /// The queue's visual browse order: WAITING sits ABOVE FRESH because a
    /// parked lead is likelier to need a nudge than an untouched one.
    ///
    /// Deliberately NOT `TriageBuckets.all`'s order (fresh before waiting) —
    /// that one is triage priority and drives SEARCH results, where relevance
    /// beats browsing habit. The asymmetry is intentional and both orders are
    /// pinned by tests. This is the single definition: the console renders from
    /// the grouped result, so the drawn order can never drift from the engine's.
    static let groupOrder: [PipelineViewModel.TriageBucket] = [
        .overdue, .dueToday, .waitingOnYou, .waitingOnThem, .fresh
    ]

    // MARK: Apply (spec §5.2, §5.4, §6.1, §6.3)

    /// The queue, resolved: population, filtering, ordering and shape in one
    /// call, so the view re-derives none of it.
    nonisolated static func apply(
        controls: LeadsListControls,
        buckets: PipelineViewModel.TriageBuckets,
        selectedBucket: PipelineViewModel.TriageBucket,
        currentUserId: String?
    ) -> LeadsQueryResult {
        // Search suspends browse (spec §5.4). Population widens to every lead
        // the tab owns — open plus unconverted wins — and BOTH the bucket chip
        // and the crew filter stand down, so a search can never dead-end
        // against a filter the operator forgot was set.
        if controls.isSearching {
            let population = buckets.all + buckets.unconvertedWon
            return .flat(sortedFlat(population.filter { matches($0, query: controls.query) },
                                    by: controls.sort))
        }

        let effective = effectiveBucket(selectedBucket, in: buckets)
        let inCrew: (Opportunity) -> Bool = {
            crewMatches($0, filter: controls.crew, currentUserId: currentUserId)
        }

        if controls.sort == .urgency, effective == .all {
            return .grouped(groupOrder.compactMap { bucket in
                let leads = buckets.leads(for: bucket).filter(inCrew)
                return leads.isEmpty ? nil : (bucket: bucket, leads: leads)
            })
        }

        return .flat(sortedFlat(buckets.leads(for: effective).filter(inCrew), by: controls.sort))
    }

    /// Mirrors the console's chip rule: a chip whose bucket has emptied drops
    /// back to ALL rather than stranding the operator on an empty list.
    /// Emptiness is measured on the RAW bucket because the chips carry raw
    /// counts — the fallback has to agree with what the chip says.
    nonisolated static func effectiveBucket(
        _ selected: PipelineViewModel.TriageBucket,
        in buckets: PipelineViewModel.TriageBuckets
    ) -> PipelineViewModel.TriageBucket {
        guard selected != .all, !buckets.leads(for: selected).isEmpty else { return .all }
        return selected
    }

    // MARK: Crew filtering (spec §5.3)

    /// AND-composes with the bucket chip while browsing; suspended entirely
    /// while searching. Both sides fold case — `UUID().uuidString` is uppercase
    /// and Postgres stores uuids lowercased.
    nonisolated static func crewMatches(
        _ lead: Opportunity,
        filter: CrewFilter,
        currentUserId: String?
    ) -> Bool {
        let assigned = normalizedId(lead.assignedTo)
        switch filter {
        case .all:
            return true
        case .mine:
            // No identity, no MINE. Returning everything would quietly lie.
            guard let me = normalizedId(currentUserId) else { return false }
            return assigned == me
        case .unassigned:
            return assigned == nil
        case .member(let id):
            guard let wanted = normalizedId(id) else { return false }
            return assigned == wanted
        }
    }

    // MARK: Sorting

    private static func sortedFlat(_ leads: [Opportunity], by sort: LeadSort) -> [Opportunity] {
        switch sort {
        case .urgency:
            // The population arrives in urgency order already — the buckets are
            // pre-sorted and concatenated in triage priority.
            return leads
        case .newest:
            return stableSorted(leads) { $0.createdAt > $1.createdAt }
        case .value:
            return stableSorted(leads) { lhs, rhs in
                switch (rankedValue(lhs), rankedValue(rhs)) {
                case let (left?, right?):
                    if left != right { return left > right }
                    return lhs.createdAt > rhs.createdAt
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.createdAt > rhs.createdAt
                }
            }
        }
    }

    /// Unpriced and zero-priced mean the same thing to an operator sorting by
    /// money: nothing to weigh. They sink together below every priced lead.
    private static func rankedValue(_ lead: Opportunity) -> Double? {
        guard let value = lead.estimatedValue, value > 0 else { return nil }
        return value
    }

    /// Ties keep the population's own order, so a sort never reshuffles equal
    /// rows between renders (mirrors `DaySheetViewModel.stableSorted`).
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

    /// nil for a missing OR blank id: an empty `assigned_to` means unassigned,
    /// not "assigned to somebody called ''".
    private static func normalizedId(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    // MARK: Search matching (spec §6.2)

    /// Case- and diacritic-insensitive multi-token match. Every whitespace-
    /// separated token must hit at least one of: `displayContactName`, `title`,
    /// `descriptionText`, `address`, `contactEmail`, `source`,
    /// `shortDisplayId`. A token carrying three or more digits ALSO matches
    /// when its digits are a substring of the lead's phone digits, so
    /// `5551234` finds `(555) 123-4567`.
    ///
    /// An empty or whitespace-only query matches everything, so a caller never
    /// has to branch before filtering.
    nonisolated static func matches(_ lead: Opportunity, query: String) -> Bool {
        let tokens = searchTokens(in: query)
        guard !tokens.isEmpty else { return true }

        let haystack = fold(searchableText(of: lead))
        let phoneDigits = digits(in: lead.contactPhone ?? "")

        return tokens.allSatisfy { token in
            if haystack.contains(token) { return true }
            let tokenDigits = digits(in: token)
            guard tokenDigits.count >= minimumPhoneDigits, !phoneDigits.isEmpty else { return false }
            return phoneDigits.contains(tokenDigits)
        }
    }

    /// Under three digits a token is a street number or a quantity, not a phone
    /// number — consulting the phone path on `55` would drag half the pipeline
    /// into the results.
    private static let minimumPhoneDigits = 3

    /// Every field the operator can reach by typing, joined by newlines: tokens
    /// are whitespace-free by construction, so a token can never straddle the
    /// seam between two fields.
    private static func searchableText(of lead: Opportunity) -> String {
        [
            lead.displayContactName,
            lead.title,
            lead.descriptionText,
            lead.address,
            lead.contactEmail,
            lead.source,
            lead.shortDisplayId
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private static func searchTokens(in query: String) -> [String] {
        fold(query)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    /// `.caseInsensitive` folding also lowercases, so one call normalises both
    /// sides of every comparison.
    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func digits(in value: String) -> String {
        value.filter { $0.isASCII && $0.isNumber }
    }
}
