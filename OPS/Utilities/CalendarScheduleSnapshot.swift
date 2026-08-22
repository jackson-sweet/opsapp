//
//  CalendarScheduleSnapshot.swift
//  OPS
//
//  Calendar cache builders and the Sendable snapshots they hand back across a
//  DataActor boundary.
//
//  Both were O(every live dated task) walks that faulted `project` / `teamMembers`
//  per row, run on the main actor from `scheduledTasksDidChange`. One reschedule
//  fired that flag once and both passes ran back to back, which is the freeze in
//  bug 1bade6dd. The work itself is unavoidable; doing it on the main thread is not.
//
//  The pure builders preserve the established visibility and scoping rules while
//  allowing the week and auxiliary windows to be fetched and assembled off-main.
//

import Foundation
import SwiftData

// MARK: - Shared day key

/// `yyyy-MM-dd`, the key both caches have always used. One formatter, because
/// building a DateFormatter per day was itself part of the month grid's cost.
enum CalendarDayKey {
    /// Shared across the main actor and the DataActor. `DateFormatter.string(from:)`
    /// is documented thread-safe (iOS 7+) and this instance is never mutated after
    /// construction, so the two rebuild paths can format concurrently.
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(for date: Date) -> String { formatter.string(from: date) }
}

// MARK: - Week canvas

/// One rebuilt week window as values: which task ids land on which day, and the
/// per-day count the day cells render. Ids rather than models — `@Model` instances
/// belong to the context that fetched them and must never cross an actor boundary.
struct CalendarWeekCacheSnapshot: Sendable {
    let weekStart: Date
    /// Day key → task ids, already ordered by start date.
    let taskIdsByDay: [String: [String]]
    /// Day key → count. Same keys as `taskIdsByDay`.
    let countsByDay: [String: Int]

    /// The cached canvas contains the visible week plus both adjacent weeks.
    /// Navigation can publish any of those weeks immediately while a new
    /// centered snapshot is prepared off the render thread.
    func covers(weekStarting candidate: Date, calendar: Calendar = .current) -> Bool {
        CalendarWeekWindow(weekStart: weekStart, calendar: calendar)
            .covers(weekStarting: candidate, calendar: calendar)
    }
}

/// Exact store-level overlap bounds for the 21-day week cache.
struct CalendarWeekWindow: Sendable, Equatable {
    let start: Date
    let endExclusive: Date

    init(weekStart: Date, calendar: Calendar = .current) {
        let anchor = calendar.startOfDay(for: weekStart)
        self.start = calendar.date(byAdding: .day, value: -7, to: anchor) ?? anchor
        self.endExclusive = calendar.date(byAdding: .day, value: 14, to: anchor) ?? anchor
    }

    func overlaps(start itemStart: Date, end itemEnd: Date?) -> Bool {
        itemStart < endExclusive && (itemEnd ?? itemStart) >= start
    }

    func covers(weekStarting candidate: Date, calendar: Calendar = .current) -> Bool {
        let candidateStart = calendar.startOfDay(for: candidate)
        guard let candidateEnd = calendar.date(byAdding: .day, value: 7, to: candidateStart) else {
            return false
        }
        return candidateStart >= start && candidateEnd <= endExclusive
    }
}

// MARK: - Calendar auxiliary sources

/// Permission and identity values resolved on the main actor before a calendar
/// read crosses to DataActor.
struct CalendarAuxiliaryScope: Sendable, Equatable {
    let userId: String
    let companyId: String
    let canViewAllCalendar: Bool
    let canApproveTimeOff: Bool
}

/// A rolling display window for personal events and booked site visits. Three
/// months is enough for a month grid plus an adjacent swipe in either direction,
/// without materializing the company's complete calendar history.
struct CalendarAuxiliaryWindow: Sendable, Equatable {
    let start: Date
    let endExclusive: Date

    init(centerDate: Date, calendar: Calendar = .current) {
        let center = calendar.startOfDay(for: centerDate)
        self.start = calendar.date(byAdding: .day, value: -45, to: center) ?? center
        self.endExclusive = calendar.date(byAdding: .day, value: 46, to: center) ?? center
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= start && day < endExclusive
    }
}

struct CalendarAuxiliarySnapshot: Sendable {
    let window: CalendarAuxiliaryWindow
    let userEventIds: [String]
    let bookedVisitIds: [String]
}

struct CalendarLoadSnapshot: Sendable {
    let week: CalendarWeekCacheSnapshot
    let auxiliary: CalendarAuxiliarySnapshot
}

enum CalendarWeekCacheBuilder {

    /// The 21-day window the canvas caches: the visible week plus one week either
    /// side, so day-swiping never hits the database.
    static let dayOffsets = -7..<14

    /// Bucket `tasks` (already scoped and filtered) into the window that starts one
    /// week before `weekStart`. A task belongs to a day by OVERLAP, so long-running
    /// work still shows on days after its start.
    static func snapshot(
        tasks: [ProjectTask],
        weekStart: Date,
        calendar: Calendar = .current
    ) -> CalendarWeekCacheSnapshot {
        var idsByDay: [String: [String]] = [:]
        var countsByDay: [String: Int] = [:]

        for dayOffset in dayOffsets {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let dateKey = CalendarDayKey.key(for: date)

            let tasksForDay = tasks.filter { task in
                guard let start = task.startDate else { return false }
                let taskStartDay = calendar.startOfDay(for: start)
                let taskEndDay = calendar.startOfDay(for: task.endDate ?? start)
                return taskStartDay <= dayStart && taskEndDay >= dayStart
            }
            .sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }

            idsByDay[dateKey] = tasksForDay.map(\.id)
            countsByDay[dateKey] = tasksForDay.count
        }

