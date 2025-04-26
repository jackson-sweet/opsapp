//
//  MonthGridView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-24.
//


import SwiftUI

struct MonthGridView: View {
    @ObservedObject var viewModel: CalendarViewModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    
    var body: some View {
        VStack(spacing: 12) {
            // Weekday headers
            HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(weekdayLabels[index])
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)
            
            // Calendar grid
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(viewModel.getVisibleDays(), id: \.timeIntervalSince1970) { date in
                    MonthDayCell(
                        date: date,
                        isSelected: DateHelper.isSameDay(date, viewModel.selectedDate),
                        projectCount: viewModel.projectCount(for: date),
                        isCurrentMonth: isSameMonth(date),
                        onTap: {
                            withAnimation {
                                viewModel.selectDate(date)
                            }
                        }
                    )
                }
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackground.opacity(0.3))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal)
    }
    
    private func isSameMonth(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.month, from: date) == calendar.component(.month, from: viewModel.selectedDate)
    }
}

struct MonthDayCell: View {
    let date: Date
    let isSelected: Bool
    let projectCount: Int
    let isCurrentMonth: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(DateHelper.dayString(from: date))
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(textColor)
                
                if projectCount > 0 {
                    ZStack {
                        Circle()
                            .fill(OPSStyle.Colors.secondaryAccent.opacity(0.7))
                            .frame(width: 20, height: 20)
                        
                        Text("\(projectCount)")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(.white)
                    }
                    .padding(.top, 2)
                } else {
                    // Empty space to maintain consistent height
                    Spacer()
                        .frame(height: 20)
                }
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(cellBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .disabled(!isCurrentMonth)
    }
    
    private var isToday: Bool {
        DateHelper.isToday(date)
    }
    
    private var textColor: Color {
        if !isCurrentMonth {
            return OPSStyle.Colors.secondaryText.opacity(0.4)
        } else if isSelected {
            return OPSStyle.Colors.primaryText
        } else if isToday {
            return OPSStyle.Colors.secondaryAccent
        } else {
            return OPSStyle.Colors.primaryText.opacity(0.8)
        }
    }
    
    private var cellBackground: some View {
        Group {
            if isSelected {
                OPSStyle.Colors.cardBackground
            } else if isToday {
                OPSStyle.Colors.cardBackground.opacity(0.3)
            } else {
                Color.clear
            }
        }
    }
}
