//
//  MonthGridView.swift
//  OPS
//
//  Rebuilt from scratch for smooth Apple Calendar-like experience
//

import SwiftUI

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

                // Time off uses amber, personal uses neutral grey so they
                // visually distinguish from project task badges.
                let displayColor = event.isTimeOff
                    ? "#C4A868"  // amber
                    : "#7A7A7A"  // neutral grey

                let label = event.title.isEmpty
                    ? (event.isTimeOff ? "Time Off" : "Personal")
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
                        taskTypeDisplay: event.isTimeOff ? "TIME OFF" : "PERSONAL"
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

    private func eventRowSpacing(for cellHeight: CGFloat) -> CGFloat {
        return 2
    }

    // MARK: - Long-press / context-menu helpers (Bug 70591eb5)

    /// Returns the first visible day of `span` within the supplied `dates`
    /// array. Used to anchor the day sheet when a badge is tapped — matches
    /// the behaviour of tapping the first day cell that the badge covers.
    private func dayDateForSpan(_ span: WeekEventSpan, dates: [Date?]) -> Date? {
        guard span.startDayIndex >= 0, span.startDayIndex < dates.count else { return nil }
        return dates[span.startDayIndex]
    }

    /// Push (or pull) a task by N days using the existing scheduling engine
    /// and the single-source-of-truth update path on DataController. Triggers
    /// medium haptic on intent, success haptic when the update commits.
    private func pushTaskByDays(eventId: String, days: Int) {
        guard let task = dataController.getTask(id: eventId) else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let result = SchedulingEngine.pushByDays(task: task, days: days)
        Task { @MainActor in
            do {
                try await dataController.updateTaskSchedule(
                    task: task,
                    startDate: result.newStart,
                    endDate: result.newEnd
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func eventRowHeight(for cellHeight: CGFloat) -> CGFloat {
        let badgeHeight: CGFloat = cellHeight < 120 ? 10 : 14
        return badgeHeight + eventRowSpacing(for: cellHeight)
    }

    private func maxVisibleSlots(for cellHeight: CGFloat) -> Int {
        let availableHeight = cellHeight - 26
        let rowSpacing = eventRowSpacing(for: cellHeight)

        if cellHeight < 120 {
            // Level 1: base slot height is 10pt
            let slotHeight: CGFloat = 10
            return max(4, Int(availableHeight / (slotHeight + rowSpacing / 2)))
        } else if cellHeight < 180 {
            // Level 2: base slot height is 14pt
            let slotHeight: CGFloat = 14
            return max(4, Int(availableHeight / (slotHeight + rowSpacing / 2)))
        } else {
            // Level 3: base slot height is 14pt (tall events use 3 slots = 42pt)
            let slotHeight: CGFloat = 14
            return max(6, Int(availableHeight / (slotHeight + rowSpacing / 2)))
        }
    }

    private func weekSpansForWeek(dates: [Date?], weekIndex: Int) -> ([WeekEventSpan], [MoreEventsIndicator]) {
        let calendar = Calendar.current
        var spans: [WeekEventSpan] = []
        var indicators: [MoreEventsIndicator] = []
        let maxSlots = maxVisibleSlots(for: cellHeight)
        let isLevel3 = cellHeight >= 180

        var occupiedSlots: [[Bool]] = Array(repeating: Array(repeating: false, count: maxSlots), count: 7)
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

        var processedEvents: Set<String> = []

        for dayIndex in 0..<7 {
            for event in eventsByDay[dayIndex] {
                if processedEvents.contains(event.eventId) {
                    continue
                }

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

                // Determine slots needed: single-day events at Level 3 need 3 slots, others need 1
                let isSingleDay = !event.isMultiDay
                let slotsNeeded = (isLevel3 && isSingleDay) ? 3 : 1

                var assignedSlot = -1
                // Reserve last slot for "+N more" indicator
                for slotIndex in 0..<(maxSlots - 1) {
                    // Check if we have enough consecutive slots available
                    if slotIndex + slotsNeeded > maxSlots - 1 {
                        break  // Not enough room for this event
                    }

                    var slotsAvailable = true
                    for slotOffset in 0..<slotsNeeded {
                        for dayIdx in weekStartIndex...weekEndIndex {
                            if occupiedSlots[dayIdx][slotIndex + slotOffset] {
                                slotsAvailable = false
                                break
                            }
                        }
                        if !slotsAvailable { break }
                    }

                    if slotsAvailable {
                        assignedSlot = slotIndex
                        // Mark all needed slots as occupied
                        for slotOffset in 0..<slotsNeeded {
                            for dayIdx in weekStartIndex...weekEndIndex {
                                occupiedSlots[dayIdx][slotIndex + slotOffset] = true
                            }
                        }
                        break
                    }
                }

                if assignedSlot >= 0 {
                    let isFirstSegment = calendar.isDate(dates[weekStartIndex]!, inSameDayAs: event.startDate)
                    let isLastSegment = calendar.isDate(dates[weekEndIndex]!, inSameDayAs: event.endDate)

                    spans.append(WeekEventSpan(
                        id: "\(event.eventId)-\(weekIndex)",
                        eventId: event.eventId,
                        title: event.title,
                        color: event.color,
                        startDate: event.startDate,
                        endDate: event.endDate,
                        startDayIndex: weekStartIndex,
                        endDayIndex: weekEndIndex,
                        row: assignedSlot,
                        isFirstSegment: isFirstSegment,
                        isLastSegment: isLastSegment,
                        isSingleDay: isSingleDay,
                        taskTypeDisplay: event.taskTypeDisplay
                    ))

                    processedEvents.insert(event.eventId)
                }
            }
        }

        for dayIndex in 0..<7 {
            let hiddenEvents = eventsByDay[dayIndex].filter { !processedEvents.contains($0.eventId) }
            let uniqueHidden = Set(hiddenEvents.map { $0.eventId })

            if uniqueHidden.count > 0 {
                indicators.append(MoreEventsIndicator(
                    dayIndex: dayIndex,
                    count: uniqueHidden.count,
                    row: maxSlots - 1
                ))
            }
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
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.line, lineWidth: 0.5)
                            )
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
                                                        } else {
                                                            Color.clear
                                                                .frame(maxWidth: .infinity)
                                                                .frame(height: cellHeight)
                                                        }
                                                    }
                                                }

                                                ForEach(weekSpans) { span in
                                                    EventBar(
                                                        span: span,
                                                        cellHeight: cellHeight,
                                                        dayWidth: dayWidth,
                                                        onTap: {
                                                            // Forward to the day cell so the day sheet
                                                            // still opens when users tap a badge —
                                                            // preserves the previous "badge is non-
                                                            // interactive" behavior.
                                                            if let tapDate = dayDateForSpan(span, dates: dates) {
                                                                sheetDate = IdentifiableDate(date: tapDate)
                                                                NotificationCenter.default.post(
                                                                    name: Notification.Name("WizardCalendarMonthDayTapped"),
                                                                    object: nil
                                                                )
                                                            }
                                                        },
                                                        onPushDays: { days in
                                                            pushTaskByDays(eventId: span.eventId, days: days)
                                                        },
                                                        onOpenReschedule: {
                                                            if let task = dataController.getTask(id: span.eventId) {
                                                                rescheduleTarget = RescheduleTarget(id: task.id, task: task)
                                                            }
                                                        },
                                                        onOpenDayDetails: {
                                                            // Open the day sheet anchored at the
                                                            // event's first day in the visible week
                                                            // so the user lands on the same place
                                                            // as a normal day-cell tap.
                                                            if let firstDate = dates[span.startDayIndex] {
                                                                sheetDate = IdentifiableDate(date: firstDate)
                                                            }
                                                        }
                                                    )
                                                    .offset(x: dayWidth * CGFloat(span.startDayIndex), y: 26 + (CGFloat(span.row) * eventRowHeight(for: cellHeight)))
                                                }

                                                ForEach(moreIndicators) { indicator in
                                                    MoreEventsIndicatorView(indicator: indicator, cellHeight: cellHeight, dayWidth: dayWidth)
                                                        .offset(x: dayWidth * CGFloat(indicator.dayIndex), y: 26 + (CGFloat(indicator.row) * eventRowHeight(for: cellHeight)))
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
                viewModel.loadUserEvents()
                if let dataController = viewModel.dataController {
                    cache.loadEvents(from: dataController, viewModel: viewModel, tutorialMode: tutorialMode)
                }
            }
            .sheet(item: $sheetDate) { identifiableDate in
                DayDetailsSheet(date: identifiableDate.date, viewModel: viewModel, cache: cache)
                    .opsSheet(detents: [.medium, .large])
            }
            .sheet(isPresented: $showMonthPicker) {
                MonthJumpPicker(viewModel: viewModel)
                    .opsSheet(detents: [.medium])
            }
            // Long-press → "Pick new date…" opens the same scheduler used
            // elsewhere in the app for full control over start/end (Bug
            // 70591eb5).
            .sheet(item: $rescheduleTarget) { target in
                MonthGridReschedulePresenter(task: target.task) { newStart, newEnd in
                    Task { @MainActor in
                        do {
                            try await dataController.updateTaskSchedule(
                                task: target.task,
                                startDate: newStart,
                                endDate: newEnd
                            )
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } catch {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        }
                    }
                } onDismiss: {
                    rescheduleTarget = nil
                }
                .environmentObject(dataController)
            }
        }
    }
}

