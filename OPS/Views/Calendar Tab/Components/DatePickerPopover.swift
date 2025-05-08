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
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
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
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(8)
                }
                
                Spacer()
                
                Text(monthString)
                    .font(.headline)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Spacer()
                
                Button {
                    moveToNextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(8)
                }
            }
            
            // Weekday headers with unique identifiers
            HStack(spacing: 0) {
                ForEach(["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 14, weight: .medium))
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
                            .font(.system(size: 16))
                            .fontWeight(isCurrentMonth ? .medium : .regular)
                            .foregroundColor(textColor(isCurrentMonth: isCurrentMonth, isSelected: isSelected))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(isSelected ? OPSStyle.Colors.primaryAccent : Color.clear)
                            )
                    }
                    .disabled(!isCurrentMonth)
                }
            }
            
            // Today button
            Button {
                selectWeek(Date())
            } label: {
                Text("Today")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 30)
                    .background(OPSStyle.Colors.primaryAccent)
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
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(8)
                }
                
                Spacer()
                
                let calendar = Calendar.current
                let year = calendar.component(.year, from: displayDate)
                Text("\(year)")
                    .font(.headline)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Spacer()
                
                Button {
                    moveToNextYear()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
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
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isSelected ? .white : OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? OPSStyle.Colors.primaryAccent : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: isSelected ? 0 : 1)
                            )
                    }
                }
            }
            
            // Today button
            Button {
                let today = Date()
                onSelectDate(today)
                dismiss()
            } label: {
                Text("Today")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 30)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(8)
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Helper Methods
    
    private func textColor(isCurrentMonth: Bool, isSelected: Bool) -> Color {
        if isSelected {
            return .white
        } else if !isCurrentMonth {
            return Color.gray.opacity(0.5)
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
        let calendar = Calendar.current
        let monthComponents = calendar.dateComponents([.year, .month], from: displayDate)
        
        guard let startOfMonth = calendar.date(from: monthComponents) else { return [] }
        
        // Get the weekday of the first day (1 = Sunday, 2 = Monday, etc.)
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        
        // Calculate offset to get to start of the first week
        let offset = (firstWeekday - 1)
        
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
        for i in 0..<remainingDays {
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
        let calendar = Calendar.current
        // Get the first day of the week containing this date
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let firstDay = calendar.date(from: components) else { return }
        
        onSelectDate(firstDay)
        dismiss()
    }
    
    private func selectMonth(_ month: Int) {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = calendar.component(.year, from: displayDate)
        components.month = month + 1 // Month is 0-based in array, 1-based in DateComponents
        components.day = 1
        
        if let date = calendar.date(from: components) {
            onSelectDate(date)
            dismiss()
        }
    }
    
    private func isSelectedWeek(_ date: Date) -> Bool {
        let calendar = Calendar.current
        
        // Get week components for the date and selected date
        let dateWeek = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let selectedWeek = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
        
        // Check if they're in the same week
        return dateWeek.yearForWeekOfYear == selectedWeek.yearForWeekOfYear && 
               dateWeek.weekOfYear == selectedWeek.weekOfYear
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
