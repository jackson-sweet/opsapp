//
//  CalendarDaySelector.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-24.
//


// CalendarDaySelector.swift
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum CalendarWeekRowEdgeDirection {
    case previous
    case next

    var offset: Int {
        switch self {
        case .previous: return -1
        case .next: return 1
        }
    }
}

enum CalendarWeekRowNavigation {
    static func activeEdgeWidth(forRowWidth rowWidth: CGFloat) -> CGFloat {
        guard rowWidth > 0 else { return 0 }
        let scaled = rowWidth * 0.09
        return min(max(scaled, 28), 44)
    }
}

enum CalendarWeekRowCaption {
    static func title(
        forWeekContaining selectedDate: Date,
        relativeTo today: Date = Date(),
        calendar sourceCalendar: Calendar = .current
    ) -> String {
        var calendar = sourceCalendar
        calendar.firstWeekday = 2

        guard
            let selectedWeekStart = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start,
            let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start
        else {
            return "This week"
        }

        let weekOffset = calendar.dateComponents(
            [.weekOfYear],
            from: currentWeekStart,
            to: selectedWeekStart
        ).weekOfYear ?? 0

        switch weekOffset {
        case 0:
            return "This week"
        case 1:
            return "Next week"
        case -1:
            return "Last week"
        case 2...3:
            return "\(weekOffset) weeks from now"
        case -3...(-2):
            return "\(abs(weekOffset)) weeks ago"
        default:
            let monthCount = max(abs(weekOffset) / 4, 1)
            let unit = monthCount == 1 ? "month" : "months"
            return weekOffset > 0
                ? "\(monthCount) \(unit) from now"
                : "\(monthCount) \(unit) ago"
        }
    }
}

