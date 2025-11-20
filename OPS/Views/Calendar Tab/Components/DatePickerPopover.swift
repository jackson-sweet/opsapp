//
//  DatePickerPopover.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-04.
//

import SwiftUI

struct DatePickerPopover: View {
    enum PickerMode {
        case week
        case month
    }
    
    let mode: PickerMode
    let selectedDate: Date
    let onSelectDate: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var displayDate: Date
    
    init(mode: PickerMode, selectedDate: Date, onSelectDate: @escaping (Date) -> Void) {
        self.mode = mode
        self.selectedDate = selectedDate
        self.onSelectDate = onSelectDate
        
        // Initialize state properties
        _displayDate = State(initialValue: selectedDate)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Content based on mode
            Group {
                if mode == .week {
                    weekPickerContent
                } else {
                    monthPickerContent
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black, radius: 10, x: 0, y: 5)
        .frame(width: 320, height: mode == .week ? 440 : 360)
    }
    
    // Week picker content
    private var weekPickerContent: some View {
        VStack(spacing: 16) {
            // Month navigation
            HStack {
                Button {
                    moveToPreviousMonth()
                } label: {
                    Image(systemName: OPSStyle.Icons.chevronLeft)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(8)
                }
                
                Spacer()
                
                Text(monthString)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Spacer()
                
                Button {
                    moveToNextMonth()
                } label: {
                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(8)
                }
            }
            
            // Weekday headers with unique identifiers - Starting with Monday
            HStack(spacing: 0) {
                ForEach(["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"], id: \.self) { day in
                    Text(day)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
            
            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(getDaysInMonth(), id: \.timeIntervalSince1970) { date in
                    let isCurrentMonth = isSameMonth(date)
                    let isSelected = isSelectedWeek(date)
                    
                    Button {
                        if isCurrentMonth {
                            // Select the week containing this date
                            selectWeek(date)
                        }
                    } label: {
                        Text(dayString(from: date))
                            .font(OPSStyle.Typography.body)
                            .fontWeight(isCurrentMonth ? .medium : .regular)
                            .foregroundColor(isSelected ? .black : textColor(isCurrentMonth: isCurrentMonth, isSelected: false))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(isSelected ? .white : Color.clear)
                            )
                            .overlay(
                                Circle()
                                    .stroke(isSelected ? .white : Color.clear, lineWidth: 1)
                            )
                    }
                    .disabled(!isCurrentMonth)
                }
            }
            
            // Today button
            Button {
                // Select today's date directly, not the start of the week
                onSelectDate(Date())
            } label: {
                Text("Today")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 30)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                    )
                    .cornerRadius(8)
            }
            .padding(.top, 8)
        }
    }
    
    // Month picker content
    private var monthPickerContent: some View {
        VStack(spacing: 16) {
            // Year display with prev/next buttons
            HStack {
                Button {
                    moveToPreviousYear()
                } label: {
                    Image(systemName: OPSStyle.Icons.chevronLeft)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(8)
                }
                
                Spacer()
                
                let calendar = Calendar.current
                let year = calendar.component(.year, from: displayDate)
                Text("\(year)")
                    .font(OPSStyle.Typography.cardSubtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Spacer()
                
                Button {
                    moveToNextYear()
                } label: {
                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(8)
                }
            }
            
            // Month grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                ForEach(0..<12, id: \.self) { month in
                    let date = getDateForMonth(month)
                    let isSelected = isSameMonth(date) && isSameYear(date)
                    
                    Button {
                        selectMonth(month)
                    } label: {
                        Text(monthString(from: date))
                            .font(OPSStyle.Typography.body)
                            .fontWeight(.medium)
                            .foregroundColor(isSelected ? .black : OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .fill(isSelected ? .white : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(isSelected ? .white : OPSStyle.Colors.secondaryText, lineWidth: 1)
                            )
                    }
                }
            }
            
            // Today button
            Button {
                let today = Date()
                onSelectDate(today)
            } label: {
                Text("RETURN TO CURRENT DATE")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 30)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                    )
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Helper Methods
    
    private func textColor(isCurrentMonth: Bool, isSelected: Bool) -> Color {
        if isSelected {
            return .white
        } else if !isCurrentMonth {
            return OPSStyle.Colors.tertiaryText
        } else {
            return OPSStyle.Colors.primaryText
        }
    }
    
    private func moveToPreviousMonth() {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .month, value: -1, to: displayDate) {
            displayDate = newDate
        }
    }
    
    private func moveToNextMonth() {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .month, value: 1, to: displayDate) {
            displayDate = newDate
        }
    }
    
    private func moveToPreviousYear() {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .year, value: -1, to: displayDate) {
            displayDate = newDate
        }
    }
    
    private func moveToNextYear() {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .year, value: 1, to: displayDate) {
            displayDate = newDate
        }
    }
    
    private func getDaysInMonth() -> [Date] {
        var calendar = Calendar.current
        // Set first weekday to Monday
        calendar.firstWeekday = 2
        
        let monthComponents = calendar.dateComponents([.year, .month], from: displayDate)
        
        guard let startOfMonth = calendar.date(from: monthComponents) else { return [] }
        
        // Get the weekday of the first day (1 = Sunday, 2 = Monday, etc.)
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        
        // Calculate offset to get to start of the first week (Monday-based)
        // Convert to Monday-based index (0 = Monday, 6 = Sunday)
        let mondayBasedWeekday = (firstWeekday + 5) % 7
        let offset = mondayBasedWeekday
        
        // Get number of days in month
        guard let range = calendar.range(of: .day, in: .month, for: startOfMonth) else { return [] }
        let daysInMonth = range.count
        
        // Generate all days needed for a complete grid (6 rows x 7 days)
        var allDates: [Date] = []
        
        // Add days from previous month to complete first week
        for i in -offset..<0 {
            if let date = calendar.date(byAdding: .day, value: i, to: startOfMonth) {
                allDates.append(date)
            }
        }
        
        // Add all days of the current month
        for i in 0..<daysInMonth {
            if let date = calendar.date(byAdding: .day, value: i, to: startOfMonth) {
                allDates.append(date)
            }
        }
        
        // Add days from next month to complete the grid (max 6 rows)
        let remainingDays = 42 - allDates.count
        for _ in 0..<remainingDays {
            if let lastDate = allDates.last, 
               let date = calendar.date(byAdding: .day, value: 1, to: lastDate) {
                allDates.append(date)
            }
        }
        
        return allDates
    }
    
    private func getDateForMonth(_ month: Int) -> Date {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = calendar.component(.year, from: displayDate)
        components.month = month + 1 // Month is 0-based in array, 1-based in DateComponents
        components.day = 1
        
        return calendar.date(from: components) ?? Date()
    }
    
    private func selectWeek(_ date: Date) {
        var calendar = Calendar.current
        // Set first weekday to Monday
        calendar.firstWeekday = 2
        
        // Get the week interval for the date (this will start on Monday)
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else { return }
        
        // Select the Monday of the week
        onSelectDate(weekInterval.start)
    }
    
    private func selectMonth(_ month: Int) {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = calendar.component(.year, from: displayDate)
        components.month = month + 1
        components.day = 1

        if let date = calendar.date(from: components) {
            print("🗓️ DatePicker: selectMonth called")
            print("🗓️ Selected month index: \(month)")
            print("🗓️ Created date: \(date)")
            print("🗓️ Year: \(components.year ?? 0), Month: \(components.month ?? 0)")
            onSelectDate(date)
            print("🗓️ onSelectDate callback called with: \(date)")
        }
    }
    
    private func isSelectedWeek(_ date: Date) -> Bool {
        var calendar = Calendar.current
        // Set first weekday to Monday
        calendar.firstWeekday = 2
        
        // Get week intervals for both dates
        guard let dateWeekInterval = calendar.dateInterval(of: .weekOfYear, for: date),
              let selectedWeekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return false
        }
        
        // Check if they're in the same week by comparing the start of the week
        return dateWeekInterval.start == selectedWeekInterval.start
    }
    
    private func isSameMonth(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.month, from: date) == calendar.component(.month, from: displayDate)
    }
    
    private func isSameYear(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.year, from: date) == calendar.component(.year, from: displayDate)
    }
    
    private var monthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: displayDate)
    }
    
    private func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    private func monthString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }
}
