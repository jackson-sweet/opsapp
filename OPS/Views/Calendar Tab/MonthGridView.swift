//
//  MonthGridView.swift
//  OPS
//
//  Rebuilt from scratch for smooth Apple Calendar-like experience
//

import SwiftUI
import SwiftData

struct IdentifiableDate: Identifiable {
    let id = UUID()
    let date: Date
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ScheduledTaskPreview: Identifiable, Equatable {
    let id: String
    let eventId: String
    let title: String
    let color: String
    let startDate: Date
    let endDate: Date
    let isMultiDay: Bool
    let dayOffset: Int
    let totalDays: Int
    let isFirst: Bool
    let isLast: Bool
    let isFirstInWeek: Bool
    let taskTypeDisplay: String?  // Task type for subtitle in tall events

    static func == (lhs: ScheduledTaskPreview, rhs: ScheduledTaskPreview) -> Bool {
        lhs.id == rhs.id
    }
}

struct WeekEventSpan: Identifiable {
    let id: String
    let eventId: String
    let title: String
    let color: String
    let startDate: Date
    let endDate: Date
    let startDayIndex: Int
    let endDayIndex: Int
    let row: Int
    let isFirstSegment: Bool
    let isLastSegment: Bool
    let isSingleDay: Bool
    let taskTypeDisplay: String?  // Task type for subtitle in tall events
}

struct MoreEventsIndicator: Identifiable {
    let id = UUID()
    let dayIndex: Int
    let count: Int
    let row: Int
}

/// Pure weekly lane allocator for the month grid. Event rows keep the mobile
/// 44pt interaction minimum; the compact `+N` lane is reserved only on days
/// that actually overflow. Replanning to a fixed point keeps multi-day spans
/// and their overflow indicators collision-free across every covered day.
struct MonthGridEventSlotPlanner {
    struct Candidate: Equatable {
        let id: String
        let startDayIndex: Int
        let endDayIndex: Int
    }

    struct Plan: Equatable {
        let rowByEventId: [String: Int]
        let hiddenEventIdsByDay: [[String]]
        let indicatorDays: Set<Int>
        let indicatorRow: Int
    }

    static func plan(
        candidates: [Candidate],
        eventIdsByDay: [[String]],
        cellHeight: CGFloat
    ) -> Plan {
        let dayCount = eventIdsByDay.count
        let availableHeight = max(0, cellHeight - OPSStyle.Layout.monthGridDayHeaderHeight)
        let indicatorHeight = cellHeight < OPSStyle.Layout.monthGridStandardHeightThreshold
            ? OPSStyle.Layout.monthGridCompactBadgeHeight
            : OPSStyle.Layout.monthGridStandardBadgeHeight
        let normalCapacity = max(
            1,
            Int(availableHeight / OPSStyle.Layout.touchTargetMin)
        )
        let overflowCapacity = max(
            1,
            Int((availableHeight - indicatorHeight) / OPSStyle.Layout.touchTargetMin)
        )

        var indicatorDays = Set<Int>()
        var rowByEventId = allocate(
            candidates: candidates,
            capacityByDay: Array(repeating: normalCapacity, count: dayCount)
        )

        // At most `dayCount` new indicator days can be discovered. A fixed-point
        // pass matters when hiding one multi-day span makes every day it covers
        // reserve the same collision-free overflow lane.
        for _ in 0...dayCount {
            let discoveredDays = Set(eventIdsByDay.indices.filter { dayIndex in
                eventIdsByDay[dayIndex].contains { rowByEventId[$0] == nil }
            })
            let expandedDays = indicatorDays.union(discoveredDays)
            if expandedDays == indicatorDays {
                break
            }

            indicatorDays = expandedDays
            let capacityByDay = eventIdsByDay.indices.map { dayIndex in
                indicatorDays.contains(dayIndex) ? overflowCapacity : normalCapacity
            }
            rowByEventId = allocate(
                candidates: candidates,
                capacityByDay: capacityByDay
            )
        }

        let hiddenEventIdsByDay = eventIdsByDay.map { eventIds in
            var seen = Set<String>()
            return eventIds.filter { id in
                guard rowByEventId[id] == nil else { return false }
                return seen.insert(id).inserted
            }
        }

        return Plan(
            rowByEventId: rowByEventId,
            hiddenEventIdsByDay: hiddenEventIdsByDay,
            indicatorDays: indicatorDays,
            indicatorRow: overflowCapacity
        )
    }

    private static func allocate(
        candidates: [Candidate],
        capacityByDay: [Int]
    ) -> [String: Int] {
        var occupiedRowsByDay = Array(repeating: Set<Int>(), count: capacityByDay.count)
        var rowByEventId: [String: Int] = [:]

        for candidate in candidates {
            guard candidate.startDayIndex >= 0,
                  candidate.endDayIndex >= candidate.startDayIndex,
                  candidate.endDayIndex < capacityByDay.count else {
                continue
            }

            let coveredDays = candidate.startDayIndex...candidate.endDayIndex
            let rowLimit = coveredDays.map { capacityByDay[$0] }.min() ?? 0
            guard rowLimit > 0 else { continue }

            for row in 0..<rowLimit {
                guard coveredDays.allSatisfy({ !occupiedRowsByDay[$0].contains(row) }) else {
                    continue
                }
                rowByEventId[candidate.id] = row
                for dayIndex in coveredDays {
                    occupiedRowsByDay[dayIndex].insert(row)
                }
                break
            }
        }

        return rowByEventId
    }
}

class MonthGridCache: ObservableObject {
    @Published var eventsByDate: [String: [ScheduledTaskPreview]] = [:]
    @Published var isLoading = false

    private let calendar = Calendar.current

    func loadEvents(from dataController: DataController, viewModel: CalendarViewModel, tutorialMode: Bool = false) {
        isLoading = true

        Task { @MainActor in
            var cache: [String: [ScheduledTaskPreview]] = [:]

            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()

            var allTasks = dataController.getAllScheduledTasks(from: oneYearAgo)

            // Tutorial mode only shows demo tasks
            if tutorialMode {
                allTasks = allTasks.filter { $0.id.hasPrefix("DEMO_") }
            }

            let filteredTasks = viewModel.applyTaskFilters(to: allTasks)

            for task in filteredTasks {
                guard let startDate = task.startDate else { continue }
                let taskStart = calendar.startOfDay(for: startDate)
                // If no end date, treat as single-day event
                let endDate = task.endDate ?? startDate
                let taskEnd = calendar.startOfDay(for: endDate)

                let isMultiDay = !calendar.isDate(taskStart, inSameDayAs: taskEnd)
                let daySpan = calendar.dateComponents([.day], from: taskStart, to: taskEnd).day ?? 0
                let totalDays = daySpan + 1

                var currentDate = taskStart
                var dayOffset = 0

                while currentDate <= taskEnd {
                    let dateKey = formatDateKey(currentDate)
                    let isFirst = dayOffset == 0
                    let isLast = currentDate >= taskEnd

                    let weekday = calendar.component(.weekday, from: currentDate)
                    let isMonday = (weekday == 2)
                    let isFirstInWeek = isFirst || isMonday

                    let displayColor = task.effectiveColor

                    // Bug 087bfaf8 — Show project title as the primary label on
                    // month-grid badges so users can identify the job at a glance.
                    // Falls back to the task's own display title when there's no
                    // associated project (rare, but possible in tutorial demo data).
                    let primaryLabel = task.project?.title.isEmpty == false
                        ? task.project!.title
                        : task.displayTitle

                    let preview = ScheduledTaskPreview(
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
                        isFirstInWeek: isFirstInWeek,
                        taskTypeDisplay: task.taskType?.display
                    )

                    if cache[dateKey] == nil {
                        cache[dateKey] = []
                    }
                    cache[dateKey]?.append(preview)

                    guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
                    currentDate = nextDate
                    dayOffset += 1
                }
            }

            // Bug 1 — Include user events (time off + personal) alongside
            // project tasks so they show up in the month grid. We reuse the
            // same ScheduledTaskPreview shape with a userEvent: prefix on the
            // eventId so the day sheet can route taps differently if needed.
            let userEvents = viewModel.userEventsForCurrentPeriod.filter { $0.deletedAt == nil }
            for event in userEvents {
                let evStart = calendar.startOfDay(for: event.startDate)
                let evEnd = calendar.startOfDay(for: event.endDate)
                let isMultiDay = !calendar.isDate(evStart, inSameDayAs: evEnd)
                let daySpan = calendar.dateComponents([.day], from: evStart, to: evEnd).day ?? 0
                let totalDays = max(daySpan + 1, 1)

                // Time off uses the tan event lane; custom events use a neutral
                // lane so they do not read as work/task badges.
                let displayColor = event.isTimeOff
                    ? "#C4A868"  // amber
                    : "#7A7A7A"  // neutral grey

                let label = event.title.isEmpty
                    ? (event.isTimeOff ? "Time Off" : "Custom")
                    : event.title

                var currentDate = evStart
                var dayOffset = 0
                while currentDate <= evEnd {
                    let dateKey = formatDateKey(currentDate)
                    let isFirst = dayOffset == 0
                    let isLast = currentDate >= evEnd
                    let weekday = calendar.component(.weekday, from: currentDate)
                    let isMonday = (weekday == 2)
                    let isFirstInWeek = isFirst || isMonday

                    let preview = ScheduledTaskPreview(
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
                        isFirstInWeek: isFirstInWeek,
                        taskTypeDisplay: event.isTimeOff ? "TIME OFF" : "CUSTOM"
                    )

                    if cache[dateKey] == nil { cache[dateKey] = [] }
                    cache[dateKey]?.append(preview)

                    guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
                    currentDate = nextDate
                    dayOffset += 1
                }
            }

            for key in cache.keys {
                cache[key] = cache[key]?.sorted { $0.startDate < $1.startDate }
            }

            eventsByDate = cache
            isLoading = false
        }
    }

