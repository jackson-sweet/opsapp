//
//  SortOptions.swift
//  OPS
//
//  Sort options for Job Board and filter views
//

import Foundation

enum ProjectSortOption: String, CaseIterable, Hashable {
    case scheduledDateDescending = "Latest Scheduled"
    case scheduledDateAscending = "Earliest Scheduled"
    case statusAscending = "Status (A-Z)"
    case statusDescending = "Status (Z-A)"
}

enum TaskSortOption: String, CaseIterable, Hashable {
    case scheduledDateDescending = "Latest Scheduled"
    case scheduledDateAscending = "Earliest Scheduled"
    case statusAscending = "Status (A-Z)"
    case statusDescending = "Status (Z-A)"
}

/// Empty enum for filter views that don't have sort options
enum NoSort: CaseIterable, Hashable {
    // No cases - this enum exists only to satisfy FilterSheet's generic constraint
}
