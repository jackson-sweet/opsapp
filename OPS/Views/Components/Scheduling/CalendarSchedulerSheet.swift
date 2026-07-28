//
//  CalendarSchedulerSheet.swift
//  OPS
//
//  Picking dates for a job.
//
//  The screen answers, in this order, the three questions a person actually
//  has when they open it:
//
//    1. WHAT AM I MOVING?   — the identity line, always on screen.
//    2. WHEN IS IT FREE?    — a continuous month scroll where every day already
//                             carries its own availability: this project's
//                             work, the crew's other jobs, the crew's time off,
//                             and how early the job's prerequisites allow.
//    3. WHAT DOES THAT COST? — the day panel names the actual jobs, clients,
//                             crew, and drive distance a pick collides with.
//
//  Nothing on this screen blocks a date. A dependency floor dims; a conflict
//  gets named; time off is spelled out — and the operator still picks the day
//  the job needs, because they know something the calendar does not. The
//  signals exist to make that choice informed, not to overrule it.
//
//  There is exactly one commit point: SAVE in the sticky footer. CLEAR resets
//  the picker and never touches stored dates; removing dates from a job is an
//  explicit, separately named UNSCHEDULE.
//
//  Availability logic lives in `SchedulerDayContext` (pure, tested). This file
//  is assembly and presentation only.
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
    /// Legacy callers persist synchronously and can celebrate on confirmation.
    /// Authoritative async callers disable this and own feedback after server ACK.
    let emitsSuccessFeedbackOnConfirm: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var dataController: DataController

    // Selection + scroll state
    @State private var selection: SchedulerSelection
    @State private var visibleMonth: Date
    @State private var scrollRequest: Date?
    @State private var showMonthPicker = false
    @State private var inspectorDay: InspectorDay?
    /// Warning haptic fires once per completed conflicting range, not on every
    /// re-render of it.
    @State private var lastWarnedRange: String?

    // Availability engine — rebuilt whenever the schedule data changes.
    @State private var dayContext: SchedulerDayContext
    /// A draft task's identity comes from its task type, which lives in the
    /// store. Resolved once on load rather than re-fetched on every render.
    @State private var draftTaskTitle: String?
    @State private var draftProjectTitle: String?

    // Quick push / cascade state
    @State private var cascadeEnabled: Bool = false
    @State private var cascadePlan: DataController.CascadePlan?
    @State private var showingCascadePreview: Bool = false
    @State private var pendingPushDays: Int = 0
    @State private var pendingPushPreservesCalendarWeek: Bool = false
    @AppStorage("showCascadePreview") private var showCascadePreviewPref: Bool = true

    private let calendar = Calendar.current
    /// Monday-first, matching the Schedule tab so the two grids read the same.
    private let weekdayLabels = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    /// The month the scroll list is built around. Fixed for the life of the
    /// sheet so the lazy list's identities never churn underneath a scroll.
    private let anchorMonth: Date

    private struct InspectorDay: Identifiable {
        let id: TimeInterval
        let date: Date

        init(_ date: Date) {
            self.date = date
            self.id = date.timeIntervalSince1970
        }
    }

    // MARK: - Initialization
    init(isPresented: Binding<Bool>,
         itemType: ScheduleItemType,
         currentStartDate: Date?,
         currentEndDate: Date?,
         onScheduleUpdate: @escaping (Date, Date) -> Void,
         onClearDates: (() -> Void)? = nil,
         preselectedTeamMemberIds: Set<String>? = nil,
         emitsSuccessFeedbackOnConfirm: Bool = true) {

        self._isPresented = isPresented
        self.itemType = itemType
        self.currentStartDate = currentStartDate
        self.currentEndDate = currentEndDate
        self.onScheduleUpdate = onScheduleUpdate
        self.onClearDates = onClearDates
        self.preselectedTeamMemberIds = preselectedTeamMemberIds
        self.emitsSuccessFeedbackOnConfirm = emitsSuccessFeedbackOnConfirm

        // Reopening an already-scheduled job shows what is scheduled today, so
        // SAVE is valid immediately and the grid opens on the right weeks.
        let calendar = Calendar.current
        let seeded = SchedulerSelection.prefilled(
            start: currentStartDate,
            end: currentEndDate,
            calendar: calendar
        )
        self._selection = State(initialValue: seeded)

        let anchorDate = currentStartDate ?? Date()
        let anchor = calendar.dateInterval(of: .month, for: anchorDate)?.start ?? anchorDate
        self.anchorMonth = anchor
        self._visibleMonth = State(initialValue: anchor)

        // A placeholder context so the first frame renders a real (empty) grid
        // instead of nothing; `loadContext` replaces it from the store on appear.
        self._dayContext = State(initialValue: SchedulerDayContext(
            item: Self.baseItem(
                itemType: itemType,
                preselectedTeamMemberIds: preselectedTeamMemberIds,
                isScheduled: currentStartDate != nil
            ),
            events: []
        ))
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < OPSStyle.Layout.schedulerCompactHeightThreshold

            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    navigationBar
                    identityRow

                    rangeStrip
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.bottom, OPSStyle.Layout.spacing2)

                    if case .task = itemType, currentStartDate != nil {
                        quickPushRow
                            .padding(.bottom, OPSStyle.Layout.spacing2)
                    }

                    if let suggested = dayContext.suggestion, !selection.isCommittable {
                        suggestionChip(suggested)
                            .padding(.bottom, OPSStyle.Layout.spacing2)
                    }

                    pinnedCalendarHeader

                    SchedulerMonthScroll(
                        context: dayContext,
                        selection: selection,
                        visibleMonth: $visibleMonth,
                        scrollRequest: $scrollRequest,
                        anchorMonth: anchorMonth,
                        onTapDay: handleDayTap,
                        onLongPressDay: handleDayLongPress
                    )
                    .frame(minHeight: OPSStyle.Layout.schedulerCalendarMinHeight)

                    dayPanel
                        .frame(
                            height: isCompact
                                ? OPSStyle.Layout.schedulerDayPanelCompactHeight
                                : OPSStyle.Layout.schedulerDayPanelHeight
                        )

                    SchedulerFooterBar(
                        selection: selection,
                        onClear: handleClear,
                        onSave: handleSave
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            loadContext()
        }
        .onChange(of: dataController.scheduledTasksDidChange) { _, _ in
            loadContext()
        }
        .sheet(isPresented: $showMonthPicker) {
            MonthJumpPicker(selectedMonth: visibleMonth) { monthStart in
                scrollRequest = monthStart
            }
            .opsSheet(detents: [.medium])
        }
        .sheet(item: $inspectorDay) { day in
            SchedulerDaySheet(
                day: day.date,
                context: dayContext,
                action: selection.dayAction,
                onApply: {
                    applyDaySelection(day.date)
                }
            )
            .opsSheet(detents: [.medium])
        }
        .sheet(isPresented: $showingCascadePreview) {
            if let plan = cascadePlan, case .task(let task) = itemType {
                CascadePreviewSheet(
                    pushedTaskName: task.displayTitle,
                    pushedTaskOldStart: task.startDate,
                    pushedTaskNewStart: plan.pushedNewStart,
                    pushedTaskNewEnd: plan.pushedNewEnd,
                    cascadeChanges: plan.cascade.changes,
                    onConfirm: {
                        Task {
                            try? await dataController.pushTaskWithCascade(
                                task,
                                byDays: pendingPushDays,
                                preserveCalendarWeeks: pendingPushPreservesCalendarWeek
                            )
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

    // MARK: - Navigation bar

    private var navigationBar: some View {
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

            Text("SCHEDULE \(itemType.displayName.uppercased())")
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            // Balances the title against Cancel without adding a second exit.
            Text("Cancel")
                .font(OPSStyle.Typography.body)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .frame(height: OPSStyle.Layout.bottomCTAHeight)
    }

    // MARK: - Identity

    private var identityRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("//")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.inactiveText)

            Text(itemTitle.uppercased())
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)

            if let project = itemProjectTitle, !project.isEmpty {
                Text("· \(project.uppercased())")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Removing a job's dates is a different act from resetting the
            // picker, so it gets its own honestly-named control — and only
            // exists when there are dates to remove.
            if canUnschedule {
                Button(action: handleUnschedule) {
                    Text("UNSCHEDULE")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.rose)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.leading, OPSStyle.Layout.spacing3_5)
        .padding(.trailing, canUnschedule ? OPSStyle.Layout.spacing2 : OPSStyle.Layout.spacing3_5)
        .frame(height: OPSStyle.Layout.schedulerIdentityHeight)
    }

    // MARK: - Range strip

    private var rangeStrip: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            rangeField("START", value: selection.startDate.map { Self.weekdayDate($0) })
            rangeField("END", value: selection.endDate.map { Self.weekdayDate($0) })
            rangeField(
                "DAYS",
                value: selection.dayCount(calendar: calendar).map(String.init),
                alignment: .trailing
            )
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(height: OPSStyle.Layout.schedulerRangeStripHeight)
        .glassSurface()
    }

    private func rangeField(
        _ label: String,
        value: String?,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(value?.uppercased() ?? "—")
                .font(OPSStyle.Typography.dataValue)
                .monospacedDigit()
                .foregroundColor(value == nil ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            alignment: alignment == .trailing ? .trailing : .leading
        )
    }

    // MARK: - Suggestion

    private func suggestionChip(_ suggested: Date) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(reduceMotion ? nil : OPSStyle.Animation.fast) {
                selection = .start(calendar.startOfDay(for: suggested))
            }
            scrollRequest = calendar.dateInterval(of: .month, for: suggested)?.start
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("SUGGESTED")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tanTextM)
                Text(suggestionDetail(suggested))
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
            .frame(height: OPSStyle.Layout.schedulerSuggestionHeight)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .fill(OPSStyle.Colors.tanFillM)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .strokeBorder(OPSStyle.Colors.tanLineM, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .contentShape(Rectangle())
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .transition(.opacity)
    }

    private func suggestionDetail(_ suggested: Date) -> String {
        let date = Self.weekdayDate(suggested).uppercased()
        guard let prerequisite = dayContext.floorPrerequisiteTitle else { return date }
        return "AFTER \(prerequisite.uppercased()) · \(date)"
    }

    // MARK: - Pinned calendar header

    private var pinnedCalendarHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Text(SchedulerDayContext.monthCaption(visibleMonth, calendar: calendar))
                    .font(OPSStyle.Typography.category)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                Button {
                    showMonthPicker = true
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Text("JUMP TO")
                            .font(OPSStyle.Typography.microLabel)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Image(systemName: OPSStyle.Icons.schedule)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .frame(minHeight: OPSStyle.Layout.chipMinHeight)
                    .nestedCard()
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, OPSStyle.Layout.spacing2)

            Rectangle()
                .fill(OPSStyle.Colors.line)
                .frame(height: OPSStyle.Layout.Border.standard)

            HStack(spacing: 0) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
        .background(OPSStyle.Colors.background)
    }

    // MARK: - Day panel

    @ViewBuilder
    private var dayPanel: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Hairline floor under the scroll: without it the panel reads as
            // more empty calendar rather than a fixed report on the pick.
            Rectangle()
                .fill(OPSStyle.Colors.line)
                .frame(height: OPSStyle.Layout.Border.standard)
                .padding(.horizontal, -OPSStyle.Layout.spacing3_5)

            switch selection {
            case .none:
                emptyPanel

            case .start(let day):
                panelHeader(
                    headline: Self.weekdayDate(day).uppercased(),
                    trailing: nil,
                    trailingIsWarning: false
                )
                dayRows(for: day)

            case .range(let start, let end):
                let review = dayContext.rangeReview(start: start, end: end)
                panelHeader(
                    headline: "\(SchedulerDayContext.shortDate(start, calendar: calendar).uppercased()) – \(SchedulerDayContext.shortDate(end, calendar: calendar).uppercased())",
                    trailing: review.conflictCount == 0
                        ? "NO CONFLICTS"
                        : (review.conflictCount == 1 ? "1 CONFLICT" : "\(review.conflictCount) CONFLICTS"),
                    trailingIsWarning: review.conflictCount > 0
                )
                rangeRows(review)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : OPSStyle.Animation.fast, value: selection)
    }

    private var emptyPanel: some View {
        VStack {
            Spacer(minLength: 0)
            Text("[ TAP A START DATE ]")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.inactiveText)
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 0)
        }
    }

    private func panelHeader(headline: String, trailing: String?, trailingIsWarning: Bool) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(headline)
                .font(OPSStyle.Typography.category)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(
                        trailingIsWarning ? OPSStyle.Colors.tanTextM : OPSStyle.Colors.tertiaryText
                    )
            }
        }
    }

    @ViewBuilder
    private func dayRows(for day: Date) -> some View {
        let split = dayContext.events(on: day)
        if split.relevant.isEmpty {
            emptyDayLine
        } else {
            fadedScroll {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(split.relevant) { event in
                        eventRow(event)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rangeRows(_ review: SchedulerDayContext.RangeReview) -> some View {
        if review.rows.isEmpty && review.floorViolation == nil {
            emptyDayLine
        } else {
            fadedScroll {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    if let floor = review.floorViolation,
                       let prerequisite = dayContext.floorPrerequisiteTitle {
                        dependencyNoteRow(prerequisite: prerequisite, floor: floor)
                    }
                    ForEach(review.rows) { event in
                        eventRow(event)
                    }
                }
            }
        }
    }

    private var emptyDayLine: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("//")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.inactiveText)
            Text(dayContext.item.crewIds.isEmpty ? "NO JOBS" : "NO JOBS · CREW CLEAR")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer(minLength: 0)
        }
    }

    private func dependencyNoteRow(prerequisite: String, floor: Date) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                .fill(OPSStyle.Colors.warningStatus)
                .frame(width: OPSStyle.Layout.schedulerSignalBarHeight)
            Text("BEFORE \(prerequisite.uppercased()) ENDS · \(SchedulerDayContext.shortDate(floor, calendar: calendar).uppercased())")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tanTextM)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .fill(OPSStyle.Colors.background.opacity(0.6))
        )
    }

    private func eventRow(_ event: SchedulerDayContext.Event) -> some View {
        SchedulerEventRow(
            event: event,
            isConflict: dayContext.isConflict(event),
            isThisProject: dayContext.isSameProject(event),
            attribution: dayContext.attribution(for: event),
            distance: dayContext.distanceLabel(to: event)
        )
    }

    /// Fades the panel's top and bottom edges so a partially scrolled list
    /// reads as "there is more" instead of a clipped row.
    private func fadedScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .padding(.vertical, OPSStyle.Layout.spacing1)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Quick Push Row

    private var quickPushRow: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach([1, 2, 3], id: \.self) { days in
                    quickPushButton(label: "+\(days)", days: days)
                }
                quickPushButton(label: "+1W", days: 7, preserveCalendarWeek: true)
            }

            // Cascade toggle (only when a push could ripple the crew or dependents)
            if case .task(let task) = itemType {
                let affectedCount = cascadeAffectedCount(for: task)
                if affectedCount > 0 {
                    Toggle(isOn: $cascadeEnabled) {
                        HStack(spacing: OPSStyle.Layout.spacing1 + 2) {
                            Text("Move the crew's jobs")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Text("\(affectedCount)")
                                .font(OPSStyle.Typography.metadata)
                                .monospacedDigit()
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding(.horizontal, OPSStyle.Layout.spacing1)
                                .background(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                        .fill(OPSStyle.Colors.surfaceActive)
                                )
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.surfaceActive))
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    private func quickPushButton(
        label: String,
        days: Int,
        preserveCalendarWeek: Bool = false
    ) -> some View {
        Button(action: {
            handleQuickPush(days: days, preserveCalendarWeek: preserveCalendarWeek)
        }) {
            Text(label)
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetMin)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .fill(OPSStyle.Colors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .contentShape(Rectangle())
        }
    }

    /// Resolve the landing dates for a quick push. A week push preserves the
    /// weekday (exactly +7, never weekend-normalized); a day push uses the
    /// plain day engine so the preview matches what commits.
    private func quickPushDates(
        for task: ProjectTask,
        days: Int,
        preserveCalendarWeek: Bool
    ) -> (newStart: Date, newEnd: Date) {
        if preserveCalendarWeek {
            return SchedulingEngine.pushByCalendarWeeks(task: task, weeks: days / 7)
        }
        return SchedulingEngine.pushByDays(task: task, days: days, skipWeekends: dataController.currentCompanySkipsWeekends)
    }

    private func handleQuickPush(days: Int, preserveCalendarWeek: Bool = false) {
        guard case .task(let task) = itemType else { return }

        // With cascade on, plan the full ripple (crew + dependencies) so the
        // preview and the optimistic update match exactly what commits.
        if cascadeEnabled,
           let plan = dataController.planCascade(for: task, byDays: days, preserveCalendarWeeks: preserveCalendarWeek) {
            if showCascadePreviewPref && !plan.cascade.changes.isEmpty {
                cascadePlan = plan
                pendingPushDays = days
                pendingPushPreservesCalendarWeek = preserveCalendarWeek
                showingCascadePreview = true
            } else {
                onScheduleUpdate(plan.pushedNewStart, plan.pushedNewEnd)
                Task {
                    try? await dataController.pushTaskWithCascade(
                        task,
                        byDays: days,
                        preserveCalendarWeeks: preserveCalendarWeek
                    )
                }
                isPresented = false
            }
        } else {
            let result = quickPushDates(for: task, days: days, preserveCalendarWeek: preserveCalendarWeek)
            onScheduleUpdate(result.newStart, result.newEnd)
            isPresented = false
        }
    }

    /// Count of jobs a cascade push could ripple — same-crew jobs scheduled on
    /// or after this one (across projects), plus task-type dependents. Drives
    /// whether the cascade toggle appears and the badge it shows.
    private func cascadeAffectedCount(for task: ProjectTask) -> Int {
        let dependents = dataController.getTasksForProject(task.projectId).filter { other in
            other.id != task.id &&
            other.effectiveDependencies.contains { $0.dependsOnTaskTypeId == task.taskTypeId }
        }
        var ids = Set(dependents.map(\.id))

        let crew = task.schedulingTeamMemberIds
        if let start = task.startDate, !crew.isEmpty {
            let calendar = Calendar.current
            let anchor = calendar.startOfDay(for: start)
            for other in dataController.getActiveTasksForCompany() where other.id != task.id && !other.schedulingLocked {
                guard !other.schedulingTeamMemberIds.isDisjoint(with: crew),
                      let otherStart = other.startDate,
                      calendar.startOfDay(for: otherStart) >= anchor else { continue }
                ids.insert(other.id)
            }
        }
        return ids.count
    }

    // MARK: - Interactions

    private func handleDayTap(_ date: Date) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let next = selection.tapping(date, calendar: calendar)
        withAnimation(reduceMotion ? nil : OPSStyle.Animation.faster) {
            selection = next
        }
        warnIfRangeConflicts(next)
    }

    private func handleDayLongPress(_ date: Date) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        inspectorDay = InspectorDay(date)
    }

    private func applyDaySelection(_ date: Date) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let next = selection.tapping(date, calendar: calendar)
        withAnimation(reduceMotion ? nil : OPSStyle.Animation.faster) {
            selection = next
        }
        inspectorDay = nil
        warnIfRangeConflicts(next)
    }

    /// One warning haptic the moment a range closes on real conflicts. Silence
    /// afterwards — the panel already carries the detail, and a buzzing sheet
    /// stops meaning anything.
    private func warnIfRangeConflicts(_ next: SchedulerSelection) {
        guard case .range(let start, let end) = next else {
            lastWarnedRange = nil
            return
        }
        let key = "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)"
        guard lastWarnedRange != key else { return }
        lastWarnedRange = key
        if dayContext.rangeReview(start: start, end: end).conflictCount > 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    /// CLEAR resets the picker only. It never writes, never unschedules, and
    /// never closes the sheet — the operator asked to start over, not to leave.
    private func handleClear() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(reduceMotion ? nil : OPSStyle.Animation.fast) {
            selection = .none
        }
        lastWarnedRange = nil
    }

    private func handleSave() {
        guard case .range(let start, let end) = selection else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Async authoritative flows own the success moment after server ACK.
        // Legacy synchronous callers retain the existing immediate feedback.
        if emitsSuccessFeedbackOnConfirm {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        onScheduleUpdate(start, end)
        isPresented = false
    }

    private func handleUnschedule() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        onClearDates?()
        isPresented = false
    }

    private var canUnschedule: Bool {
        onClearDates != nil && (currentStartDate != nil || currentEndDate != nil)
    }

    // MARK: - Data

    /// Rebuilds the availability engine from the local store. Runs on appear
    /// and on every schedule republish, so the grid can never show a stale
    /// picture of who is free.
    private func loadContext() {
        resolveDraftIdentity()

        // The scroll spans ±12 months, so the data window must too — a grid
        // that silently stops carrying signals past a boundary is worse than
        // no grid at all.
        let windowStart = calendar.date(byAdding: .month, value: -12, to: anchorMonth) ?? anchorMonth
        let windowEnd = calendar.date(byAdding: .month, value: 13, to: anchorMonth) ?? anchorMonth

        let crewIds = currentItemTeamMemberIds
        let tasks = dataController.getScheduledTasks(in: windowStart...windowEnd)
        let userEvents = dataController.getUserEvents(in: windowStart...windowEnd)

        // Resolve crew names from the company roster ONCE, by id. A task's
        // `teamMembers` relationship is populated by sync's relationship
        // linking and is routinely empty on freshly fetched rows, while the
        // id CSV is always there — so a relationship-only lookup silently
        // degrades every attribution chip to a generic "CREW". Naming the
        // person is the whole point of the row.
        var rosterNames: [String: String] = [:]
        if let companyId = dataController.currentUser?.companyId {
            for member in dataController.getTeamMembers(companyId: companyId) {
                rosterNames[member.id] = member.firstName
            }
        }

        var events: [SchedulerDayContext.Event] = []
        events.reserveCapacity(tasks.count + userEvents.count)

        for task in tasks {
            guard let start = task.startDate else { continue }
            let end = task.endDate ?? start
            var firstNames: [String: String] = [:]
            for member in task.teamMembers {
                firstNames[member.id] = member.firstName
            }
            for id in task.getTeamMemberIds() where firstNames[id] == nil {
                if let name = rosterNames[id] { firstNames[id] = name }
            }
            events.append(
                SchedulerDayContext.Event(
                    id: task.id,
                    kind: .job,
                    // A bare task-type name ("Installation") identifies nothing
                    // when three jobs share it. The project does.
                    title: task.project?.title.isEmpty == false
                        ? task.project!.title
                        : task.displayTitle,
                    subtitle: task.project?.effectiveClientName,
                    taskTitle: task.displayTitle,
                    projectId: task.projectId,
                    start: start,
                    end: end,
                    crewIds: Set(task.getTeamMemberIds()),
                    crewFirstNames: firstNames,
                    latitude: task.project?.latitude,
                    longitude: task.project?.longitude
                )
            )
        }

        for event in userEvents {
            var owners = Set(event.teamMemberIds ?? [])
            owners.insert(event.userId)
            guard !owners.isEmpty else { continue }
            var firstNames: [String: String] = [:]
            for owner in owners {
                firstNames[owner] = rosterNames[owner]
                    ?? dataController.getUser(id: owner)?.firstName
                    ?? "Crew"
            }
            let headline = owners
                .compactMap { firstNames[$0] }
                .sorted()
                .first ?? "Crew"
            events.append(
                SchedulerDayContext.Event(
                    id: "userevent:\(event.id)",
                    kind: .timeOff,
                    title: headline,
                    start: event.startDate,
                    end: event.endDate,
                    crewIds: owners,
                    crewFirstNames: firstNames
                )
            )
        }

        let dependencies = resolvedDependencies()
        let prerequisites = resolvedPrerequisites(dependencies: dependencies)
        let projectCoordinate = itemCoordinate()

        let context = SchedulerDayContext(
            item: SchedulerDayContext.Item(
                selfTaskId: selfTaskId,
                projectId: itemType.projectId,
                crewIds: crewIds,
                latitude: projectCoordinate?.latitude,
                longitude: projectCoordinate?.longitude,
                dependencies: dependencies,
                isScheduled: currentStartDate != nil
            ),
            events: events,
            prerequisites: prerequisites,
            skipsWeekends: dataController.currentCompanySkipsWeekends,
            calendar: calendar
        )
        dayContext = context

        // An unscheduled job with a prerequisite opens on the first week it
        // could actually start, rather than on a today that is not an option.
        if currentStartDate == nil,
           selection == .none,
           let suggested = context.suggestion,
           let suggestedMonth = calendar.dateInterval(of: .month, for: suggested)?.start,
           !calendar.isDate(suggestedMonth, equalTo: visibleMonth, toGranularity: .month) {
            scrollRequest = suggestedMonth
        }
    }

    /// Dependencies declared by the thing being scheduled. Projects have none;
    /// a draft reads them from its task type.
    private func resolvedDependencies() -> [TaskTypeDependency] {
        switch itemType {
        case .project:
            return []
        case .task(let task):
            return task.effectiveDependencies
        case .draftTask(let taskTypeId, _, _):
            guard !taskTypeId.isEmpty else { return [] }
            let descriptor = FetchDescriptor<TaskType>(
                predicate: #Predicate<TaskType> { $0.id == taskTypeId }
            )
            return (try? modelContext.fetch(descriptor))?.first?.dependencies ?? []
        }
    }

    /// Prerequisites that are BOTH declared and already on the calendar. A
    /// prerequisite nobody has scheduled yet constrains nothing, so it is
    /// absent here — and no day gets dimmed.
    private func resolvedPrerequisites(
        dependencies: [TaskTypeDependency]
    ) -> [SchedulerDayContext.Prerequisite] {
        guard !dependencies.isEmpty, let projectId = itemType.projectId else { return [] }
        let targets = Set(dependencies.map(\.dependsOnTaskTypeId))

        return dataController.getTasksForProject(projectId).compactMap { task in
            guard task.deletedAt == nil,
                  task.status != .cancelled,
                  task.id != selfTaskId,
                  targets.contains(task.taskTypeId),
                  let start = task.startDate else { return nil }
            return SchedulerDayContext.Prerequisite(
                taskTypeId: task.taskTypeId,
                title: task.displayTitle,
                start: start,
                duration: max(task.duration, 1)
            )
        }
    }

    private func itemCoordinate() -> (latitude: Double?, longitude: Double?)? {
        switch itemType {
        case .project(let project):
            return (project.latitude, project.longitude)
        case .task(let task):
            guard let project = task.project else { return nil }
            return (project.latitude, project.longitude)
        case .draftTask(_, _, let projectId):
            guard let projectId, let project = dataController.getProject(id: projectId) else { return nil }
            return (project.latitude, project.longitude)
        }
    }

    private var selfTaskId: String? {
        if case .task(let task) = itemType { return task.id }
        return nil
    }

    /// Set of team-member ids belonging to the item currently being scheduled.
    /// Centralized so the grid, the panel, and the day inspector all reason
    /// about the same crew.
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

    private var itemTitle: String {
        switch itemType {
        case .project(let project):
            return project.title
        case .task(let task):
            return task.displayTitle
        case .draftTask:
            return draftTaskTitle ?? itemType.displayName
        }
    }

    private var itemProjectTitle: String? {
        switch itemType {
        case .project:
            return nil
        case .task(let task):
            return task.project?.title
        case .draftTask:
            return draftProjectTitle
        }
    }

    /// Resolves a draft's task-type name and project name once per load. Doing
    /// this in a computed property would fetch on every render of the identity
    /// row — the same per-render re-query that made the previous sheet stutter.
    private func resolveDraftIdentity() {
        guard case .draftTask(let taskTypeId, _, let projectId) = itemType else { return }
        if !taskTypeId.isEmpty {
            let descriptor = FetchDescriptor<TaskType>(
                predicate: #Predicate<TaskType> { $0.id == taskTypeId }
            )
            draftTaskTitle = (try? modelContext.fetch(descriptor))?.first?.display
        }
        if let projectId {
            draftProjectTitle = dataController.getProject(id: projectId)?.title
        }
    }

    // MARK: - Static helpers

    private static func baseItem(
        itemType: ScheduleItemType,
        preselectedTeamMemberIds: Set<String>?,
        isScheduled: Bool
    ) -> SchedulerDayContext.Item {
        let crew: Set<String> = {
            if let preselected = preselectedTeamMemberIds, !preselected.isEmpty { return preselected }
            switch itemType {
            case .project(let project): return Set(project.getTeamMemberIds())
            case .task(let task): return Set(task.getTeamMemberIds())
            case .draftTask(_, let teamMemberIds, _): return Set(teamMemberIds)
            }
        }()
        let selfId: String? = {
            if case .task(let task) = itemType { return task.id }
            return nil
        }()
        return SchedulerDayContext.Item(
            selfTaskId: selfId,
            projectId: itemType.projectId,
            crewIds: crew,
            dependencies: [],
            isScheduled: isScheduled
        )
    }

    static func weekdayDate(_ date: Date) -> String {
        SchedulerDayContext.weekdayDate(date)
    }

    // MARK: - Enums

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

