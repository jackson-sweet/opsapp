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
            VStack(spacing: 0) {
                ZStack {
                    // Week days display container
                    HStack(spacing: 8) {
                        ForEach(Array(getCurrentWeekDays().enumerated()), id: \.element.timeIntervalSince1970) { index, date in
                            WeekDayCell(
                                date: date,
                                isSelected: DateHelper.isSameDay(date, viewModel.selectedDate),
                                eventCount: viewModel.projectCount(for: date),
                                tasks: viewModel.scheduledTasks(for: date),
                                onTap: {
                                    viewModel.selectDate(date, userInitiated: true)
                                }
                            )
                            .frame(maxWidth: .infinity)
                            .opacity(index < cellsVisible.count ? (cellsVisible[index] ? 1 : 0) : 1)
                            .offset(y: index < cellsVisible.count ? (cellsVisible[index] ? 0 : 5) : 0)
                        }

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
        .frame(height: 80)
        .onAppear {
            triggerCellAnimation()
        }
        // Update the week when selectedDate changes from external sources (like DatePickerPopover)
        .onChange(of: viewModel.selectedDate) { _, _ in
            triggerCellAnimation()
        }
        // Watch for calendar event changes and force refresh
        .onChange(of: dataController.scheduledTasksDidChange) { _, _ in
            // Use objectWillChange instead of forcing full view recreation
            viewModel.objectWillChange.send()
        }
    }

    private func triggerCellAnimation() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            cellsVisible = Array(repeating: true, count: 7)
            return
        }
        // Reset all to hidden first
        cellsVisible = Array(repeating: false, count: 7)
        // Stagger each column in
        for i in 0..<7 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.025) {
                withAnimation(.easeOut(duration: 0.12)) {
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

        // Smooth single-phase animation: slide out, update data, slide in
        isTransitioning = true
        let slideDirection: CGFloat = offset > 0 ? -1 : 1

        // Slide current week out
        withAnimation(.easeIn(duration: 0.15)) {
            transitionOffset = slideDirection * screenWidth * 0.4
            dragOffset = 0
            isDragging = false
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))

            // Update data while off-screen
            viewModel.selectDate(newWeekStart, userInitiated: false)
            impactFeedback.impactOccurred()

            // Position new week just off-screen on the opposite side
            transitionOffset = -slideDirection * screenWidth * 0.25

            // Slide new week in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                transitionOffset = 0
            }

            try? await Task.sleep(for: .milliseconds(250))
            isTransitioning = false
        }
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
