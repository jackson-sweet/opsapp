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

    /// Format a Date as a Supabase `timestamptz` ISO-8601 string with fractional seconds.
    /// Use for `timestamptz` / `timestamp` columns (e.g. deleted_at, archived_at).
    static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }

    /// Format a Date as a Supabase `date` column string ("yyyy-MM-dd").
    /// Use for `date`-only columns (e.g. expected_close_date, actual_close_date).
    static func formatDate(_ date: Date) -> String {
        dateOnly.string(from: date)
    }

    /// Re-anchor an ISO-8601 instant to LOCAL midnight of its calendar day
    /// (device time zone), as an internet date-time string. Keeps all-day task
    /// schedule dates canonical so they never render a day off across clients.
    static func localMidnightISO(from iso: String) -> String? {
        guard let instant = parse(iso) else { return nil }
        return scheduleMidnight.string(from: Calendar.current.startOfDay(for: instant))
    }

    /// Return a copy of an outbound project_task payload with `start_date` /
    /// `end_date` re-anchored to local midnight. String values only; nulls and
    /// unparseable values are left untouched. Idempotent. Used by BOTH outbound
    /// paths (OutboundProcessor and DataActor) so they cannot drift.
    static func anchoringScheduleDates(_ payload: [String: Any]) -> [String: Any] {
        var p = payload
        for key in ["start_date", "end_date"] {
            if let iso = p[key] as? String, let anchored = localMidnightISO(from: iso) {
                p[key] = anchored
            }
        }
        return p
    }

    private static let scheduleMidnight: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
