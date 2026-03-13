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

    // Ongoing tasks sorted by ID for stable vertical position across pages
    private var ongoingTasks: [ProjectTask] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        return tasksForDate.filter { task in
            cal.startOfDay(for: task.startDate ?? Date()) != dayStart
        }
        .sorted { $0.id < $1.id }
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

    private var newTasks: [ProjectTask] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        return tasksForDate.filter { task in
            cal.startOfDay(for: task.startDate ?? Date()) == dayStart
        }
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
                ScrollView {
                    VStack(spacing: 0) {
                        // Ongoing (multi-day) tasks first — labels always visible so
                        // they appear to stay in place during horizontal page swipes.
                        ForEach(Array(ongoingTasks.enumerated()), id: \.element.id) { index, task in
                            CalendarEventCard(
                                task: task,
                                isFirst: index == 0,
                                isOngoing: true,
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
                            .overlay(alignment: .topTrailing) {
                                if isSelectMode {
                                    Image(systemName: selectedTaskIds.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(selectedTaskIds.contains(task.id) ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                                        .padding(8)
                                }
                            }
                        }

                        // Tasks starting on this day — always show labels
                        ForEach(Array(newTasks.enumerated()), id: \.element.id) { index, task in
                            CalendarEventCard(
                                task: task,
                                isFirst: ongoingTasks.isEmpty && index == 0,
                                isOngoing: false,
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
                            .overlay(alignment: .topTrailing) {
                                if isSelectMode {
                                    Image(systemName: selectedTaskIds.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(selectedTaskIds.contains(task.id) ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                                        .padding(8)
                                }
                            }
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
                                        // Only trigger on mostly-horizontal rightward swipe
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

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("[ NO TASKS SCHEDULED ]")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(Color.white.opacity(0.30))
                .tracking(1)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
