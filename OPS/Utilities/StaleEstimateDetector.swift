//
//  StaleEstimateDetector.swift
//  OPS
//
//  Computes the list of projects stuck in `.estimated` status beyond a
//  configurable threshold. No persistence — recomputed on demand from
//  SwiftData. Mirrors the shape of OverdueProjectDetector so it can plug
//  into the same periodic review-check pipeline.
//

import Foundation

struct StaleEstimateDetector {

    /// Returns projects that have been sitting in `.estimated` for longer
    /// than the threshold without any client follow-up. Uses the project's
    /// `lastSyncedAt` as a recency proxy (falls back to `startDate` if
    /// never synced, then `.distantPast`). Projects without any dates are
    /// considered maximally stale and always included.
    static func staleEstimatedProjects(
        from projects: [Project],
        thresholdDays: Int = 30
    ) -> [Project] {
        let now = Date()
        let calendar = Calendar.current

        return projects
            .filter { $0.deletedAt == nil }
            .filter { $0.status == .estimated }
            .filter { project in
                let recency = project.lastSyncedAt ?? project.startDate ?? .distantPast
                let daysSince = calendar.dateComponents([.day], from: recency, to: now).day ?? Int.max
                return daysSince >= thresholdDays
            }
            .sorted { (lhs, rhs) in
                let lhsStamp = lhs.lastSyncedAt ?? lhs.startDate ?? .distantPast
                let rhsStamp = rhs.lastSyncedAt ?? rhs.startDate ?? .distantPast
                return lhsStamp < rhsStamp  // Oldest first
            }
    }

    /// Days since a project's last recency anchor. 0 when never synced
    /// and no start date — treat as "brand new" rather than stale.
    static func daysSinceUpdate(_ project: Project) -> Int {
        let recency = project.lastSyncedAt ?? project.startDate ?? Date()
        return max(0, Calendar.current.dateComponents([.day], from: recency, to: Date()).day ?? 0)
    }
}