    func events(for date: Date) -> [ScheduledTaskPreview] {
        let dateKey = formatDateKey(date)
        return eventsByDate[dateKey] ?? []
    }

    private func formatDateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct MonthGridView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @StateObject private var cache = MonthGridCache()
    /// Inherited from the tab slot — the month grid lives inside SCHEDULE.
    @Environment(\.isActiveTab) private var isActiveTab
    /// A user event changed while SCHEDULE was hidden; the grid rebuild waits.
    @State private var needsUserEventsReload = false
    @State private var cellHeight: CGFloat = 120
    @State private var sheetDate: IdentifiableDate?
    @State private var scrollOffset: CGFloat = 0
    @State private var gestureStartHeight: CGFloat = 120
    @State private var hasScrolledToCurrentMonth = false
    @State private var isProgrammaticScroll = false
    @State private var lastScrollTriggeredMonth: Date?
    @State private var initialScrollOffset: CGFloat?
    @State private var hasNotifiedTutorialScroll = false
    @State private var hasNotifiedTutorialPinch = false
    @State private var scrollDirection: ScrollDirection = .down
    @State private var showMonthPicker = false

    // Long-press / context-menu reschedule state (Bug 70591eb5)
    @State private var rescheduleTarget: RescheduleTarget?
    @State private var showingCascadePreview = false
    @State private var pendingCascadePlan: DataController.CascadePlan?
    @State private var pendingCascadeTask: ProjectTask?
    @State private var pendingCascadeDays = 0
    @AppStorage("showCascadePreview") private var showCascadePreviewPref = true

    /// Identifiable wrapper so SwiftUI can drive the reschedule sheet from a
    /// `@State` of the task. ProjectTask isn't Identifiable in its model
    /// definition.
    fileprivate struct RescheduleTarget: Identifiable {
        let id: String
        let task: ProjectTask
    }

    private enum ScrollDirection {
        case up, down
    }
    @EnvironmentObject private var dataController: DataController
    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(ScheduleDragSession.self) private var dragSession

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdayLabels = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    private let minHeight: CGFloat = 80
    private let maxHeight: CGFloat = 320

    private var monthsToDisplay: [Date] {
        let calendar = Calendar.current
        let centerDate = Date()

        var months: [Date] = []
        for offset in -12...12 {
            if let month = calendar.date(byAdding: .month, value: offset, to: centerDate),
               let monthStart = calendar.dateInterval(of: .month, for: month)?.start {
                months.append(monthStart)
            }
        }
        return months
    }

    /// Re-read user events and rebuild the grid's event cache. Shared by the
    /// live listener and the deferred spend on activation so both do identical
    /// work.
    private func reloadUserEvents() {
        viewModel.loadUserEvents()
        if let dataController = viewModel.dataController {
            cache.loadEvents(from: dataController, viewModel: viewModel, tutorialMode: tutorialMode)
        }
    }

    private func datesForMonth(_ monthStart: Date) -> [Date?] {
        let calendar = Calendar.current

        guard let monthInterval = calendar.dateInterval(of: .month, for: monthStart) else { return [] }
        let firstOfMonth = monthInterval.start
        guard let lastOfMonth = calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .month, value: 1, to: firstOfMonth)!) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let daysFromMonday = (firstWeekday + 5) % 7

        var dates: [Date?] = []

        for _ in 0..<daysFromMonday {
            dates.append(nil)
        }

        var currentDate = firstOfMonth
        while currentDate <= lastOfMonth {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        while dates.count % 7 != 0 {
            dates.append(nil)
        }

        return dates
    }