        return CalendarWeekCacheSnapshot(
            weekStart: weekStart,
            taskIdsByDay: idsByDay,
            countsByDay: countsByDay
        )
    }
}

// MARK: - Month grid

enum CalendarMonthPreviewBuilder {

    /// Expand each task into one badge per day it covers, keyed by day.
    static func previews(
        tasks: [ProjectTask],
        calendar: Calendar = .current
    ) -> [String: [ScheduledTaskPreview]] {
        var cache: [String: [ScheduledTaskPreview]] = [:]

        for task in tasks {
            guard let startDate = task.startDate else { continue }
            let taskStart = calendar.startOfDay(for: startDate)
            // No end date → single-day event.
            let taskEnd = calendar.startOfDay(for: task.endDate ?? startDate)

            let isMultiDay = !calendar.isDate(taskStart, inSameDayAs: taskEnd)
            let totalDays = (calendar.dateComponents([.day], from: taskStart, to: taskEnd).day ?? 0) + 1

            // Bug 087bfaf8 — the project title is the primary label so operators can
            // identify the job at a glance; the task's own title is the fallback for
            // rows with no project (tutorial demo data).
            let primaryLabel = task.project?.title.isEmpty == false
                ? (task.project?.title ?? task.displayTitle)
                : task.displayTitle
            let displayColor = task.effectiveColor
            let taskTypeDisplay = task.taskType?.display

            var currentDate = taskStart
            var dayOffset = 0

            while currentDate <= taskEnd {
                let dateKey = CalendarDayKey.key(for: currentDate)
                let isFirst = dayOffset == 0
                let isLast = currentDate >= taskEnd
                let isMonday = calendar.component(.weekday, from: currentDate) == 2

                cache[dateKey, default: []].append(
                    ScheduledTaskPreview(
                        id: "\(task.id)_\(dayOffset)",
                        eventId: task.id,
                        title: primaryLabel,
                        color: displayColor,
                        startDate: taskStart,
                        endDate: taskEnd,
                        isMultiDay: isMultiDay,
                        dayOffset: dayOffset,
                        totalDays: totalDays,
                        isFirst: isFirst,
                        isLast: isLast,
                        isFirstInWeek: isFirst || isMonday,
                        taskTypeDisplay: taskTypeDisplay
                    )
                )

                guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
                currentDate = nextDate
                dayOffset += 1
            }
        }

        return cache
    }

    /// Time off and personal events share the badge shape, with a `userevent:`
    /// prefix on the event id so the day sheet can route taps differently.
    /// Stays on the main actor: these rows are already in hand there and there is
    /// no relationship to fault.
    static func previews(
        userEvents: [CalendarUserEvent],
        calendar: Calendar = .current
    ) -> [String: [ScheduledTaskPreview]] {
        var cache: [String: [ScheduledTaskPreview]] = [:]

        for event in userEvents {
            let evStart = calendar.startOfDay(for: event.startDate)
            let evEnd = calendar.startOfDay(for: event.endDate)
            let isMultiDay = !calendar.isDate(evStart, inSameDayAs: evEnd)
            let totalDays = max((calendar.dateComponents([.day], from: evStart, to: evEnd).day ?? 0) + 1, 1)

            // Time off uses the tan event lane; custom events use a neutral lane so
            // they do not read as work badges.
            let displayColor = event.isTimeOff ? "#C4A868" : "#7A7A7A"
            let label = event.title.isEmpty
                ? (event.isTimeOff ? "Time Off" : "Custom")
                : event.title

            var currentDate = evStart
            var dayOffset = 0

            while currentDate <= evEnd {
                let dateKey = CalendarDayKey.key(for: currentDate)
                let isFirst = dayOffset == 0
                let isLast = currentDate >= evEnd
                let isMonday = calendar.component(.weekday, from: currentDate) == 2

                cache[dateKey, default: []].append(
                    ScheduledTaskPreview(
                        id: "userevent_\(event.id)_\(dayOffset)",
                        eventId: "userevent:\(event.id)",
                        title: label,
                        color: displayColor,
                        startDate: evStart,
                        endDate: evEnd,
                        isMultiDay: isMultiDay,
                        dayOffset: dayOffset,
                        totalDays: totalDays,
                        isFirst: isFirst,
                        isLast: isLast,
                        isFirstInWeek: isFirst || isMonday,
                        taskTypeDisplay: event.isTimeOff ? "TIME OFF" : "CUSTOM"
                    )
                )

                guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
                currentDate = nextDate
                dayOffset += 1
            }
        }

        return cache
    }

    /// Fold the user-event badges into the task badges and put every day's row in
    /// start-date order — the grid's row packer depends on that order.
    static func merged(
        _ taskPreviews: [String: [ScheduledTaskPreview]],
        _ userEventPreviews: [String: [ScheduledTaskPreview]]
    ) -> [String: [ScheduledTaskPreview]] {
        var cache = taskPreviews
        for (dateKey, previews) in userEventPreviews {
            cache[dateKey, default: []].append(contentsOf: previews)
        }
        for key in cache.keys {
            cache[key] = cache[key]?.sorted { $0.startDate < $1.startDate }
        }
        return cache
    }
}
