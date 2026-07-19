//
//  VinylOrderFilter.swift
//  OPS
//
//  Vinyl-task detection for the Job Board (bug c6e90385). The inline filter
//  mode this file once carried was replaced by the VINYL ORDERS board
//  (2026-07-16) — the pill now opens VinylOrdersBoardView, which consumes
//  this same pure detection.
//

import Foundation

/// Pure detection logic, kept free of SwiftData so it is unit-testable.
enum VinylTaskFilter {
    /// Task-type ids whose display name reads as vinyl work. Substring match so
    /// "Vinyl", "Vinyl Install", "Vinyl Membrane" all qualify. Case-insensitive.
    static func vinylTaskTypeIds(displaysById: [String: String]) -> Set<String> {
        Set(
            displaysById
                .filter { $0.value.lowercased().contains("vinyl") }
                .map(\.key)
        )
    }

    /// A project carries vinyl work when any of its live (non-deleted) tasks is a
    /// vinyl-type task.
    static func hasVinylTask(taskTypeIds: [String], vinylTaskTypeIds: Set<String>) -> Bool {
        guard !vinylTaskTypeIds.isEmpty else { return false }
        return taskTypeIds.contains { vinylTaskTypeIds.contains($0) }
    }
}