    private func updateVisibleMonth(for date: Date, offset: CGFloat) {
        guard !isProgrammaticScroll else { return }

        let calendar = Calendar.current
        // Threshold: change month when first week is within this range of scroll view top
        // Higher value = month changes earlier when scrolling into new month
        // ~200pt ≈ 3/5 of typical visible scroll area before month reaches top
        let threshold: CGFloat = 200

        if offset > -threshold && offset < threshold {
            if let monthStart = calendar.dateInterval(of: .month, for: date)?.start {
                if !calendar.isDate(viewModel.visibleMonth, equalTo: monthStart, toGranularity: .month) {
                    // Determine scroll direction based on month comparison
                    let isScrollingToLaterMonth = monthStart > viewModel.visibleMonth
                    scrollDirection = isScrollingToLaterMonth ? .down : .up
                    // Track that this change came from scrolling
                    lastScrollTriggeredMonth = monthStart
                    // Update with animation for smooth transition
                    withAnimation(OPSStyle.Animation.fast) {
                        viewModel.visibleMonth = monthStart
                    }
                }
            }
        }
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).uppercased()
    }

    // MARK: - Long-press / context-menu helpers (Bug 70591eb5)

    /// Returns the first visible day of `span` within the supplied `dates`
    /// array. Used to anchor the day sheet when a badge is tapped — matches
    /// the behaviour of tapping the first day cell that the badge covers.
    private func dayDateForSpan(_ span: WeekEventSpan, dates: [Date?]) -> Date? {
        guard span.startDayIndex >= 0, span.startDayIndex < dates.count else { return nil }
        return dates[span.startDayIndex]
    }

    /// Full schedule-action contract for a task badge. Non-task spans and tasks
    /// outside the user's calendar.edit scope remain read-only.
    private func scheduleQuickActions(for span: WeekEventSpan) -> ScheduleCardQuickActions? {
        guard let task = dataController.getTask(id: span.eventId), task.canEditSchedule else {
            return nil
        }

        return ScheduleCardQuickActions(
            onPush: { pushTaskByDays(eventId: task.id, days: $0) },
            onExtend: { extendTaskByDays(eventId: task.id, days: $0) },
            onCascade: { prepareCascade(eventId: task.id, days: $0) },
            onReschedule: {
                rescheduleTarget = RescheduleTarget(id: task.id, task: task)
            },
            onSelect: nil
        )
    }

    /// Build a drag payload for a badge if its event may be rescheduled. Tasks are
    /// gated on calendar.edit (scope-aware); non-recurring user events on the same
    /// owner+crew gate UserEventSheet uses. Returns nil → the badge isn't draggable.
    private func dragPayload(for span: WeekEventSpan) -> RescheduleDragPayload? {
        let cal = Calendar.current
        if span.eventId.hasPrefix("userevent:") {
            let eventId = String(span.eventId.dropFirst("userevent:".count))
            guard let event = dataController.getUserEvent(id: eventId),
                  !event.isRecurringInstance,
                  PermissionStore.shared.canEditSchedule(
                    assigneeIds: [event.userId] + (event.teamMemberIds ?? [])) else { return nil }
            let days = (cal.dateComponents([.day],
                                           from: cal.startOfDay(for: event.startDate),
                                           to: cal.startOfDay(for: event.endDate)).day ?? 0) + 1
            return RescheduleDragPayload(id: eventId, kind: .userEvent, title: event.title,
                                         durationDays: max(days, 1),
                                         startEpoch: event.startDate.timeIntervalSince1970)
        } else {
            guard let task = dataController.getTask(id: span.eventId),
                  task.canEditSchedule, let start = task.startDate else { return nil }
            // Calendar-day span (matches targetDates + the month-grid bar renderer) so
            // the highlight never disagrees with the landed drop for tasks whose stored
            // end time-of-day precedes the start time-of-day.
            let days = (cal.dateComponents([.day],
                                           from: cal.startOfDay(for: start),
                                           to: cal.startOfDay(for: task.endDate ?? start)).day ?? 0) + 1
            return RescheduleDragPayload(id: task.id, kind: .task, title: task.displayTitle,
                                         durationDays: max(days, 1),
                                         startEpoch: start.timeIntervalSince1970)
        }
    }

    /// Event badges for one week. Extracted from the month-grid body so EventBar's
    /// initializer doesn't inflate that deeply-nested week expression past the
    /// Swift type-checker's budget. Schedule actions are gated per-task on
    /// calendar.edit by `scheduleQuickActions(for:)`.
    @ViewBuilder
    private func eventBars(_ weekSpans: [WeekEventSpan], dates: [Date?], dayWidth: CGFloat) -> some View {
        ForEach(weekSpans) { span in
            EventBar(
                span: span,
                cellHeight: cellHeight,
                dayWidth: dayWidth,
                onTap: {
                    // Forward to the day cell so the day sheet still opens when
                    // users tap a badge — preserves the previous "badge is
                    // non-interactive" behavior.
                    if let tapDate = dayDateForSpan(span, dates: dates) {
                        sheetDate = IdentifiableDate(date: tapDate)
                        NotificationCenter.default.post(
                            name: Notification.Name("WizardCalendarMonthDayTapped"),
                            object: nil
                        )
                    }
                },
                quickActions: scheduleQuickActions(for: span),
                onOpenDayDetails: {
                    // Open the day sheet anchored at the event's first day in the
                    // visible week so the user lands on the same place as a normal
                    // day-cell tap.
                    if let firstDate = dates[span.startDayIndex] {
                        sheetDate = IdentifiableDate(date: firstDate)
                    }
                }
            )
            .offset(
                x: dayWidth * CGFloat(span.startDayIndex),
                y: OPSStyle.Layout.monthGridDayHeaderHeight + (CGFloat(span.row) * eventRowHeight)
            )
            .reschedulable(dragPayload(for: span), session: dragSession)
        }
    }

    /// Push (or pull) a task by N days using the existing scheduling engine
    /// and the single-source-of-truth update path on DataController. Triggers
    /// medium haptic on intent, success haptic when the update commits.
    private func pushTaskByDays(eventId: String, days: Int) {
        // Schedule mutations are gated on calendar.edit, scope-aware: own-scope
        // users may push only their own tasks. Crew / Unassigned (no grant) get
        // no push/pull surface — bail before any state change.
        guard let task = dataController.getTask(id: eventId) else { return }
        guard task.canEditSchedule else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // A week-sized push ("Push 1 week") is a calendar-week move: exactly +7
        // on the same weekday, never weekend-normalized — identical to every
        // other surface. Sub-week day nudges honor the company weekend-skip.
        let result = (days != 0 && days % 7 == 0)
            ? SchedulingEngine.pushByCalendarWeeks(task: task, weeks: days / 7)
            : SchedulingEngine.pushByDays(task: task, days: days, skipWeekends: dataController.currentCompanySkipsWeekends)
        Task { @MainActor in
            do {
                try await dataController.updateTaskSchedule(
                    task: task,
                    startDate: result.newStart,
                    endDate: result.newEnd
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                ToastCenter.shared.present(Feedback.Task.scheduledFor(start: result.newStart, end: result.newEnd))
            } catch {
                presentScheduleFailure()
            }
        }
    }

    private func extendTaskByDays(eventId: String, days: Int) {
        guard let task = dataController.getTask(id: eventId), task.canEditSchedule,
              let start = task.startDate,
              let end = task.endDate,
              let newEnd = Calendar.current.date(byAdding: .day, value: days, to: end) else {
            return
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { @MainActor in
            do {
                try await dataController.updateTaskSchedule(
                    task: task,
                    startDate: start,
                    endDate: newEnd
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                ToastCenter.shared.present(Feedback.Task.scheduledFor(start: start, end: newEnd))
            } catch {
                presentScheduleFailure()
            }
        }
    }

    private func prepareCascade(eventId: String, days: Int) {
        guard let task = dataController.getTask(id: eventId), task.canEditSchedule,
              let plan = dataController.planCascade(for: task, byDays: days) else {
            return
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if showCascadePreviewPref && !plan.cascade.changes.isEmpty {
            pendingCascadePlan = plan
            pendingCascadeTask = task
            pendingCascadeDays = days
            showingCascadePreview = true
        } else {
            commitCascade(task: task, plan: plan, days: days)
        }
    }

    private func commitCascade(task: ProjectTask, plan: DataController.CascadePlan, days: Int) {
        Task { @MainActor in
            guard task.canEditSchedule else {
                presentScheduleFailure()
                return
            }
            do {
                try await dataController.pushTaskWithCascade(task, byDays: days)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                ToastCenter.shared.present(
                    Feedback.Task.scheduledFor(start: plan.pushedNewStart, end: plan.pushedNewEnd)
                )
            } catch {
                presentScheduleFailure()
            }
        }
    }

    private func presentScheduleFailure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        ToastCenter.shared.present(Toast(label: Feedback.Err.operationFailed, tone: .error))
    }

    private var eventRowHeight: CGFloat { OPSStyle.Layout.touchTargetMin }

    private func weekSpansForWeek(dates: [Date?], weekIndex: Int) -> ([WeekEventSpan], [MoreEventsIndicator]) {
        let calendar = Calendar.current
        var eventsByDay: [[ScheduledTaskPreview]] = Array(repeating: [], count: 7)

        for (dayIndex, date) in dates.enumerated() {
            guard let date = date else { continue }
            var dayEvents = cache.events(for: date)

            dayEvents.sort { event1, event2 in
                if event1.isMultiDay != event2.isMultiDay {
                    return event1.isMultiDay
                }
                return event1.startDate < event2.startDate
            }

            eventsByDay[dayIndex] = dayEvents
        }

        var seenEventIds = Set<String>()
        var orderedEvents: [ScheduledTaskPreview] = []
        var plannerCandidates: [MonthGridEventSlotPlanner.Candidate] = []

        for dayIndex in 0..<7 {
            for event in eventsByDay[dayIndex] {
                guard seenEventIds.insert(event.eventId).inserted else { continue }

                var weekStartIndex = -1
                var weekEndIndex = -1

                for (checkDayIndex, checkDate) in dates.enumerated() {
                    guard let checkDate = checkDate else { continue }
                    if calendar.isDate(checkDate, inSameDayAs: event.startDate) ||
                       (checkDate >= event.startDate && checkDate <= event.endDate) {
                        if weekStartIndex == -1 {
                            weekStartIndex = checkDayIndex
                        }
                        weekEndIndex = checkDayIndex
                    }
                }

                guard weekStartIndex >= 0 && weekEndIndex >= 0 else { continue }
                orderedEvents.append(event)
                plannerCandidates.append(.init(
                    id: event.eventId,
                    startDayIndex: weekStartIndex,
                    endDayIndex: weekEndIndex
                ))
            }
        }

        let plan = MonthGridEventSlotPlanner.plan(
            candidates: plannerCandidates,
            eventIdsByDay: eventsByDay.map { $0.map(\.eventId) },
            cellHeight: cellHeight
        )

        let candidateById = Dictionary(uniqueKeysWithValues: plannerCandidates.map { ($0.id, $0) })
        let spans = orderedEvents.compactMap { event -> WeekEventSpan? in
            guard let candidate = candidateById[event.eventId],
                  let assignedRow = plan.rowByEventId[event.eventId],
                  let firstDate = dates[candidate.startDayIndex],
                  let lastDate = dates[candidate.endDayIndex] else {
                return nil
            }

            return WeekEventSpan(
                id: "\(event.eventId)-\(weekIndex)",
                eventId: event.eventId,
                title: event.title,
                color: event.color,
                startDate: event.startDate,
                endDate: event.endDate,
                startDayIndex: candidate.startDayIndex,
                endDayIndex: candidate.endDayIndex,
                row: assignedRow,
                isFirstSegment: calendar.isDate(firstDate, inSameDayAs: event.startDate),
                isLastSegment: calendar.isDate(lastDate, inSameDayAs: event.endDate),
                isSingleDay: !event.isMultiDay,
                taskTypeDisplay: event.taskTypeDisplay
            )
        }

        let indicators: [MoreEventsIndicator] = plan.hiddenEventIdsByDay.enumerated().compactMap { entry in
            let (dayIndex, hiddenIds) = entry
            guard !hiddenIds.isEmpty else { return nil }
            return MoreEventsIndicator(
                dayIndex: dayIndex,
                count: hiddenIds.count,
                row: plan.indicatorRow
            )
        }

        return (spans, indicators)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // Sticky header: Month/Year + Weekday labels
                VStack(spacing: 0) {
                    // Month and Year with jump-to-month picker
                    HStack {
                        Text(monthYearString(from: viewModel.visibleMonth))
                            .font(OPSStyle.Typography.subtitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .id(viewModel.visibleMonth)
                            .transition(.asymmetric(
                                insertion: .move(edge: scrollDirection == .down ? .bottom : .top).combined(with: .opacity),
                                removal: .move(edge: scrollDirection == .down ? .top : .bottom).combined(with: .opacity)
                            ))

                        Spacer()

                        // Jump-to-month button
                        Button {
                            showMonthPicker = true
                        } label: {
                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                Text("JUMP TO")
                                    .font(OPSStyle.Typography.microLabel)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .nestedCard()
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing1)
                    .padding(.bottom, 6)

                    // Separator line
                    Rectangle()
                        .fill(OPSStyle.Colors.secondaryText.opacity(0.3))
                        .frame(height: 0.5)
                        .padding(.horizontal, OPSStyle.Layout.spacing1)

                    // Weekday labels
                    HStack(spacing: 0) {
                        ForEach(weekdayLabels, id: \.self) { label in
                            Text(label)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 6)
                }
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .clipped()
                .background(OPSStyle.Colors.background)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ForEach(Array(monthsToDisplay.enumerated()), id: \.offset) { monthIndex, monthStart in
                            let calendar = Calendar.current
                            let dates = datesForMonth(monthStart)
                            let monthComponent = calendar.component(.month, from: monthStart)

                            VStack(spacing: 0) {
                                HStack {
                                    Text(monthYearString(from: monthStart))
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                        .padding(.leading, OPSStyle.Layout.spacing1)
                                        .padding(.top, monthIndex == 0 ? 0 : 16)
                                        .padding(.bottom, OPSStyle.Layout.spacing2)
                                    Spacer()
                                }

                                ForEach(0..<(dates.count / 7), id: \.self) { weekIndex in
                                    let weekDates = Array(dates[(weekIndex * 7)..<min((weekIndex + 1) * 7, dates.count)])
                                    let (weekSpans, moreIndicators) = weekSpansForWeek(dates: weekDates, weekIndex: weekIndex)

                                    VStack(spacing: 0) {
                                        Rectangle()
                                            .fill(OPSStyle.Colors.secondaryText.opacity(0.2))
                                            .frame(height: 0.5)

                                        GeometryReader { geo in
                                            let dayWidth = geo.size.width / 7

                                            ZStack(alignment: .topLeading) {
                                                HStack(spacing: 0) {
                                                    ForEach(0..<7, id: \.self) { dayIndex in
                                                        let index = weekIndex * 7 + dayIndex
                                                        if let date = dates[index] {
                                                            MonthDayCell(
                                                                date: date,
                                                                currentMonth: monthComponent,
                                                                viewModel: viewModel,
                                                                cache: cache,
                                                                cellHeight: cellHeight,
                                                                onTap: {
                                                                    sheetDate = IdentifiableDate(date: date)
                                                                    NotificationCenter.default.post(name: Notification.Name("WizardCalendarMonthDayTapped"), object: nil)
                                                                }
                                                            )
                                                            .wizardTarget("tap_month_day")
                                                            .reschedulableDropTarget(day: date)
                                                        } else {
                                                            Color.clear
                                                                .frame(maxWidth: .infinity)
                                                                .frame(height: cellHeight)
                                                        }
                                                    }
                                                }

                                                // Badges sit above the day cells; during a drag they must
                                                // stand aside so drops always reach the MonthDayCell drop
                                                // targets beneath. Gated on `isDragInFlight`, not on
                                                // `active` (bug 4baf3104): `active` used to be cleared
                                                // mid-drag by the drag preview's teardown, which handed
                                                // the badges their hit-testing back and let them swallow
                                                // the drop — the drag then did nothing at all.
                                                eventBars(weekSpans, dates: dates, dayWidth: dayWidth)
                                                    .allowsHitTesting(!dragSession.isDragInFlight)

                                                ForEach(moreIndicators) { indicator in
                                                    MoreEventsIndicatorView(indicator: indicator, cellHeight: cellHeight, dayWidth: dayWidth)
                                                        .offset(
                                                            x: dayWidth * CGFloat(indicator.dayIndex),
                                                            y: OPSStyle.Layout.monthGridDayHeaderHeight + (CGFloat(indicator.row) * eventRowHeight)
                                                        )
                                                        .allowsHitTesting(false)
                                                }
                                            }
                                        }
                                        .frame(height: cellHeight)
                                    }
                                    .padding(.horizontal, OPSStyle.Layout.spacing1)
                                    .background(
                                        GeometryReader { geo in
                                            let offset = geo.frame(in: .named("scroll")).minY
                                            Color.clear
                                                .preference(key: ScrollOffsetPreferenceKey.self, value: offset)
                                                .onChange(of: offset) { _, newOffset in
                                                    if weekIndex == 0 {
                                                        updateVisibleMonth(for: monthStart, offset: newOffset)
                                                    }
                                                }
                                                .onAppear {
                                                    if weekIndex == 0 {
                                                        updateVisibleMonth(for: monthStart, offset: offset)
                                                    }
                                                }
                                        }
                                    )
                                }
                            }
                            .id(monthStart)
                        }
                    }
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    // Track initial scroll offset (used by both tutorial and wizard systems)
                    if initialScrollOffset == nil {
                        initialScrollOffset = value
                    }

                    // Detect user scroll — significant movement from initial position
                    if !hasNotifiedTutorialScroll && !isProgrammaticScroll {
                        if let initial = initialScrollOffset, abs(value - initial) > 30 {
                            hasNotifiedTutorialScroll = true
                            NotificationCenter.default.post(
                                name: Notification.Name("CalendarMonthViewScrolled"),
                                object: nil
                            )
                        }
                    }

                    scrollOffset = value
                }
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let newHeight = gestureStartHeight * value
                            cellHeight = min(max(newHeight, minHeight), maxHeight)

                            // Detect pinch (used by both tutorial and wizard systems)
                            if !hasNotifiedTutorialPinch && abs(value - 1.0) > 0.1 {
                                hasNotifiedTutorialPinch = true
                                NotificationCenter.default.post(
                                    name: Notification.Name("CalendarMonthViewPinched"),
                                    object: nil
                                )
                            }
                        }
                        .onEnded { _ in
                            gestureStartHeight = cellHeight
                        }
                )
            }
            .onAppear {
                if let dataController = viewModel.dataController {
                    cache.loadEvents(from: dataController, viewModel: viewModel, tutorialMode: tutorialMode)
                }

                if !hasScrolledToCurrentMonth {
                    let calendar = Calendar.current
                    let today = Date()
                    if let currentMonth = calendar.dateInterval(of: .month, for: today)?.start {
                        viewModel.visibleMonth = currentMonth
                        if !calendar.isDate(viewModel.selectedDate, equalTo: today, toGranularity: .day) {
                            viewModel.selectDate(today, userInitiated: false)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(currentMonth, anchor: .top)
                            hasScrolledToCurrentMonth = true
                        }
                    }
                }
            }
            // Scroll to month when changed from picker (not from user scrolling)
            .onChange(of: viewModel.visibleMonth) { oldMonth, newMonth in
                let calendar = Calendar.current
                // Only scroll if this wasn't triggered by user scrolling
                if let lastScroll = lastScrollTriggeredMonth,
                   calendar.isDate(lastScroll, equalTo: newMonth, toGranularity: .month) {
                    // This change came from scrolling, don't scroll programmatically
                    return
                }
                // This change came from the picker, scroll to the month
                isProgrammaticScroll = true
                withAnimation(OPSStyle.Animation.standard) {
                    proxy.scrollTo(newMonth, anchor: .top)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isProgrammaticScroll = false
                }
            }
            .onChange(of: viewModel.selectedTeamMemberIds) { _, _ in
                if let dataController = viewModel.dataController {
                    cache.loadEvents(from: dataController, viewModel: viewModel, tutorialMode: tutorialMode)
                }
            }
            .onChange(of: viewModel.selectedTaskTypeIds) { _, _ in
                if let dataController = viewModel.dataController {
                    cache.loadEvents(from: dataController, viewModel: viewModel, tutorialMode: tutorialMode)
                }
            }
            .onChange(of: viewModel.selectedClientIds) { _, _ in
                if let dataController = viewModel.dataController {
                    cache.loadEvents(from: dataController, viewModel: viewModel, tutorialMode: tutorialMode)
                }
            }
            .onChange(of: dataController.scheduledTasksDidChange) { _, _ in
                if let dataController = viewModel.dataController {
                    cache.loadEvents(from: dataController, viewModel: viewModel, tutorialMode: tutorialMode)
                }
            }
            // Bug 1 — Reload month grid when user events (time off / personal)
            // are added, edited, deleted, or synced from the server.
            .onChange(of: viewModel.userEventsForCurrentPeriod.count) { _, _ in
                if let dataController = viewModel.dataController {
                    cache.loadEvents(from: dataController, viewModel: viewModel, tutorialMode: tutorialMode)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CalendarUserEventsDidChange"))) { _ in
                guard isActiveTab else {
                    needsUserEventsReload = true
                    return
                }
                reloadUserEvents()
            }
            .onChange(of: isActiveTab) { _, active in
                guard active, needsUserEventsReload else { return }
                needsUserEventsReload = false
                reloadUserEvents()
            }
            .sheet(item: $sheetDate) { identifiableDate in
                DayDetailsSheet(date: identifiableDate.date, viewModel: viewModel)
                    .opsSheet(detents: [.medium, .large])
            }
            .sheet(isPresented: $showMonthPicker) {
                MonthJumpPicker(selectedMonth: viewModel.visibleMonth) { monthStart in
                    viewModel.visibleMonth = monthStart
                    viewModel.selectDate(monthStart, userInitiated: true)
                }
                .opsSheet(detents: [.medium])
            }
            // Long-press → "Pick new date…" opens the same scheduler used
            // elsewhere in the app for full control over start/end (Bug
            // 70591eb5).
            .sheet(item: $rescheduleTarget) { target in
                MonthGridReschedulePresenter(task: target.task) { newStart, newEnd in
                    Task { @MainActor in
                        guard target.task.canEditSchedule else {
                            presentScheduleFailure()
                            return
                        }
                        do {
                            try await dataController.updateTaskSchedule(
                                task: target.task,
                                startDate: newStart,
                                endDate: newEnd
                            )
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            ToastCenter.shared.present(Feedback.Task.scheduledFor(start: newStart, end: newEnd))
                        } catch {
                            presentScheduleFailure()
                        }
                    }
                } onDismiss: {
                    rescheduleTarget = nil
                }
                .environmentObject(dataController)
            }
            .sheet(isPresented: $showingCascadePreview) {
                if let plan = pendingCascadePlan, let task = pendingCascadeTask {
                    CascadePreviewSheet(
                        pushedTaskName: task.displayTitle,
                        pushedTaskOldStart: task.startDate,
                        pushedTaskNewStart: plan.pushedNewStart,
                        pushedTaskNewEnd: plan.pushedNewEnd,
                        cascadeChanges: plan.cascade.changes,
                        onConfirm: {
                            commitCascade(task: task, plan: plan, days: pendingCascadeDays)
                        },
                        onCancel: { }
                    )
                    .environmentObject(dataController)
                    .presentationDetents([.medium])
                }
            }
        }
    }
}

