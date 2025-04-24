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
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.getVisibleDays(), id: \.timeIntervalSince1970) { date in
                        DayCell(
                            date: date,
                            isSelected: DateHelper.isSameDay(date, viewModel.selectedDate),
                            projectCount: viewModel.projectCount(for: date),
                            onTap: {
                                withAnimation {
                                    viewModel.selectDate(date)
                                }
                            }
                        )
                        .id(date.timeIntervalSince1970)
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: viewModel.selectedDate) { _, newDate in
                // Scroll to selected date
                withAnimation {
                    scrollProxy.scrollTo(newDate.timeIntervalSince1970)
                }
            }
            .onAppear {
                // Initially scroll to today
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation {
                        scrollProxy.scrollTo(viewModel.selectedDate.timeIntervalSince1970)
                    }
                }
            }
        }
    }
}