// MARK: - Month Jump Picker

private struct MonthJumpPicker: View {
    @ObservedObject var viewModel: CalendarViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var displayYear: Int

    private let calendar = Calendar.current
    private let monthNames = Calendar.current.shortMonthSymbols

    init(viewModel: CalendarViewModel) {
        self.viewModel = viewModel
        self._displayYear = State(initialValue: Calendar.current.component(.year, from: viewModel.visibleMonth))
    }

    /// The month (1-12) of the currently visible month in the grid
    private var currentMonth: Int {
        calendar.component(.month, from: viewModel.visibleMonth)
    }

    /// The year of the currently visible month
    private var currentYear: Int {
        calendar.component(.year, from: viewModel.visibleMonth)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("JUMP TO DATE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .tracking(1)

                Spacer()

                Button("DONE") {
                    dismiss()
                }
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, OPSStyle.Layout.spacing4)

            // Year navigation
            HStack {
                Button {
                    withAnimation(OPSStyle.Animation.fast) { displayYear -= 1 }
                } label: {
                    Image(systemName: OPSStyle.Icons.chevronLeft)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }

                Spacer()

                Text(String(displayYear))
                    .font(OPSStyle.Typography.headingBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .contentTransition(.numericText())

                Spacer()

                Button {
                    withAnimation(OPSStyle.Animation.fast) { displayYear += 1 }
                } label: {
                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, OPSStyle.Layout.spacing3_5)

            // Month grid (3x4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2_5), count: 3), spacing: OPSStyle.Layout.spacing2_5) {
                ForEach(1...12, id: \.self) { month in
                    let isSelected = month == currentMonth && displayYear == currentYear
                    let isCurrentMonth = month == calendar.component(.month, from: Date()) && displayYear == calendar.component(.year, from: Date())

                    Button {
                        selectMonth(month)
                    } label: {
                        Text(monthNames[month - 1].uppercased())
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(isSelected ? OPSStyle.Colors.invertedText : OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetMin)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .fill(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBackgroundDark)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(
                                        isCurrentMonth && !isSelected ? OPSStyle.Colors.primaryAccent.opacity(0.5) : OPSStyle.Colors.cardBorder,
                                        lineWidth: OPSStyle.Layout.Border.standard
                                    )
                            )
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            Spacer().frame(height: 24)

            // Today shortcut
            Button {
                let today = Date()
                let todayYear = calendar.component(.year, from: today)
                let todayMonth = calendar.component(.month, from: today)
                displayYear = todayYear
                selectMonth(todayMonth)
            } label: {
                Text("TODAY")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .tracking(1)
                    .padding(.vertical, 10)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(OPSStyle.Colors.cardBackgroundDark)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 0.5)
                    )
            }
            .padding(.bottom, OPSStyle.Layout.spacing3_5)
        }
        .background(OPSStyle.Colors.background)
    }

