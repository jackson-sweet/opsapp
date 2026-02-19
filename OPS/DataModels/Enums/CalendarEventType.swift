//
//  CalendarEventType.swift
//  OPS
//
//  Calendar event type differentiation
//

import Foundation

enum CalendarEventType: String, Codable, CaseIterable {
    case task       = "task"
    case siteVisit  = "site_visit"
    case other      = "other"
}
