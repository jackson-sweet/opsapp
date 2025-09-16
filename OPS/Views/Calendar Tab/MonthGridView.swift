//
//  MonthGridView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-24.
//

import SwiftUI

// Track scroll position
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// Track month positions
struct MonthPositionPreferenceKey: PreferenceKey {
    struct MonthPosition: Equatable {
        let month: Date
        let minY: CGFloat
        let maxY: CGFloat
    }
    
    static var defaultValue: [MonthPosition] = []
    static func reduce(value: inout [MonthPosition], nextValue: () -> [MonthPosition]) {
        value.append(contentsOf: nextValue())
    }
}

struct MonthGridView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @State private var eventCache: [String: Int] = [:] // Cache event counts by date key
    @State private var scrollOffset: CGFloat = 0
    @State private var monthPositions: [MonthPositionPreferenceKey.MonthPosition] = []
    @State private var isScrolling = false
    @State private var scrollProxy: ScrollViewProxy?
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdayLabels = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    
    // Generate a continuous array of dates for multiple months
    private var calendarDates: [Date] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .month, value: -12, to: Date()) ?? Date()
        let endDate = calendar.date(byAdding: .month, value: 12, to: Date()) ?? Date()
        
        // Get the first day we should show (start of week containing first of month)
        guard let startInterval = calendar.dateInterval(of: .month, for: startDate),
              let endInterval = calendar.dateInterval(of: .month, for: endDate) else {
            return []
        }
        
        let firstOfStartMonth = startInterval.start
        let lastOfEndMonth = calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .month, value: 1, to: endInterval.start)!)!
        
        // Find the Monday before or on the first of start month
        let firstWeekday = calendar.component(.weekday, from: firstOfStartMonth)
        let daysFromMonday = (firstWeekday + 5) % 7
        let gridStartDate = calendar.date(byAdding: .day, value: -daysFromMonday, to: firstOfStartMonth)!
        
        // Find the Sunday after or on the last of end month
        let lastWeekday = calendar.component(.weekday, from: lastOfEndMonth)
        let daysToSunday = (8 - lastWeekday) % 7
        let gridEndDate = calendar.date(byAdding: .day, value: daysToSunday, to: lastOfEndMonth)!
        
        // Generate all dates
        var dates: [Date] = []
        var currentDate = gridStartDate
        while currentDate <= gridEndDate {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return dates
    }
    
    // Get unique months from calendar dates
    private var monthsInCalendar: [Date] {
        let calendar = Calendar.current
        var uniqueMonths: Set<Date> = []
        var orderedMonths: [Date] = []
        
        for date in calendarDates {
            if let monthStart = calendar.dateInterval(of: .month, for: date)?.start {
                if !uniqueMonths.contains(monthStart) {
                    uniqueMonths.insert(monthStart)
                    orderedMonths.append(monthStart)
                }
            }
        }
        
        return orderedMonths
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Fixed weekday header
                        HStack(spacing: 0) {
                            ForEach(weekdayLabels, id: \.self) { label in
                                Text(label)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(OPSStyle.Colors.background)
                        
                        // Calendar grid with month markers
                        LazyVStack(spacing: 8, pinnedViews: []) {
                            ForEach(monthsInCalendar, id: \.self) { monthStart in
                                VStack(spacing: 4) {
                                    // Month header
                                    Text(monthHeader(for: monthStart))
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                        .id(monthStart) // For ScrollViewReader
                                    
                                    // Days grid for this month
                                    LazyVGrid(columns: columns, spacing: 4) {
                                        ForEach(datesForMonth(monthStart), id: \.timeIntervalSince1970) { date in
                                            CalendarDayCell(
                                                date: date,
                                                viewModel: viewModel,
                                                eventCache: $eventCache,
                                                visibleMonth: $viewModel.visibleMonth,
                                                monthOfCell: monthStart
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .background(
                                        GeometryReader { monthGeometry in
                                            Color.clear
                                                .preference(
                                                    key: MonthPositionPreferenceKey.self,
                                                    value: [MonthPositionPreferenceKey.MonthPosition(
                                                        month: monthStart,
                                                        minY: monthGeometry.frame(in: .global).minY,
                                                        maxY: monthGeometry.frame(in: .global).maxY
                                                    )]
                                                )
                                        }
                                    )
                                }
                            }
                        }
                        .background(
                            GeometryReader { scrollGeometry in
                                Color.clear
                                    .preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: scrollGeometry.frame(in: .global).minY
                                    )
                            }
                        )
                    }
                    .onAppear {
                        scrollProxy = proxy
                        // Scroll to today on appear
                        if let todayMonth = monthForDate(Date()) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                proxy.scrollTo(todayMonth, anchor: .top)
                                viewModel.visibleMonth = todayMonth
                            }
                        }
                    }
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { _ in
                        if !isScrolling {
                            updateVisibleMonth(in: geometry)
                        }
                    }
                    .onPreferenceChange(MonthPositionPreferenceKey.self) { positions in
                        monthPositions = positions
                        if !isScrolling {
                            updateVisibleMonth(in: geometry)
                        }
                    }
                    .onChange(of: viewModel.selectedDate) { _, newDate in
                        // Only scroll if the month changed
                        let calendar = Calendar.current
                        if !calendar.isDate(viewModel.visibleMonth, equalTo: newDate, toGranularity: .month) {
                            if let targetMonth = monthForDate(newDate) {
                                isScrolling = true
                                viewModel.visibleMonth = targetMonth // Update immediately for UI consistency
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(targetMonth, anchor: .top)
                                }
                                // Use shorter delay just to reset scroll flag
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    isScrolling = false
                                }
                            }
                        }
                    }
                }
                // Add scroll end detection for snapping
                .simultaneousGesture(
                    DragGesture()
                        .onEnded { _ in
                            // Snap to nearest month after scroll ends
                            snapToNearestMonth(proxy: proxy, geometry: geometry)
                        }
                )
            }
        }
    }
    
    private func monthHeader(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).uppercased()
    }
    
    private func monthForDate(_ date: Date) -> Date? {
        let calendar = Calendar.current
        return calendar.dateInterval(of: .month, for: date)?.start
    }
    
    private func datesForMonth(_ monthStart: Date) -> [Date] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthStart) else {
            return []
        }
        
        let firstOfMonth = monthInterval.start
        guard let lastOfMonth = calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .month, value: 1, to: firstOfMonth)!) else {
            return []
        }
        
        // Find the Monday before or on the first of month
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let daysFromMonday = (firstWeekday + 5) % 7
        let gridStartDate = calendar.date(byAdding: .day, value: -daysFromMonday, to: firstOfMonth)!
        
        // Find the Sunday after or on the last of month
        let lastWeekday = calendar.component(.weekday, from: lastOfMonth)
        let daysToSunday = (8 - lastWeekday) % 7
        let gridEndDate = calendar.date(byAdding: .day, value: daysToSunday, to: lastOfMonth)!
        
        // Generate dates for this month's grid
        var dates: [Date] = []
        var currentDate = gridStartDate
        while currentDate <= gridEndDate {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return dates
    }
    
    private func updateVisibleMonth(in geometry: GeometryProxy) {
        // Use consistent reference point with snap behavior
        let referencePoint = geometry.frame(in: .global).minY + 100 // Account for header
        
        // Find which month is most visible
        var closestMonth: Date?
        var closestDistance: CGFloat = .infinity
        
        for position in monthPositions {
            // Check if month is visible on screen
            let isVisible = position.minY < referencePoint + geometry.size.height && position.maxY > referencePoint
            if isVisible {
                // Prefer month at top of screen
                let distance = abs(position.minY - referencePoint)
                if distance < closestDistance {
                    closestDistance = distance
                    closestMonth = position.month
                }
            }
        }
        
        if let newMonth = closestMonth, !Calendar.current.isDate(newMonth, equalTo: viewModel.visibleMonth, toGranularity: .month) {
            viewModel.visibleMonth = newMonth
        }
    }
    
    private func snapToNearestMonth(proxy: ScrollViewProxy, geometry: GeometryProxy) {
        let screenTop = geometry.frame(in: .global).minY + 100 // Account for header
        
        // Find the month that's closest to the top of the screen
        var closestMonth: Date?
        var closestDistance: CGFloat = .infinity
        
        for position in monthPositions {
            let distance = abs(position.minY - screenTop)
            
            if distance < closestDistance {
                closestDistance = distance
                closestMonth = position.month
            }
        }
        
        if let targetMonth = closestMonth {
            isScrolling = true
            viewModel.visibleMonth = targetMonth // Update immediately for UI consistency
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(targetMonth, anchor: .top)
            }
            // Use shorter delay just to reset scroll flag
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isScrolling = false
            }
        }
    }
    
    private func updateCalendarHeader(to month: Date) {
        // This will trigger the calendar header in the parent view to update
        // The parent view should observe visibleMonth changes
    }
}

