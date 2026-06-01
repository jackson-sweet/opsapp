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
    @Environment(\.tutorialMode) private var tutorialMode
    @EnvironmentObject private var dataController: DataController

    // Calendar state
    @State private var selectedStartDate: Date
    @State private var selectedEndDate: Date
    @State private var viewMode: ViewMode = .selecting
    @State private var currentMonth: Date = Date()
    @State private var conflictingEvents: [ProjectTask] = []
    @State private var showingConflictWarning = false

    // Filter chips — independent, multi-select. Default state depends on
    // itemType so the most useful signal is on without user effort:
    //   • project / task with crew → MY CREW + THIS PROJECT both on
    //   • draft task with crew but no project → MY CREW on
    //   • everything else → both off (show all)
    @State private var showThisProjectFilter: Bool = true
    @State private var showMyCrewFilter: Bool = true

    @State private var allScheduledTasks: [ProjectTask] = []
    @State private var filteredScheduledTasks: [ProjectTask] = []

    // Quick push / cascade state
    @State private var cascadeEnabled: Bool = false
    @State private var cascadeResult: SchedulingEngine.CascadeResult?
    @State private var showingCascadePreview: Bool = false
    @State private var pendingPushDays: Int = 0
    @AppStorage("showCascadePreview") private var showCascadePreviewPref: Bool = true

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

        // Default filter state — MY CREW / THIS PROJECT both on when the
        // itemType has both signals available. Otherwise turn off whichever
        // signal isn't applicable so the user isn't seeing a lit chip that
        // does nothing.
        let hasProject: Bool = {
            switch itemType {
            case .project: return true
            case .task: return true
            case .draftTask(_, _, let projectId): return projectId != nil
            }
        }()
        let hasCrew: Bool = {
            switch itemType {
            case .project(let project):
                if let preselected = preselectedTeamMemberIds, !preselected.isEmpty { return true }
                return !project.getTeamMemberIds().isEmpty
            case .task(let task):
                if let preselected = preselectedTeamMemberIds, !preselected.isEmpty { return true }
                return !task.getTeamMemberIds().isEmpty
            case .draftTask(_, let teamMemberIds, _):
                return !teamMemberIds.isEmpty
            }
        }()
        self._showThisProjectFilter = State(initialValue: hasProject)
        self._showMyCrewFilter = State(initialValue: hasCrew)
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

                        // Filter chips — above the grid so users actually find
                        // them. They scope which events are encoded into day
                        // cells and which appear in the day inspector below.
                        filterChipStrip

                        // Quick push bar (only for tasks with existing dates)
                        if case .task = itemType, currentStartDate != nil {
                            quickPushBar
                        }

                        // Calendar Grid
                        calendarSectionFullWidth

                        // Legend — explains the three signals so the first
                        // session reads correctly without a tutorial.
                        cellLegendStrip

                        // Day inspector — lists actual events on the focused
                        // day so the user can see WHAT is scheduled, not just
                        // that something is. Replaces the old "conflict only"
                        // warning card with an always-available detail panel.
                        dayInspectorPanel
                            .padding(.horizontal, 20)

                        // Action Button (always visible, disabled when no dates)
                        actionButtons
                            .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            loadScheduledTasks()
        }
        .sheet(isPresented: $showingCascadePreview) {
            if let cascade = cascadeResult, case .task(let task) = itemType {
                CascadePreviewSheet(
                    pushedTaskName: task.displayTitle,
                    pushedTaskOldStart: task.startDate,
                    pushedTaskNewStart: SchedulingEngine.pushByDays(task: task, days: pendingPushDays).newStart,
                    pushedTaskNewEnd: SchedulingEngine.pushByDays(task: task, days: pendingPushDays).newEnd,
                    cascadeChanges: cascade.changes,
                    onConfirm: {
                        Task {
                            try? await dataController.pushTaskWithCascade(task, byDays: pendingPushDays)
                        }
                        isPresented = false
                    },
                    onCancel: { }
                )
                .environmentObject(dataController)
                .presentationDetents([.medium])
            }
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
                        guard !tutorialMode else { return } // Disabled in tutorial mode
                        isPresented = false
                    }
                    .foregroundColor(tutorialMode ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                    .font(OPSStyle.Typography.body)
                    .allowsHitTesting(!tutorialMode)
                    .opacity(tutorialMode ? 0.5 : 1.0)

                    Spacer()

                    Text("Schedule \(itemType.displayName)")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    // Clear button — resets the in-sheet date selection AND,
                    // when dates already exist on the item, clears them on
                    // save. Bug f3604d52 — always show when onClearDates is
                    // wired so users can reset their picker mid-flow even
                    // before committing a schedule.
                    if onClearDates != nil {
                        Button {
                            handleClearDates()
                        } label: {
                            Text("Clear")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
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
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
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
                .strokeBorder(hasSelectedDates ? OPSStyle.Colors.primaryAccent.opacity(0.3) : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, 20)
        .animation(OPSStyle.Animation.fast, value: hasSelectedDates)
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

    // MARK: - Filter Chip Strip
    //
    // Two independent chips above the calendar. Tapping toggles each on/off.
    // Both off = "show everything," which is the most permissive filter.
    // Multi-select (not mutually exclusive) so the user can see e.g. tasks
    // that match either project OR crew at the same time.
    private var filterChipStrip: some View {
        let projectChipEnabled = itemType.projectId != nil
        let crewChipEnabled = !currentItemTeamMemberIds.isEmpty

        return HStack(spacing: OPSStyle.Layout.spacing2) {
            filterChip(
                label: "THIS PROJECT",
                icon: OPSStyle.Icons.taskType,
                isActive: showThisProjectFilter,
                isEnabled: projectChipEnabled,
                onTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showThisProjectFilter.toggle()
                    filterScheduledTasks()
                }
            )

            filterChip(
                label: "MY CREW",
                icon: OPSStyle.Icons.crew,
                isActive: showMyCrewFilter,
                isEnabled: crewChipEnabled,
                onTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showMyCrewFilter.toggle()
                    filterScheduledTasks()
                }
            )

            Spacer(minLength: 0)

            // Live count of visible events in the current window — confirms
            // filters actually do something and gives the user a sense of
            // density before they start tapping days.
            Text("\(filteredScheduledTasks.count)")
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.primaryText)
            +
            Text(" SHOWN")
                .font(OPSStyle.Typography.category)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    private func filterChip(
        label: String,
        icon: String,
        isActive: Bool,
        isEnabled: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: { if isEnabled { onTap() } }) {
            HStack(spacing: OPSStyle.Layout.spacing1 + 2) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                Text(label)
                    .font(OPSStyle.Typography.category)
            }
            .foregroundColor(
                !isEnabled ? OPSStyle.Colors.tertiaryText.opacity(0.4)
                : isActive ? OPSStyle.Colors.invertedText
                : OPSStyle.Colors.primaryText
            )
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .fill(isActive ? OPSStyle.Colors.primaryText : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .strokeBorder(
                        !isEnabled ? OPSStyle.Colors.cardBorderSubtle
                        : isActive ? Color.clear
                        : OPSStyle.Colors.cardBorder,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
            .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
    }

    // MARK: - Cell Legend Strip
    //
    // Three tiny inline samples that explain the cell encoding. Kept compact
    // so first-time readers can decode the grid without a tour. Hidden in the
    // tutorial flow because the tutorial has its own onboarding overlay.
    private var cellLegendStrip: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            legendItem(swatch: AnyView(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .fill(OPSStyle.Colors.primaryText)
                    .frame(width: 2, height: 16)
            ), label: "PROJECT")

            legendItem(swatch: AnyView(
                Text("3")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                    .padding(.horizontal, OPSStyle.Layout.spacing1)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                            .strokeBorder(OPSStyle.Colors.warningStatus.opacity(0.6), lineWidth: OPSStyle.Layout.Border.standard)
                    )
            ), label: "CONFLICT")

            legendItem(swatch: AnyView(
                HStack(spacing: OPSStyle.Layout.spacing1 / 2) {
                    Circle().fill(OPSStyle.Colors.primaryAccent).frame(
                        width: OPSStyle.Layout.Indicator.dotSM,
                        height: OPSStyle.Layout.Indicator.dotSM
                    )
                    Circle().fill(OPSStyle.Colors.successStatus).frame(
                        width: OPSStyle.Layout.Indicator.dotSM,
                        height: OPSStyle.Layout.Indicator.dotSM
                    )
                }
            ), label: "CREW")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .opacity(0.85)
    }

    private func legendItem(swatch: AnyView, label: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            swatch
                .frame(minWidth: OPSStyle.Layout.IconSize.xs, alignment: .center)
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    // MARK: - Day Inspector Panel
    //
    // Shows the real list of events on the currently focused day. When a
    // single day is selected we show that day's events; when a range is
    // selected we show events grouped by day across the range. Replaces the
    // old "only on conflict" warning card with a panel that's useful during
    // exploration, not just after committing.
    @ViewBuilder
    private var dayInspectorPanel: some View {
        let focused = inspectorEvents()
        if !focused.events.isEmpty {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(focused.headline)
                        .font(OPSStyle.Typography.category)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Text("\(focused.events.count)")
                        .font(OPSStyle.Typography.dataValue)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    +
                    Text(focused.events.count == 1 ? " EVENT" : " EVENTS")
                        .font(OPSStyle.Typography.category)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(focused.events.prefix(5)) { task in
                        dayInspectorRow(task: task)
                    }
                    if focused.events.count > 5 {
                        Text("+ \(focused.events.count - 5) MORE")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        } else {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("//")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.inactiveText)
                Text("NO EVENTS · \(focused.headline.uppercased())")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .strokeBorder(OPSStyle.Colors.cardBorderSubtle, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    private func dayInspectorRow(task: ProjectTask) -> some View {
        let isSameProject = (task.projectId == itemType.projectId) && itemType.projectId != nil
        let isCrewConflict = !Set(task.getTeamMemberIds()).isDisjoint(with: currentItemTeamMemberIds)
        let dayLabel: String = {
            if let start = task.startDate {
                return formatDate(start, short: true)
            }
            return "—"
        }()

        return HStack(spacing: OPSStyle.Layout.spacing2_5) {
            // Left stripe: white if same project, task color otherwise.
            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                .fill(isSameProject ? OPSStyle.Colors.primaryText : task.swiftUIColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(task.displayTitle)
                        .font(OPSStyle.Typography.cardSubtitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    if isSameProject {
                        Text("THIS PROJECT")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.invertedText)
                            .padding(.horizontal, OPSStyle.Layout.spacing1)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                    .fill(OPSStyle.Colors.primaryText)
                            )
                    }
                }
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(dayLabel.uppercased())
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    if !task.teamMembers.isEmpty {
                        Text("·")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.inactiveText)
                        HStack(spacing: OPSStyle.Layout.spacing1 / 2) {
                            ForEach(task.teamMembers.prefix(4)) { user in
                                Circle()
                                    .fill(colorFor(user: user))
                                    .frame(
                                        width: OPSStyle.Layout.Indicator.dotMD - 1,
                                        height: OPSStyle.Layout.Indicator.dotMD - 1
                                    )
                            }
                            if task.teamMembers.count > 4 {
                                Text("+\(task.teamMembers.count - 4)")
                                    .font(OPSStyle.Typography.metadata)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if isCrewConflict {
                Text("CONFLICT")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                    .padding(.horizontal, OPSStyle.Layout.spacing1)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                            .strokeBorder(OPSStyle.Colors.warningStatus.opacity(0.6), lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .fill(OPSStyle.Colors.background.opacity(0.6))
        )
    }

    private struct InspectorContext {
        let headline: String
        let events: [ProjectTask]
    }

    private func inspectorEvents() -> InspectorContext {
        switch viewMode {
        case .selecting:
            // Single tapped day — show that day's events.
            let events = filteredScheduledTasks.filter { task in
                task.spannedDates.contains { Calendar.current.isDate($0, inSameDayAs: selectedStartDate) }
            }
            return InspectorContext(
                headline: formatDate(selectedStartDate),
                events: events.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            )
        case .reviewing:
            // Range selected — show all events overlapping the range.
            let range = selectedStartDate...selectedEndDate
            let events = filteredScheduledTasks.filter { task in
                guard let s = task.startDate, let e = task.endDate else { return false }
                return (s...e).overlaps(range)
            }
            let days = daysBetween(selectedStartDate, selectedEndDate)
            let headline = "\(formatDate(selectedStartDate, short: true).uppercased()) – \(formatDate(selectedEndDate, short: true).uppercased())  \(days)D"
            return InspectorContext(
                headline: headline,
                events: events.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            )
        }
    }

    // MARK: - Month Navigation
    private var monthNavigationView: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
            }

            Spacer()

            Text(monthYearString(from: currentMonth))
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
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
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(daysInMonth(), id: \.self) { date in
                let visibleEvents = getEventsForDate(date)
                SchedulerDayCell(
                    date: date,
                    isInCurrentMonth: isInCurrentMonth(date),
                    eventCount: visibleEvents.count,
                    isThisProjectDay: isThisProjectDay(on: date, in: visibleEvents),
                    crewColors: crewColorsForDate(visibleEvents),
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
                                    .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                    }

                    Button(action: handleConfirmSchedule) {
                        Text("CONFIRM ANYWAY")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(OPSStyle.Colors.primaryText)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
            } else {
                // Single confirm button (disabled when no dates selected)
                Button(action: handleConfirmSchedule) {
                    Text("CONFIRM DATES")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(hasSelectedDates ? OPSStyle.Colors.invertedText : OPSStyle.Colors.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(hasSelectedDates ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .strokeBorder(hasSelectedDates ? Color.clear : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                .disabled(!hasSelectedDates)
            }
        }
        .animation(OPSStyle.Animation.fast, value: hasSelectedDates)
    }

    // MARK: - Quick Push Bar

    private var quickPushBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach([1, 2, 3], id: \.self) { days in
                    quickPushButton(label: "+\(days)", days: days)
                }
                quickPushButton(label: "+1W", days: 7)
            }

            // Cascade toggle (only for tasks with dependents)
            if case .task(let task) = itemType {
                let dependentCount = countDependentTasks(for: task)
                if dependentCount > 0 {
                    HStack {
                        Toggle(isOn: $cascadeEnabled) {
                            HStack(spacing: 6) {
                                Text("Push dependent tasks")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                Text("\(dependentCount)")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(OPSStyle.Colors.primaryAccent)
                                    .cornerRadius(8)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.text))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func quickPushButton(label: String, days: Int) -> some View {
        Button(action: {
            handleQuickPush(days: days)
        }) {
            Text(label)
                .font(OPSStyle.Typography.button)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(OPSStyle.Colors.primaryAccent)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        }
    }

    private func handleQuickPush(days: Int) {
        guard case .task(let task) = itemType else { return }

        let result = SchedulingEngine.pushByDays(task: task, days: days)

        if cascadeEnabled {
            let allTasks = dataController.getTasksForProject(task.projectId)
            let cascade = SchedulingEngine.calculateCascade(
                pushedTaskId: task.id,
                newStartDate: result.newStart,
                newEndDate: result.newEnd,
                allProjectTasks: allTasks
            )

            if showCascadePreviewPref && !cascade.changes.isEmpty {
                cascadeResult = cascade
                pendingPushDays = days
                showingCascadePreview = true
            } else {
                onScheduleUpdate(result.newStart, result.newEnd)
                Task {
                    try? await dataController.pushTaskWithCascade(task, byDays: days)
                }
                isPresented = false
            }
        } else {
            onScheduleUpdate(result.newStart, result.newEnd)
            isPresented = false
        }
    }

    private func countDependentTasks(for task: ProjectTask) -> Int {
        let allTasks = dataController.getTasksForProject(task.projectId)
        return allTasks.filter { other in
            other.id != task.id &&
            other.effectiveDependencies.contains { $0.dependsOnTaskTypeId == task.taskTypeId }
        }.count
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

    private func getEventsForDate(_ date: Date) -> [ProjectTask] {
        filteredScheduledTasks.filter { task in
            task.spannedDates.contains { Calendar.current.isDate($0, inSameDayAs: date) }
        }
    }

    /// True when at least one of the visible events on `date` belongs to the
    /// current item's project. Powers the left-edge "this project" stripe on
    /// the day cell.
    private func isThisProjectDay(on date: Date, in events: [ProjectTask]) -> Bool {
        guard let pid = itemType.projectId else { return false }
        // Exclude the current task itself when editing — a task's own dates
        // are already shown via the selection chrome and shouldn't double up
        // as a "same project" signal.
        let selfId: String? = {
            if case .task(let t) = itemType { return t.id }
            return nil
        }()
        return events.contains { task in
            task.projectId == pid && task.id != selfId
        }
    }

    /// Distinct crew-member colors for the visible events on a day, scoped to
    /// crew that overlaps with the current item's assigned crew. Empty array
    /// when no crew context exists (e.g. draft with no assignees).
    private func crewColorsForDate(_ events: [ProjectTask]) -> [Color] {
        let myCrew = currentItemTeamMemberIds
        guard !myCrew.isEmpty else { return [] }

        var seen = Set<String>()
        var colors: [Color] = []
        for task in events {
            for user in task.teamMembers where myCrew.contains(user.id) {
                if seen.insert(user.id).inserted {
                    colors.append(colorFor(user: user))
                }
            }
        }
        return colors
    }

    private func colorFor(user: User) -> Color {
        if let hex = user.userColor, !hex.isEmpty, let color = Color(hex: hex) {
            return color
        }
        return user.roleColor
    }

    /// Set of team-member ids belonging to the item currently being scheduled.
    /// Centralized so the filter chips, the day cell, and the inspector panel
    /// all reason about the same crew.
    private var currentItemTeamMemberIds: Set<String> {
        if let preselected = preselectedTeamMemberIds, !preselected.isEmpty {
            return preselected
        }
        switch itemType {
        case .project(let project): return Set(project.getTeamMemberIds())
        case .task(let task): return Set(task.getTeamMemberIds())
        case .draftTask(_, let teamMemberIds, _): return Set(teamMemberIds)
        }
    }

    private func hasConflicts(on date: Date) -> Bool {
        guard viewMode == .reviewing else { return false }
        return conflictingEvents.contains { task in
            task.spannedDates.contains { Calendar.current.isDate($0, inSameDayAs: date) }
        }
    }

    private func hasTeamConflicts(on date: Date) -> Bool {
        let myCrew = currentItemTeamMemberIds
        guard !myCrew.isEmpty else { return false }

        return filteredScheduledTasks.contains { scheduledTask in
            let isSameItem: Bool
            switch itemType {
            case .project: isSameItem = false
            case .task(let task): isSameItem = scheduledTask.id == task.id
            case .draftTask: isSameItem = false
            }
            guard !isSameItem else { return false }
            guard scheduledTask.spannedDates.contains(where: { Calendar.current.isDate($0, inSameDayAs: date) }) else { return false }
            return !Set(scheduledTask.getTeamMemberIds()).isDisjoint(with: myCrew)
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

    private func loadScheduledTasks() {
        // Load all scheduled tasks in the date range
        let calendar = Calendar.current
        let searchStart = calendar.date(byAdding: .month, value: -3, to: selectedStartDate) ?? selectedStartDate
        let searchEnd = calendar.date(byAdding: .month, value: 3, to: selectedEndDate) ?? selectedEndDate

        // Use optimized range query
        allScheduledTasks = dataController.getScheduledTasks(in: searchStart...searchEnd)

        // Filter tasks
        filterScheduledTasks()
    }

    private func filterScheduledTasks() {
        // Exclude the current task itself from the visible set — its dates
        // are already shown via the selection chrome and shouldn't pollute
        // counts or appear in the day inspector.
        let selfId: String? = {
            if case .task(let task) = itemType { return task.id }
            return nil
        }()
        let pool = allScheduledTasks.filter { task in
            if let id = selfId, task.id == id { return false }
            return true
        }

        // Both filters off → show everything in the loaded window.
        if !showThisProjectFilter && !showMyCrewFilter {
            filteredScheduledTasks = pool
            return
        }

        let projectId = itemType.projectId
        let myCrew = currentItemTeamMemberIds

        // Additive (OR) — a task is visible if it matches any lit chip.
        filteredScheduledTasks = pool.filter { task in
            if showThisProjectFilter, let pid = projectId, task.projectId == pid {
                return true
            }
            if showMyCrewFilter, !myCrew.isEmpty {
                let taskCrew = Set(task.getTeamMemberIds())
                if !taskCrew.isDisjoint(with: myCrew) {
                    return true
                }
            }
            return false
        }
    }

    private func checkForConflicts() {
        // Conflict review uses the visible (filtered) set so the conflict
        // card aligns with what the user is looking at in the grid.
        conflictingEvents = filteredScheduledTasks.filter { scheduledTask in
            let isSameItem: Bool
            switch itemType {
            case .project:
                isSameItem = false
            case .task(let task):
                isSameItem = scheduledTask.id == task.id
            case .draftTask:
                isSameItem = false
            }

            // Check for date overlap
            if !isSameItem, let taskStart = scheduledTask.startDate, let taskEnd = scheduledTask.endDate {
                let taskRange = taskStart...taskEnd
                let selectedRange = selectedStartDate...selectedEndDate
                return taskRange.overlaps(selectedRange)
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
        // Bug f3604d52 — Clear resets both the in-sheet picker state AND
        // (if the item already has dates persisted) fires onClearDates so
        // the caller can strip them. When no dates are persisted yet the
        // picker just resets and the sheet closes without a write.

        // Light haptic on tap (reset is not destructive — user is just
        // undoing their in-progress selection).
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Reset the in-sheet picker back to a neutral default so if the
        // sheet reopens without closing, the stale selection is gone.
        let today = Date()
        selectedStartDate = today
        selectedEndDate = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        viewMode = .selecting
        conflictingEvents = []

        // If the item currently has persisted dates, warn via success
        // haptic (the clear will mutate the stored record) and propagate.
        if currentStartDate != nil || currentEndDate != nil {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            onClearDates?()
        }
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
//
// Encodes three independent signals into a 56pt-tall cell:
//
//   1. THIS PROJECT — 2px white stripe on the LEFT edge, present when at
//      least one visible event on this day belongs to the item's project.
//      Reads as a primary "ownership" marker without diluting the steel-blue
//      accent (which is reserved for CTAs and focus rings per OPS spec v2).
//
//   2. EVENT COUNT — tabular count chip in the TOP-RIGHT corner. Outlined in
//      a hairline when there are events; fills in tan when there's a crew
//      conflict on this day. Empty days show no chip (consistent with the
//      "empty = nothing" convention; the design system reserves "—" for
//      empty inline values, not for empty grid cells).
//
//   3. CREW BUSY — up to 3 small dots along the BOTTOM, each in the user's
//      `userColor` (or role color fallback). Tells the user WHO is busy on
//      this day, not just that something is. `+N` overflow chip past 3.
//
// Selection chrome (start/end/range/today) overlays on top of these signals
// and uses different visual channels (border vs fill) so the encodings stay
// readable when a day is also selected.
//
private struct SchedulerDayCell: View {
    let date: Date
    let isInCurrentMonth: Bool
    let eventCount: Int
    let isThisProjectDay: Bool
    let crewColors: [Color]
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
            ZStack(alignment: .topLeading) {
                // TODAY indicator — hairline accent ring, not a fill. The
                // OPS spec reserves steel-blue for "primary CTA + focus ring
                // ONLY" so an outline reads as a focus marker, not a CTA.
                if isToday && !isStartDate && !isEndDate && !isInRange {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .strokeBorder(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.standard)
                }

                // THIS PROJECT stripe — 2pt white bar on the leading edge.
                if isThisProjectDay && isInCurrentMonth {
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                            .fill(OPSStyle.Colors.primaryText)
                            .frame(width: 2)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                        Spacer(minLength: 0)
                    }
                }

                // Day number — JetBrains Mono per OPS rule "Numbers are
                // always mono, tabular-lining, slashed zero." Mohave is for
                // body and hero numbers; calendar day numbers are data.
                VStack(alignment: .leading, spacing: 0) {
                    Text(dayNumber)
                        .font(OPSStyle.Typography.dataValue)
                        .foregroundColor(textColor)
                    Spacer(minLength: 0)
                }
                .padding(.leading, OPSStyle.Layout.spacing2)
                .padding(.top, OPSStyle.Layout.spacing2)

                // Event count chip — top-right.
                if eventCount > 0 && isInCurrentMonth {
                    VStack {
                        HStack {
                            Spacer(minLength: 0)
                            countChip
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.trailing, OPSStyle.Layout.spacing1)
                    .padding(.top, OPSStyle.Layout.spacing1)
                }

                // Crew dots — bottom row. Token-correct dot diameter.
                if !crewColors.isEmpty && isInCurrentMonth {
                    VStack {
                        Spacer(minLength: 0)
                        HStack(spacing: OPSStyle.Layout.spacing1 / 2) {
                            ForEach(Array(crewColors.prefix(3).enumerated()), id: \.offset) { _, color in
                                Circle()
                                    .fill(color)
                                    .frame(
                                        width: OPSStyle.Layout.Indicator.dotSM,
                                        height: OPSStyle.Layout.Indicator.dotSM
                                    )
                            }
                            if crewColors.count > 3 {
                                Text("+\(crewColors.count - 3)")
                                    .font(OPSStyle.Typography.metadata)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        }
                    }
                    .padding(.bottom, OPSStyle.Layout.spacing1)
                }

                // Selection chrome — drawn ON TOP so it stays the dominant
                // signal whenever a date is part of the user's pick.
                selectionOverlay
                    .animation(OPSStyle.Animation.faster, value: isStartDate)
                    .animation(OPSStyle.Animation.faster, value: isEndDate)
                    .animation(OPSStyle.Animation.faster, value: isInRange)

                // Conflict halo in reviewing mode — tan ring on dates that
                // overlap the picked range.
                if hasConflicts {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .strokeBorder(OPSStyle.Colors.warningStatus.opacity(0.5), lineWidth: OPSStyle.Layout.Border.thick)
                        .padding(OPSStyle.Layout.Border.thick)
                }
            }
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .disabled(!isInCurrentMonth)
    }

    private var countChip: some View {
        let conflict = hasTeamConflicts && !isStartDate && !isEndDate && !isInRange
        let fg = conflict ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.secondaryText
        let border = conflict ? OPSStyle.Colors.warningStatus.opacity(0.6) : OPSStyle.Colors.cardBorder
        return Text("\(eventCount)")
            .font(OPSStyle.Typography.metadata)
            .monospacedDigit()
            .foregroundColor(fg)
            .padding(.horizontal, OPSStyle.Layout.spacing1)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .strokeBorder(border, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        Group {
            if isStartDate && isEndDate {
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .strokeBorder(OPSStyle.Colors.primaryText, lineWidth: OPSStyle.Layout.Border.thick)
            } else if isStartDate {
                UnevenRoundedRectangle(
                    topLeadingRadius: OPSStyle.Layout.cardCornerRadius,
                    bottomLeadingRadius: OPSStyle.Layout.cardCornerRadius,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                )
                .strokeBorder(OPSStyle.Colors.primaryText, lineWidth: OPSStyle.Layout.Border.thick)
            } else if isEndDate {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: OPSStyle.Layout.cardCornerRadius,
                    topTrailingRadius: OPSStyle.Layout.cardCornerRadius
                )
                .strokeBorder(OPSStyle.Colors.primaryText, lineWidth: OPSStyle.Layout.Border.thick)
            } else if isInRange {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(OPSStyle.Colors.primaryText)
                        .frame(height: OPSStyle.Layout.Border.thick)
                    Spacer()
                    Rectangle()
                        .fill(OPSStyle.Colors.primaryText)
                        .frame(height: OPSStyle.Layout.Border.thick)
                }
            }
        }
        .opacity(isStartDate || isEndDate || isInRange ? 1 : 0)
    }

    private var textColor: Color {
        if !isInCurrentMonth {
            return OPSStyle.Colors.tertiaryText.opacity(0.3)
        }
        // Today's day number wears the accent foreground to pair with the
        // hairline accent ring around the cell — only when not part of an
        // active selection (selection chrome takes priority).
        if isToday && !isStartDate && !isEndDate && !isInRange {
            return OPSStyle.Colors.primaryAccent
        }
        return OPSStyle.Colors.primaryText
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
