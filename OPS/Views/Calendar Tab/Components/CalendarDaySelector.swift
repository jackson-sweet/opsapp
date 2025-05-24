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
        ScrollViewReader { scrollProxy in
            GeometryReader { geometry in
                let totalPadding: CGFloat = 32 // 16 points on each side
                let spacing: CGFloat = 8
                let visibleDays: CGFloat = 5
                let totalSpacing = spacing * (visibleDays - 1)
                let dayWidth = (geometry.size.width - totalPadding - totalSpacing) / visibleDays
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: spacing) {
                        ForEach(getWeekDays(), id: \.timeIntervalSince1970) { date in
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
                            .frame(width: dayWidth)
                            .id(date.timeIntervalSince1970)
                        }
                    }
                    .padding(.horizontal, 16)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: .constant(viewModel.selectedDate.timeIntervalSince1970))
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .padding(.horizontal, 16)
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            let threshold: CGFloat = 50
                            if value.translation.width > threshold {
                                // Swipe right - go to previous day
                                let calendar = Calendar.current
                                if let previousDay = calendar.date(byAdding: .day, value: -1, to: viewModel.selectedDate) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        viewModel.selectDate(previousDay, userInitiated: true)
                                    }
                                }
                            } else if value.translation.width < -threshold {
                                // Swipe left - go to next day
                                let calendar = Calendar.current
                                if let nextDay = calendar.date(byAdding: .day, value: 1, to: viewModel.selectedDate) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        viewModel.selectDate(nextDay, userInitiated: true)
                                    }
                                }
                            }
                        }
                )
                .onChange(of: viewModel.selectedDate) { _, newDate in
                    if viewModel.viewMode == .week {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo(newDate.timeIntervalSince1970, anchor: .center)
                        }
                    }
                }
                .onAppear {
                    if viewModel.viewMode == .week {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                scrollProxy.scrollTo(viewModel.selectedDate.timeIntervalSince1970, anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(height: 80)
        }
    }
    
    // Generate week days starting from Monday - extended range for sliding
    private func getWeekDays() -> [Date] {
        let calendar = Calendar.current
        let baseDate = viewModel.selectedDate // Use selected date as base instead of today
        
        // Get the week containing the selected date, starting from Monday
        guard let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: baseDate)?.start else {
            return []
        }
        
        // Adjust to start from Monday (weekday 2 in Gregorian calendar)
        let mondayOffset = (calendar.component(.weekday, from: startOfWeek) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: startOfWeek) else {
            return []
        }
        
        // Generate 5 weeks (35 days) for better sliding experience
        var days: [Date] = []
        for i in -14...20 { // 2 weeks before + current week + 2 weeks after
            if let day = calendar.date(byAdding: .day, value: i, to: monday) {
                days.append(day)
            }
        }
        
        return days
    }
}
