//
//  ProjectAutoNamer.swift
//  OPS
//
//  Client-side mirror of the server's `private.derive_project_name`
//  (applied by the `projects_autoname` BEFORE trigger whenever
//  `projects.title_is_auto` is true). Any preview iOS shows before a
//  conversion MUST use this so the operator sees the exact name the server
//  will derive — keep the two implementations in lockstep.
//
//  Derivation order:
//    1. Address with a comma  → street line before the first comma.
//    2. Comma-less address    → civic number + street name up to a
//                               recognized street suffix (+ optional
//                               directional), e.g. "972 Lyall St" out of
//                               "972 Lyall St Esquimalt BC V9A 5E8".
//    3. Unrecognizable address → the whole trimmed address (server parity).
//    4. No address            → "<client>'s Project".
//    5. Nothing               → "New project".
//

import Foundation

enum ProjectAutoNamer {
    static func derivedTitle(from address: String) -> String {
        streetLine(from: address) ?? "New project"
    }

    /// Mirrors `private.derive_project_name(p_address, p_client_name)`.
    static func derive(address: String?, clientName: String?) -> String {
        if let address, let line = streetLine(from: address) {
            return line
        }
        let trimmedClient = clientName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedClient.isEmpty {
            return "\(trimmedClient)'s Project"
        }
        return "New project"
    }

    static func titleReplacingAddressComponent(
        in title: String,
        previousAddress: String?,
        nextAddress: String
    ) -> String? {
        guard
            let previousAddress,
            let previousStreet = streetLine(from: previousAddress),
            let nextStreet = streetLine(from: nextAddress),
            previousStreet != nextStreet
        else {
            return nil
        }

        if let range = title.range(of: previousStreet) {
            return title.replacingCharacters(in: range, with: nextStreet)
        }

        if let range = title.range(of: previousStreet, options: [.caseInsensitive, .diacriticInsensitive]) {
            return title.replacingCharacters(in: range, with: nextStreet)
        }

        return nil
    }

    /// The street line an address resolves to, or nil when the address is
    /// blank. Never returns an empty string.
    static func streetLine(from address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Canonical comma-separated addresses (autocomplete output): the
        // street line is everything before the first comma.
        if trimmed.contains(",") {
            let beforeComma = trimmed
                .components(separatedBy: ",")
                .first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            return beforeComma.isEmpty ? trimmed : beforeComma
        }

        // Hand-typed comma-less addresses: conservative civic-number +
        // street-suffix extraction. Precision over recall — when nothing
        // matches, fall back to the full address (the server's old behavior)
        // rather than guessing.
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if let match = Self.streetLineRegex.firstMatch(in: trimmed, options: [], range: range),
           let matchRange = Range(match.range, in: trimmed) {
            let line = String(trimmed[matchRange]).trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { return line }
        }
        return trimmed
    }

    /// Canonicalizes a hand-typed comma-less address by inserting the comma
    /// after the street line ("972 Lyall St Esquimalt BC" →
    /// "972 Lyall St, Esquimalt BC"). The server's LIVE `derive_project_name`
    /// only splits on commas, so persisting the canonical comma form is what
    /// guarantees the server derives the same street-line name iOS previews.
    /// Comma-bearing, unrecognizable, and street-line-only addresses pass
    /// through untouched; the operation is idempotent.
    static func canonicalizedAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(",") else { return trimmed }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = Self.streetLineRegex.firstMatch(in: trimmed, options: [], range: range),
              let matchRange = Range(match.range, in: trimmed) else { return trimmed }

        let streetLine = String(trimmed[matchRange]).trimmingCharacters(in: .whitespaces)
        let remainder = String(trimmed[matchRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !streetLine.isEmpty, !remainder.isEmpty else { return trimmed }
        return "\(streetLine), \(remainder)"
    }

    /// Anchored civic-number + street-name + street-suffix matcher.
    /// Suffix list is deliberately conservative (unambiguous street types
    /// only) — bare words that double as place names (Hill, Bay, Green…)
    /// are excluded so "3040 Cedar Hill Rd" never truncates to the wrong
    /// token. Keep in lockstep with the SQL in `derive_project_name`.
    private static let streetLineRegex: NSRegularExpression = {
        let unitPrefix = #"(?:(?:unit|apt|apartment|suite|ste|#)\s*[0-9A-Za-z-]+[\s,]+)?"#
        let civicNumber = #"\d+[A-Za-z]?(?:[-/]\d+[A-Za-z]?)?"#
        let intermediateWords = #"(?:[A-Za-z0-9'.\-]+\s+){0,4}"#
        let suffix = #"(?:st|street|ave|avenue|av|rd|road|dr|drive|blvd|boulevard|"#
            + #"cres|crescent|crt|ct|court|pl|place|ln|lane|way|ter|terr|terrace|"#
            + #"hwy|highway|pkwy|parkway|cir|circle|trl|trail|sq|square|gdns|gardens)\b\.?"#
        let directional = #"(?:\s+(?:N|S|E|W|NE|NW|SE|SW|North|South|East|West)\b)?"#
        let pattern = "^" + unitPrefix + civicNumber + #"\s+"# + intermediateWords + suffix + directional
        // Force-unwrap is safe: the pattern is a compile-time constant
        // exercised by ProjectAutoNamerTests.
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()
}
