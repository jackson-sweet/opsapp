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
                    // No completedAt — use endDate as fallback, or include if no date at all
                    if let endDate = project.endDate {
                        let daysSince = calendar.dateComponents([.day], from: endDate, to: now).day ?? 0
                        return daysSince >= thresholdDays
                    }
                    return true // No date info — include for safety
                }
                let daysSince = calendar.dateComponents([.day], from: completedAt, to: now).day ?? 0
                return daysSince >= thresholdDays
            }
            .sorted { ($0.completedAt ?? $0.endDate ?? .distantPast) < ($1.completedAt ?? $1.endDate ?? .distantPast) }
    }

    /// Number of days since project was completed
    static func daysSinceCompleted(_ project: Project) -> Int {
        let referenceDate = project.completedAt ?? project.endDate ?? Date()
        return Calendar.current.dateComponents([.day], from: referenceDate, to: Date()).day ?? 0
    }
}