struct MonthDayCell: View {
    let date: Date
    let currentMonth: Int
    @ObservedObject var viewModel: CalendarViewModel
    @ObservedObject var cache: MonthGridCache
    let cellHeight: CGFloat
    let onTap: () -> Void

    private var isSelected: Bool {
        DateHelper.isSameDay(date, viewModel.selectedDate)
    }

    private var isToday: Bool {
        DateHelper.isToday(date)
    }

    /// Bug 23ecb01a — a statutory holiday is a fact about the day, so it
    /// colours the date itself rather than taking one of the four event-bar
    /// rows away from real work. The day sheet names it.
    private var isHoliday: Bool {
        StatutoryHolidays.holiday(on: date) != nil
    }

    private var textColor: Color {
        if isToday {
            // Today's date is black on white circle
            return .black
        } else if isHoliday {
            return OPSStyle.Colors.tanTextM
        } else if isSelected {
            return OPSStyle.Colors.primaryText
        } else {
            return OPSStyle.Colors.primaryText.opacity(0.8)
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            if isToday {
                // Today's date with white circle background
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.primaryText)
                        .frame(width: 24, height: 24)

                    Text(DateHelper.dayString(from: date))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.invertedText)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, OPSStyle.Layout.spacing1)
            } else {
                Text(DateHelper.dayString(from: date))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(textColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, OPSStyle.Layout.spacing1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight, alignment: .top)
        .contentShape(Rectangle())
        .background(isToday ? OPSStyle.Colors.primaryAccent.opacity(0.5) : Color.clear)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(isSelected ? OPSStyle.Colors.primaryText : Color.clear, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .onTapGesture {
            onTap()
        }
    }
}

