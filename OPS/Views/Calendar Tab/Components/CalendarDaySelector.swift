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

    var body: some View {
        Group {
            if viewModel.viewMode == .week {
                weekView
            } else {
                MonthGridView(viewModel: viewModel)
            }
        }
    }
    
    private var weekView: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ZStack {
                    // Week days display container
                    HStack(spacing: 8) {
                        ForEach(getCurrentWeekDays(), id: \.timeIntervalSince1970) { date in
                            WeekDayCell(
                                date: date,
                                isSelected: DateHelper.isSameDay(date, viewModel.selectedDate),
                                eventCount: viewModel.projectCount(for: date),
                                events: viewModel.calendarEvents(for: date),
                                onTap: {
                                    viewModel.selectDate(date, userInitiated: true)
                                }
                            )
                            .frame(maxWidth: .infinity)
                        }

                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 6)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .offset(x: isTransitioning ? transitionOffset : dragOffset)
                    .opacity(isTransitioning ? Double(1.0 - abs(transitionOffset) / geometry.size.width) : 1.0)
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
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                    isDragging = false
                                }
                            }
                        }
                )
            }
        }
        .frame(height: 80)
        // Update the week when selectedDate changes from external sources (like DatePickerPopover)
        .onChange(of: viewModel.selectedDate) { _, _ in
            // The view will automatically refresh with the new week
        }
        // Watch for calendar event changes and force refresh
        .onChange(of: dataController.calendarEventsDidChange) { _, _ in
            // Use objectWillChange instead of forcing full view recreation
            viewModel.objectWillChange.send()
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

        // Start rolling animation
        isTransitioning = true
        let slideDirection: CGFloat = offset > 0 ? -1 : 1 // Slide opposite to swipe direction

        // First phase: slide current week out
        withAnimation(.easeIn(duration: 0.15)) {
            transitionOffset = slideDirection * screenWidth * 0.5
            dragOffset = 0
            isDragging = false
        }

        // Update the date mid-animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            viewModel.selectDate(newWeekStart, userInitiated: false)
            impactFeedback.impactOccurred()

            // Reset position for incoming animation
            transitionOffset = -slideDirection * screenWidth * 0.3

            // Second phase: slide new week in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                transitionOffset = 0
            }

            // Clean up after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isTransitioning = false
            }
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
