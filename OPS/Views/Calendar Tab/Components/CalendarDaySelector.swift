//
//  CalendarDaySelector.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-24.
//


// CalendarDaySelector.swift
import SwiftUI

struct CalendarDaySelector: View {
    @ObservedObject var viewModel: CalendarViewModel
    
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
            // Week days display - only show current week
            HStack(spacing: 8) {
                ForEach(getCurrentWeekDays(), id: \.timeIntervalSince1970) { date in
                    WeekDayCell(
                        date: date,
                        isSelected: DateHelper.isSameDay(date, viewModel.selectedDate),
                        projectCount: viewModel.projectCount(for: date),
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
            .padding(.horizontal, 16)
        }
        .frame(height: 80)
        // Update the week when selectedDate changes from external sources (like DatePickerPopover)
        .onChange(of: viewModel.selectedDate) { _, _ in
            // The view will automatically refresh with the new week
        }
    }
    
    // Generate only the current week days (7 days starting from Sunday)
    private func getCurrentWeekDays() -> [Date] {
        let calendar = Calendar.current
        let baseDate = viewModel.selectedDate
        
        // Get the week containing the selected date
        guard let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: baseDate)?.start else {
            return []
        }
        
        // Generate all 7 days of the week
        var days: [Date] = []
        for i in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: i, to: startOfWeek) {
                days.append(day)
            }
        }
        
        return days
    }
}
