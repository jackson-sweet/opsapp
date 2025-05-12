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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.getVisibleDays(), id: \.timeIntervalSince1970) { date in
                        DayCell(
                            date: date,
                            isSelected: DateHelper.isSameDay(date, viewModel.selectedDate),
                            projectCount: viewModel.projectCount(for: date),
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.selectDate(date, userInitiated: true)
                                }
                            }
                        )
                        .id(date.timeIntervalSince1970)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Color("CardBackgroundDark"))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .padding(.horizontal)
            .onChange(of: viewModel.selectedDate) { _, newDate in
                // Only scroll in week view
                if viewModel.viewMode == .week {
                    withAnimation {
                        scrollProxy.scrollTo(newDate.timeIntervalSince1970, anchor: .center)
                    }
                }
            }
            .onAppear {
                // Initially scroll to today
                if viewModel.viewMode == .week {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation {
                            scrollProxy.scrollTo(viewModel.selectedDate.timeIntervalSince1970, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}
