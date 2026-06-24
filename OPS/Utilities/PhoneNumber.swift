//
//  PhoneNumber.swift
//  OPS
//
//  Phone-number normalization for around-call lead dedup (iOS feature 154cb8a3).
//  OPS is NANP-centric (Canada / US); normalization collapses formatting and the
//  optional country code so "+1 (604) 555-0142", "604-555-0142" and
//  "6045550142" all compare equal. Used both to match an inbound/outbound caller
//  to an existing lead (avoiding pipeline pollution) and as the canonical form
//  stored in activities.caller_number.
//

import Foundation

enum PhoneNumber {

    /// Reduce a raw phone string to canonical digits for comparison + storage.
    ///
    /// - Strips every non-digit (spaces, dashes, parens, a leading `+`).
    /// - Drops a leading NANP country code `1` when the result is 11 digits, so
    ///   a number stored with the country code matches the same number without.
    /// - Returns `nil` for input that carries no digits at all.
    static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var digits = String(raw.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) })
        guard !digits.isEmpty else { return nil }
        if digits.count == 11, digits.hasPrefix("1") {
            digits = String(digits.dropFirst())
        }
        return digits
    }

    /// True when two raw phone strings refer to the same number after
    /// normalization. `nil`/blank inputs never match.
    static func sameNumber(_ a: String?, _ b: String?) -> Bool {
        guard let na = normalize(a), let nb = normalize(b) else { return false }
        return na == nb
    }

    /// CallKit-ready E.164 as `Int64` (NANP-centric: a 10-digit number gets a `1`
    /// country code). Used to feed the Call Directory extension. Returns `nil`
    /// when the result isn't a plausible phone integer.
    static func e164Int64(_ raw: String?) -> Int64? {
        guard let digits = normalize(raw) else { return nil }
        let withCountry = digits.count == 10 ? "1" + digits : digits
        guard withCountry.count >= 11, withCountry.count <= 15 else { return nil }
        return Int64(withCountry)
    }
}