struct EventBadge: View {
    let event: ScheduledTaskPreview
    let cellHeight: CGFloat

    private var badgeHeight: CGFloat? {
        if cellHeight <= 80 {
            return 8
        } else if cellHeight > 250 {
            return nil
        } else if cellHeight > 150 {
            return 18
        } else {
            return 14
        }
    }

    private var fontSize: Font {
        Font.system(size: 11)
    }

    private var showText: Bool {
        cellHeight > 80
    }

    private var badgeOpacity: Double {
        // Bug 4: lower-opacity fill (~0.25) at all zoom levels
        if cellHeight <= 80 {
            return 0.25
        } else {
            return 0.18
        }
    }

    private var allowTextWrap: Bool {
        cellHeight > 250
    }

    private var topLeftRadius: CGFloat {
        event.isFirst ? 3 : 0
    }

    private var bottomLeftRadius: CGFloat {
        event.isFirst ? 3 : 0
    }

    private var topRightRadius: CGFloat {
        event.isLast ? 3 : 0
    }

    private var bottomRightRadius: CGFloat {
        event.isLast ? 3 : 0
    }

    private var horizontalPadding: EdgeInsets {
        if event.isMultiDay {
            if event.isFirst && event.isLast {
                return EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)
            } else if event.isFirst {
                return EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 0)
            } else if event.isLast {
                return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 2)
            } else {
                return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            }
        }
        return EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)
    }

    // Badge shape helper
    private func badgeShape() -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topLeftRadius,
            bottomLeadingRadius: bottomLeftRadius,
            bottomTrailingRadius: bottomRightRadius,
            topTrailingRadius: topRightRadius
        )
    }

    var body: some View {
        let badgeColor = Color(hex: event.color) ?? OPSStyle.Colors.primaryAccent

        // Bug 4: fixed vertical padding of 1pt around each badge for breathing room
        Group {
            if let height = badgeHeight {
                badgeColor.opacity(badgeOpacity)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipShape(badgeShape())
                    // Bug 4: stroke border at same color, 30% opacity
                    .overlay(
                        badgeShape()
                            .stroke(badgeColor.opacity(0.30), lineWidth: 0.5)
                    )
                    .padding(horizontalPadding)
                    .overlay(alignment: .leading) {
                        if showText && (!event.isMultiDay || event.isFirst || event.isFirstInWeek) {
                            Text(event.title)
                                .font(fontSize)
                                .foregroundColor(badgeColor)
                                .lineLimit(1)
                                .padding(.horizontal, OPSStyle.Layout.spacing1)
                                .padding(.vertical, 2)
                                .fixedSize(horizontal: event.isMultiDay, vertical: false)
                                .allowsHitTesting(false)
                                .padding(.leading, horizontalPadding.leading)
                        }
                    }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if showText && (!event.isMultiDay || event.isFirst || event.isFirstInWeek) {
                        Text(event.title)
                            .font(fontSize)
                            .foregroundColor(badgeColor)
                            .lineLimit(allowTextWrap ? nil : 1)
                            .padding(.horizontal, OPSStyle.Layout.spacing1)
                            .padding(.vertical, 2)
                            .fixedSize(horizontal: event.isMultiDay, vertical: false)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    badgeColor.opacity(badgeOpacity)
                        .clipShape(badgeShape())
                )
                .overlay(
                    badgeShape()
                        .stroke(badgeColor.opacity(0.30), lineWidth: 0.5)
                )
                .padding(horizontalPadding)
            }
        }
        // Bug 4: vertical padding around each badge
        .padding(.vertical, 1)
    }
}

struct EventBar: View {
    let span: WeekEventSpan
    let cellHeight: CGFloat
    let dayWidth: CGFloat

