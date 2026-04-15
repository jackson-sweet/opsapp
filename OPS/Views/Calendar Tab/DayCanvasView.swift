//
//  DayCanvasView.swift
//  OPS
//
//  Horizontal day pager — swipe left/right to navigate days.
//  Uses ScrollView + LazyHStack with native paging for glitch-free navigation.
//

import SwiftUI
import SwiftData

struct DayCanvasView: View {
    @ObservedObject var viewModel: CalendarViewModel

    @State private var scrollPosition: Int? = 0
    @State private var isExternalNavigation = false

    /// Reference date for computing day offsets (start of today when the type loads)
    private static let referenceDate: Date = Calendar.current.startOfDay(for: Date())
    /// Pre-computed offset array — ~3 months each direction
    private static let dayOffsets: [Int] = Array(-90...90)

    private func date(for offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Self.referenceDate)!
    }

    private func offset(for date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Self.referenceDate,
                                        to: Calendar.current.startOfDay(for: date)).day ?? 0
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Self.dayOffsets, id: \.self) { dayOffset in
                    DayPageView(
                        date: date(for: dayOffset),
                        viewModel: viewModel,
                        isActivePage: dayOffset == (scrollPosition ?? 0)
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(dayOffset)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrollPosition)
        .scrollIndicators(.hidden)
        .onAppear {
            let target = offset(for: viewModel.selectedDate)
            if target != scrollPosition {
                scrollPosition = target
            }
        }
        // User swiped to a new day
        .onChange(of: scrollPosition) { _, newOffset in
            guard let newOffset, !isExternalNavigation else { return }
            viewModel.selectDate(date(for: newOffset), userInitiated: true)
        }
        // External navigation (week strip tap, month grid tap, etc.)
        .onChange(of: viewModel.selectedDate) { _, newDate in
            let target = offset(for: newDate)
            guard target != scrollPosition else { return }
            isExternalNavigation = true
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                scrollPosition = target
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isExternalNavigation = false
            }
        }
    }
}

// MARK: - Single Day Page

struct DayPageView: View {
    let date: Date
    @ObservedObject var viewModel: CalendarViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataController: DataController
    let isActivePage: Bool

    /// Lightweight wrapper for unified task iteration (nil task = spacer for alignment).
    /// Multi-day entries use "slot-N" IDs so all pages share the same ID space
    /// for cross-page scroll sync.
    private struct TaskEntry: Identifiable {
        let task: ProjectTask?
        let isOngoing: Bool
        let slot: Int
        var id: String {
            if slot >= 0 { return "slot-\(slot)" }
            return task?.id ?? UUID().uuidString
        }
        var isSpacer: Bool { task == nil }
    }

