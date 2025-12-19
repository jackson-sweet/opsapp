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

struct CalendarEventPreview: Identifiable, Equatable {
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

    static func == (lhs: CalendarEventPreview, rhs: CalendarEventPreview) -> Bool {
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
}

struct MoreEventsIndicator: Identifiable {
    let id = UUID()
    let dayIndex: Int
    let count: Int
    let row: Int
}

class MonthGridCache: ObservableObject {
    @Published var eventsByDate: [String: [CalendarEventPreview]] = [:]
    @Published var isLoading = false

    private let calendar = Calendar.current

    func loadEvents(from dataController: DataController, viewModel: CalendarViewModel, tutorialMode: Bool = false) {
        isLoading = true

        Task { @MainActor in
            var cache: [String: [CalendarEventPreview]] = [:]

            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()

            // Task-only scheduling migration: active property removed
            var allEvents = dataController.getAllCalendarEvents(from: oneYearAgo)

            // Tutorial mode only shows demo events
            if tutorialMode {
                allEvents = allEvents.filter { $0.id.hasPrefix("DEMO_") }
            }

            let filteredEvents = viewModel.applyEventFilters(to: allEvents)

            for event in filteredEvents {
                guard let startDate = event.startDate else { continue }
                let eventStart = calendar.startOfDay(for: startDate)
                // If no end date, treat as single-day event
                let endDate = event.endDate ?? startDate
                let eventEnd = calendar.startOfDay(for: endDate)

                let isMultiDay = !calendar.isDate(eventStart, inSameDayAs: eventEnd)
                let daySpan = calendar.dateComponents([.day], from: eventStart, to: eventEnd).day ?? 0
                let totalDays = daySpan + 1

                var currentDate = eventStart
                var dayOffset = 0

                while currentDate <= eventEnd {
                    let dateKey = formatDateKey(currentDate)
                    let isFirst = dayOffset == 0
                    let isLast = currentDate >= eventEnd

                    let weekday = calendar.component(.weekday, from: currentDate)
                    let isMonday = (weekday == 2)
                    let isFirstInWeek = isFirst || isMonday

                    // Task-only scheduling migration: Use stored color for all events
                    let displayColor = event.color

                    let preview = CalendarEventPreview(
                        id: "\(event.id)_\(dayOffset)",
                        eventId: event.id,
                        title: event.title,
                        color: displayColor,
                        startDate: eventStart,
                        endDate: eventEnd,
                        isMultiDay: isMultiDay,
                        dayOffset: dayOffset,
                        totalDays: totalDays,
                        isFirst: isFirst,
                        isLast: isLast,
                        isFirstInWeek: isFirstInWeek
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

            for key in cache.keys {
                cache[key] = cache[key]?.sorted { $0.startDate < $1.startDate }
            }

            eventsByDate = cache
            isLoading = false
        }
    }

    func events(for date: Date) -> [CalendarEventPreview] {
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
    @State private var updateWorkItem: DispatchWorkItem?
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
        let threshold: CGFloat = 100

        if offset > -threshold && offset < threshold {
            if let monthStart = calendar.dateInterval(of: .month, for: date)?.start {
                if !calendar.isDate(viewModel.visibleMonth, equalTo: monthStart, toGranularity: .month) {
                    updateWorkItem?.cancel()
                    let workItem = DispatchWorkItem {
                        self.viewModel.visibleMonth = monthStart
                    }
                    updateWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
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

    private func eventRowHeight(for cellHeight: CGFloat) -> CGFloat {
        let badgeHeight: CGFloat = cellHeight < 120 ? 10 : 14
        return badgeHeight + eventRowSpacing(for: cellHeight)
    }

    private func maxVisibleRows(for cellHeight: CGFloat) -> Int {
        let availableHeight = cellHeight - 26
        let rowSpacing = eventRowSpacing(for: cellHeight)

        if cellHeight < 120 {
            let rowHeight: CGFloat = 10
            return max(4, Int(availableHeight / (rowHeight + rowSpacing / 2)))
        } else if cellHeight < 180 {
            let rowHeight: CGFloat = 14
            return max(4, Int(availableHeight / (rowHeight + rowSpacing / 2)))
        } else {
            let rowHeight: CGFloat = 14
            return max(5, Int(availableHeight / (rowHeight + rowSpacing / 2)))
        }
    }

    private func weekSpansForWeek(dates: [Date?], weekIndex: Int) -> ([WeekEventSpan], [MoreEventsIndicator]) {
        let calendar = Calendar.current
        var spans: [WeekEventSpan] = []
        var indicators: [MoreEventsIndicator] = []
        let maxRows = maxVisibleRows(for: cellHeight)

        var occupiedRows: [[Bool]] = Array(repeating: Array(repeating: false, count: maxRows), count: 7)
        var eventsByDay: [[CalendarEventPreview]] = Array(repeating: [], count: 7)

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

                var assignedRow = -1
                for rowIndex in 0..<(maxRows - 1) {
                    var rowAvailable = true
                    for dayIdx in weekStartIndex...weekEndIndex {
                        if occupiedRows[dayIdx][rowIndex] {
                            rowAvailable = false
                            break
                        }
                    }

                    if rowAvailable {
                        assignedRow = rowIndex
                        for dayIdx in weekStartIndex...weekEndIndex {
                            occupiedRows[dayIdx][rowIndex] = true
                        }
                        break
                    }
                }

                if assignedRow >= 0 {
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
                        row: assignedRow,
                        isFirstSegment: isFirstSegment,
                        isLastSegment: isLastSegment,
                        isSingleDay: !event.isMultiDay
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
                    row: maxRows - 1
                ))
            }
        }

        return (spans, indicators)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(weekdayLabels, id: \.self) { label in
                        Text(label)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 8)
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
                                        .padding(.leading, 4)
                                        .padding(.top, monthIndex == 0 ? 0 : 16)
                                        .padding(.bottom, 8)
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
                                                                }
                                                            )
                                                        } else {
                                                            Color.clear
                                                                .frame(maxWidth: .infinity)
                                                                .frame(height: cellHeight)
                                                        }
                                                    }
                                                }

