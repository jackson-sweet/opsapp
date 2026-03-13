//
//  UserEventSheet.swift
//  OPS
//
//  Unified sheet for creating personal events and time-off requests.
//  Replaces PersonalEventSheet and TimeOffRequestSheet with a single view
//  that provides calendar context showing existing scheduled events.
//

import SwiftUI
import SwiftData

// MARK: - Event Mode

enum UserEventMode: String, CaseIterable {
    case personalEvent = "EVENT"
    case timeOff = "TIME OFF"
}

// MARK: - UserEventSheet

struct UserEventSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataController: DataController
    @ObservedObject var viewModel: CalendarViewModel

    let initialMode: UserEventMode

    // Form state
    @State private var mode: UserEventMode
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var allDay: Bool = true
    @State private var isSaving: Bool = false

    // Section state
    @State private var isDetailsExpanded: Bool = true
    @State private var isScheduleExpanded: Bool = true

    // Calendar state
    @State private var selectedStartDate: Date
    @State private var selectedEndDate: Date
    @State private var selectionPhase: SelectionPhase = .selectingStart
    @State private var currentMonth: Date = Date()
    @State private var scheduledTasks: [ProjectTask] = []
    @State private var userEvents: [CalendarUserEvent] = []

    // Grid config
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    enum SelectionPhase {
        case selectingStart
        case selectingEnd
    }

    // MARK: - Init

    init(isPresented: Binding<Bool>, viewModel: CalendarViewModel, mode: UserEventMode = .personalEvent) {
        _isPresented = isPresented
        self.viewModel = viewModel
        self.initialMode = mode
        _mode = State(initialValue: mode)
        let today = viewModel.selectedDate
        _selectedStartDate = State(initialValue: today)
        _selectedEndDate = State(initialValue: today)
        if let monthStart = Calendar.current.dateInterval(of: .month, for: today)?.start {
            _currentMonth = State(initialValue: monthStart)
        }
    }

    // MARK: - Computed

    private var isFormValid: Bool {
        switch mode {
        case .personalEvent:
            return !title.trimmingCharacters(in: .whitespaces).isEmpty
        case .timeOff:
            return true
        }
    }

    private var durationDays: Int {
        let components = Calendar.current.dateComponents([.day], from: selectedStartDate, to: selectedEndDate)
        return (components.day ?? 0) + 1
    }

    private var hasDateRange: Bool {
        selectionPhase == .selectingEnd
    }

    private var actionButtonText: String {
        mode == .personalEvent ? "SAVE" : "SUBMIT"
    }

    private var sheetTitle: String {
        mode == .personalEvent ? "NEW EVENT" : "REQUEST TIME OFF"
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        // Mode toggle
                        modeToggle
                            .padding(.top, OPSStyle.Layout.spacing2)

                        // Time Off info banner
                        if mode == .timeOff {
                            timeOffBanner
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Details section (fields first)
                        ExpandableSection(
                            title: mode == .personalEvent ? "EVENT DETAILS" : "TIME OFF DETAILS",
                            icon: mode == .personalEvent ? "calendar.badge.plus" : "clock.badge.questionmark",
                            isExpanded: $isDetailsExpanded,
                            collapsible: false
                        ) {
                            detailsContent
                        }

                        // Schedule section (calendar below)
                        ExpandableSection(
                            title: "SELECT DATES",
                            icon: "calendar",
                            isExpanded: $isScheduleExpanded,
                            collapsible: false
                        ) {
                            scheduleContent
                        }

                        Spacer().frame(height: OPSStyle.Layout.spacing3)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.bottom, 100)
                }
            }
            .standardSheetToolbar(
                title: sheetTitle,
                actionText: actionButtonText,
                isActionEnabled: isFormValid && hasDateRange,
                isSaving: isSaving,
                onCancel: { isPresented = false },
                onAction: { save() }
            )
        }
        .interactiveDismissDisabled()
        .colorScheme(.dark)
        .onAppear {
            loadExistingEvents()
        }
        .animation(OPSStyle.Animation.standard, value: mode)
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach(UserEventMode.allCases, id: \.self) { eventMode in
                Button {
                    withAnimation(OPSStyle.Animation.fast) {
                        mode = eventMode
                        if eventMode == .timeOff { allDay = true }
                    }
                } label: {
                    Text(eventMode.rawValue)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(mode == eventMode ? OPSStyle.Colors.invertedText : OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(mode == eventMode ? OPSStyle.Colors.primaryText : Color.clear)
                }
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Time Off Banner

    private var timeOffBanner: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.warningStatus)

            Text("REQUEST WILL BE SENT TO YOUR ADMIN FOR APPROVAL.")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.warningStatus)
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.warningStatus.opacity(0.08))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.warningStatus.opacity(0.20), lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Details Content (inside ExpandableSection)

    private var detailsContent: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Title / Reason field
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text(mode == .personalEvent ? "TITLE" : "REASON (OPTIONAL)")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                TextField("", text: $title)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .placeholder(when: title.isEmpty) {
                        Text(mode == .personalEvent ? "Enter event title" : "Enter reason for time off")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.placeholderText)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }

            // All-day toggle (personal event only)
            if mode == .personalEvent {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ALL DAY")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text("Event spans full days")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    Spacer()

                    Toggle("", isOn: $allDay)
                        .labelsHidden()
                        .tint(OPSStyle.Colors.primaryAccent)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }

            // Notes (personal event only)
            if mode == .personalEvent {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text("NOTES (OPTIONAL)")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    TextEditor(text: $notes)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 80, maxHeight: 200)
                        .padding(12)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
            }
        }
    }

    // MARK: - Schedule Content (inside ExpandableSection)

    private var scheduleContent: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            // Date range display
            dateRangeHeader

            // Month navigation
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .frame(width: 44, height: 44)
                }

                Spacer()

                Text(monthYearString(from: currentMonth).uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .frame(width: 44, height: 44)
                }
            }

            // Weekday headers
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
            }

            // Calendar grid
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(daysInMonth(), id: \.self) { date in
                    EventDayCell(
                        date: date,
                        isInCurrentMonth: isInCurrentMonth(date),
                        isToday: Calendar.current.isDateInToday(date),
                        isStartDate: Calendar.current.isDate(date, inSameDayAs: selectedStartDate) && hasDateRange,
                        isEndDate: hasDateRange && Calendar.current.isDate(date, inSameDayAs: selectedEndDate),
                        isInRange: hasDateRange && isDateInRange(date),
                        taskDots: taskDotsForDate(date),
                        hasPersonalEvent: hasPersonalEventOnDate(date),
                        hasTimeOff: hasTimeOffOnDate(date),
                        onTap: { handleDateTap(date) }
                    )
                }
            }

            // Legend
            HStack(spacing: OPSStyle.Layout.spacing3) {
                legendSquare(color: OPSStyle.Colors.primaryAccent, label: "TODAY")
                legendSquare(color: OPSStyle.Colors.successStatus, label: "EVENT")
                legendSquare(color: OPSStyle.Colors.warningStatus, label: "TIME OFF")
                legendDots(label: "TASKS")
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Date Range Header

    private var dateRangeHeader: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("START")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(hasDateRange ? formatDate(selectedStartDate) : "Tap a date")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(hasDateRange ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(hasDateRange ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)

            VStack(alignment: .leading, spacing: 2) {
                Text("END")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(hasDateRange ? formatDate(selectedEndDate) : "Tap a date")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(hasDateRange ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text("DAYS")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(hasDateRange ? "\(durationDays)" : "—")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(hasDateRange ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(OPSStyle.Colors.background)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(
                    hasDateRange ? OPSStyle.Colors.primaryAccent.opacity(0.3) : OPSStyle.Colors.inputFieldBorder,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
        .animation(OPSStyle.Animation.fast, value: hasDateRange)
    }

    // MARK: - Legend

    private func legendSquare(color: Color, label: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    private func legendDots(label: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            HStack(spacing: 1) {
                Circle().fill(Color.blue).frame(width: 4, height: 4)
                Circle().fill(Color.orange).frame(width: 4, height: 4)
                Circle().fill(Color.green).frame(width: 4, height: 4)
            }
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    // MARK: - Date Handling

    private func handleDateTap(_ date: Date) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if selectionPhase == .selectingStart || selectedStartDate != selectedEndDate {
            // First tap or resetting after a range was already chosen
            selectedStartDate = date
            selectedEndDate = date
            selectionPhase = .selectingEnd
        } else {
            // Second tap: finalize the range (auto-sort)
            if date < selectedStartDate {
                selectedEndDate = selectedStartDate
                selectedStartDate = date
            } else {
                selectedEndDate = date
            }
        }
    }

    private func isDateInRange(_ date: Date) -> Bool {
        let dayStart = Calendar.current.startOfDay(for: date)
        let rangeStart = Calendar.current.startOfDay(for: selectedStartDate)
        let rangeEnd = Calendar.current.startOfDay(for: selectedEndDate)
        return dayStart >= rangeStart && dayStart <= rangeEnd
    }

    // MARK: - Event Data

    /// Returns up to 3 task colors for dots on a given date — uses actual task colors like CalendarSchedulerSheet
    private func taskDotsForDate(_ date: Date) -> [Color] {
        let matching = scheduledTasks.filter { task in
            task.spannedDates.contains { Calendar.current.isDate($0, inSameDayAs: date) }
        }
        return Array(matching.prefix(3).map { $0.swiftUIColor })
    }

    private func hasPersonalEventOnDate(_ date: Date) -> Bool {
        userEvents.contains { event in
            event.isPersonal && event.overlaps(date: date) && event.deletedAt == nil
        }
    }

    private func hasTimeOffOnDate(_ date: Date) -> Bool {
        userEvents.contains { event in
            event.isTimeOff && event.overlaps(date: date) && event.deletedAt == nil
        }
    }

    private func loadExistingEvents() {
        // Load scheduled tasks for ±3 months
        let calendar = Calendar.current
        let searchStart = calendar.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        let searchEnd = calendar.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        scheduledTasks = dataController.getScheduledTasks(in: searchStart...searchEnd)

        // Load user events from SwiftData
        guard let context = dataController.modelContext,
              let userId = dataController.currentUser?.id else { return }
        let descriptor = FetchDescriptor<CalendarUserEvent>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil }
        )
        userEvents = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Calendar Helpers

    private func daysInMonth() -> [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2

        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else { return [] }

        let firstOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let daysFromMonday = (firstWeekday - calendar.firstWeekday + 7) % 7

        guard let startDate = calendar.date(byAdding: .day, value: -daysFromMonday, to: firstOfMonth) else { return [] }

        var dates: [Date] = []
        for i in 0..<42 {
            if let date = calendar.date(byAdding: .day, value: i, to: startDate) {
                dates.append(date)
            }
        }
        return dates
    }

    private func isInCurrentMonth(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: currentMonth, toGranularity: .month)
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

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    // MARK: - Save

    private func save() {
        guard let userId = dataController.currentUser?.id,
              let companyId = dataController.currentUser?.companyId else { return }

        isSaving = true

        let eventType: CalendarUserEventType = mode == .personalEvent ? .personal : .timeOff
        let eventTitle: String
        let eventStatus: String
        let eventNotes: String?

        switch mode {
        case .personalEvent:
            eventTitle = title.trimmingCharacters(in: .whitespaces)
            eventStatus = CalendarUserEventStatus.none.rawValue
            eventNotes = notes.isEmpty ? nil : notes
        case .timeOff:
            let trimmed = title.trimmingCharacters(in: .whitespaces)
            eventTitle = trimmed.isEmpty ? "Time Off Request" : trimmed
            eventStatus = CalendarUserEventStatus.pending.rawValue
            eventNotes = trimmed.isEmpty ? nil : trimmed
        }

        let isAllDay = mode == .timeOff ? true : allDay

        let event = CalendarUserEvent(
            userId: userId,
            companyId: companyId,
            type: eventType,
            title: eventTitle,
            startDate: selectedStartDate,
            endDate: selectedEndDate,
            allDay: isAllDay,
            notes: eventNotes
        )
        event.status = eventStatus
        event.needsSync = true

        guard let context = dataController.modelContext else {
            isSaving = false
            return
        }
        context.insert(event)
        try? context.save()

        // Sync to Supabase
        Task {
            let repo = CalendarUserEventRepository(companyId: companyId)
            let iso = ISO8601DateFormatter()
            let dto = CreateCalendarUserEventDTO(
                userId: userId,
                companyId: companyId,
                type: eventType.rawValue,
                title: eventTitle,
                startDate: iso.string(from: selectedStartDate),
                endDate: iso.string(from: selectedEndDate),
                allDay: isAllDay,
                notes: eventNotes,
                status: eventStatus
            )
            if let saved = try? await repo.create(dto) {
                await MainActor.run {
                    event.id = saved.id
                    event.needsSync = false
                    event.lastSyncedAt = Date()
                    try? context.save()
                }
            }
            await MainActor.run {
                isSaving = false
                viewModel.loadUserEvents()
                isPresented = false
            }
        }
    }
}

// MARK: - Event Day Cell

private struct EventDayCell: View {
    let date: Date
    let isInCurrentMonth: Bool
    let isToday: Bool
    let isStartDate: Bool
    let isEndDate: Bool
    let isInRange: Bool
    let taskDots: [Color]        // Actual task colors (up to 3)
    let hasPersonalEvent: Bool
    let hasTimeOff: Bool
    let onTap: () -> Void

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    /// Background fill color for the cell — time off and events show as fills
    private var cellFillColor: Color? {
        if hasTimeOff {
            return OPSStyle.Colors.warningStatus
        } else if hasPersonalEvent {
            return OPSStyle.Colors.successStatus
        }
        return nil
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Layer 1: Time off / event background fill (subtle)
                if let fill = cellFillColor, !isToday {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                        .fill(fill.opacity(0.15))
                        .padding(2)
                }

                // Layer 2: Today — solid square fill
                if isToday {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                        .fill(OPSStyle.Colors.primaryAccent)
                        .padding(2)
                }

                // Layer 3: Selection borders (on top of fills)
                Group {
                    if isStartDate && isEndDate {
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .strokeBorder(OPSStyle.Colors.primaryText, lineWidth: OPSStyle.Layout.Border.thick)
                    } else if isStartDate {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 8,
                            bottomLeadingRadius: 8,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        )
                        .strokeBorder(OPSStyle.Colors.primaryText, lineWidth: OPSStyle.Layout.Border.thick)
                    } else if isEndDate {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 8,
                            topTrailingRadius: 8
                        )
                        .strokeBorder(OPSStyle.Colors.primaryText, lineWidth: OPSStyle.Layout.Border.thick)
                    } else if isInRange {
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
                .animation(OPSStyle.Animation.faster, value: isStartDate)
                .animation(OPSStyle.Animation.faster, value: isEndDate)
                .animation(OPSStyle.Animation.faster, value: isInRange)

                // Layer 4: Day number + task dots
                VStack(spacing: 2) {
                    Text(dayNumber)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(textColor)

                    // Task dots only (events and time off are shown as fills)
                    if !taskDots.isEmpty {
                        HStack(spacing: 1) {
                            ForEach(Array(taskDots.prefix(3).enumerated()), id: \.offset) { _, color in
                                Circle()
                                    .fill(color)
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
            return .white
        } else if !isInCurrentMonth {
            return OPSStyle.Colors.tertiaryText.opacity(0.3)
        } else if hasTimeOff {
            return OPSStyle.Colors.warningStatus
        } else if hasPersonalEvent {
            return OPSStyle.Colors.successStatus
        } else {
            return OPSStyle.Colors.primaryText
        }
    }
}
