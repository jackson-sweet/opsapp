//
//  LeadClientMatcher.swift
//  OPS
//
//  Bug 1d5ab9aa — a lead saved on iOS never created its client. The web
//  email/lead-engine paths create-and-link a `clients` row; the manual paths
//  did not, so a hand-entered lead ("James Boss") existed only as free-text
//  contact fields and Won-conversion produced a client-less project.
//
//  This is the match half: BEFORE creating a client, look for one the company
//  already has so repeat callers never spawn duplicates. Matching is local
//  SwiftData (clients sync down), strongest signal first:
//
//    1. phone  — digits-only, suffix match ≥7 digits (survives +1 / formatting)
//    2. email  — case-insensitive exact
//    3. name   — case- and whitespace-insensitive exact
//
//  The create half lives at the call site (AddLeadSheet) via
//  DataController.createClient — the durable local-insert + sync-op path.
//

import Foundation

enum LeadClientMatcher {

    /// Digits-only form of a phone number; nil when fewer than 7 digits
    /// (too short to be a meaningful match key).
    static func normalizedPhone(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let digits = raw.filter(\.isNumber)
        return digits.count >= 7 ? digits : nil
    }

    /// Trimmed, lowercased email; nil when empty or not plausibly an email.
    static func normalizedEmail(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), trimmed.count >= 3 else { return nil }
        return trimmed
    }

    /// Trimmed, lowercased name; nil when empty.
    static func normalizedName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Two phone numbers match when either digits-string is a suffix of the
    /// other (handles "+1 604 555 0142" vs "604-555-0142" vs "5550142" is NOT
    /// matched — both sides must keep ≥7 digits, and the shorter side must be
    /// ≥7 so a bare extension can never claim a client).
    static func phonesMatch(_ a: String?, _ b: String?) -> Bool {
        guard let na = normalizedPhone(a), let nb = normalizedPhone(b) else { return false }
        return na.hasSuffix(nb) || nb.hasSuffix(na)
    }

    /// First live client matching phone → email → name, in that priority.
    /// Soft-deleted clients never match.
    static func match(
        in clients: [Client],
        name: String?,
        email: String?,
        phone: String?
    ) -> Client? {
        let live = clients.filter { $0.deletedAt == nil }

        if normalizedPhone(phone) != nil,
           let byPhone = live.first(where: { phonesMatch($0.phoneNumber, phone) }) {
            return byPhone
        }

        if let targetEmail = normalizedEmail(email),
           let byEmail = live.first(where: { normalizedEmail($0.email) == targetEmail }) {
            return byEmail
        }

        if let targetName = normalizedName(name),
           let byName = live.first(where: { normalizedName($0.name) == targetName }) {
            return byName
        }

        return nil
    }
}