                                                ForEach(weekSpans) { span in
                                                    EventBar(span: span, cellHeight: cellHeight, dayWidth: dayWidth)
                                                        .offset(x: dayWidth * CGFloat(span.startDayIndex), y: 26 + (CGFloat(span.row) * eventRowHeight(for: cellHeight)))
                                                        .allowsHitTesting(false)
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
                                    .padding(.horizontal, 4)
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
                    scrollOffset = value
                }
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let newHeight = gestureStartHeight * value
                            cellHeight = min(max(newHeight, minHeight), maxHeight)
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
            .onChange(of: viewModel.visibleMonth) { oldMonth, newMonth in
                let calendar = Calendar.current
                print("📅 MonthGridView: visibleMonth changed from \(oldMonth) to \(newMonth)")

                if let oldStart = calendar.dateInterval(of: .month, for: oldMonth)?.start,
                   let newStart = calendar.dateInterval(of: .month, for: newMonth)?.start {

                    print("📅 Comparing months: old=\(oldStart) new=\(newStart)")

                    if !calendar.isDate(oldStart, equalTo: newStart, toGranularity: .month) {
                        print("📅 Scrolling to \(newStart)")
                        isProgrammaticScroll = true
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(newStart, anchor: .top)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            isProgrammaticScroll = false
                        }
                    } else {
                        print("📅 Same month, not scrolling")
                    }
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
            .onChange(of: dataController.calendarEventsDidChange) { _, _ in
                if let dataController = viewModel.dataController {
                    cache.loadEvents(from: dataController, viewModel: viewModel, tutorialMode: tutorialMode)
                }
            }
            .sheet(item: $sheetDate) { identifiableDate in
                DayDetailsSheet(date: identifiableDate.date, viewModel: viewModel, cache: cache)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
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
        // Only show outline when day sheet is visible (shouldShowDaySheet == true)
        viewModel.shouldShowDaySheet && DateHelper.isSameDay(date, viewModel.selectedDate)
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
        VStack(alignment: .leading, spacing: 2) {
            if isToday {
                // Today's date with white circle background
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 24, height: 24)

                        Text(DateHelper.dayString(from: date))
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.black)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 4)

                    Spacer()
                }
            } else {
                Text(DateHelper.dayString(from: date))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight, alignment: .top)
        .contentShape(Rectangle())
        .background(isToday ? OPSStyle.Colors.primaryAccent.opacity(0.5) : Color.clear)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.white : Color.clear, lineWidth: 1)
        )
        .onTapGesture {
            onTap()
        }
    }
}

