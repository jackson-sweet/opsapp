//
//  String+AddressFormatting.swift
//  OPS
//
//  Extension for formatting addresses to show only street number, name, and area

import Foundation

extension String {
    /// Formats an address to show only street number, name, and area
    /// Example: "123 Main Street, Vancouver, BC V6B 2W9, Canada" -> "123 Main Street, Vancouver"
    func formatAsSimpleAddress() -> String {
        // Split by comma to get address components
        let components = self.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        // If we have at least 2 components (street and city), use them
        if components.count >= 2 {
            // First component is usually street address
            let street = components[0]
            // Second component is usually city/area
            let area = components[1]
            
            return "\(street), \(area)"
        }
        
        // If format is unexpected, return the original
        return self
    }
    
    /// Extracts just the street portion of an address
    /// Example: "123 Main Street, Vancouver, BC" -> "123 Main Street"
    func extractStreetAddress() -> String {
        let components = self.components(separatedBy: ",")
        return components.first?.trimmingCharacters(in: .whitespaces) ?? self
    }
    
    /// Extracts just the area/city portion of an address
    /// Example: "123 Main Street, Vancouver, BC" -> "Vancouver"
    func extractArea() -> String {
        let components = self.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        if components.count >= 2 {
            return components[1]
        }

        return ""
    }

    /// Capitalizes each word in the string
    /// Example: "john doe plumbing" -> "John Doe Plumbing"
    func capitalizedWords() -> String {
        return self.capitalized
    }
}