    // Optional handlers keep preview / tutorial callers working without
    // behavior changes. Editable task spans receive the shared quick-action
    // contract used by every other calendar surface.
    var onTap: (() -> Void)? = nil
    var quickActions: ScheduleCardQuickActions? = nil
    var onOpenDayDetails: (() -> Void)? = nil

    private enum DisplayLevel {
        case level1  // < 120: compact dots
        case level2  // 120-180: short bars with title
        case level3  // >= 180: short (multi-day) or tall (single-day) bars
    }

    private var displayLevel: DisplayLevel {
        if cellHeight < OPSStyle.Layout.monthGridStandardHeightThreshold {
            return .level1
        } else if cellHeight < OPSStyle.Layout.monthGridExpandedHeightThreshold {
            return .level2
        } else {
            return .level3
        }
    }

    // At Level 3, single-day events are tall (3x height)
    private var isTallEvent: Bool {
        displayLevel == .level3 && span.isSingleDay
    }

    // Base slot height (unit height for positioning)
    private var baseSlotHeight: CGFloat {
        displayLevel == .level1
            ? OPSStyle.Layout.monthGridCompactBadgeHeight
            : OPSStyle.Layout.monthGridStandardBadgeHeight
    }

    // Actual bar height: tall events are 3x base height
    private var barHeight: CGFloat {
        if isTallEvent {
            return baseSlotHeight * 3  // 42pt for tall single-day events
        }
        return baseSlotHeight
    }

    private var badgeOpacity: Double {
        displayLevel == .level1 ? 0.5 : 0.2
    }

    private var showText: Bool {
        displayLevel != .level1
    }

    private var eventColor: Color {
        Color(hex: span.color) ?? OPSStyle.Colors.primaryAccent
    }

    private var scheduleAccessibilityLabel: String {
        "\(span.title), \(span.startDate.formatted(date: .abbreviated, time: .omitted)) to \(span.endDate.formatted(date: .abbreviated, time: .omitted))"
    }

    private var scheduleAccessibilityHint: String {
        quickActions == nil
            ? "Tap for day details."
            : "Tap for day details. Hold for schedule actions."
    }

    var body: some View {
        Group {
            if isTallEvent {
                tallEventContent
            } else {
                shortEventContent
            }
        }
        .frame(width: dayWidth * CGFloat(span.endDayIndex - span.startDayIndex + 1))
        .frame(height: barHeight)
        .clipped()
        .background(eventBackground)
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        // Keep the compact month-grid visual while giving every badge its own
        // non-overlapping, field-usable interaction row.
        .frame(height: OPSStyle.Layout.touchTargetMin, alignment: .top)
        // Bug 70591eb5: tap forwards to the day sheet (preserving the
        // previous "badge is non-interactive" behaviour) and long-press
        // exposes quick reschedule actions via the system context menu.
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .contextMenu {
            if quickActions != nil || onOpenDayDetails != nil {
                if let quickActions {
                    ScheduleQuickActionMenu(actions: quickActions, includesPullBack: true)
                }
                if let openDayDetails = onOpenDayDetails {
                    Button {
                        openDayDetails()
                    } label: {
                        Label("View details", systemImage: OPSStyle.Icons.info)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(scheduleAccessibilityLabel)
        .accessibilityHint(scheduleAccessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    // Short event: single line title (Level 1, 2, and multi-day at Level 3)
    private var shortEventContent: some View {
        HStack(alignment: .center, spacing: 0) {
            if showText && (span.isSingleDay || span.isFirstSegment) {
                Text(span.title)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(eventColor)
                    .lineLimit(1)
                    .padding(.horizontal, OPSStyle.Layout.spacing1)
                    .padding(.vertical, 2)
            }
            Spacer(minLength: 0)
        }
    }

    // Tall event: 2 lines title + 1 line task type (single-day at Level 3)
    private var tallEventContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title: 2 lines max, fixed to top two rows
            if span.isFirstSegment || span.isSingleDay {
                Text(span.title)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(eventColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, OPSStyle.Layout.spacing1)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)

            // Task type subtitle: always on 3rd row (bottom)
            if let taskType = span.taskTypeDisplay, !taskType.isEmpty {
                Text(taskType.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
                    .padding(.horizontal, OPSStyle.Layout.spacing1)
                    .padding(.bottom, 2)
            }
        }
    }

    private var eventBackground: some View {
        eventColor.opacity(badgeOpacity)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: span.isSingleDay || span.isFirstSegment ? 3 : 0,
                bottomLeadingRadius: span.isSingleDay || span.isFirstSegment ? 3 : 0,
                bottomTrailingRadius: span.isSingleDay || span.isLastSegment ? 3 : 0,
                topTrailingRadius: span.isSingleDay || span.isLastSegment ? 3 : 0
            ))
    }
}

struct MoreEventsIndicatorView: View {
    let indicator: MoreEventsIndicator
    let cellHeight: CGFloat
    let dayWidth: CGFloat

    private var badgeHeight: CGFloat {
        if cellHeight < OPSStyle.Layout.monthGridStandardHeightThreshold {
            return OPSStyle.Layout.monthGridCompactBadgeHeight
        } else {
            return OPSStyle.Layout.monthGridStandardBadgeHeight
        }
    }

    private var fontSize: Font {
        Font.system(size: 10)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("+ \(indicator.count)")
                .font(fontSize)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .lineLimit(1)
                .padding(.horizontal, OPSStyle.Layout.spacing1)
                .padding(.vertical, 2)
            Spacer(minLength: 0)
        }
        .frame(width: dayWidth, height: badgeHeight)
        .background(OPSStyle.Colors.secondaryText.opacity(0.1))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal, 2)
    }
}

// MARK: - Reschedule Presenter (Bug 70591eb5)

/// Hosts the existing `CalendarSchedulerSheet` for a single task triggered
/// from the month-grid long-press menu. Wraps the sheet so it can be
/// presented from `.sheet(item:)` while still satisfying the scheduler's
/// `Binding<Bool>` API.
private struct MonthGridReschedulePresenter: View {
    let task: ProjectTask
    let onScheduleUpdate: (Date, Date) -> Void
    let onDismiss: () -> Void

    @State private var isPresented: Bool = true

    var body: some View {
        CalendarSchedulerSheet(
            isPresented: $isPresented,
            itemType: .task(task),
            currentStartDate: task.startDate,
            currentEndDate: task.endDate,
            onScheduleUpdate: { newStart, newEnd in
                onScheduleUpdate(newStart, newEnd)
            }
        )
        .onChange(of: isPresented) { _, newValue in
            if !newValue {
                onDismiss()
            }
        }
    }
}

struct DayDetailsSheet: View {
    let date: Date
    @ObservedObject var viewModel: CalendarViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var appState: AppState
    @State private var rescheduleTask: ProjectTask?
    @State private var showingCascadePreview = false
    @State private var pendingCascadePlan: DataController.CascadePlan?
    @State private var pendingCascadeTask: ProjectTask?
    @State private var pendingCascadeDays = 0
    @AppStorage("showCascadePreview") private var showCascadePreviewPref = true

    private var scheduledTasks: [ProjectTask] {
        // Resolve from the calendar's source of truth — the same path day/week
        // view uses — not the month grid's derived cache. That cache is built
        // asynchronously and only rebuilt on a handful of triggers, so it can be
        // empty or stale the moment the sheet reads it, which surfaced as "the day
        // sheet is not picking up any events in month view" while day view worked.
        // scheduledTasks(for:) is scope- and filter-aware and always current, so
        // the month day sheet now matches day view exactly.
        viewModel.scheduledTasks(for: date)
    }

    /// User-owned events overlapping this date (Bug 1 — surface time-off /
    /// personal events in the month-grid day sheet).
    private var dayUserEvents: [CalendarUserEvent] {
        viewModel.userEvents(for: date)
    }

    /// Booked site visits on this date — the calendar's third source.
    private var dayBookedVisits: [SiteVisit] {
        viewModel.bookedVisits(for: date)
    }

    /// Statutory holiday falling on this date, computed on device. Bug 23ecb01a.
    private var dayHoliday: StatutoryHoliday? {
        StatutoryHolidays.holiday(on: date)
    }

    private var totalEventCount: Int {
        scheduledTasks.count + dayUserEvents.count + dayBookedVisits.count
    }