    private func selectMonth(_ month: Int) {
        var components = DateComponents()
        components.year = displayYear
        components.month = month
        components.day = 1

        guard let date = calendar.date(from: components),
              let monthStart = calendar.dateInterval(of: .month, for: date)?.start else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        viewModel.visibleMonth = monthStart
        viewModel.selectDate(monthStart, userInitiated: true)
        dismiss()
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

    private var textColor: Color {
        if isToday {
            // Today's date is black on white circle
            return .black
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

    // Optional handlers added for Bug 70591eb5 (push / quick reschedule from
    // long-press). Defaults keep backwards-compatible callers (e.g. previews
    // or tutorial mode) working without behaviour change.
    var onTap: (() -> Void)? = nil
    var onPushDays: ((Int) -> Void)? = nil
    var onOpenReschedule: (() -> Void)? = nil
    var onOpenDayDetails: (() -> Void)? = nil

    private enum DisplayLevel {
        case level1  // < 120: compact dots
        case level2  // 120-180: short bars with title
        case level3  // >= 180: short (multi-day) or tall (single-day) bars
    }

    private var displayLevel: DisplayLevel {
        if cellHeight < 120 {
            return .level1
        } else if cellHeight < 180 {
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
        displayLevel == .level1 ? 10 : 14
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
        // Bug 70591eb5: tap forwards to the day sheet (preserving the
        // previous "badge is non-interactive" behaviour) and long-press
        // exposes quick reschedule actions via the system context menu.
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .contextMenu {
            if onPushDays != nil || onOpenReschedule != nil || onOpenDayDetails != nil {
                if let push = onPushDays {
                    Button {
                        push(1)
                    } label: {
                        Label("Push 1 day", systemImage: "arrow.right")
                    }
                    Button {
                        push(3)
                    } label: {
                        Label("Push 3 days", systemImage: "arrow.right.to.line")
                    }
                    Button {
                        push(7)
                    } label: {
                        Label("Push 1 week", systemImage: "calendar.badge.plus")
                    }
                    Button {
                        push(-1)
                    } label: {
                        Label("Pull back 1 day", systemImage: "arrow.left")
                    }
                    Divider()
                }
                if let openReschedule = onOpenReschedule {
                    Button {
                        openReschedule()
                    } label: {
                        Label("Pick new date…", systemImage: "calendar")
                    }
                }
                if let openDayDetails = onOpenDayDetails {
                    Button {
                        openDayDetails()
                    } label: {
                        Label("View details", systemImage: "info.circle")
                    }
                }
            }
        }
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
        if cellHeight < 120 {
            return 10
        } else {
            return 14
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
    @ObservedObject var cache: MonthGridCache
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var appState: AppState

    private var eventPreviews: [ScheduledTaskPreview] {
        cache.events(for: date)
    }

    private var scheduledTasks: [ProjectTask] {
        // User-event entries use a "userevent:" prefix on eventId — skip them
        // here so they don't get resolved against the task store (Bug 1).
        let taskIds = Set(eventPreviews
            .map { $0.eventId }
            .filter { !$0.hasPrefix("userevent:") })
        return taskIds.compactMap { id in
            dataController.getTask(id: id)
        }
    }

    /// User-owned events overlapping this date (Bug 1 — surface time-off /
    /// personal events in the month-grid day sheet).
    private var dayUserEvents: [CalendarUserEvent] {
        viewModel.userEvents(for: date)
    }

    private var totalEventCount: Int {
        scheduledTasks.count + dayUserEvents.count
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

                if scheduledTasks.isEmpty && dayUserEvents.isEmpty {
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
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
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
            Button("Reschedule") {
                showingReschedule = true
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
    }

    private func updateTaskSchedule(startDate: Date, endDate: Date) {
        Task {
            do {
                try await dataController.updateTaskSchedule(task: task, startDate: startDate, endDate: endDate)
            } catch {
                print("Error updating task schedule: \(error)")
            }
        }
    }
}
