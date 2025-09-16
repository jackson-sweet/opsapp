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
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    
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
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.selectDate(date, userInitiated: true)
                                }
                            }
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .offset(x: dragOffset)
            }
            .padding(.horizontal, 16)
            .clipped() // Prevent content from going outside safe area
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Add resistance when dragging
                        let resistance: CGFloat = 0.5
                        dragOffset = value.translation.width * resistance
                        isDragging = true
                    }
                    .onEnded { value in
                        let threshold: CGFloat = 50
                        let velocity = value.predictedEndTranslation.width - value.translation.width
                        
                        // Consider both distance and velocity for more natural feel
                        if value.translation.width > threshold || velocity > 200 {
                            // Swipe right - go to previous week
                            navigateToWeek(offset: -1)
                        } else if value.translation.width < -threshold || velocity < -200 {
                            // Swipe left - go to next week
                            navigateToWeek(offset: 1)
                        }
                        
                        // Always reset the offset after gesture ends
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                            isDragging = false
                        }
                    }
            )
        }
        .frame(height: 80)
        // Update the week when selectedDate changes from external sources (like DatePickerPopover)
        .onChange(of: viewModel.selectedDate) { _, _ in
            // The view will automatically refresh with the new week
        }
    }
    
    private func navigateToWeek(offset: Int) {
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
        
        // Select the first day of the new week with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            viewModel.selectDate(newWeekStart, userInitiated: false)
        }
        
        impactFeedback.impactOccurred()
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