// MARK: - Event Row

/// One named commitment. Shared by the day panel and the long-press inspector
/// so a conflict reads identically wherever the operator meets it.
///
/// A row must answer "whose job, for whom, with which of my crew, how far" —
/// a task-type name alone ("Installation") identifies nothing when three jobs
/// share it.
struct SchedulerEventRow: View {
    let event: SchedulerDayContext.Event
    let isConflict: Bool
    let isThisProject: Bool
    let attribution: String?
    let distance: String?

    private var stripeColor: Color {
        if isConflict { return OPSStyle.Colors.warningStatus }
        if isThisProject { return OPSStyle.Colors.primaryText }
        return OPSStyle.Colors.cardBorder
    }

    private var metadataLine: String {
        var parts = [SchedulerDayContext.weekdayDate(event.start).uppercased()]
        if let distance { parts.append(distance) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                .fill(stripeColor)
                .frame(width: OPSStyle.Layout.schedulerSignalBarHeight)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1 / 2) {
                // Job name first, client second — you recognise a job by the
                // project, and confirm it by the client. Mohave: these are
                // names, not data (DESIGN.md §4).
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(event.kind == .timeOff ? "\(event.title) · Time off" : event.title)
                        .font(OPSStyle.Typography.cardBody)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if event.kind == .job, let subtitle = event.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(OPSStyle.Typography.smallBody)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(0)
                    }
                    Spacer(minLength: 0)
                }
                Text(metadataLine)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            trailingChip
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .fill(OPSStyle.Colors.background.opacity(0.6))
        )
    }

    @ViewBuilder
    private var trailingChip: some View {
        if event.kind == .timeOff {
            chip("OFF", foreground: OPSStyle.Colors.tanTextM, border: OPSStyle.Colors.tanLineM)
        } else if let attribution {
            chip(attribution, foreground: OPSStyle.Colors.tanTextM, border: OPSStyle.Colors.tanLineM)
        } else if isThisProject {
            Text("THIS PROJECT")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.invertedText)
                .padding(.horizontal, OPSStyle.Layout.spacing1)
                .padding(.vertical, OPSStyle.Layout.Border.standard)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .fill(OPSStyle.Colors.primaryText)
                )
        }
    }

    private func chip(_ label: String, foreground: Color, border: Color) -> some View {
        Text(label)
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(foreground)
            .padding(.horizontal, OPSStyle.Layout.spacing1)
            .padding(.vertical, OPSStyle.Layout.Border.standard)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .strokeBorder(border, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }
}
