//
//  DayCanvasView.swift
//  OPS
//
//  Horizontal day pager — swipe left/right to navigate days.
//  Uses 3-page infinite scroll trick.
//

import SwiftUI

struct DayCanvasView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataController: DataController
    @State private var pageIndex: Int = 1  // Always start on middle page
    @State private var cardAnimationTrigger: Date = Date()
    @State private var isSnappingBack: Bool = false

    // The 3 dates for the current page window
    private var pages: [Date] {
        let calendar = Calendar.current
        let selected = viewModel.selectedDate
        return [
            calendar.date(byAdding: .day, value: -1, to: selected)!,
            selected,
            calendar.date(byAdding: .day, value: 1, to: selected)!
        ]
    }

    var body: some View {
        TabView(selection: $pageIndex) {
            ForEach(0..<3, id: \.self) { index in
                DayPageView(
                    date: pages[index],
                    viewModel: viewModel,
                    cardAnimationTrigger: cardAnimationTrigger
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: pageIndex) { _, newIndex in
            guard newIndex != 1, !isSnappingBack else { return }
            isSnappingBack = true
            let offset = newIndex == 2 ? 1 : -1
            let calendar = Calendar.current
            if let newDate = calendar.date(byAdding: .day, value: offset, to: viewModel.selectedDate) {
                viewModel.selectDate(newDate, userInitiated: true)
                cardAnimationTrigger = newDate
            }
            // Re-center to middle page — no animation, instant snap back
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                pageIndex = 1
                isSnappingBack = false
            }
        }
        // When viewModel.selectedDate changes from strip tap, reset to middle page
        .onChange(of: viewModel.selectedDate) { _, _ in
            pageIndex = 1
            cardAnimationTrigger = Date()
        }
    }
}

// MARK: - Single Day Page

struct DayPageView: View {
    let date: Date
    @ObservedObject var viewModel: CalendarViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataController: DataController
    let cardAnimationTrigger: Date
    @State private var isAnimating: Bool = false

    private var tasksForDate: [ProjectTask] {
        viewModel.scheduledTasks(for: date)
    }

    private var userEventsForDate: [CalendarUserEvent] {
        viewModel.userEvents(for: date)
    }

    private var newTasks: [ProjectTask] {
        tasksForDate.filter { task in
            Calendar.current.isDate(task.startDate ?? Date(), inSameDayAs: date)
        }
    }

    private var ongoingTasks: [ProjectTask] {
        tasksForDate.filter { task in
            let startDate = task.startDate ?? Date()
            return !Calendar.current.isDate(startDate, inSameDayAs: date)
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
                    VStack(spacing: 10) {
                        // Tasks starting on this day
                        ForEach(Array(newTasks.enumerated()), id: \.element.id) { index, task in
                            CalendarEventCard(
                                task: task,
                                isFirst: index == 0,
                                isOngoing: false,
                                dayPosition: dayPosition(for: task, on: date),
                                onTap: { handleTaskTap(task) }
                            )
                            .padding(.horizontal, 20)
                            .opacity(isAnimating ? 1 : 0)
                            .offset(y: isAnimating ? 0 : 14)
                            .animation(
                                UIAccessibility.isReduceMotionEnabled ? .none :
                                    .easeOut(duration: 0.16).delay(Double(index) * 0.04),
                                value: isAnimating
                            )
                        }

                        // Ongoing divider + ongoing tasks
                        if !ongoingTasks.isEmpty {
                            HStack(spacing: 8) {
                                Text("ONGOING")
                                    .font(.custom("Kosugi-Regular", size: 11))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                Rectangle()
                                    .fill(OPSStyle.Colors.tertiaryText.opacity(0.25))
                                    .frame(height: 0.5)
                                Text("[\(ongoingTasks.count)]")
                                    .font(.custom("Kosugi-Regular", size: 11))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 4)

                            ForEach(Array(ongoingTasks.enumerated()), id: \.element.id) { index, task in
                                CalendarEventCard(
                                    task: task,
                                    isFirst: false,
                                    isOngoing: true,
                                    dayPosition: dayPosition(for: task, on: date),
                                    onTap: { handleTaskTap(task) }
                                )
                                .padding(.leading, 20) // no trailing padding — card bleeds right
                                .opacity(isAnimating ? 1 : 0)
                                .offset(y: isAnimating ? 0 : 14)
                                .animation(
                                    UIAccessibility.isReduceMotionEnabled ? .none :
                                        .easeOut(duration: 0.16).delay(Double(newTasks.count + index) * 0.04),
                                    value: isAnimating
                                )
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
        .onAppear {
            guard Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate) else { return }
            isAnimating = false
            withAnimation { isAnimating = true }
        }
        .onChange(of: cardAnimationTrigger) { _, _ in
            isAnimating = false
            withAnimation { isAnimating = true }
        }
    }

    // MARK: - Day Header

    private var dayHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayOfWeek)
                    .font(.custom("Mohave-Bold", size: 22))
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(dateString)
                    .font(.custom("Kosugi-Regular", size: 12))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .textCase(.uppercase)
            }

            Spacer()

            let count = tasksForDate.count + userEventsForDate.count
            if count > 0 {
                Text("[\(count)]")
                    .font(.custom("Kosugi-Regular", size: 12))
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
                .font(.custom("Kosugi-Regular", size: 12))
                .foregroundColor(Color.white.opacity(0.30))
                .tracking(1)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
        let start = task.startDate ?? date
        let end = task.endDate ?? date
        let isStart = cal.isDate(start, inSameDayAs: date)
        let isEnd = cal.isDate(end, inSameDayAs: date)
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