struct EventBadge: View {
    let event: CalendarEventPreview
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
        if cellHeight <= 80 {
            return 0.5
        } else {
            return 0.2
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

    var body: some View {
        Group {
            if let height = badgeHeight {
                (Color(hex: event.color) ?? OPSStyle.Colors.primaryAccent).opacity(badgeOpacity)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: topLeftRadius,
                        bottomLeadingRadius: bottomLeftRadius,
                        bottomTrailingRadius: bottomRightRadius,
                        topTrailingRadius: topRightRadius
                    ))
                    .padding(horizontalPadding)
                    .overlay(alignment: .leading) {
                        if showText && (!event.isMultiDay || event.isFirst || event.isFirstInWeek) {
                            Text(event.title)
                                .font(fontSize)
                                .foregroundColor(Color(hex: event.color) ?? OPSStyle.Colors.primaryText)
                                .lineLimit(1)
                                .padding(.horizontal, 4)
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
                            .foregroundColor(Color(hex: event.color) ?? OPSStyle.Colors.primaryText)
                            .lineLimit(allowTextWrap ? nil : 1)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .fixedSize(horizontal: event.isMultiDay, vertical: false)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    (Color(hex: event.color) ?? OPSStyle.Colors.primaryAccent).opacity(badgeOpacity)
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: topLeftRadius,
                            bottomLeadingRadius: bottomLeftRadius,
                            bottomTrailingRadius: bottomRightRadius,
                            topTrailingRadius: topRightRadius
                        ))
                )
                .padding(horizontalPadding)
            }
        }
    }
}

struct EventBar: View {
    let span: WeekEventSpan
    let cellHeight: CGFloat
    let dayWidth: CGFloat

    private enum DisplayLevel {
        case level1
        case level2
        case level3
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

    private var badgeHeight: CGFloat {
        switch displayLevel {
        case .level1:
            return 10
        case .level2:
            return 14
        case .level3:
            return 14
        }
    }

    private var badgeOpacity: Double {
        displayLevel == .level1 ? 0.5 : 0.2
    }

    private var showText: Bool {
        displayLevel != .level1
    }

    private var fontSize: Font {
        Font.system(size: 10)
    }

    private var lineLimit: Int {
        1
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if showText && (span.isSingleDay || span.isFirstSegment) {
                Text(span.title)
                    .font(fontSize)
                    .foregroundColor(Color(hex: span.color) ?? OPSStyle.Colors.primaryText)
                    .lineLimit(lineLimit)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            }
            Spacer(minLength: 0)
        }
        .frame(width: dayWidth * CGFloat(span.endDayIndex - span.startDayIndex + 1), height: badgeHeight)
        .clipped()
        .background(
            (Color(hex: span.color) ?? OPSStyle.Colors.primaryAccent).opacity(badgeOpacity)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: span.isSingleDay || span.isFirstSegment ? 3 : 0,
                    bottomLeadingRadius: span.isSingleDay || span.isFirstSegment ? 3 : 0,
                    bottomTrailingRadius: span.isSingleDay || span.isLastSegment ? 3 : 0,
                    topTrailingRadius: span.isSingleDay || span.isLastSegment ? 3 : 0
                ))
        )
        .padding(.horizontal, 2)
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
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            Spacer(minLength: 0)
        }
        .frame(width: dayWidth, height: badgeHeight)
        .background(OPSStyle.Colors.secondaryText.opacity(0.1))
        .cornerRadius(3)
        .padding(.horizontal, 2)
    }
}

struct DayDetailsSheet: View {
    let date: Date
    @ObservedObject var viewModel: CalendarViewModel
    @ObservedObject var cache: MonthGridCache
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var appState: AppState

    private var events: [CalendarEventPreview] {
        cache.events(for: date)
    }

    private var calendarEvents: [CalendarEvent] {
        let eventIds = Set(events.map { $0.eventId })
        return eventIds.compactMap { id in
            dataController.getCalendarEvent(id: id)
        }
    }

    // Separate new and ongoing events (matching week view)
    private var newEvents: [CalendarEvent] {
        calendarEvents.filter { event in
            Calendar.current.isDate(event.startDate ?? Date(), inSameDayAs: date)
        }
    }

    private var ongoingEvents: [CalendarEvent] {
        calendarEvents.filter { event in
            let startDate = event.startDate ?? Date()
            return !Calendar.current.isDate(startDate, inSameDayAs: date)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(date.formatted(date: .complete, time: .omitted))
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal)
                    .padding(.top, 8)

                Text("\(calendarEvents.count) event\(calendarEvents.count == 1 ? "" : "s")")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.horizontal)

