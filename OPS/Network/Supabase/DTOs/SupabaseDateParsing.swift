//
//  SupabaseDateParsing.swift
//  OPS
//
//  Shared ISO 8601 date parsing for Supabase DTOs.
//  Supabase returns fractional-second timestamps (e.g. "2024-01-15T10:30:00.123456+00:00")
//  which the default ISO8601DateFormatter cannot parse.
//

import Foundation

enum SupabaseDate {
    /// Formatter that handles Supabase timestamps with fractional seconds.
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Fallback formatter without fractional seconds for edge cases.
    private static let fallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Date-only formatter for `date` columns (no time component).
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Parse a Supabase ISO 8601 string, trying fractional seconds first.
    static func parse(_ string: String) -> Date? {
        formatter.date(from: string) ?? fallback.date(from: string)
    }

    /// Parse a Supabase `date` column ("yyyy-MM-dd"). Returns midnight UTC.
    static func parseDateOnly(_ string: String) -> Date? {
        dateOnly.date(from: string)
    }
}