    /// Unified task list using window-independent slot-packing so multi-day
    /// tasks maintain the exact same vertical position on every day they span.
    ///
    /// Key difference from earlier approach: sort and overlap checks use
    /// ABSOLUTE dates (not window-relative indices), making the slot assignment
    /// deterministic regardless of which day's window we compute from.
    private var unifiedTasks: [TaskEntry] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)

        // --- Gather all multi-day tasks in a ±7-day window ---
        var processedIds = Set<String>()
        var multiDayTasks: [ProjectTask] = []

        for offset in -7...7 {
            guard let wd = cal.date(byAdding: .day, value: offset, to: dayStart) else { continue }
            for task in viewModel.scheduledTasks(for: cal.startOfDay(for: wd)) {
                guard !processedIds.contains(task.id) else { continue }
                processedIds.insert(task.id)

                let start = cal.startOfDay(for: task.startDate ?? Date.distantPast)
                let end = cal.startOfDay(for: task.endDate ?? start)
                guard start != end else { continue }  // skip single-day
                multiDayTasks.append(task)
            }
        }

        // --- Deterministic sort using ABSOLUTE dates (not window-relative) ---
        multiDayTasks.sort { a, b in
            let aStart = cal.startOfDay(for: a.startDate ?? Date.distantPast)
            let aEnd = cal.startOfDay(for: a.endDate ?? aStart)
            let bStart = cal.startOfDay(for: b.startDate ?? Date.distantPast)
            let bEnd = cal.startOfDay(for: b.endDate ?? bStart)

            let aSpan = cal.dateComponents([.day], from: aStart, to: aEnd).day ?? 0
            let bSpan = cal.dateComponents([.day], from: bStart, to: bEnd).day ?? 0

            if aSpan != bSpan { return aSpan > bSpan }
            if aStart != bStart { return aStart < bStart }
            return a.id < b.id
        }

        // --- Greedy slot packing using actual date-range overlap ---
        // This is window-independent: two tasks conflict iff their date ranges intersect.
        let maxSlots = 20
        var taskSlot: [String: Int] = [:]
        var slotRanges: [Int: [(start: Date, end: Date)]] = [:]

        for task in multiDayTasks {
            let taskStart = cal.startOfDay(for: task.startDate ?? Date.distantPast)
            let taskEnd = cal.startOfDay(for: task.endDate ?? taskStart)

            for slot in 0..<maxSlots {
                let ranges = slotRanges[slot] ?? []
                let hasConflict = ranges.contains { taskStart <= $0.end && $0.start <= taskEnd }
                if !hasConflict {
                    taskSlot[task.id] = slot
                    slotRanges[slot, default: []].append((start: taskStart, end: taskEnd))
                    break
                }
            }
        }

        // --- Assemble today's list with spacers for empty slots ---
        let todayTaskIds = Set(tasksForDate.map { $0.id })

        var slottedTasks: [Int: ProjectTask] = [:]
        for task in multiDayTasks {
            guard todayTaskIds.contains(task.id),
                  let slot = taskSlot[task.id] else { continue }
            slottedTasks[slot] = task
        }

        let maxSlotToday = slottedTasks.keys.max() ?? -1

        var multiDayEntries: [TaskEntry] = []
        if maxSlotToday >= 0 {
            for slot in 0...maxSlotToday {
                if let task = slottedTasks[slot] {
                    let start = cal.startOfDay(for: task.startDate ?? Date.distantPast)
                    multiDayEntries.append(TaskEntry(task: task, isOngoing: start != dayStart, slot: slot))
                } else {
                    multiDayEntries.append(TaskEntry(task: nil, isOngoing: false, slot: slot))
                }
            }
        }

        // Single-day tasks after multi-day, sorted by start date then ID
        let multiDayIds = Set(multiDayTasks.map { $0.id })
        let singleDayEntries = tasksForDate
            .filter { !multiDayIds.contains($0.id) }
            .sorted { a, b in
                let aStart = a.startDate ?? Date.distantPast
                let bStart = b.startDate ?? Date.distantPast
                if aStart != bStart { return aStart < bStart }
                return a.id < b.id
            }
            .map { TaskEntry(task: $0, isOngoing: false, slot: -1) }

        return multiDayEntries + singleDayEntries
    }

    // Multi-select state
    @State private var isSelectMode = false
    @State private var selectedTaskIds: Set<String> = []

    // Push / cascade state
    @State private var showingCascadePreview = false
    @State private var pendingCascade: SchedulingEngine.CascadeResult?
    @State private var pendingTask: ProjectTask?
    @State private var pendingDays: Int = 0
    @State private var swipeOffset: [String: CGFloat] = [:]
    @AppStorage("showCascadePreview") private var showCascadePreviewPref = true
    @State private var showingScheduler = false

    private var tasksForDate: [ProjectTask] {
        viewModel.scheduledTasks(for: date)
    }

    /// Resolves the single selected task ID to a ProjectTask (for scheduler sheet)
    private var selectedTaskForScheduler: ProjectTask? {
        guard selectedTaskIds.count == 1, let taskId = selectedTaskIds.first else { return nil }
        return tasksForDate.first { $0.id == taskId }
    }

    private var userEventsForDate: [CalendarUserEvent] {
        viewModel.userEvents(for: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Day header (pinned above scroll)
            dayHeader
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

            // Scrollable task list
            if tasksForDate.isEmpty && userEventsForDate.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // Unified task list — multi-day tasks maintain stable vertical
                            // positions across days for seamless cross-day card connection.
                            // Empty slots get invisible spacers to preserve alignment.
                            ForEach(Array(unifiedTasks.enumerated()), id: \.element.id) { index, entry in
                                if entry.isSpacer {
                                    // Invisible spacer matching card height (64) + vertical padding (8)
                                    Color.clear
                                        .frame(height: 72)
                                        .id(entry.id)
                                } else if let task = entry.task {
                                    taskRow(task: task, isOngoing: entry.isOngoing, isFirst: index == 0)
                                        .id(entry.id)
                                }
                            }

                            // User events (personal + time off)
                            ForEach(userEventsForDate) { event in
                                CalendarUserEventCard(
                                    event: event,
                                    onTap: { /* future: open event detail */ },
                                    onDelete: { deleteUserEvent(event) }
                                )
                            }
                        }
                        .padding(.bottom, 100) // tab bar clearance
                        // Track scroll offset on the active page
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: DayScrollOffsetKey.self,
                                    value: geo.frame(in: .named("dayScroll")).minY
                                )
                            }
                        )
                    }
                    .coordinateSpace(name: "dayScroll")
                    // Active page: convert pixel offset to slot ID, push to viewModel
                    .onPreferenceChange(DayScrollOffsetKey.self) { offset in
                        if isActivePage {
                            let slot = max(0, Int(-offset / 72))
                            let slotId = "slot-\(slot)"
                            if viewModel.dayScrollAnchor != slotId {
                                viewModel.dayScrollAnchor = slotId
                            }
                        }
                    }
                    // Non-active pages: mirror the shared scroll position
                    .onChange(of: viewModel.dayScrollAnchor) { _, anchor in
                        if !isActivePage, let anchor {
                            proxy.scrollTo(anchor, anchor: .top)
                        }
                    }
                    // When page first appears, sync to shared position
                    .onAppear {
                        if let shared = viewModel.dayScrollAnchor {
                            proxy.scrollTo(shared, anchor: .top)
                        }
                    }
                    // Wizard: scroll to the active target when a new step activates
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardScrollToTarget"))) { notification in
                        if let stepId = notification.userInfo?["stepId"] as? String {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo("wizard_active_\(stepId)", anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            bulkActionBar
        }
        .sheet(isPresented: $showingScheduler) {
            if let task = selectedTaskForScheduler {
                CalendarSchedulerSheet(
                    isPresented: $showingScheduler,
                    itemType: .task(task),
                    currentStartDate: task.startDate,
                    currentEndDate: task.endDate,
                    onScheduleUpdate: { newStart, newEnd in
                        Task {
                            try? await dataController.updateTaskSchedule(task: task, startDate: newStart, endDate: newEnd)
                        }
                        exitSelectMode()
                    }
                )
                .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingCascadePreview) {
            if let cascade = pendingCascade, let task = pendingTask {
                CascadePreviewSheet(
                    pushedTaskName: task.displayTitle,
                    pushedTaskOldStart: task.startDate,
                    pushedTaskNewStart: SchedulingEngine.pushByDays(task: task, days: pendingDays).newStart,
                    pushedTaskNewEnd: SchedulingEngine.pushByDays(task: task, days: pendingDays).newEnd,
                    cascadeChanges: cascade.changes,
                    onConfirm: {
                        Task {
                            try? await dataController.pushTaskWithCascade(task, byDays: pendingDays)
                        }
                    },
                    onCancel: { }
                )
                .environmentObject(dataController)
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Task Row

    @ViewBuilder
    private func taskRow(task: ProjectTask, isOngoing: Bool, isFirst: Bool) -> some View {
        let card = CalendarEventCard(
            task: task,
            isFirst: isFirst,
            isOngoing: isOngoing,
            dayPosition: dayPosition(for: task, on: date),
            showLabels: true,
            onTap: {
                if isSelectMode {
                    toggleSelection(task.id)
                } else {
                    handleTaskTap(task)
                }
            }
        )
        .wizardTarget("tap_task")
        .overlay(alignment: .topTrailing) {
            if isSelectMode {
                Image(systemName: selectedTaskIds.contains(task.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(selectedTaskIds.contains(task.id) ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .padding(8)
            }
        }

        if isOngoing {
            card
        } else {
            card
                .offset(x: swipeOffset[task.id] ?? 0)
                .background(alignment: .leading) {
                    if (swipeOffset[task.id] ?? 0) > 10 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right")
                            Text("+1")
                        }
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.leading, 12)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 50)
                        .onChanged { value in
                            let horizontal = value.translation.width
                            let vertical = abs(value.translation.height)
                            guard horizontal > 0, horizontal > vertical * 2 else { return }
                            withAnimation(.interactiveSpring()) {
                                swipeOffset[task.id] = min(horizontal * 0.4, 70)
                            }
                        }
                        .onEnded { value in
                            let horizontal = value.translation.width
                            let vertical = abs(value.translation.height)
                            if horizontal > 80, horizontal > vertical * 2 {
                                pushTask(task, days: 1)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                swipeOffset[task.id] = 0
                            }
                        }
                )
                .contextMenu {
                    Section("Push") {
                        Button(action: { pushTask(task, days: 1) }) {
                            Label("+1 Day", systemImage: "arrow.right")
                        }
                        Button(action: { pushTask(task, days: 2) }) {
                            Label("+2 Days", systemImage: "arrow.right")
                        }
                        Button(action: { pushTask(task, days: 3) }) {
                            Label("+3 Days", systemImage: "arrow.right")
                        }
                        Button(action: { pushTask(task, days: 7) }) {
                            Label("+1 Week", systemImage: "arrow.right.to.line")
                        }
                    }

                    Section("Extend") {
                        Button(action: { extendTask(task, days: 1) }) {
                            Label("+1 Day", systemImage: "arrow.right.and.line.vertical.and.arrow.left")
                        }
                        Button(action: { extendTask(task, days: 2) }) {
                            Label("+2 Days", systemImage: "arrow.right.and.line.vertical.and.arrow.left")
                        }
                        Button(action: { extendTask(task, days: 3) }) {
                            Label("+3 Days", systemImage: "arrow.right.and.line.vertical.and.arrow.left")
                        }
                        Button(action: { extendTask(task, days: 7) }) {
                            Label("+1 Week", systemImage: "arrow.right.and.line.vertical.and.arrow.left")
                        }
                    }

                    Section("Cascade") {
                        Button(action: { pushTaskWithCascade(task, days: 1) }) {
                            Label("+1 Day (+ dependents)", systemImage: "arrow.triangle.branch")
                        }
                        Button(action: { pushTaskWithCascade(task, days: 2) }) {
                            Label("+2 Days (+ dependents)", systemImage: "arrow.triangle.branch")
                        }
                    }

                    Section {
                        Button(action: { handleTaskTap(task) }) {
                            Label("Reschedule...", systemImage: "calendar")
                        }
                        Button(action: {
                            enterSelectMode()
                            selectedTaskIds.insert(task.id)
                        }) {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                    }
                }
        }
    }

    // MARK: - Day Header

    private var dayHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayOfWeek)
                    .font(OPSStyle.Typography.headingBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(dateString)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .textCase(.uppercase)
            }

            Spacer()

            let count = tasksForDate.count + userEventsForDate.count
            if count > 0 {
                Text("[ EVENTS — \(count) ]")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            }
        }
    }

    // MARK: - Empty State

    /// True when the company has zero projects at all (first-time user) and hasn't dismissed the prompt
    private var hasNoProjectsAtAll: Bool {
        !UserDefaults.standard.bool(forKey: "hasDismissedScheduleWizardPrompt") &&
        dataController.getAllProjects().isEmpty
    }

    private var emptyState: some View {
        Group {
            if hasNoProjectsAtAll {
                firstTimeSchedulePrompt
            } else {
                // Standard empty state for a day with no tasks
                VStack(spacing: 24) {
                    Spacer()
                    Text(emptyStateMessage)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(Color.white.opacity(0.30))
                        .tracking(1)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Wizard-styled prompt for users with zero projects
    private var firstTimeSchedulePrompt: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                // Icon + Title
                HStack(spacing: 12) {
                    Image(systemName: OPSStyle.Icons.schedule)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.wizardAccent)

                    Text("YOUR SCHEDULE")
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.bottom, 16)

                // Description
                Text("Projects, tasks, and meetings show up here as you create them. Your crew sees their schedule the moment they open OPS.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineSpacing(4)
                    .padding(.bottom, 20)

                // Bullet points
                VStack(alignment: .leading, spacing: 0) {
                    wizardBullet(index: 1, text: "Create your first project")
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorderSubtle)
                        .frame(height: 1)
                        .padding(.leading, 30)
                    wizardBullet(index: 2, text: "Add tasks and assign your crew")
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorderSubtle)
                        .frame(height: 1)
                        .padding(.leading, 30)
                    wizardBullet(index: 3, text: "Schedule it on the calendar")
                }
                .padding(.bottom, 24)

                // CTA button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    // Trigger the project lifecycle wizard
                    if let wizard = WizardRegistry.contextualWizard(for: "project_lifecycle") {
                        NotificationCenter.default.post(
                            name: Notification.Name("WizardStartRequested"),
                            object: nil,
                            userInfo: ["wizardId": wizard.wizardId]
                        )
                    } else {
                        // Fallback: open project creation via FAB
                        NotificationCenter.default.post(
                            name: Notification.Name("CreateNewProject"),
                            object: nil
                        )
                    }
                } label: {
                    HStack {
                        Text("CREATE YOUR FIRST PROJECT")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.buttonText)

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.buttonText)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(OPSStyle.Colors.wizardAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .padding(.bottom, 12)

                // Dismiss option
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    UserDefaults.standard.set(true, forKey: "hasDismissedScheduleWizardPrompt")
                    // Force view refresh
                    viewModel.objectWillChange.send()
                } label: {
                    Text("I'LL EXPLORE ON MY OWN")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetMin)
                }
            }
            .padding(28)
            .background(
                BlurView(style: .systemUltraThinMaterialDark)
                    .overlay(OPSStyle.Colors.cardBackgroundDark.opacity(0.7))
            )
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    private func wizardBullet(index: Int, text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.wizardAccent)
                .frame(width: 20, alignment: .center)

            Text(text)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(.vertical, 10)
    }

    /// Context-aware empty state: shows team member name when filtering by member
    private var emptyStateMessage: String {
        if case .member(let memberId) = viewModel.scheduleScope,
           let member = viewModel.availableTeamMembers.first(where: { $0.id == memberId }) {
            return "[ NO TASKS SCHEDULED FOR \(member.firstName.uppercased()) ]"
        }
        return "[ NO TASKS SCHEDULED ]"
    }

    // MARK: - Multi-Select

    @ViewBuilder
    private var bulkActionBar: some View {
        if isSelectMode && !selectedTaskIds.isEmpty {
            OPSActionBar {
                VStack(spacing: 8) {
                    // Push section
                    HStack(spacing: 4) {
                        Text("PUSH")
                            .font(OPSStyle.Typography.caption)
                            .tracking(0.8)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(width: 52)

                        OPSActionBarButton(icon: "arrow.right", label: "+1D") {
                            bulkPush(days: 1)
                        }
                        OPSActionBarButton(icon: "arrow.right", label: "+2D") {
                            bulkPush(days: 2)
                        }
                        OPSActionBarButton(icon: "arrow.right", label: "+3D") {
                            bulkPush(days: 3)
                        }
                        OPSActionBarButton(icon: "arrow.right.to.line", label: "+1W") {
                            bulkPush(days: 7)
                        }

                        Spacer()
                    }

                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorderSubtle)
                        .frame(height: 1)

                    // Extend section
                    HStack(spacing: 4) {
                        Text("EXTEND")
                            .font(OPSStyle.Typography.caption)
                            .tracking(0.8)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(width: 52)

                        OPSActionBarButton(icon: "arrow.right.and.line.vertical.and.arrow.left", label: "+1D") {
                            bulkExtend(days: 1)
                        }
                        OPSActionBarButton(icon: "arrow.right.and.line.vertical.and.arrow.left", label: "+2D") {
                            bulkExtend(days: 2)
                        }
                        OPSActionBarButton(icon: "arrow.right.and.line.vertical.and.arrow.left", label: "+3D") {
                            bulkExtend(days: 3)
                        }
                        OPSActionBarButton(icon: "arrow.right.and.line.vertical.and.arrow.left", label: "+1W") {
                            bulkExtend(days: 7)
                        }

                        Spacer()
                    }

                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorderSubtle)
                        .frame(height: 1)

                    // Bottom row: count + schedule + done
                    HStack(spacing: 4) {
                        Text("[ \(selectedTaskIds.count) SELECTED ]")
                            .font(OPSStyle.Typography.caption)
                            .tracking(0.8)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Spacer()

                        if selectedTaskIds.count == 1 {
                            OPSActionBarButton(
                                icon: "calendar",
                                label: "SCHEDULE"
                            ) {
                                showingScheduler = true
                            }
                        }

                        OPSActionBarButton(
                            icon: "xmark.circle",
                            label: "DONE",
                            iconColor: OPSStyle.Colors.primaryAccent,
                            labelColor: OPSStyle.Colors.primaryAccent
                        ) {
                            exitSelectMode()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func enterSelectMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelectMode = true
            appState.isScheduleSelectionMode = true
        }
    }

    private func exitSelectMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelectMode = false
            selectedTaskIds.removeAll()
            appState.isScheduleSelectionMode = false
        }
    }

    private func toggleSelection(_ taskId: String) {
        if selectedTaskIds.contains(taskId) {
            selectedTaskIds.remove(taskId)
        } else {
            selectedTaskIds.insert(taskId)
        }
    }

    private func bulkPush(days: Int) {
        guard let ctx = dataController.modelContext else { return }
        let ids = selectedTaskIds
        Task {
            for taskId in ids {
                let predicate = #Predicate<ProjectTask> { $0.id == taskId }
                let descriptor = FetchDescriptor<ProjectTask>(predicate: predicate)
                if let task = try? ctx.fetch(descriptor).first {
                    try? await dataController.pushTask(task, byDays: days)
                }
            }
            await MainActor.run {
                selectedTaskIds.removeAll()
                isSelectMode = false
                appState.isScheduleSelectionMode = false
            }
        }
    }

    private func bulkExtend(days: Int) {
        guard let ctx = dataController.modelContext else { return }
        let ids = selectedTaskIds
        let cal = Calendar.current
        Task {
            for taskId in ids {
                let predicate = #Predicate<ProjectTask> { $0.id == taskId }
                let descriptor = FetchDescriptor<ProjectTask>(predicate: predicate)
                if let task = try? ctx.fetch(descriptor).first,
                   let start = task.startDate,
                   let end = task.endDate,
                   let newEnd = cal.date(byAdding: .day, value: days, to: end) {
                    try? await dataController.updateTaskSchedule(task: task, startDate: start, endDate: newEnd)
                }
            }
            await MainActor.run {
                selectedTaskIds.removeAll()
                isSelectMode = false
                appState.isScheduleSelectionMode = false
            }
        }
    }

    // MARK: - Push / Cascade / Extend

    private func extendTask(_ task: ProjectTask, days: Int) {
        guard let start = task.startDate,
              let end = task.endDate,
              let newEnd = Calendar.current.date(byAdding: .day, value: days, to: end) else { return }
        Task {
            try? await dataController.updateTaskSchedule(task: task, startDate: start, endDate: newEnd)
        }

        postScheduleBanner(task: task, newDate: newEnd, action: "extended to")
    }

    private func pushTask(_ task: ProjectTask, days: Int) {
        // Compute new start before the async push mutates the task
        let cal = Calendar.current
        let newStart = cal.date(byAdding: .day, value: days, to: task.startDate ?? Date()) ?? Date()

        Task {
            try? await dataController.pushTask(task, byDays: days)
        }

        postScheduleBanner(task: task, newDate: newStart, action: "pushed to")
    }

    private func postScheduleBanner(task: ProjectTask, newDate: Date, action: String) {
        let projectName = task.project?.title ?? task.displayTitle
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let dateStr = formatter.string(from: newDate)

        NotificationCenter.default.post(
            name: Notification.Name("ShowScheduleBanner"),
            object: nil,
            userInfo: [
                "title": "\(projectName) \(action) \(dateStr)"
            ]
        )
    }

    private func pushTaskWithCascade(_ task: ProjectTask, days: Int) {
        let allTasks = dataController.getTasksForProject(task.projectId)
        let newDates = SchedulingEngine.pushByDays(task: task, days: days)
        let cascade = SchedulingEngine.calculateCascade(
            pushedTaskId: task.id,
            newStartDate: newDates.newStart,
            newEndDate: newDates.newEnd,
            allProjectTasks: allTasks
        )

        if showCascadePreviewPref && !cascade.changes.isEmpty {
            pendingCascade = cascade
            pendingTask = task
            pendingDays = days
            showingCascadePreview = true
        } else {
            Task {
                try? await dataController.pushTaskWithCascade(task, byDays: days)
            }
        }
    }

    // MARK: - Helpers

    private static let dayOfWeekFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private static let dateStringFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    private var dayOfWeek: String {
        DayPageView.dayOfWeekFormatter.string(from: date).uppercased()
    }

    private var dateString: String {
        DayPageView.dateStringFormatter.string(from: date).uppercased()
    }

    private func dayPosition(for task: ProjectTask, on date: Date) -> DayPosition {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let startDay = cal.startOfDay(for: task.startDate ?? date)
        let endDay = cal.startOfDay(for: task.endDate ?? date)
        let isStart = startDay == dayStart
        let isEnd = endDay == dayStart
        if isStart && isEnd { return .single }
        if isStart { return .start }
        if isEnd { return .end }
        return .middle
    }

    private func handleTaskTap(_ task: ProjectTask) {
        let userInfo: [String: String] = ["taskID": task.id, "projectID": task.projectId]
        NotificationCenter.default.post(
            name: Notification.Name("ShowCalendarTaskDetails"),
            object: nil,
            userInfo: userInfo
        )
        NotificationCenter.default.post(name: Notification.Name("WizardCalendarTaskTapped"), object: nil)
    }

    private func deleteUserEvent(_ event: CalendarUserEvent) {
        guard let context = dataController.modelContext,
              let companyId = dataController.currentUser?.companyId else { return }

        event.deletedAt = Date()
        try? context.save()
        viewModel.loadUserEvents()
        let eventId = event.id
        Task {
            let repo = CalendarUserEventRepository(companyId: companyId)
            try? await repo.softDelete(eventId)
        }
    }
}

// MARK: - Scroll Sync

/// Preference key for tracking vertical scroll offset across day pages
private struct DayScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
