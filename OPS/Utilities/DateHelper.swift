//
//  DateHelper.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-24.
//


// DateHelper.swift
import Foundation

struct DateHelper {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
    
    static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter
    }()
    
    static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter
    }()
    
    static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()
    
    static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()
    
    static func isToday(_ date: Date) -> Bool {
        return Calendar.current.isDateInToday(date)
    }
    
    static func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
        return Calendar.current.isDate(date1, inSameDayAs: date2)
    }
    
    static func dayString(from date: Date) -> String {
        return dayFormatter.string(from: date)
    }
    
    static func weekdayString(from date: Date) -> String {
        return weekdayFormatter.string(from: date)
    }
    
    static func monthYearString(from date: Date) -> String {
        return "\(monthFormatter.string(from: date)), \(yearFormatter.string(from: date))"
    }
    
    static func fullDateString(from date: Date) -> String {
        return fullDateFormatter.string(from: date)
    }
}