// Optimized calendar day cell
struct CalendarDayCell: View {
    let date: Date
    @ObservedObject var viewModel: CalendarViewModel
    @Binding var eventCache: [String: Int]
    @Binding var visibleMonth: Date
    let monthOfCell: Date
    
    @State private var eventCount: Int = 0
    @State private var hasLoadedEvents = false
    
    private var dateKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ddMMyyyy"
        return formatter.string(from: date)
    }
    
    private var isInCellMonth: Bool {
        Calendar.current.isDate(date, equalTo: monthOfCell, toGranularity: .month)
    }
    
    private var isSelected: Bool {
        DateHelper.isSameDay(date, viewModel.selectedDate)
    }
    
    private var isToday: Bool {
        DateHelper.isToday(date)
    }
    
    private var textColor: Color {
        if !isInCellMonth {
            return OPSStyle.Colors.secondaryText.opacity(0.3)
        } else if isSelected {
            return OPSStyle.Colors.primaryText
        } else if isToday {
            return OPSStyle.Colors.primaryText
        } else {
            return OPSStyle.Colors.primaryText.opacity(0.8)
        }
    }
    
    private var cellBackground: some View {
        Group {
            if isToday {
                OPSStyle.Colors.primaryAccent
            } else {
                Color.clear
            }
        }
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectDate(date, userInitiated: true)
            }
        }) {
            ZStack {
                // Day number
                Text(DateHelper.dayString(from: date))
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(textColor)
                
                // Event indicator (only if events exist)
                if eventCount > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Circle()
                                .fill(OPSStyle.Colors.primaryAccent.opacity(0.8))
                                .frame(width: 6, height: 6)
                                .padding(.bottom, 2)
                                .padding(.trailing, 2)
                        }
                    }
                }
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(cellBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white, lineWidth: isSelected ? 1 : 0)
            )
        }
        .onAppear {
            loadEventCountIfNeeded()
        }
        .onChange(of: visibleMonth) { _, _ in
            // Reload events when visible month changes if we're now visible
            if Calendar.current.isDate(visibleMonth, equalTo: monthOfCell, toGranularity: .month) && !hasLoadedEvents {
                loadEventCountIfNeeded()
            }
        }
    }
    
    private func loadEventCountIfNeeded() {
        // Only load events for dates in or near the visible month
        let calendar = Calendar.current
        let isNearVisible = calendar.isDate(monthOfCell, equalTo: visibleMonth, toGranularity: .month) ||
                           abs(calendar.dateComponents([.month], from: monthOfCell, to: visibleMonth).month ?? 0) <= 1
        
        guard isNearVisible else { return }
        
        // Check cache first
        if let cachedCount = eventCache[dateKey] {
            eventCount = cachedCount
            hasLoadedEvents = true
            return
        }
        
        // Load from data source
        Task { @MainActor in
            let count = viewModel.projectCount(for: date)
            eventCount = count
            eventCache[dateKey] = count
            hasLoadedEvents = true
        }
    }
}

// Helper extensions - removed duplicate function