struct WeekRowEdgeDropDelegate: DropDelegate {
    let direction: CalendarWeekRowEdgeDirection
    let fallbackDay: Date
    let session: ScheduleDragSession
    let dataController: DataController
    let onHover: (CalendarWeekRowEdgeDirection?) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.opsRescheduleItem])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        let calendar = Calendar.current
        let changed = session.hoveredDate.map { !calendar.isDate($0, inSameDayAs: fallbackDay) } ?? true
        if changed {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        session.hoveredDate = fallbackDay
        onHover(direction)
    }

    func dropExited(info: DropInfo) {
        let calendar = Calendar.current
        if let hovered = session.hoveredDate, calendar.isDate(hovered, inSameDayAs: fallbackDay) {
            session.hoveredDate = nil
        }
        onHover(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.opsRescheduleItem]).first else {
            onHover(nil)
            return false
        }

        _ = provider.loadTransferable(type: RescheduleDragPayload.self) { result in
            Task { @MainActor in
                defer { onHover(nil) }
                guard case .success(let payload) = result else {
                    session.end()
                    return
                }
                RescheduleCoordinator.handleDrop(
                    payload,
                    on: fallbackDay,
                    dataController: dataController,
                    session: session
                )
                session.end()
            }
        }
        return true
    }
}

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
    @Environment(ScheduleDragSession.self) private var dragSession
    // Drag-to-strip: width for the edge-paging animation + the dwell timer that
    // flips weeks when a reschedule drag lingers on the first/last strip cell.
    @State private var weekViewWidth: CGFloat = 0
    @State private var edgePageTask: Task<Void, Never>?
    @State private var edgePageGen: Int = 0
    @State private var activeEdgePageDirection: CalendarWeekRowEdgeDirection?

    var body: some View {
        ZStack(alignment: .top) {
            if viewModel.isMonthExpanded {
                MonthGridView(viewModel: viewModel)
                    .wizardTarget("explore_month")
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
        .animation(OPSStyle.Animation.standard, value: viewModel.isMonthExpanded)
    }

    private var weekView: some View {
        GeometryReader { geometry in
            let weekDays = getCurrentWeekDays()
            let edgeWidth = CalendarWeekRowNavigation.activeEdgeWidth(forRowWidth: geometry.size.width)
            VStack(spacing: OPSStyle.Layout.spacing1) {
                weekCaption

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
                                        NotificationCenter.default.post(name: Notification.Name("WizardCalendarDayTapped"), object: nil)
                                    }
                                )
                                .frame(maxWidth: .infinity)
                                .wizardTarget("tap_day")
                                // Drop target: drag a job card up to a strip day to
                                // reschedule it there. Highlight clamps to this week.
                                .reschedulableDropTarget(
                                    day: date,
                                    weekClamp: (weekDays.first ?? date)...(weekDays.last ?? date))
                                .opacity(index < cellsVisible.count ? (cellsVisible[index] ? 1 : 0) : 1)
                                .offset(y: index < cellsVisible.count ? (cellsVisible[index] ? 0 : 5) : 0)
                            }
                        }

                        // Spanning event bars overlay
                        weekBarsOverlay(weekDays: weekDays)
                    }
                    // Bug 2b61daa0 — bumped vertical padding from 12 → 16 so
                    // the day labels and bottom event-bars overlay get real
                    // breathing room from the card border instead of butting
                    // up against it.
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                    .padding(.horizontal, 6)
                    .glassSurface()
                    .offset(x: isTransitioning ? transitionOffset : dragOffset)
                    .opacity(isTransitioning ? Double(1.0 - abs(transitionOffset) / geometry.size.width) : 1.0)
                    .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.85), value: dragOffset)
                    .overlay(alignment: .leading) {
                        weekEdgeDropZone(
                            direction: .previous,
                            fallbackDay: weekDays.first,
                            width: edgeWidth
                        )
                    }
                    .overlay(alignment: .trailing) {
                        weekEdgeDropZone(
                            direction: .next,
                            fallbackDay: weekDays.last,
                            width: edgeWidth
                        )
                    }
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
                                withAnimation(OPSStyle.Animation.quick) {
                                    dragOffset = 0
                                    isDragging = false
                                }
                            }
                        }
                )
            }
            .onAppear { weekViewWidth = geometry.size.width }
            .onChange(of: geometry.size.width) { _, w in weekViewWidth = w }
            // Edge-paging: a reschedule drag lingering on the first/last strip cell
            // flips to the previous/next week so you can drop on any week.
            .onChange(of: dragSession.hoveredDate) { _, newValue in
                handleDragEdgeHover(newValue)
            }
        }
        // Bug 2b61daa0 — bumped from 86 → 118 to honor the internal vertical
        // padding (16 top + 16 bottom = 32) plus the 86pt WeekDayCell. The
        // old 86pt outer frame compressed the cell and ate the padding,
        // leaving the cards visually cramped against the card border.
        .frame(height: 140)
        .wizardTarget("scroll_week")
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
            // Defer past current render pass to avoid
            // "Publishing changes from within view updates" warning.
            DispatchQueue.main.async {
                viewModel.objectWillChange.send()
            }
        }
        // Bug 1 — Refresh week strip when user events change locally or sync
        // from the server.
        .onChange(of: viewModel.userEventsForCurrentPeriod.count) { _, _ in
            DispatchQueue.main.async {
                viewModel.objectWillChange.send()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CalendarUserEventsDidChange"))) { _ in
            viewModel.loadUserEvents()
        }
    }

    private var weekCaption: some View {
        HStack {
            Text(CalendarWeekRowCaption.title(forWeekContaining: viewModel.selectedDate))
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.text3)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
    }

    @ViewBuilder
    private func weekEdgeDropZone(
        direction: CalendarWeekRowEdgeDirection,
        fallbackDay: Date?,
        width: CGFloat
    ) -> some View {
        if let fallbackDay, width > 0 {
            Color.clear
                .contentShape(Rectangle())
                .frame(width: width)
                .onDrop(
                    of: [.opsRescheduleItem],
                    delegate: WeekRowEdgeDropDelegate(
                        direction: direction,
                        fallbackDay: fallbackDay,
                        session: dragSession,
                        dataController: dataController,
                        onHover: handleDragRowEdgeHover
                    )
                )
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

    private struct WeekBarLayout {
        let spans: [WeekBarSpan]
        let overflowPerDay: [Int]
    }

    /// Compute spanning bars for the visible week, sorted multi-day first for stable row assignment.
    /// Returns both the bar spans and a per-day overflow count for "+N" indicators.
    private func computeWeekBarLayout(weekDays: [Date]) -> WeekBarLayout {
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

        // Bug 1 — Include user events (time off + personal) so the week strip
        // shows their span bars alongside project tasks.
        let timeOffColor = Color(red: 196/255, green: 168/255, blue: 104/255)
        let personalColor = Color(white: 0.55)
        var processedUserEventIds = Set<String>()
        for dayIndex in 0..<weekDays.count {
            let events = viewModel.userEvents(for: weekDays[dayIndex])
            for event in events {
                guard !processedUserEventIds.contains(event.id) else { continue }
                processedUserEventIds.insert(event.id)

                let evStart = cal.startOfDay(for: event.startDate)
                let evEnd = cal.startOfDay(for: event.endDate)
                var startIdx = dayIndex
                var endIdx = dayIndex
                for i in 0..<weekDays.count {
                    let dayStart = cal.startOfDay(for: weekDays[i])
                    if dayStart >= evStart && dayStart <= evEnd {
                        if i < startIdx { startIdx = i }
                        if i > endIdx { endIdx = i }
                    }
                }

                let isFirst = cal.startOfDay(for: weekDays[startIdx]) == evStart
                let isLast = cal.startOfDay(for: weekDays[endIdx]) == evEnd

                rawSpans.append(RawSpan(
                    taskId: "userevent:\(event.id)",
                    color: event.isTimeOff ? timeOffColor : personalColor,
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
        var assignedTaskIds = Set<String>()

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

            assignedTaskIds.insert(raw.taskId)
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

        // Compute per-day overflow: tasks on that day that didn't get a bar
        var overflowPerDay = Array(repeating: 0, count: weekDays.count)
        for dayIdx in 0..<weekDays.count {
            var uniqueIds = Set<String>()
            for task in tasksByDay[dayIdx] {
                uniqueIds.insert(task.id)
            }
            // Include user events in overflow accounting (Bug 1)
            for event in viewModel.userEvents(for: weekDays[dayIdx]) {
                uniqueIds.insert("userevent:\(event.id)")
            }
            let displayedOnDay = uniqueIds.intersection(assignedTaskIds).count
            overflowPerDay[dayIdx] = max(0, uniqueIds.count - displayedOnDay)
        }

        return WeekBarLayout(spans: result, overflowPerDay: overflowPerDay)
    }

    /// Overlay view rendering spanning event bars at the bottom of the week cell area
    private func weekBarsOverlay(weekDays: [Date]) -> some View {
        GeometryReader { geo in
            let dayWidth = geo.size.width / CGFloat(weekDays.count)
            let layout = computeWeekBarLayout(weekDays: weekDays)
            let barHeight: CGFloat = 3
            let barSpacing: CGFloat = 2
            let edgeInset: CGFloat = 6

            ZStack(alignment: .topLeading) {
                ForEach(layout.spans) { span in
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

                // "+N" overflow indicators for days with more tasks than visible bars
                ForEach(0..<weekDays.count, id: \.self) { dayIdx in
                    let overflow = layout.overflowPerDay[dayIdx]
                    if overflow > 0 {
                        // Find the highest occupied row for this day to position below it
                        let maxOccupiedRow = layout.spans
                            .filter { $0.startDayIndex <= dayIdx && $0.endDayIndex >= dayIdx }
                            .map { $0.row }
                            .max() ?? -1
                        let yPos = CGFloat(maxOccupiedRow + 1) * (barHeight + barSpacing)

                        Text("+\(overflow)")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(width: dayWidth, alignment: .center)
                            .offset(x: dayWidth * CGFloat(dayIdx), y: yPos)
                    }
                }
            }
        }
        .frame(height: 20)
        .padding(.bottom, OPSStyle.Layout.spacing2)
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
                withAnimation(OPSStyle.Animation.quick) {
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
        withAnimation(OPSStyle.Animation.hover) {
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
            withAnimation(OPSStyle.Animation.standard) {
                transitionOffset = 0
            }

            try? await Task.sleep(for: .milliseconds(280))
            isTransitioning = false

            // Notify wizard system that the week strip was scrolled
            NotificationCenter.default.post(name: Notification.Name("CalendarWeekViewScrolled"), object: nil)

            if let direction = activeEdgePageDirection, dragSession.active != nil {
                armEdgePage(direction)
            }
        }
    }

    /// Returns the Monday that starts the week containing `date` (or selectedDate).
    private func currentWeekStart(for date: Date? = nil) -> Date? {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: date ?? viewModel.selectedDate)?.start
    }

    /// Flip the visible week when a reschedule drag dwells on the first/last strip
    /// day, so the operator can drop a job on any week without ending the drag.
    private func handleDragEdgeHover(_ hovered: Date?) {
        guard dragSession.active != nil, let hovered else {
            cancelEdgePage()
            return
        }
        let cal = Calendar.current
        let week = getCurrentWeekDays()
        let atStart = week.first.map { cal.isDate($0, inSameDayAs: hovered) } ?? false
        let atEnd = week.last.map { cal.isDate($0, inSameDayAs: hovered) } ?? false
        guard atStart != atEnd else {
            cancelEdgePage()
            return
        }
        handleDragRowEdgeHover(atStart ? .previous : .next)
    }

    private func handleDragRowEdgeHover(_ direction: CalendarWeekRowEdgeDirection?) {
        guard dragSession.active != nil, let direction else {
            cancelEdgePage()
            return
        }

        if activeEdgePageDirection != direction {
            edgePageTask?.cancel()
            edgePageTask = nil
        }
        activeEdgePageDirection = direction
        armEdgePage(direction)
    }

    private func armEdgePage(_ direction: CalendarWeekRowEdgeDirection) {
        guard edgePageTask == nil else { return }
        let width = weekViewWidth > 0 ? weekViewWidth : UIScreen.main.bounds.width
        // Generation token: a cancelled task resumes asynchronously, so it must not
        // clear edgePageTask if a newer dwell has already re-armed one.
        edgePageGen &+= 1
        let gen = edgePageGen
        edgePageTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard gen == edgePageGen else { return }   // superseded by a newer arm
            edgePageTask = nil
            guard
                !Task.isCancelled,
                dragSession.active != nil,
                activeEdgePageDirection == direction,
                !isTransitioning
            else {
                return
            }
            navigateToWeek(offset: direction.offset, screenWidth: width)
        }
    }

    private func cancelEdgePage() {
        edgePageGen &+= 1
        edgePageTask?.cancel()
        edgePageTask = nil
        activeEdgePageDirection = nil
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