    /// A booking is always lead-attached; the name is the card's identity.
    private func visitLead(_ visit: SiteVisit) -> Opportunity? {
        guard let context = dataController.modelContext,
              let opportunityId = visit.opportunityId else { return nil }
        let lower = opportunityId.lowercased()
        var descriptor = FetchDescriptor<Opportunity>(
            predicate: #Predicate { $0.id == lower }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // Separate new and ongoing tasks (matching week view)
    private var newTasks: [ProjectTask] {
        scheduledTasks.filter { task in
            Calendar.current.isDate(task.startDate ?? Date(), inSameDayAs: date)
        }
    }

    private var ongoingTasks: [ProjectTask] {
        scheduledTasks.filter { task in
            let startDate = task.startDate ?? Date()
            return !Calendar.current.isDate(startDate, inSameDayAs: date)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                Text(date.formatted(date: .complete, time: .omitted))
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal)
                    .padding(.top, OPSStyle.Layout.spacing2)

                Text("\(totalEventCount) event\(totalEventCount == 1 ? "" : "s")")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.horizontal)

                // A statutory holiday frames the day, so it leads — and stays
                // on an empty day, which is the day it most needs explaining.
                // Bug 23ecb01a.
                if let holiday = dayHoliday {
                    CalendarHolidayCard(holiday: holiday)
                }

                if scheduledTasks.isEmpty && dayUserEvents.isEmpty && dayBookedVisits.isEmpty {
                    VStack(spacing: OPSStyle.Layout.spacing2_5) {
                        Image(systemName: OPSStyle.Icons.calendar)
                            .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Text("No events on this day")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    // New tasks section (matching week view template)
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(Array(newTasks.enumerated()), id: \.element.id) { index, task in
                            CalendarEventCard(
                                task: task,
                                isFirst: index == 0,
                                isOngoing: false,
                                hostQuickActions: quickActions(for: task),
                                onTap: {
                                    handleTaskTap(task)
                                }
                            )
                            .wizardTarget("tap_task")
                            .padding(.horizontal)
                        }
                    }

                    // Ongoing section divider and tasks (matching week view template)
                    if !ongoingTasks.isEmpty {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Text("ONGOING")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            Rectangle()
                                .fill(OPSStyle.Colors.tertiaryText.opacity(0.3))
                                .frame(height: 1)

                            Text("[\(ongoingTasks.count)]")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .padding(.horizontal, OPSStyle.Layout.spacing4)

                        VStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(Array(ongoingTasks.enumerated()), id: \.element.id) { index, task in
                                CalendarEventCard(
                                    task: task,
                                    isFirst: false,
                                    isOngoing: true,
                                    hostQuickActions: quickActions(for: task),
                                    onTap: {
                                        handleTaskTap(task)
                                    }
                                )
                                .wizardTarget("tap_task")
                                .padding(.horizontal)
                            }
                        }
                    }
                }

                // Booked site visits — appointments, not tasks. Month view is
                // for scanning, so tap opens the lead (the full start /
                // reschedule branch lives on the day canvas and lead surfaces).
                if !dayBookedVisits.isEmpty {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text("SITE VISITS")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Rectangle()
                            .fill(OPSStyle.Colors.tertiaryText.opacity(0.3))
                            .frame(height: 1)

                        Text("[\(dayBookedVisits.count)]")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)

                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(dayBookedVisits, id: \.id) { visit in
                            if let scheduledAt = visit.scheduledAt {
                                CalendarSiteVisitCard(
                                    leadName: visitLead(visit)?.displayContactName ?? "Site visit",
                                    address: visitLead(visit)?.address,
                                    scheduledAt: scheduledAt,
                                    durationMinutes: visit.durationMinutes,
                                    isInProgress: visit.status == .inProgress,
                                    onTap: {
                                        guard let opportunityId = visit.opportunityId else { return }
                                        NotificationCenter.default.post(
                                            name: Notification.Name("OpenLeadDetails"),
                                            object: nil,
                                            userInfo: ["leadId": opportunityId]
                                        )
                                    }
                                )
                            }
                        }
                    }
                }

