//
//  CalendarDaySelector.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-24.
//


// CalendarDaySelector.swift
import SwiftUI
import UIKit

struct CalendarDaySelector: View {
    @ObservedObject var viewModel: CalendarViewModel
    @EnvironmentObject private var dataController: DataController
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var isTransitioning: Bool = false
    @State private var transitionOffset: CGFloat = 0
    @State private var cellsVisible: [Bool] = Array(repeating: false, count: 7)
    @State private var lastWeekStart: Date? = nil
    @Namespace private var calendarNamespace

    var body: some View {
        ZStack(alignment: .top) {
            if viewModel.isMonthExpanded {
                MonthGridView(viewModel: viewModel)
                    .matchedGeometryEffect(id: "calendarContainer", in: calendarNamespace)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                    ))
            } else {
                weekView
                    .matchedGeometryEffect(id: "calendarContainer", in: calendarNamespace)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isMonthExpanded)
    }

    private var weekView: some View {
        GeometryReader { geometry in
            let weekDays = getCurrentWeekDays()
            VStack(spacing: 0) {
                ZStack {
                    // Week days display container with spanning bars overlay
                    ZStack(alignment: .bottom) {
                        HStack(spacing: 0) {
                            ForEach(Array(weekDays.enumerated()), id: \.element.timeIntervalSince1970) { index, date in
                                WeekDayCell(
                                    date: date,
                                    isSelected: DateHelper.isSameDay(date, viewModel.selectedDate),
                                    onTap: {
                                        viewModel.selectDate(date, userInitiated: true)
                                    }
                                )
                                .frame(maxWidth: .infinity)
                                .opacity(index < cellsVisible.count ? (cellsVisible[index] ? 1 : 0) : 1)
                                .offset(y: index < cellsVisible.count ? (cellsVisible[index] ? 0 : 5) : 0)
                            }
                        }

                        // Spanning event bars overlay
                        weekBarsOverlay(weekDays: weekDays)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 6)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .offset(x: isTransitioning ? transitionOffset : dragOffset)
                    .opacity(isTransitioning ? Double(1.0 - abs(transitionOffset) / geometry.size.width) : 1.0)
                    .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.85), value: dragOffset)
                }
                .clipped() // Prevent content from going outside safe area
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !isTransitioning else { return }
                            // Add resistance when dragging
                            let resistance: CGFloat = 0.5
                            dragOffset = value.translation.width * resistance
                            isDragging = true
                        }
                        .onEnded { value in
                            guard !isTransitioning else { return }
                            let threshold: CGFloat = 50
                            let velocity = value.predictedEndTranslation.width - value.translation.width

                            // Consider both distance and velocity for more natural feel
                            if value.translation.width > threshold || velocity > 200 {
                                // Swipe right - go to previous week
                                navigateToWeek(offset: -1, screenWidth: geometry.size.width)
                            } else if value.translation.width < -threshold || velocity < -200 {
                                // Swipe left - go to next week
                                navigateToWeek(offset: 1, screenWidth: geometry.size.width)
                            } else {
                                // Not enough to trigger week change, snap back
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    dragOffset = 0
                                    isDragging = false
                                }
                            }
                        }
                )
            }
        }
        .frame(height: 86)
        .onAppear {
            lastWeekStart = currentWeekStart()
            triggerCellAnimation()
        }
        // Only re-animate cells when the week changes (not just the selected day)
        .onChange(of: viewModel.selectedDate) { _, newDate in
            let newWeekStart = currentWeekStart(for: newDate)
            if newWeekStart != lastWeekStart {
                lastWeekStart = newWeekStart
                triggerCellAnimation()
            }
        }
        // Watch for calendar event changes and force refresh
        .onChange(of: dataController.scheduledTasksDidChange) { _, _ in
            // Use objectWillChange instead of forcing full view recreation
            viewModel.objectWillChange.send()
        }
    }

    // MARK: - Week spanning bars

    private struct WeekBarSpan: Identifiable {
        let id: String
        let color: Color
        let startDayIndex: Int
        let endDayIndex: Int
        let row: Int
        let isFirstSegment: Bool
        let isLastSegment: Bool
    }

    /// Compute spanning bars for the visible week, sorted multi-day first for stable row assignment
    private func computeWeekBarSpans(weekDays: [Date]) -> [WeekBarSpan] {
        let cal = Calendar.current
        var processedIds = Set<String>()

        // Gather all tasks for every day this week
        var tasksByDay: [[ProjectTask]] = []
        for date in weekDays {
            tasksByDay.append(viewModel.scheduledTasks(for: date))
        }

        // Collect unique tasks with their span info
        struct RawSpan {
            let taskId: String
            let color: Color
            let startIdx: Int
            let endIdx: Int
            let isFirstSegment: Bool
            let isLastSegment: Bool
        }

        var rawSpans: [RawSpan] = []

        for dayIndex in 0..<weekDays.count {
            for task in tasksByDay[dayIndex] {
                guard !processedIds.contains(task.id) else { continue }
                processedIds.insert(task.id)

                let taskStart = cal.startOfDay(for: task.startDate ?? weekDays[dayIndex])
                let taskEnd = cal.startOfDay(for: task.endDate ?? weekDays[dayIndex])

                var startIdx = dayIndex
                var endIdx = dayIndex
                for i in 0..<weekDays.count {
                    let dayStart = cal.startOfDay(for: weekDays[i])
                    if dayStart >= taskStart && dayStart <= taskEnd {
                        if i < startIdx { startIdx = i }
                        if i > endIdx { endIdx = i }
                    }
                }

                let isFirst = cal.startOfDay(for: weekDays[startIdx]) == taskStart
                let isLast = cal.startOfDay(for: weekDays[endIdx]) == taskEnd

                rawSpans.append(RawSpan(
                    taskId: task.id,
                    color: task.swiftUIColor,
                    startIdx: startIdx,
                    endIdx: endIdx,
                    isFirstSegment: isFirst,
                    isLastSegment: isLast
                ))
            }
        }

        // Sort: multi-day first (wider spans first), then by start index
        rawSpans.sort { a, b in
            let aSpan = a.endIdx - a.startIdx
            let bSpan = b.endIdx - b.startIdx
            if aSpan != bSpan { return aSpan > bSpan }
            return a.startIdx < b.startIdx
        }

        // Assign rows (slot packing)
        let maxRows = 4
        var occupiedSlots: [[Bool]] = Array(repeating: Array(repeating: false, count: maxRows), count: weekDays.count)
        var result: [WeekBarSpan] = []

        for raw in rawSpans {
            var assignedRow = -1
            for row in 0..<maxRows {
                var available = true
                for dayIdx in raw.startIdx...raw.endIdx {
                    if occupiedSlots[dayIdx][row] {
                        available = false
                        break
                    }
                }
                if available {
                    assignedRow = row
                    for dayIdx in raw.startIdx...raw.endIdx {
                        occupiedSlots[dayIdx][row] = true
                    }
                    break
                }
            }

            guard assignedRow >= 0 else { continue }

            result.append(WeekBarSpan(
                id: raw.taskId,
                color: raw.color,
                startDayIndex: raw.startIdx,
                endDayIndex: raw.endIdx,
                row: assignedRow,
                isFirstSegment: raw.isFirstSegment,
                isLastSegment: raw.isLastSegment
            ))
        }

        return result
    }

    /// Overlay view rendering spanning event bars at the bottom of the week cell area
    private func weekBarsOverlay(weekDays: [Date]) -> some View {
        GeometryReader { geo in
            let dayWidth = geo.size.width / CGFloat(weekDays.count)
            let spans = computeWeekBarSpans(weekDays: weekDays)
            let barHeight: CGFloat = 3
            let barSpacing: CGFloat = 2
            let edgeInset: CGFloat = 6

            ZStack(alignment: .topLeading) {
                ForEach(spans) { span in
                    let fullSpanWidth = dayWidth * CGFloat(span.endDayIndex - span.startDayIndex + 1)
                    let leadingInset: CGFloat = span.isFirstSegment ? edgeInset : 0
                    let trailingInset: CGFloat = span.isLastSegment ? edgeInset : 0
                    let barWidth = fullSpanWidth - leadingInset - trailingInset
                    let xPos = dayWidth * CGFloat(span.startDayIndex) + leadingInset
                    let yPos = CGFloat(span.row) * (barHeight + barSpacing)

                    UnevenRoundedRectangle(
                        topLeadingRadius: span.isFirstSegment ? 1.5 : 0,
                        bottomLeadingRadius: span.isFirstSegment ? 1.5 : 0,
                        bottomTrailingRadius: span.isLastSegment ? 1.5 : 0,
                        topTrailingRadius: span.isLastSegment ? 1.5 : 0
                    )
                    .fill(span.color.opacity(0.85))
                    .frame(width: max(barWidth, 0), height: barHeight)
                    .offset(x: xPos, y: yPos)
                }
            }
        }
        .frame(height: 20)
        .padding(.bottom, 4)
        .allowsHitTesting(false)
    }

    private func triggerCellAnimation() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            cellsVisible = Array(repeating: true, count: 7)
            return
        }
        // Reset all to hidden first
        cellsVisible = Array(repeating: false, count: 7)
        // Stagger each column in with snappy spring
        for i in 0..<7 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.02) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    cellsVisible[i] = true
                }
            }
        }
    }

    private func navigateToWeek(offset: Int, screenWidth: CGFloat) {
        guard !isTransitioning else { return }

        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday

        // Get the current week's start date
        guard let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: viewModel.selectedDate)?.start else {
            return
        }

        // Calculate the new week's start date
        guard let newWeekStart = calendar.date(byAdding: .weekOfYear, value: offset, to: currentWeekStart) else {
            return
        }

        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.prepare()

        // Two-phase animation: slide out → update data off-screen → slide in
        isTransitioning = true
        let slideDirection: CGFloat = offset > 0 ? -1 : 1

        // Phase 1: Slide current week out (fast exit)
        withAnimation(.easeIn(duration: 0.12)) {
            transitionOffset = slideDirection * screenWidth * 0.35
            dragOffset = 0
            isDragging = false
        }

        Task { @MainActor in
            // Wait for slide-out to complete
            try? await Task.sleep(for: .milliseconds(130))

            // Update data while content is off-screen
            viewModel.selectDate(newWeekStart, userInitiated: false)
            impactFeedback.impactOccurred()

            // Position new week on the opposite side, slightly off-screen
            transitionOffset = -slideDirection * screenWidth * 0.2

            // Phase 2: Slide new week in (spring settle)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                transitionOffset = 0
            }

            try? await Task.sleep(for: .milliseconds(280))
            isTransitioning = false
        }
    }

    /// Returns the Monday that starts the week containing `date` (or selectedDate).
    private func currentWeekStart(for date: Date? = nil) -> Date? {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: date ?? viewModel.selectedDate)?.start
    }

    // Generate only the current week days (7 days starting from Monday)
    private func getCurrentWeekDays() -> [Date] {
        var calendar = Calendar.current
        // Set first weekday to Monday (2 in Calendar, where Sunday = 1)
        calendar.firstWeekday = 2

        let baseDate = viewModel.selectedDate

        // Get the week containing the selected date
        guard let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: baseDate)?.start else {
            return []
        }

        // Since we changed firstWeekday to Monday, startOfWeek is now Monday
        // Generate all 7 days of the week starting from Monday
        var days: [Date] = []
        for i in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: i, to: startOfWeek) {
                days.append(day)
            }
        }

        return days
    }
}