                if calendarEvents.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: OPSStyle.Icons.calendar)
                            .font(.system(size: 48))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Text("No events on this day")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    // New events section (matching week view template)
                    ForEach(Array(newEvents.enumerated()), id: \.element.id) { index, event in
                        CalendarEventCard(
                            event: event,
                            isFirst: index == 0,
                            isOngoing: false,
                            onTap: {
                                handleEventTap(event)
                            }
                        )
                        .padding(.horizontal)
                    }

                    // Ongoing section divider and events (matching week view template)
                    if !ongoingEvents.isEmpty {
                        HStack(spacing: 8) {
                            Text("ONGOING")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            Rectangle()
                                .fill(OPSStyle.Colors.tertiaryText.opacity(0.3))
                                .frame(height: 1)

                            Text("[\(ongoingEvents.count)]")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 24)

                        ForEach(Array(ongoingEvents.enumerated()), id: \.element.id) { index, event in
                            CalendarEventCard(
                                event: event,
                                isFirst: false,
                                isOngoing: true,
                                onTap: {
                                    handleEventTap(event)
                                }
                            )
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .background(OPSStyle.Colors.background)
        .presentationDetents([.fraction(0.3), .fraction(0.7), .large])
    }

    private func handleEventTap(_ event: CalendarEvent) {
        // Task-only scheduling migration: All events are task events
        if let task = event.task {
            // Send task ID and project ID
            let userInfo: [String: String] = [
                "taskID": task.id,
                "projectID": task.projectId
            ]

            // Post notification for task details
            NotificationCenter.default.post(
                name: Notification.Name("ShowCalendarTaskDetails"),
                object: nil,
                userInfo: userInfo
            )
        }
        dismiss()
    }
}

struct EventDetailCard: View {
    let event: CalendarEvent
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @State private var showingQuickActions = false
    @State private var showingReschedule = false
    @State private var showingDetailView = false
    @State private var isLongPressing = false
    @State private var hasTriggeredHaptic = false
    @State private var isPressed = false

    private var eventColor: Color {
        Color(hex: event.color) ?? OPSStyle.Colors.primaryAccent
    }

    private var dateRangeText: String {
        if let start = event.startDate, let end = event.endDate {
            return "\(start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))"
        } else {
            return "No dates"
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(eventColor)
                    .frame(width: 4)
                    .cornerRadius(2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    if let project = event.project {
                        Text(project.title)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }

                    if let task = event.task {
                        Text(task.displayTitle)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: OPSStyle.Icons.calendar)
                            .font(.system(size: 12))
                        Text(dateRangeText)
                            .font(OPSStyle.Typography.smallCaption)
                    }
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(12)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
    }

    var body: some View {
        cardContent
        .contentShape(Rectangle())
        .scaleEffect(isLongPressing ? 0.95 : (isPressed ? 0.98 : 1.0))
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isLongPressing)
        .animation(.spring(response: 0.1, dampingFraction: 0.8), value: isPressed)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
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
            // Task-only scheduling migration: All events are task events
            if let task = event.task, let project = task.project {
                TaskDetailsView(task: task, project: project)
                    .environmentObject(dataController)
                    .environmentObject(appState)
                    .environment(\.modelContext, dataController.modelContext!)
            }
        }
        .sheet(isPresented: $showingReschedule) {
            // Task-only scheduling migration: All events are task events
            if let task = event.task {
                CalendarSchedulerSheet(
                    isPresented: $showingReschedule,
                    itemType: .task(task),
                    currentStartDate: event.startDate,
                    currentEndDate: event.endDate,
                    onScheduleUpdate: { newStart, newEnd in
                        updateTaskSchedule(task: task, startDate: newStart, endDate: newEnd)
                    }
                )
                .environmentObject(dataController)
            }
        }
    }

    private func updateTaskSchedule(task: ProjectTask, startDate: Date, endDate: Date) {
        guard let calendarEvent = task.calendarEvent else { return }

        Task {
            do {
                try await dataController.updateCalendarEvent(event: calendarEvent, startDate: startDate, endDate: endDate)
            } catch {
                print("Error updating task schedule: \(error)")
            }
        }
    }

    private func updateProjectSchedule(project: Project, startDate: Date, endDate: Date) {
        Task {
            do {
                try await dataController.rescheduleProject(
                    project,
                    startDate: startDate,
                    endDate: endDate,
                    calendarEvent: event
                )
                print("[MONTH_GRID] ✅ Project rescheduled successfully")
            } catch {
                print("[MONTH_GRID] ❌ Error rescheduling project: \(error)")
            }
        }
    }
}