                // Bug 1 — User events (time off + personal) for this date.
                if !dayUserEvents.isEmpty {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text("PERSONAL")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Rectangle()
                            .fill(OPSStyle.Colors.tertiaryText.opacity(0.3))
                            .frame(height: 1)

                        Text("[\(dayUserEvents.count)]")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)

                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(dayUserEvents) { event in
                            CalendarUserEventCard(
                                event: event,
                                onTap: {},
                                onDelete: {
                                    dataController.deleteRecurringEvent(event, scope: .thisOnly)
                                    viewModel.loadUserEvents()
                                }
                            )
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        // Wizard: scroll to the active target when a new step activates
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardScrollToTarget"))) { notification in
            if let stepId = notification.userInfo?["stepId"] as? String {
                withAnimation(OPSStyle.Animation.standard) {
                    proxy.scrollTo("wizard_active_\(stepId)", anchor: .top)
                }
            }
        }
        } // ScrollViewReader
        .background(OPSStyle.Colors.background)
        .presentationDetents([.fraction(0.3), .fraction(0.7), .large])
        .sheet(item: $rescheduleTask) { task in
            CalendarSchedulerSheet(
                isPresented: Binding(
                    get: { rescheduleTask != nil },
                    set: { if !$0 { rescheduleTask = nil } }
                ),
                itemType: .task(task),
                currentStartDate: task.startDate,
                currentEndDate: task.endDate,
                onScheduleUpdate: { newStart, newEnd in
                    updateTaskSchedule(task, startDate: newStart, endDate: newEnd)
                }
            )
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showingCascadePreview) {
            if let plan = pendingCascadePlan, let task = pendingCascadeTask {
                CascadePreviewSheet(
                    pushedTaskName: task.displayTitle,
                    pushedTaskOldStart: task.startDate,
                    pushedTaskNewStart: plan.pushedNewStart,
                    pushedTaskNewEnd: plan.pushedNewEnd,
                    cascadeChanges: plan.cascade.changes,
                    onConfirm: {
                        commitCascade(task: task, plan: plan, days: pendingCascadeDays)
                    },
                    onCancel: { }
                )
                .environmentObject(dataController)
                .presentationDetents([.medium])
            }
        }
    }

    private func quickActions(for task: ProjectTask) -> ScheduleCardQuickActions {
        ScheduleCardQuickActions(
            onPush: { pushTask(task, days: $0) },
            onExtend: { extendTask(task, days: $0) },
            onCascade: { prepareCascade(task, days: $0) },
            onReschedule: {
                guard task.canEditSchedule else {
                    presentScheduleFailure()
                    return
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                rescheduleTask = task
            },
            onSelect: nil
        )
    }

    private func pushTask(_ task: ProjectTask, days: Int) {
        guard task.canEditSchedule else { return }
        let preserveCalendarWeek = days != 0 && days % 7 == 0
        let result = preserveCalendarWeek
            ? SchedulingEngine.pushByCalendarWeeks(task: task, weeks: days / 7)
            : SchedulingEngine.pushByDays(
                task: task,
                days: days,
                skipWeekends: dataController.currentCompanySkipsWeekends
            )

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { @MainActor in
            do {
                try await dataController.pushTask(
                    task,
                    byDays: days,
                    preserveCalendarWeeks: preserveCalendarWeek
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                ToastCenter.shared.present(
                    Feedback.Task.scheduledFor(start: result.newStart, end: result.newEnd)
                )
            } catch {
                presentScheduleFailure()
            }
        }
    }

    private func extendTask(_ task: ProjectTask, days: Int) {
        guard task.canEditSchedule,
              let start = task.startDate,
              let end = task.endDate,
              let newEnd = Calendar.current.date(byAdding: .day, value: days, to: end) else {
            return
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { @MainActor in
            do {
                try await dataController.updateTaskSchedule(
                    task: task,
                    startDate: start,
                    endDate: newEnd
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                ToastCenter.shared.present(Feedback.Task.scheduledFor(start: start, end: newEnd))
            } catch {
                presentScheduleFailure()
            }
        }
    }

    private func prepareCascade(_ task: ProjectTask, days: Int) {
        guard task.canEditSchedule,
              let plan = dataController.planCascade(for: task, byDays: days) else {
            return
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if showCascadePreviewPref && !plan.cascade.changes.isEmpty {
            pendingCascadePlan = plan
            pendingCascadeTask = task
            pendingCascadeDays = days
            showingCascadePreview = true
        } else {
            commitCascade(task: task, plan: plan, days: days)
        }
    }

    private func commitCascade(task: ProjectTask, plan: DataController.CascadePlan, days: Int) {
        Task { @MainActor in
            guard task.canEditSchedule else {
                presentScheduleFailure()
                return
            }
            do {
                try await dataController.pushTaskWithCascade(task, byDays: days)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                ToastCenter.shared.present(
                    Feedback.Task.scheduledFor(start: plan.pushedNewStart, end: plan.pushedNewEnd)
                )
            } catch {
                presentScheduleFailure()
            }
        }
    }

    private func updateTaskSchedule(_ task: ProjectTask, startDate: Date, endDate: Date) {
        guard task.canEditSchedule else {
            presentScheduleFailure()
            return
        }
        Task { @MainActor in
            do {
                try await dataController.updateTaskSchedule(
                    task: task,
                    startDate: startDate,
                    endDate: endDate
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                ToastCenter.shared.present(Feedback.Task.scheduledFor(start: startDate, end: endDate))
            } catch {
                presentScheduleFailure()
            }
        }
    }

    private func presentScheduleFailure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        ToastCenter.shared.present(Toast(label: Feedback.Err.operationFailed, tone: .error))
    }

    private func handleTaskTap(_ task: ProjectTask) {
        let userInfo: [String: String] = [
            "taskID": task.id,
            "projectID": task.projectId
        ]

        NotificationCenter.default.post(
            name: Notification.Name("ShowCalendarTaskDetails"),
            object: nil,
            userInfo: userInfo
        )
        NotificationCenter.default.post(name: Notification.Name("WizardCalendarTaskTapped"), object: nil)
        dismiss()
    }
}

struct EventDetailCard: View {
    let task: ProjectTask
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @State private var showingQuickActions = false
    @State private var showingReschedule = false
    @State private var showingDetailView = false
    @State private var isLongPressing = false
    @State private var hasTriggeredHaptic = false
    @State private var isPressed = false
    @State private var showingCascadePreview = false
    @State private var pendingCascadePlan: DataController.CascadePlan?
    @State private var pendingCascadeDays = 0
    @AppStorage("showCascadePreview") private var showCascadePreviewPref = true

    // Reschedule is a schedule mutation — gated on calendar.edit, scope-aware on
    // this task (own-scope → only the user's own tasks). Crew / Unassigned (no
    // grant) get no Reschedule action from the long-press dialog.
    private var canModify: Bool {
        task.canEditSchedule
    }

    private var eventColor: Color {
        Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent
    }

    private var dateRangeText: String {
        if let start = task.startDate, let end = task.endDate {
            return "\(start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))"
        } else {
            return "No dates"
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Rectangle()
                    .fill(eventColor)
                    .frame(width: 4)
                    .cornerRadius(OPSStyle.Layout.smallCornerRadius)

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(task.displayTitle)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    if let project = task.project {
                        Text(project.title)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }

                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: OPSStyle.Icons.calendar)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        Text(dateRangeText)
                            .font(OPSStyle.Typography.smallCaption)
                    }
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(OPSStyle.Layout.spacing2_5)
        .glassSurface()
    }

    var body: some View {
        cardContent
        .contentShape(Rectangle())
        .scaleEffect(isLongPressing ? 0.95 : (isPressed ? 0.98 : 1.0))
        .animation(OPSStyle.Animation.quick, value: isLongPressing)
        .animation(OPSStyle.Animation.quick, value: isPressed)
        .onTapGesture {
            withAnimation(OPSStyle.Animation.hover) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(OPSStyle.Animation.hover) {
                    isPressed = false
                }
                showingDetailView = true
            }
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            showingQuickActions = true
        } onPressingChanged: { pressing in
            if pressing {
                isLongPressing = true
                hasTriggeredHaptic = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if isLongPressing && !hasTriggeredHaptic {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        hasTriggeredHaptic = true
                    }
                }
            } else {
                isLongPressing = false
                hasTriggeredHaptic = false
            }
        }
        .confirmationDialog("Quick Actions", isPresented: $showingQuickActions, titleVisibility: .hidden) {
            if canModify {
                Button("Push 1 day") {
                    pushTask(days: 1)
                }
                Button("Push 3 days") {
                    pushTask(days: 3)
                }
                Button("Push 1 week") {
                    pushTask(days: 7)
                }
                Button("Extend 1 day") {
                    extendTask(days: 1)
                }
                Button("Extend 3 days") {
                    extendTask(days: 3)
                }
                Button("Extend 1 week") {
                    extendTask(days: 7)
                }
                Button("Cascade 1 day") {
                    pushTaskWithCascade(days: 1)
                }
                Button("Cascade 3 days") {
                    pushTaskWithCascade(days: 3)
                }
                Button("Pick new date") {
                    showingReschedule = true
                }
            }

            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingDetailView) {
            if let project = task.project {
                TaskDetailsView(task: task, project: project)
                    .environmentObject(dataController)
                    .environmentObject(appState)
                    .environment(\.modelContext, dataController.modelContext!)
            }
        }
        .sheet(isPresented: $showingReschedule) {
            CalendarSchedulerSheet(
                isPresented: $showingReschedule,
                itemType: .task(task),
                currentStartDate: task.startDate,
                currentEndDate: task.endDate,
                onScheduleUpdate: { newStart, newEnd in
                    updateTaskSchedule(startDate: newStart, endDate: newEnd)
                }
            )
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showingCascadePreview) {
            if let plan = pendingCascadePlan {
                CascadePreviewSheet(
                    pushedTaskName: task.displayTitle,
                    pushedTaskOldStart: task.startDate,
                    pushedTaskNewStart: plan.pushedNewStart,
                    pushedTaskNewEnd: plan.pushedNewEnd,
                    cascadeChanges: plan.cascade.changes,
                    onConfirm: {
                        Task {
                            _ = try? await dataController.pushTaskWithCascade(task, byDays: pendingCascadeDays)
                            await MainActor.run {
                                postScheduleBanner(newDate: plan.pushedNewStart, action: "pushed to")
                            }
                        }
                    },
                    onCancel: { }
                )
                .environmentObject(dataController)
                .presentationDetents([.medium])
            }
        }
    }

    private func updateTaskSchedule(startDate: Date, endDate: Date) {
        Task {
            do {
                try await dataController.updateTaskSchedule(task: task, startDate: startDate, endDate: endDate)
                await MainActor.run {
                    ToastCenter.shared.present(Feedback.Task.scheduledFor(start: startDate, end: endDate))
                }
            } catch {
                print("Error updating task schedule: \(error)")
            }
        }
    }

    private func extendTask(days: Int) {
        guard canModify,
              let start = task.startDate,
              let end = task.endDate,
              let newEnd = Calendar.current.date(byAdding: .day, value: days, to: end) else { return }

        Task {
            do {
                try await dataController.updateTaskSchedule(task: task, startDate: start, endDate: newEnd)
                await MainActor.run {
                    postScheduleBanner(newDate: newEnd, action: "extended to")
                    ToastCenter.shared.present(Feedback.Task.scheduledFor(start: start, end: newEnd))
                }
            } catch {
                await MainActor.run {
                    ToastCenter.shared.present(Toast(label: Feedback.Err.operationFailed, tone: .error))
                }
            }
        }
    }

    private func pushTask(days: Int) {
        guard canModify else { return }
        let preserveCalendarWeek = days != 0 && days % 7 == 0
        let result = preserveCalendarWeek
            ? SchedulingEngine.pushByCalendarWeeks(task: task, weeks: days / 7)
            : SchedulingEngine.pushByDays(task: task, days: days, skipWeekends: dataController.currentCompanySkipsWeekends)

        Task {
            do {
                try await dataController.pushTask(task, byDays: days, preserveCalendarWeeks: preserveCalendarWeek)
                await MainActor.run {
                    postScheduleBanner(newDate: result.newStart, action: "pushed to")
                    ToastCenter.shared.present(Feedback.Task.scheduledFor(start: result.newStart, end: result.newEnd))
                }
            } catch {
                await MainActor.run {
                    ToastCenter.shared.present(Toast(label: Feedback.Err.operationFailed, tone: .error))
                }
            }
        }
    }

    private func pushTaskWithCascade(days: Int) {
        guard canModify, let plan = dataController.planCascade(for: task, byDays: days) else { return }

        if showCascadePreviewPref && !plan.cascade.changes.isEmpty {
            pendingCascadePlan = plan
            pendingCascadeDays = days
            showingCascadePreview = true
        } else {
            Task {
                _ = try? await dataController.pushTaskWithCascade(task, byDays: days)
                await MainActor.run {
                    postScheduleBanner(newDate: plan.pushedNewStart, action: "pushed to")
                }
            }
        }
    }

    private func postScheduleBanner(newDate: Date, action: String) {
        let projectName = task.project?.title ?? task.displayTitle
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let dateStr = formatter.string(from: newDate)

        NotificationCenter.default.post(
            name: Notification.Name("ShowScheduleBanner"),
            object: nil,
            userInfo: [
                "title": "\(projectName) \(action) \(dateStr)"
            ]
        )
    }
}
