//
//  TaskTypeDependency.swift
//  OPS
//
//  Codable struct representing a dependency between task types.
//  Used in TaskType.dependenciesJSON and ProjectTask.dependencyOverridesJSON.
//

import Foundation

/// Represents a dependency from one task type to another,
/// with overlap configured as either a percentage of predecessor duration
/// or a fixed constant number of days.
struct TaskTypeDependency: Codable, Equatable, Hashable {
    /// The task type ID that this task depends on (predecessor)
    let dependsOnTaskTypeId: String

    /// Percentage (0-100) of the predecessor's duration that can overlap.
    /// 0 = no overlap (finish-to-start), 50 = can start when predecessor is halfway done, etc.
    /// Used when overlapMode is "percentage".
    let overlapPercentage: Int

    /// "percentage" or "constant"
    let overlapMode: String

    /// Fixed number of days of overlap, regardless of predecessor duration.
    /// Used when overlapMode is "constant".
    let overlapConstantDays: Double

    enum CodingKeys: String, CodingKey {
        case dependsOnTaskTypeId = "depends_on_task_type_id"
        case overlapPercentage   = "overlap_percentage"
        case overlapMode         = "overlap_mode"
        case overlapConstantDays = "overlap_constant_days"
    }

    // MARK: - Initializer

    init(
        dependsOnTaskTypeId: String,
        overlapPercentage: Int,
        overlapMode: String = "percentage",
        overlapConstantDays: Double = 0
    ) {
        self.dependsOnTaskTypeId = dependsOnTaskTypeId
        self.overlapPercentage = overlapPercentage
        self.overlapMode = overlapMode
        self.overlapConstantDays = overlapConstantDays
    }

    // MARK: - Backward-Compatible Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dependsOnTaskTypeId = try container.decode(String.self, forKey: .dependsOnTaskTypeId)
        overlapPercentage = try container.decode(Int.self, forKey: .overlapPercentage)
        overlapMode = try container.decodeIfPresent(String.self, forKey: .overlapMode) ?? "percentage"
        overlapConstantDays = try container.decodeIfPresent(Double.self, forKey: .overlapConstantDays) ?? 0
    }

    // MARK: - Scheduling Helper

    /// Calculate the earliest start date for the dependent task,
    /// given the predecessor's start date and duration in days.
    ///
    /// - Parameters:
    ///   - predecessorStart: The start date of the predecessor task
    ///   - predecessorDuration: The duration (in days) of the predecessor task
    /// - Returns: The earliest date this dependent task can begin
    func earliestStart(predecessorStart: Date, predecessorDuration: Int) -> Date {
        let calendar = Calendar.current

        if overlapMode == "constant" {
            // Fixed overlap: task can start this many days before predecessor ends
            let overlapDays = Int(round(overlapConstantDays))
            let clampedOverlap = max(0, min(predecessorDuration, overlapDays))
            let daysToWait = predecessorDuration - clampedOverlap
            return calendar.date(byAdding: .day, value: daysToWait, to: predecessorStart) ?? predecessorStart
        } else {
            // Percentage overlap (original logic)
            let clampedOverlap = max(0, min(100, overlapPercentage))
            let completedFraction = Double(100 - clampedOverlap) / 100.0
            let daysToWait = Int(ceil(Double(predecessorDuration) * completedFraction))
            return calendar.date(byAdding: .day, value: daysToWait, to: predecessorStart) ?? predecessorStart
        }
    }
}
