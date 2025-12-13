//
//  CalendarSchedulerSheet.swift
//  OPS
//
//  Calendar-based scheduler for rescheduling projects and tasks
//  Allows selecting new dates while viewing potential conflicts
//

import SwiftUI
import SwiftData

struct CalendarSchedulerSheet: View {
    // MARK: - Properties
    @Binding var isPresented: Bool
    let itemType: ScheduleItemType
    let currentStartDate: Date?
    let currentEndDate: Date?
    let onScheduleUpdate: (Date, Date) -> Void
    let onClearDates: (() -> Void)?
    let preselectedTeamMemberIds: Set<String>?  // Optional pre-selected team members for filtering

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController

    // Calendar state
    @State private var selectedStartDate: Date
    @State private var selectedEndDate: Date
    @State private var viewMode: ViewMode = .selecting
    @State private var currentMonth: Date = Date()
    @State private var conflictingEvents: [CalendarEvent] = []
    @State private var showingConflictWarning = false
    @State private var showOnlyTeamEvents = true  // Filter by team members by default
    @State private var showOnlyProjectTasks = true  // Filter by same project tasks - default ON
    @State private var allCalendarEvents: [CalendarEvent] = []
    @State private var filteredCalendarEvents: [CalendarEvent] = []

    // Grid configuration
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    // Start with Monday
    private let weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    // MARK: - Initialization
    init(isPresented: Binding<Bool>,
         itemType: ScheduleItemType,
         currentStartDate: Date?,
         currentEndDate: Date?,
         onScheduleUpdate: @escaping (Date, Date) -> Void,
         onClearDates: (() -> Void)? = nil,
         preselectedTeamMemberIds: Set<String>? = nil) {

        self._isPresented = isPresented
        self.itemType = itemType
        self.currentStartDate = currentStartDate
        self.currentEndDate = currentEndDate
        self.onScheduleUpdate = onScheduleUpdate
        self.onClearDates = onClearDates
        self.preselectedTeamMemberIds = preselectedTeamMemberIds

        // Initialize with current dates or today
        let startDate = currentStartDate ?? Date()
        let endDate = currentEndDate ?? Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate

        self._selectedStartDate = State(initialValue: startDate)
        self._selectedEndDate = State(initialValue: endDate)

        // Start with the month of the current start date
        if let monthStart = Calendar.current.dateInterval(of: .month, for: startDate)?.start {
            self._currentMonth = State(initialValue: monthStart)
        }
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                
                // Calendar View
                ScrollView {
                    VStack(spacing: 20) {

                        // Selected dates display (always visible, same size)
                        selectedDatesHeader
                            .padding(.top, 8)

                        // Calendar Grid
                        calendarSectionFullWidth

                        // Conflict Warning (show immediately after calendar when reviewing)
                        if !conflictingEvents.isEmpty && viewMode == .reviewing {
                            conflictWarningCard
                                .padding(.horizontal, 20)
                        }

                        // Action Button (always visible, disabled when no dates)
                        actionButtons
                            .padding(.horizontal, 20)

                        // Filter toggles
                        teamFilterToggle

                        // Project tasks filter (only show for tasks)
                        if case .task = itemType {
                            projectTasksFilterToggle
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            loadCalendarEvents()
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        ZStack {
            SchedulerBlurView(style: .dark)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .font(OPSStyle.Typography.body)

                    Spacer()

                    Text("Schedule \(itemType.displayName)")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    // Clear dates button (only if callback is provided and dates exist)
                    if onClearDates != nil && (currentStartDate != nil || currentEndDate != nil) {
                        Button {
                            handleClearDates()
                        } label: {
                            Text("Clear")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                    } else {
                        // Invisible spacer for balance
                        Text("Cancel")
                            .font(OPSStyle.Typography.body)
                            .opacity(0)
                    }
                }
                .padding()
            }
        }
        .frame(height: 60)
    }

    // MARK: - Selected Dates Header
    private var hasSelectedDates: Bool {
        // User has completed date selection (in reviewing mode)
        viewMode == .reviewing
    }

    private var selectedDatesHeader: some View {
        HStack(spacing: 0) {
            // Start date
            VStack(alignment: .leading, spacing: 4) {
                Text("START")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(hasSelectedDates ? formatDate(selectedStartDate) : "Select date")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(hasSelectedDates ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(hasSelectedDates ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, 12)

            // End date
            VStack(alignment: .leading, spacing: 4) {
                Text("END")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(hasSelectedDates ? formatDate(selectedEndDate) : "Select date")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(hasSelectedDates ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Duration
            VStack(alignment: .trailing, spacing: 4) {
                Text("DURATION")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(hasSelectedDates ? "\(daysBetween(selectedStartDate, selectedEndDate)) days" : "—")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(hasSelectedDates ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .strokeBorder(hasSelectedDates ? OPSStyle.Colors.primaryAccent.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.2), value: hasSelectedDates)
    }

    // MARK: - Calendar Section (Full Width)
    private var calendarSectionFullWidth: some View {
        VStack(spacing: 16) {
            // Month Navigation
            monthNavigationView
                .padding(.horizontal, 20)

            // Weekday Headers
            weekdayHeadersView
                .padding(.horizontal, 16)

            // Calendar Grid
            calendarGridView
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Team Filter Toggle
    private var teamFilterToggle: some View {
        HStack {
            Image(systemName: OPSStyle.Icons.crew)
                .foregroundColor(showOnlyTeamEvents ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text("TEAM EVENTS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text("Show events with conflicting team assignments")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer()

            Toggle("", isOn: $showOnlyTeamEvents)
                .labelsHidden()
                .tint(OPSStyle.Colors.primaryAccent)
                .scaleEffect(0.8)
        }
        .padding(14)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .onChange(of: showOnlyTeamEvents) { _ in
            if showOnlyTeamEvents {
                showOnlyProjectTasks = false
            }
            filterCalendarEvents()
        }
    }

    // MARK: - Project Tasks Filter Toggle
    private var projectTasksFilterToggle: some View {
        HStack {
            Image(systemName: OPSStyle.Icons.taskType)
                .foregroundColor(showOnlyProjectTasks ? OPSStyle.Colors.secondaryAccent : OPSStyle.Colors.tertiaryText)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text("PROJECT TASKS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text("Show other tasks from this project")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer()

            Toggle("", isOn: $showOnlyProjectTasks)
                .labelsHidden()
                .tint(OPSStyle.Colors.secondaryAccent)
                .scaleEffect(0.8)
        }
        .padding(14)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .onChange(of: showOnlyProjectTasks) { _ in
            if showOnlyProjectTasks {
                showOnlyTeamEvents = false
            }
            filterCalendarEvents()
        }
    }

    // MARK: - Month Navigation
    private var monthNavigationView: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .font(.system(size: 18, weight: .semibold))
            }

            Spacer()

            Text(monthYearString(from: currentMonth))
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .font(.system(size: 18, weight: .semibold))
            }
        }
    }

    // MARK: - Weekday Headers
    private var weekdayHeadersView: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
        }
    }

    // MARK: - Calendar Grid
    private var calendarGridView: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(daysInMonth(), id: \.self) { date in
                SchedulerDayCell(
                    date: date,
                    isInCurrentMonth: isInCurrentMonth(date),
                    events: getEventsForDate(date),
                    isSelected: isDateSelected(date),
                    isInRange: isDateInRange(date),
                    isStartDate: isStartDate(date),
                    isEndDate: isEndDate(date),
                    hasConflicts: hasConflicts(on: date),
                    hasTeamConflicts: hasTeamConflicts(on: date),
                    isToday: isToday(date),
                    onTap: { handleDateSelection(date) }
                )
            }
        }
    }

    // MARK: - Conflict Warning Card
    private var conflictWarningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("SCHEDULING CONFLICTS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                    .font(.system(size: 14))
            }

            Text("The following items overlap with your selected dates:")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 8) {
                ForEach(conflictingEvents.prefix(3)) { event in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(event.swiftUIColor)
                            .frame(width: 8, height: 8)

                        Text(event.title)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)

                        Spacer()

                        let startDateStr = event.startDate.map { formatDate($0, short: true) } ?? "-"
                        let endDateStr = event.endDate.map { formatDate($0, short: true) } ?? "-"
                        Text("\(startDateStr) - \(endDateStr)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }

                if conflictingEvents.count > 3 {
                    Text("+ \(conflictingEvents.count - 3) more conflicts")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .strokeBorder(OPSStyle.Colors.warningStatus.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if !conflictingEvents.isEmpty && hasSelectedDates {
                // Conflicts exist - show both options
                HStack(spacing: 12) {
                    Button(action: {
                        // Reset to single date selection
                        selectedStartDate = currentStartDate ?? Date()
                        selectedEndDate = selectedStartDate
                        conflictingEvents = []
                        viewMode = .selecting
                    }) {
                        Text("CHANGE")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }

                    Button(action: handleConfirmSchedule) {
                        Text("CONFIRM ANYWAY")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
            } else {
                // Single confirm button (disabled when no dates selected)
                Button(action: handleConfirmSchedule) {
                    Text("CONFIRM DATES")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(hasSelectedDates ? .black : OPSStyle.Colors.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(hasSelectedDates ? .white : OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .strokeBorder(hasSelectedDates ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .disabled(!hasSelectedDates)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hasSelectedDates)
    }

    // MARK: - Helper Methods

    private func daysInMonth() -> [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Start week on Monday

        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else {
            return []
        }

        let firstOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)

        // Calculate days from Monday (accounting for firstWeekday = 2)
        let daysFromMonday = (firstWeekday - calendar.firstWeekday + 7) % 7

        guard let startDate = calendar.date(byAdding: .day, value: -daysFromMonday, to: firstOfMonth) else {
            return []
        }

        var dates: [Date] = []
        for i in 0..<42 { // 6 weeks
            if let date = calendar.date(byAdding: .day, value: i, to: startDate) {
                dates.append(date)
            }
        }

        return dates
    }

    private func isInCurrentMonth(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: currentMonth, toGranularity: .month)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func isDateSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedStartDate) ||
        Calendar.current.isDate(date, inSameDayAs: selectedEndDate)
    }

    private func isStartDate(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedStartDate)
    }

    private func isEndDate(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedEndDate)
    }

    private func isDateInRange(_ date: Date) -> Bool {
        date >= selectedStartDate && date <= selectedEndDate
    }

    private func getEventsForDate(_ date: Date) -> [CalendarEvent] {
        // Return events scheduled on this date based on filter
        let events = (showOnlyTeamEvents || showOnlyProjectTasks) ? filteredCalendarEvents : allCalendarEvents
        return events.filter { event in
            event.spannedDates.contains { Calendar.current.isDate($0, inSameDayAs: date) }
        }
    }

    private func hasConflicts(on date: Date) -> Bool {
        // Check if selected range would conflict with existing events on this date
        guard viewMode == .reviewing else { return false }

        return conflictingEvents.contains { event in
            event.spannedDates.contains { Calendar.current.isDate($0, inSameDayAs: date) }
        }
    }

    private func hasTeamConflicts(on date: Date) -> Bool {
        // Check if this date has events with overlapping team members
        let eventsToCheck = (showOnlyTeamEvents || showOnlyProjectTasks) ? filteredCalendarEvents : allCalendarEvents

        // Get team members for the current item
        let currentTeamMembers: Set<String>

        // If preselected team members are provided, use those
        if let preselectedIds = preselectedTeamMemberIds, !preselectedIds.isEmpty {
            currentTeamMembers = preselectedIds
        } else {
            // Otherwise, get from the current item
            switch itemType {
            case .project(let project):
                currentTeamMembers = Set(project.getTeamMemberIds())
            case .task(let task):
                currentTeamMembers = Set(task.getTeamMemberIds())
            case .draftTask(_, let teamMemberIds, _):
                currentTeamMembers = Set(teamMemberIds)
            }
        }

        // Check if any events on this date share team members (excluding current item)
        return eventsToCheck.contains { event in
            // Don't count the current item being rescheduled
            let isSameItem: Bool
            switch itemType {
            case .project(let project):
                // All events are task events now - project events no longer exist
                isSameItem = false
            case .task(let task):
                isSameItem = event.taskId == task.id
            case .draftTask:
                // Draft tasks don't have an ID yet, so they can't match existing events
                isSameItem = false
            }

            if !isSameItem && event.spannedDates.contains(where: { Calendar.current.isDate($0, inSameDayAs: date) }) {
                // Use linked task's team members if available
                let eventTeamMembers: Set<String>
                if let task = event.task {
                    eventTeamMembers = Set(task.getTeamMemberIds())
                } else {
                    eventTeamMembers = Set(event.getTeamMemberIds())
                }
                return !currentTeamMembers.isDisjoint(with: eventTeamMembers)
            }
            return false
        }
    }

    private func handleDateSelection(_ date: Date) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        if selectedStartDate == selectedEndDate {
            // Second date selected - auto-sort so earlier date is start, later is end
            let firstDate = selectedStartDate
            let secondDate = date

            if secondDate < firstDate {
                selectedStartDate = secondDate
                selectedEndDate = firstDate
            } else {
                selectedStartDate = firstDate
                selectedEndDate = secondDate
            }

            // Check for conflicts and move to review mode
            checkForConflicts()
            viewMode = .reviewing
        } else {
            // Reset to single date selection
            selectedStartDate = date
            selectedEndDate = date
            // Clear conflicts and go back to selecting
            conflictingEvents = []
            viewMode = .selecting
        }
    }

    private func loadCalendarEvents() {
        // Load all calendar events in the date range (optimized)
        let calendar = Calendar.current
        let searchStart = calendar.date(byAdding: .month, value: -3, to: selectedStartDate) ?? selectedStartDate
        let searchEnd = calendar.date(byAdding: .month, value: 3, to: selectedEndDate) ?? selectedEndDate

        // Use optimized range query instead of day-by-day loop
        allCalendarEvents = dataController.getCalendarEvents(in: searchStart...searchEnd)

        // Filter events
        filterCalendarEvents()
    }

    private func filterCalendarEvents() {
        // Handle project tasks filter (only for items with a project)
        if showOnlyProjectTasks {
            if let projectId = itemType.projectId {
                // Show only other tasks from the same project
                let currentTaskId: String? = {
                    if case .task(let task) = itemType { return task.id }
                    return nil
                }()

                filteredCalendarEvents = allCalendarEvents.filter { event in
                    // Must be from the same project
                    guard event.projectId == projectId else { return false }

                    // Exclude the current task being scheduled (if editing existing task)
                    if let taskId = currentTaskId, event.taskId == taskId {
                        return false
                    }

                    return true
                }
                return
            } else {
                // No project ID available - show nothing for project tasks filter
                filteredCalendarEvents = []
                return
            }
        }

        // Handle team events filter
        guard showOnlyTeamEvents else {
            filteredCalendarEvents = allCalendarEvents
            return
        }

        // Get team members for the current item
        let currentTeamMembers: Set<String>

        // If preselected team members are provided, use those
        if let preselectedIds = preselectedTeamMemberIds, !preselectedIds.isEmpty {
            currentTeamMembers = preselectedIds
        } else {
            // Otherwise, get from the current item
            switch itemType {
            case .project(let project):
                currentTeamMembers = Set(project.getTeamMemberIds())
            case .task(let task):
                currentTeamMembers = Set(task.getTeamMemberIds())
            case .draftTask(_, let teamMemberIds, _):
                currentTeamMembers = Set(teamMemberIds)
            }
        }

        // Filter events that share at least one team member
        // Use the linked task's team members (more accurate than stored event team members)
        filteredCalendarEvents = allCalendarEvents.filter { event in
            // Get team members from the linked task if available, otherwise fall back to event's stored IDs
            let eventTeamMembers: Set<String>
            if let task = event.task {
                eventTeamMembers = Set(task.getTeamMemberIds())
            } else {
                eventTeamMembers = Set(event.getTeamMemberIds())
            }
            return !currentTeamMembers.isDisjoint(with: eventTeamMembers)
        }
    }

    private func checkForConflicts() {
        // Get events to check based on current filter
        let eventsToCheck = (showOnlyTeamEvents || showOnlyProjectTasks) ? filteredCalendarEvents : allCalendarEvents

        // Filter for events that overlap with the selected date range
        conflictingEvents = eventsToCheck.filter { event in
            // Don't count the current item being rescheduled as a conflict
            let isSameItem: Bool
            switch itemType {
            case .project(let project):
                // All events are task events now - project events no longer exist
                isSameItem = false
            case .task(let task):
                isSameItem = event.taskId == task.id
            case .draftTask:
                // Draft tasks don't have an ID yet, so they can't match existing events
                isSameItem = false
            }

            // Check for date overlap
            if !isSameItem, let eventStart = event.startDate, let eventEnd = event.endDate {
                let eventRange = eventStart...eventEnd
                let selectedRange = selectedStartDate...selectedEndDate
                return eventRange.overlaps(selectedRange)
            }
            return false
        }.sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
    }

    private func handleConfirmSchedule() {
        // Apply the schedule change
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        onScheduleUpdate(selectedStartDate, selectedEndDate)
        isPresented = false
    }

    private func handleClearDates() {
        // Apply haptic feedback for destructive action
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        onClearDates?()
        isPresented = false
    }

    private func previousMonth() {
        if let newMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = newMonth
        }
    }

    private func nextMonth() {
        if let newMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = newMonth
        }
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date, short: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = short ? "MMM d" : "EEE, MMM d"
        return formatter.string(from: date)
    }

    private func daysBetween(_ start: Date, _ end: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: start, to: end)
        return (components.day ?? 0) + 1
    }

    // MARK: - Enums
    enum ViewMode {
        case selecting
        case reviewing
    }

    enum ScheduleItemType {
        case project(Project)
        case task(ProjectTask)
        case draftTask(taskTypeId: String, teamMemberIds: [String], projectId: String?)

        var displayName: String {
            switch self {
            case .project:
                return "Project"
            case .task, .draftTask:
                return "Task"
            }
        }

        var isDraft: Bool {
            if case .draftTask = self { return true }
            return false
        }

        var projectId: String? {
            switch self {
            case .project(let project):
                return project.id
            case .task(let task):
                return task.projectId
            case .draftTask(_, _, let projectId):
                return projectId
            }
        }
    }
}

// MARK: - Day Cell Component
private struct SchedulerDayCell: View {
    let date: Date
    let isInCurrentMonth: Bool
    let events: [CalendarEvent]
    let isSelected: Bool
    let isInRange: Bool
    let isStartDate: Bool
    let isEndDate: Bool
    let hasConflicts: Bool
    let hasTeamConflicts: Bool
    let isToday: Bool
    let onTap: () -> Void

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background for today only
                if isToday {
                    // Today: always has primaryAccent background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(OPSStyle.Colors.primaryAccent)
                }

                // Border styling for selected dates with animation
                Group {
                    if isStartDate && isEndDate {
                        // Single date selection: fully rounded border
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(OPSStyle.Colors.primaryText, lineWidth: 2)
                    } else if isStartDate {
                        // Start date: rounded left corners only
                        UnevenRoundedRectangle(
                            topLeadingRadius: 8,
                            bottomLeadingRadius: 8,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        )
                        .strokeBorder(OPSStyle.Colors.primaryText, lineWidth: 2)
                    } else if isEndDate {
                        // End date: rounded right corners only
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 8,
                            topTrailingRadius: 8
                        )
                        .strokeBorder(OPSStyle.Colors.primaryText, lineWidth: 2)
                    } else if isInRange {
                        // Top and bottom borders only for intermediate dates
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(OPSStyle.Colors.primaryText)
                                .frame(height: 2)
                            Spacer()
                            Rectangle()
                                .fill(OPSStyle.Colors.primaryText)
                                .frame(height: 2)
                        }
                    }
                }
                .opacity(isStartDate || isEndDate || isInRange ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isStartDate)
                .animation(.easeInOut(duration: 0.15), value: isEndDate)
                .animation(.easeInOut(duration: 0.15), value: isInRange)

                // Conflict indicator overlay
                if hasConflicts {
                    Circle()
                        .fill(OPSStyle.Colors.warningStatus.opacity(0.3))
                        .padding(4)
                }

                VStack(spacing: 2) {
                    Text(dayNumber)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(textColor)

                    // Event dots with actual colors
                    if !events.isEmpty {
                        HStack(spacing: 1) {
                            ForEach(Array(events.prefix(3).enumerated()), id: \.offset) { index, event in
                                Circle()
                                    .fill(event.swiftUIColor)
                                    .frame(width: 4, height: 4)
                            }
                        }
                    }
                }
            }
            .frame(height: 44)
        }
        .disabled(!isInCurrentMonth)
    }

    private var textColor: Color {
        if isToday {
            // White text on today's primaryAccent background
            return .white
        } else if !isInCurrentMonth {
            return OPSStyle.Colors.tertiaryText.opacity(0.3)
        } else if hasTeamConflicts {
            // Gray out dates with team conflicts
            return OPSStyle.Colors.primaryText.opacity(0.7)
        } else {
            // Normal text color for all dates including selected ones
            return OPSStyle.Colors.primaryText
        }
    }
}

// MARK: - BlurView Helper
struct SchedulerBlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
