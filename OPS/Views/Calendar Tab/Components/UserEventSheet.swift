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

// MARK: - Recurrence

/// Bug a5001a70 — recurrence frequency for personal events. Implementation
/// strategy: expand into N standalone CalendarUserEvent rows on save (no DB
/// schema change required). Hard cap of 100 occurrences and 1 year forward
/// (whichever is earlier) to avoid runaway data growth.
enum RecurrenceFrequency: String, CaseIterable, Identifiable {
    case never
    case daily
    case weekly
    case biweekly
    case monthly
    case yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never:    return "Never"
        case .daily:    return "Daily"
        case .weekly:   return "Weekly"
        case .biweekly: return "Every 2 Weeks"
        case .monthly:  return "Monthly"
        case .yearly:   return "Yearly"
        }
    }

    /// Calendar component + value used to advance one occurrence.
    var step: (component: Calendar.Component, value: Int)? {
        switch self {
        case .never:    return nil
        case .daily:    return (.day, 1)
        case .weekly:   return (.weekOfYear, 1)
        case .biweekly: return (.weekOfYear, 2)
        case .monthly:  return (.month, 1)
        case .yearly:   return (.year, 1)
        }
    }
}

// MARK: - UserEventSheet

struct UserEventSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataController: DataController
    @ObservedObject var viewModel: CalendarViewModel

    let initialMode: UserEventMode

    /// When non-nil, the sheet runs in edit mode against this row instead of
    /// creating new rows. The row's series_id determines whether the save
    /// fans out to siblings — `editScope` decides which siblings.
    let editingEvent: CalendarUserEvent?

    /// Series scope for the save path. Ignored in create mode and in edit
    /// mode for non-recurring events (those always use `.thisOnly`).
    let editScope: RecurringEventScope

    // Form state
    @State private var mode: UserEventMode
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var allDay: Bool = true
    @State private var isSaving: Bool = false

    /// First-event-save permission ask for iPhone Calendar Mirror.
    @State private var showingMirrorPrompt: Bool = false

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

    // Bug a5001a70 — Team invites
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var showingTeamPicker: Bool = false

    // Bug a5001a70 — Time of day (active when allDay == false)
    @State private var startTime: Date
    @State private var endTime: Date

    // Bug a5001a70 — Recurrence
    @State private var recurrence: RecurrenceFrequency = .never
    @State private var recurrenceEnd: Date? = nil
    @State private var recurrenceUseEndDate: Bool = false

    // Grid config
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    enum SelectionPhase {
        case selectingStart
        case selectingEnd
    }

    /// True in edit mode — drives copy, hides the create-only mode toggle
    /// and recurrence row, and routes save() through the recurring-event
    /// helpers in DataController instead of creating new rows.
    private var isEditing: Bool { editingEvent != nil }

    // MARK: - Init

    /// Create-mode init — kept identical to the original signature so call
    /// sites (calendar FAB, schedule wizard) don't change.
    init(isPresented: Binding<Bool>, viewModel: CalendarViewModel, mode: UserEventMode = .personalEvent) {
        _isPresented = isPresented
        self.viewModel = viewModel
        self.initialMode = mode
        self.editingEvent = nil
        self.editScope = .thisOnly
        _mode = State(initialValue: mode)

        let today = viewModel.selectedDate
        _selectedStartDate = State(initialValue: today)
        _selectedEndDate = State(initialValue: today)
        _startTime = State(initialValue: UserEventSheet.defaultStartTime())
        _endTime = State(initialValue: UserEventSheet.defaultEndTime())
        if let monthStart = Calendar.current.dateInterval(of: .month, for: today)?.start {
            _currentMonth = State(initialValue: monthStart)
        }
    }

    /// Edit-mode init — prepopulates every form field from `event` and
    /// stamps the chosen scope so save() routes through the scoped helper.
    /// `selectionPhase` is forced to `.selectingEnd` so the date range
    /// reads as "already chosen" and SAVE is enabled immediately.
    init(
        isPresented: Binding<Bool>,
        viewModel: CalendarViewModel,
        editing event: CalendarUserEvent,
        scope: RecurringEventScope
    ) {
        _isPresented = isPresented
        self.viewModel = viewModel
        let resolvedMode: UserEventMode = event.isTimeOff ? .timeOff : .personalEvent
        self.initialMode = resolvedMode
        self.editingEvent = event
        self.editScope = scope
        _mode = State(initialValue: resolvedMode)
        _title = State(initialValue: event.title)
        _notes = State(initialValue: event.notes ?? "")
        _allDay = State(initialValue: event.allDay)
        _selectedStartDate = State(initialValue: event.startDate)
        _selectedEndDate = State(initialValue: event.endDate)
        _selectionPhase = State(initialValue: .selectingEnd)
        _selectedTeamMemberIds = State(initialValue: Set(event.teamMemberIds ?? []))

        // Pre-fill the time pickers from the row's start/end so they don't
        // jump if the user toggles All Day off mid-edit.
        let calendar = Calendar.current
        let startTimeSeed: Date
        let endTimeSeed: Date
        if event.allDay {
            startTimeSeed = UserEventSheet.defaultStartTime()
            endTimeSeed = UserEventSheet.defaultEndTime()
        } else {
            startTimeSeed = event.startDate
            endTimeSeed = event.endDate
        }
        _startTime = State(initialValue: startTimeSeed)
        _endTime = State(initialValue: endTimeSeed)

        if let monthStart = calendar.dateInterval(of: .month, for: event.startDate)?.start {
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
        if isEditing { return "SAVE" }
        return mode == .personalEvent ? "SAVE" : "SUBMIT"
    }

    private var sheetTitle: String {
        if isEditing {
            switch editScope {
            case .thisOnly:       return mode == .personalEvent ? "EDIT EVENT" : "EDIT TIME OFF"
            case .thisAndFuture:  return "EDIT FUTURE EVENTS"
            case .allEvents:      return "EDIT ALL EVENTS"
            }
        }
        return mode == .personalEvent ? "NEW EVENT" : "REQUEST TIME OFF"
    }

    /// Default workday start (8:00 AM) used when "All Day" is toggled off.
    private static func defaultStartTime() -> Date {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }

    /// Default workday end (5:00 PM) used when "All Day" is toggled off.
    private static func defaultEndTime() -> Date {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        // Mode toggle — hidden in edit mode; an existing row's
                        // type is fixed once it's been saved.
                        if !isEditing {
                            modeToggle
                                .padding(.top, OPSStyle.Layout.spacing2)
                        }

                        // Edit-scope banner — clarifies what "save" will affect
                        // when the user picked future/all from the scope sheet.
                        if isEditing && editScope != .thisOnly {
                            editScopeBanner
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Time Off info banner
                        if mode == .timeOff && !isEditing {
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
        // Bug a5001a70 — team picker sheet. Reuses the existing
        // TeamMemberPickerSheet so visuals stay identical to TaskFormSheet
        // and PersonalEventSheet.
        .sheet(isPresented: $showingTeamPicker) {
            if let companyId = dataController.currentUser?.companyId {
                let members = dataController.getTeamMembers(companyId: companyId)
                    .sorted { $0.fullName < $1.fullName }
                TeamMemberPickerSheet(
                    selectedTeamMemberIds: $selectedTeamMemberIds,
                    allTeamMembers: members
                )
            }
        }
        // Bug 68123654 — first-event-save iPhone Calendar Mirror permission ask.
        .sheet(isPresented: $showingMirrorPrompt) {
            CalendarMirrorPromptSheet(isPresented: $showingMirrorPrompt)
        }
        .onChange(of: showingMirrorPrompt) { _, isShowing in
            if !isShowing {
                isPresented = false
            }
        }
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

    // MARK: - Edit Scope Banner

    /// Reminds the user what their save is about to affect when they chose
    /// "future" or "all" in the scope sheet — so SAVE is never a surprise.
    private var editScopeBanner: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(OPSStyle.Icons.dependency)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.primaryAccent)

            Text(editScope == .thisAndFuture
                 ? "CHANGES APPLY TO THIS EVENT AND EVERY LATER OCCURRENCE."
                 : "CHANGES APPLY TO EVERY OCCURRENCE IN THE SERIES.")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.primaryAccent.opacity(0.10))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.30),
                        lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Time Off Banner

    private var timeOffBanner: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(OPSStyle.Icons.stale)
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

                // Bug a5001a70 — start/end time pickers (only when not all-day)
                if !allDay {
                    timePickerRow(label: "STARTS", time: $startTime)
                    timePickerRow(label: "ENDS", time: $endTime)
                }
            }

            // Bug a5001a70 — team invite picker (personal event only).
            // Time-off requests don't invite the crew — they belong to the
            // requester only.
            if mode == .personalEvent {
                teamInviteRow
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

    // MARK: - Time Picker Row (Bug a5001a70)

    /// One styled row containing a label and a compact `DatePicker` showing
    /// only hour and minute. Matches the visual rhythm of the All-Day row
    /// above it.
    private func timePickerRow(label: String, time: Binding<Date>) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            DatePicker(
                "",
                selection: time,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .colorScheme(.dark)
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

    // MARK: - Team Invite Row (Bug a5001a70)

    private var teamInviteRow: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("INVITE TEAM")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Button {
                showingTeamPicker = true
            } label: {
                HStack {
                    if selectedTeamMemberIds.isEmpty {
                        Text("ADD CREW")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    } else {
                        Text("\(selectedTeamMemberIds.count) ASSIGNED")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }

                    Spacer()

                    Image(OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Recurrence Row (Bug a5001a70)

    /// Repeat picker + optional end-date picker. Hidden in time-off mode —
    /// recurring time-off requests would all need approval and admins would
    /// reject the model outright. Stays simple: standalone-event expansion
    /// on save, no DB schema change.
    @ViewBuilder
    private var recurrenceRow: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("REPEAT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Menu {
                ForEach(RecurrenceFrequency.allCases) { option in
                    Button {
                        recurrence = option
                        if option == .never {
                            recurrenceUseEndDate = false
                            recurrenceEnd = nil
                        }
                    } label: {
                        if recurrence == option {
                            Label(option.label, image: OPSStyle.Icons.checkmarkCircle)
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(recurrence.label.uppercased())
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(recurrence == .never ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)

                    Spacer()

                    Image(OPSStyle.Icons.sort)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }

            // End condition — only meaningful when recurrence != .never
            if recurrence != .never {
                HStack(spacing: 0) {
                    recurrenceEndPill(
                        title: "FOREVER",
                        subtitle: "Locks 1 year of dates",
                        isSelected: !recurrenceUseEndDate,
                        action: {
                            recurrenceUseEndDate = false
                            recurrenceEnd = nil
                        }
                    )

                    recurrenceEndPill(
                        title: "UNTIL DATE",
                        subtitle: nil,
                        isSelected: recurrenceUseEndDate,
                        action: {
                            recurrenceUseEndDate = true
                            if recurrenceEnd == nil {
                                // Default end: 1 month from selected start
                                recurrenceEnd = Calendar.current.date(byAdding: .month, value: 1, to: selectedStartDate)
                            }
                        }
                    )
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .padding(.top, 4)

                if recurrenceUseEndDate {
                    HStack {
                        Text("ENDS ON")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Spacer()

                        DatePicker(
                            "",
                            selection: Binding(
                                get: { recurrenceEnd ?? Calendar.current.date(byAdding: .month, value: 1, to: selectedStartDate) ?? Date() },
                                set: { recurrenceEnd = $0 }
                            ),
                            in: selectedStartDate...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .tint(OPSStyle.Colors.primaryAccent)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .padding(.top, 4)
                }
            }
        }
    }

    private func recurrenceEndPill(title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(isSelected ? OPSStyle.Colors.invertedText : OPSStyle.Colors.primaryText)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(isSelected ? OPSStyle.Colors.invertedText.opacity(0.7) : OPSStyle.Colors.tertiaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? OPSStyle.Colors.primaryText : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Schedule Content (inside ExpandableSection)

    private var scheduleContent: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            // Date range display
            dateRangeHeader

            // Bug a5001a70 — recurrence picker (create-mode personal events
            // only). In edit mode we deliberately hide it: changing the
            // recurrence rule on an existing series is a structural change
            // that's better handled by deleting + recreating the series.
            if mode == .personalEvent && !isEditing {
                recurrenceRow
            }

            // Month navigation
            HStack {
                Button(action: previousMonth) {
                    Image(OPSStyle.Icons.chevronLeft)
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
                    Image(OPSStyle.Icons.chevronRight)
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

            Image(OPSStyle.Icons.arrowRight)
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
        guard !isSaving else { return }
        guard let userId = dataController.currentUser?.id,
              let companyId = dataController.currentUser?.companyId else { return }

        isSaving = true

        // Edit mode shortcuts the create path entirely — fields are routed
        // through DataController.updateRecurringEvent which handles series
        // fanout, detach-on-thisOnly, and remote sync.
        if let editing = editingEvent {
            saveEdit(target: editing)
            return
        }

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

        // Bug a5001a70 — merge time-of-day into the date components when the
        // user disabled All Day. Time pickers are personal-event only, so
        // time-off requests always keep midnight boundaries.
        let baseStart: Date
        let baseEnd: Date
        if mode == .personalEvent && !isAllDay {
            baseStart = mergeDateAndTime(date: selectedStartDate, time: startTime)
            baseEnd = mergeDateAndTime(date: selectedEndDate, time: endTime)
        } else {
            baseStart = selectedStartDate
            baseEnd = selectedEndDate
        }

        // Bug a5001a70 — team member IDs (personal events only).
        let teamIds: [String]?
        if mode == .personalEvent && !selectedTeamMemberIds.isEmpty {
            teamIds = Array(selectedTeamMemberIds)
        } else {
            teamIds = nil
        }

        // Expand recurrence into N occurrences. Time-off mode never recurs.
        let occurrences: [(start: Date, end: Date)]
        if mode == .personalEvent && recurrence != .never {
            occurrences = expandRecurrence(
                start: baseStart,
                end: baseEnd,
                frequency: recurrence,
                customEnd: recurrenceUseEndDate ? recurrenceEnd : nil
            )
        } else {
            occurrences = [(baseStart, baseEnd)]
        }

        // Stamp every expanded row with the same series_id so we can later
        // resolve siblings for "edit/delete this one / future / all" scopes.
        // Single-occurrence events leave it nil — there's nothing to group.
        let seriesId: String? = occurrences.count > 1 ? UUID().uuidString : nil

        guard let context = dataController.modelContext else {
            isSaving = false
            return
        }

        // Insert all occurrences locally up front so the calendar reflects
        // them immediately even if Supabase sync fails.
        var localEvents: [CalendarUserEvent] = []
        for occurrence in occurrences {
            let event = CalendarUserEvent(
                userId: userId,
                companyId: companyId,
                type: eventType,
                title: eventTitle,
                startDate: occurrence.start,
                endDate: occurrence.end,
                allDay: isAllDay,
                notes: eventNotes,
                address: nil,
                teamMemberIds: teamIds,
                seriesId: seriesId
            )
            event.status = eventStatus
            event.needsSync = true
            context.insert(event)
            localEvents.append(event)
        }
        try? context.save()

        // Sync to Supabase — one row per occurrence, all sharing the same
        // series_id. Editing a single occurrence will detach it (set
        // series_id = nil); "edit future" / "edit all" will batch-update
        // the rest.
        Task {
            let repo = CalendarUserEventRepository(companyId: companyId)
            let iso = ISO8601DateFormatter()

            for (index, occurrence) in occurrences.enumerated() {
                let dto = CreateCalendarUserEventDTO(
                    userId: userId,
                    companyId: companyId,
                    type: eventType.rawValue,
                    title: eventTitle,
                    startDate: iso.string(from: occurrence.start),
                    endDate: iso.string(from: occurrence.end),
                    allDay: isAllDay,
                    notes: eventNotes,
                    status: eventStatus,
                    address: nil,
                    teamMemberIds: teamIds,
                    seriesId: seriesId
                )
                if let saved = try? await repo.create(dto) {
                    let savedId = saved.id
                    await MainActor.run {
                        guard index < localEvents.count else { return }
                        localEvents[index].id = savedId
                        localEvents[index].needsSync = false
                        localEvents[index].lastSyncedAt = Date()
                        try? context.save()
                    }
                }
            }

            await MainActor.run {
                isSaving = false
                viewModel.loadUserEvents()
                // Bug 68123654 — surface the iPhone Calendar Mirror prompt at most
                // once per install, at the moment the user clearly cares about
                // their calendar. If the user has already seen the prompt, or has
                // already granted permission, dismiss directly.
                if !CalendarMirrorService.shared.hasShownPrompt
                    && CalendarMirrorService.shared.authorizationStatus == .notDetermined {
                    showingMirrorPrompt = true
                } else {
                    isPresented = false
                }
            }
        }
    }

    // MARK: - Recurrence Helpers (Bug a5001a70)

    /// Combines the day from `date` with the hour/minute/second from `time`.
    private func mergeDateAndTime(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        return calendar.date(
            bySettingHour: timeComponents.hour ?? 0,
            minute: timeComponents.minute ?? 0,
            second: timeComponents.second ?? 0,
            of: date
        ) ?? date
    }

    // MARK: - Edit save path

    /// Apply the form fields to `target` via the recurring-event helper.
    /// Dismiss runs immediately after the local mutation — remote sync is
    /// fire-and-forget inside the helper so the user doesn't wait on the
    /// network for the sheet to close.
    private func saveEdit(target: CalendarUserEvent) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let resolvedTitle: String = trimmedTitle.isEmpty
            ? (mode == .timeOff ? "Time Off Request" : target.title)
            : trimmedTitle
        let resolvedNotes: String? = notes.isEmpty ? nil : notes
        let resolvedAllDay = mode == .timeOff ? true : allDay

        // Merge time-of-day into the chosen calendar dates when not all-day.
        let resolvedStart: Date
        let resolvedEnd: Date
        if mode == .personalEvent && !resolvedAllDay {
            resolvedStart = mergeDateAndTime(date: selectedStartDate, time: startTime)
            resolvedEnd = mergeDateAndTime(date: selectedEndDate, time: endTime)
        } else {
            resolvedStart = selectedStartDate
            resolvedEnd = selectedEndDate
        }

        let teamIds: [String]?
        if mode == .personalEvent && !selectedTeamMemberIds.isEmpty {
            teamIds = Array(selectedTeamMemberIds)
        } else {
            teamIds = nil
        }

        let payload = DataController.CalendarUserEventEditPayload(
            title: resolvedTitle,
            notes: resolvedNotes,
            allDay: resolvedAllDay,
            startDate: resolvedStart,
            endDate: resolvedEnd,
            teamMemberIds: teamIds
        )

        // Fire haptic: medium = commit beat for a series-affecting save.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        dataController.updateRecurringEvent(target, payload: payload, scope: editScope)
        viewModel.loadUserEvents()
        isSaving = false
        isPresented = false
    }

    /// Expands a base start/end date into a list of occurrences capped by:
    /// - 100 occurrences (hard ceiling)
    /// - 1 year forward from the base start (when no custom end is set)
    /// - the user-chosen `customEnd` date (when supplied)
    /// Whichever limit is reached first stops generation.
    private func expandRecurrence(
        start: Date,
        end: Date,
        frequency: RecurrenceFrequency,
        customEnd: Date?
    ) -> [(start: Date, end: Date)] {
        guard let step = frequency.step else { return [(start, end)] }

        let calendar = Calendar.current
        let oneYearForward = calendar.date(byAdding: .year, value: 1, to: start) ?? start
        let cap = customEnd.map { min($0, oneYearForward) } ?? oneYearForward

        var occurrences: [(start: Date, end: Date)] = [(start, end)]
        var currentStart = start
        var currentEnd = end

        // Hard ceiling at 100 occurrences regardless of date math, so a
        // misconfigured `customEnd` can't run away with us.
        let hardLimit = 100

        while occurrences.count < hardLimit {
            guard
                let nextStart = calendar.date(byAdding: step.component, value: step.value, to: currentStart),
                let nextEnd = calendar.date(byAdding: step.component, value: step.value, to: currentEnd)
            else { break }

            if nextStart > cap { break }

            occurrences.append((nextStart, nextEnd))
            currentStart = nextStart
            currentEnd = nextEnd
        }

        return occurrences
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
