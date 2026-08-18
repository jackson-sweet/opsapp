//
//  StatutoryHolidays.swift
//  OPS
//
//  Bug 23ecb01a — statutory holidays on the calendar.
//
//  Computed on device, never fetched. A crew scheduling next month needs the
//  holidays whether or not the phone has signal, and a date arithmetic table
//  that has been fixed in law for decades has no business behind a network
//  call, an API key, or a sync table.
//
//  Jurisdiction: Canada federal + British Columbia provincial — the company is
//  BC-based. The two lists overlap almost entirely; where they differ the
//  holiday says which one it belongs to (Boxing Day is federal but not a BC
//  statutory holiday; BC Day and Family Day are provincial only).
//
//  Fixed-date holidays are listed on the day they fall. Neither list is
//  "observed-day shifted" here: BC's Employment Standards Act pays the
//  statutory day itself, and a substituted day off is an employer arrangement
//  the app has no way to know about.
//

import Foundation

struct StatutoryHoliday: Identifiable, Hashable {
    /// Which list the day comes from — the badge the calendar prints.
    enum Jurisdiction: String {
        /// A BC statutory holiday (every one of which is also federal).
        case britishColumbia
        /// Federally observed, but not a BC statutory holiday.
        case federal

        var badge: String {
            switch self {
            case .britishColumbia: return "STAT"
            case .federal:         return "FEDERAL"
            }
        }
    }

    /// Local start-of-day.
    let date: Date
    let name: String
    let jurisdiction: Jurisdiction

    var id: String {
        "holiday:\(Int(date.timeIntervalSince1970)):\(name)"
    }
}

enum StatutoryHolidays {

    // MARK: - Lookup

    /// The statutory holiday falling on `date`, or nil. Day-granular.
    static func holiday(on date: Date, calendar: Calendar = .current) -> StatutoryHoliday? {
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: day)
        return holidays(inYear: year, calendar: calendar).first { $0.date == day }
    }

    /// Every statutory holiday in a closed date range, oldest first.
    static func holidays(in range: ClosedRange<Date>, calendar: Calendar = .current) -> [StatutoryHoliday] {
        let firstYear = calendar.component(.year, from: range.lowerBound)
        let lastYear = calendar.component(.year, from: range.upperBound)
        let lower = calendar.startOfDay(for: range.lowerBound)
        let upper = calendar.startOfDay(for: range.upperBound)
        return (firstYear...lastYear)
            .flatMap { holidays(inYear: $0, calendar: calendar) }
            .filter { $0.date >= lower && $0.date <= upper }
            .sorted { $0.date < $1.date }
    }

    /// Every statutory holiday in a calendar year, oldest first. Memoized —
    /// a month grid asks this question once per visible cell.
    static func holidays(inYear year: Int, calendar: Calendar = .current) -> [StatutoryHoliday] {
        let key = CacheKey(year: year, timeZone: calendar.timeZone.identifier)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[key] { return cached }
        let computed = compute(year: year, calendar: calendar)
        cache[key] = computed
        return computed
    }

    // MARK: - Derivation

    private static func compute(year: Int, calendar: Calendar) -> [StatutoryHoliday] {
        var holidays: [StatutoryHoliday] = []

        func add(_ date: Date?, _ name: String, _ jurisdiction: StatutoryHoliday.Jurisdiction = .britishColumbia) {
            guard let date else { return }
            holidays.append(
                StatutoryHoliday(
                    date: calendar.startOfDay(for: date),
                    name: name,
                    jurisdiction: jurisdiction
                )
            )
        }

        add(fixed(year: year, month: 1, day: 1, calendar: calendar), "New Year's Day")
        // BC Family Day moved to the THIRD Monday of February in 2019.
        add(nthWeekday(year: year, month: 2, weekday: 2, ordinal: 3, calendar: calendar), "Family Day")
        add(goodFriday(year: year, calendar: calendar), "Good Friday")
        add(victoriaDay(year: year, calendar: calendar), "Victoria Day")
        add(fixed(year: year, month: 7, day: 1, calendar: calendar), "Canada Day")
        add(nthWeekday(year: year, month: 8, weekday: 2, ordinal: 1, calendar: calendar), "BC Day")
        add(nthWeekday(year: year, month: 9, weekday: 2, ordinal: 1, calendar: calendar), "Labour Day")
        add(
            fixed(year: year, month: 9, day: 30, calendar: calendar),
            "National Day for Truth and Reconciliation"
        )
        add(nthWeekday(year: year, month: 10, weekday: 2, ordinal: 2, calendar: calendar), "Thanksgiving")
        add(fixed(year: year, month: 11, day: 11, calendar: calendar), "Remembrance Day")
        add(fixed(year: year, month: 12, day: 25, calendar: calendar), "Christmas Day")
        // Federal general holiday; BC does not make it statutory.
        add(fixed(year: year, month: 12, day: 26, calendar: calendar), "Boxing Day", .federal)

        return holidays.sorted { $0.date < $1.date }
    }

    private static func fixed(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// `weekday` is Gregorian (1 = Sunday, 2 = Monday).
    private static func nthWeekday(
        year: Int,
        month: Int,
        weekday: Int,
        ordinal: Int,
        calendar: Calendar
    ) -> Date? {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                weekday: weekday,
                weekdayOrdinal: ordinal
            )
        )
    }

    /// Victoria Day: the Monday preceding May 25 — i.e. the last Monday on or
    /// before May 24.
    private static func victoriaDay(year: Int, calendar: Calendar) -> Date? {
        guard let may24 = fixed(year: year, month: 5, day: 24, calendar: calendar) else { return nil }
        let weekday = calendar.component(.weekday, from: may24)
        let daysBackToMonday = (weekday - 2 + 7) % 7
        return calendar.date(byAdding: .day, value: -daysBackToMonday, to: may24)
    }

    /// Good Friday: two days before Easter Sunday.
    private static func goodFriday(year: Int, calendar: Calendar) -> Date? {
        guard let easter = easterSunday(year: year, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: -2, to: easter)
    }

    /// Gregorian Easter — the Meeus/Jones/Butcher algorithm, all integer
    /// division. Exact for every year in the Gregorian calendar.
    private static func easterSunday(year: Int, calendar: Calendar) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return fixed(year: year, month: month, day: day, calendar: calendar)
    }

    // MARK: - Memoization

    private struct CacheKey: Hashable {
        let year: Int
        let timeZone: String
    }

    private static let cacheLock = NSLock()
    private static var cache: [CacheKey: [StatutoryHoliday]] = [:]
}
