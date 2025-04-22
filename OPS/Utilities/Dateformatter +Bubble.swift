//
//  Dateformatter +Bubble.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
import Foundation

/// Extension to handle various date formats from Bubble API
extension DateFormatter {
    
    /// Formatter that handles typical Bubble API date formats
    static let bubbleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    /// Parse a date string from Bubble in a more robust way than ISO8601DateFormatter
    /// - Parameter dateString: The date string to parse
    /// - Returns: Parsed Date or nil if parsing failed
    static func dateFromBubble(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        
        // Try a series of common formats
        let formatters = [
            bubbleFormatter,  // Primary format: 2023-04-21T09:30:00.000Z
            iso8601Full(),    // Full ISO8601: 2023-04-21T09:30:00Z
            iso8601(),        // Basic ISO8601: 2023-04-21T09:30:00
            dayOnly()         // Just the day: 2023-04-21
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        
        // Fallback - try ISO8601DateFormatter which has more flexibility
        return ISO8601DateFormatter().date(from: dateString)
    }
    
    /// ISO8601 formatter with full timezone
    private static func iso8601Full() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
    
    /// Basic ISO8601 formatter
    private static func iso8601() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
    
    /// Just the day formatter
    private static func dayOnly() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
}
