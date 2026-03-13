//
//  OverdueProjectDetector.swift
//  OPS
//

import SwiftData
import Foundation

/// Computes the list of projects that are completed but overdue for payment review.
/// No persistence — recomputed on demand from SwiftData.
struct OverdueProjectDetector {

    /// Returns projects that have been in `.completed` status longer than the threshold.
    /// Only considers `completedAt` — projects without it are excluded (legacy data).
    static func overdueProjects(
        from projects: [Project],
        thresholdDays: Int = 14
    ) -> [Project] {
        let now = Date()
        let calendar = Calendar.current

        return projects
            .filter { $0.status == .completed }
            .filter { project in
                guard let completedAt = project.completedAt else {
                    return false // No completedAt — can't determine if overdue
                }
                let daysSince = calendar.dateComponents([.day], from: completedAt, to: now).day ?? 0
                return daysSince >= thresholdDays
            }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    /// Number of days since project was completed. Returns 0 if no completedAt date.
    static func daysSinceCompleted(_ project: Project) -> Int {
        guard let completedAt = project.completedAt else { return 0 }
        return Calendar.current.dateComponents([.day], from: completedAt, to: Date()).day ?? 0
    }
}
