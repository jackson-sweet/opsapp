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

// MARK: - Engine

enum LeadsQueryEngine {

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
