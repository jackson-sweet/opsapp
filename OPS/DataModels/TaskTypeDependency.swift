//
//  TaskTypeDependency.swift
//  OPS
//
//  Codable struct representing a dependency between task types.
//  Used in TaskType.dependenciesJSON and ProjectTask.dependencyOverridesJSON.
//

import Foundation

/// Represents a dependency from one task type to another.
///
/// Three timing modes (controlled by `overlapMode`):
///   - `percentage` — start when N% of predecessor's duration has elapsed (overlap)
///   - `constant`   — start `overlapConstantDays` days before predecessor ends (overlap)
///   - `after_end`  — start `minGapDaysAfterEnd` days after predecessor ends,
///                    optionally rounded up to a specific weekday
///
/// Pair behavior (only meaningful when this dependency is declared on a
/// downstream task type that should auto-spawn):
///   - `autoCreate`   — when a task of `dependsOnTaskTypeId` is created,
///                      auto-create a task of this type (the owning type)
///   - `inheritCrew`  — copy the predecessor's team_member_ids onto the spawn
struct TaskTypeDependency: Codable, Equatable, Hashable {
    /// The task type ID that this task depends on (predecessor)
    let dependsOnTaskTypeId: String

    /// Percentage (0-100) of the predecessor's duration that can overlap.
    /// 0 = no overlap (finish-to-start), 50 = can start when predecessor is halfway done, etc.
    /// Used when overlapMode is "percentage".
    let overlapPercentage: Int

    /// "percentage" | "constant" | "after_end"
    let overlapMode: String

    /// Fixed number of days of overlap, regardless of predecessor duration.
    /// Used when overlapMode is "constant".
    let overlapConstantDays: Double

    // MARK: - Pair + after_end fields (additive, backward-compatible defaults)

    /// When true, creating a task of `dependsOnTaskTypeId` auto-spawns a
    /// task of the owning type. Spawn is one-shot per predecessor instance.
    let autoCreate: Bool

    /// When true and `autoCreate` is true, the spawned task inherits the
    /// predecessor's team_member_ids (falling back to the owning type's
    /// `defaultTeamMemberIds` if the predecessor has no crew).
    let inheritCrew: Bool

    /// Minimum number of days after predecessor's end date before the
    /// dependent task can start. Used when overlapMode == "after_end".
    /// Signed — but for `after_end` only non-negative makes sense; the
    /// `constant`/`percentage` modes cover the overlap case.
    let minGapDaysAfterEnd: Int

    /// ISO weekday constraint: 1=Mon, 2=Tue, ..., 7=Sun. nil = any day.
    /// Used when overlapMode == "after_end". After applying the gap, the
    /// start date is rounded UP (never down) to the next occurrence of this
    /// weekday.
    let weekdayConstraint: Int?

    enum CodingKeys: String, CodingKey {
        case dependsOnTaskTypeId  = "depends_on_task_type_id"
        case overlapPercentage    = "overlap_percentage"
        case overlapMode          = "overlap_mode"
        case overlapConstantDays  = "overlap_constant_days"
        case autoCreate           = "auto_create"
        case inheritCrew          = "inherit_crew"
        case minGapDaysAfterEnd   = "min_gap_days_after_end"
        case weekdayConstraint    = "weekday_constraint"
    }

    // MARK: - Initializer

    init(
        dependsOnTaskTypeId: String,
        overlapPercentage: Int,
        overlapMode: String = "percentage",
        overlapConstantDays: Double = 0,
        autoCreate: Bool = false,
        inheritCrew: Bool = true,
        minGapDaysAfterEnd: Int = 0,
        weekdayConstraint: Int? = nil
    ) {
        self.dependsOnTaskTypeId = dependsOnTaskTypeId
        self.overlapPercentage = overlapPercentage
        self.overlapMode = overlapMode
        self.overlapConstantDays = overlapConstantDays
        self.autoCreate = autoCreate
        self.inheritCrew = inheritCrew
        self.minGapDaysAfterEnd = minGapDaysAfterEnd
        self.weekdayConstraint = weekdayConstraint
    }

    // MARK: - Backward-Compatible Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dependsOnTaskTypeId = try container.decode(String.self, forKey: .dependsOnTaskTypeId)
        overlapPercentage = try container.decode(Int.self, forKey: .overlapPercentage)
        overlapMode = try container.decodeIfPresent(String.self, forKey: .overlapMode) ?? "percentage"
        overlapConstantDays = try container.decodeIfPresent(Double.self, forKey: .overlapConstantDays) ?? 0
        autoCreate = try container.decodeIfPresent(Bool.self, forKey: .autoCreate) ?? false
        inheritCrew = try container.decodeIfPresent(Bool.self, forKey: .inheritCrew) ?? true
        minGapDaysAfterEnd = try container.decodeIfPresent(Int.self, forKey: .minGapDaysAfterEnd) ?? 0
        weekdayConstraint = try container.decodeIfPresent(Int.self, forKey: .weekdayConstraint)
    }

    // MARK: - Scheduling Helper

    /// Calculate the earliest start date for the dependent task,
    /// given the predecessor's start date and duration in days.
    func earliestStart(predecessorStart: Date, predecessorDuration: Int) -> Date {
        let calendar = Calendar.current

        switch overlapMode {
        case "after_end":
            // predecessor ends on day (duration - 1) inclusive
            let endOffset = max(predecessorDuration - 1, 0)
            let predEnd = calendar.date(byAdding: .day, value: endOffset, to: predecessorStart) ?? predecessorStart
            // The dependent starts on the day AFTER predecessor ends, plus the gap.
            // Gap = 0 means "starts the next day"; gap = 7 means "starts 7 days after the day after end".
            let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: predEnd) ?? predEnd
            let gappedStart = calendar.date(byAdding: .day, value: max(minGapDaysAfterEnd, 0), to: dayAfterEnd) ?? dayAfterEnd
            return Self.roundUpToWeekday(gappedStart, isoWeekday: weekdayConstraint, calendar: calendar)

        case "constant":
            // Fixed overlap: task can start this many days before predecessor ends
            let overlapDays = Int(round(overlapConstantDays))
            let clampedOverlap = max(0, min(predecessorDuration, overlapDays))
            let daysToWait = predecessorDuration - clampedOverlap
            return calendar.date(byAdding: .day, value: daysToWait, to: predecessorStart) ?? predecessorStart

        default:
            // Percentage overlap (original logic)
            let clampedOverlap = max(0, min(100, overlapPercentage))
            let completedFraction = Double(100 - clampedOverlap) / 100.0
            let daysToWait = Int(ceil(Double(predecessorDuration) * completedFraction))
            return calendar.date(byAdding: .day, value: daysToWait, to: predecessorStart) ?? predecessorStart
        }
    }

    // MARK: - Weekday Round-Up

    /// Advance `date` to the next occurrence of the given ISO weekday.
    /// ISO weekday: 1=Mon, 2=Tue, ..., 7=Sun. nil means no constraint.
    /// If `date` already falls on the target weekday, it is returned unchanged.
    static func roundUpToWeekday(_ date: Date, isoWeekday: Int?, calendar: Calendar) -> Date {
        guard let isoWeekday = isoWeekday, (1...7).contains(isoWeekday) else { return date }
        // Calendar.weekday convention: 1=Sun, 2=Mon, ..., 7=Sat
        // ISO 8601: 1=Mon, 2=Tue, ..., 7=Sun
        let calendarTarget = (isoWeekday % 7) + 1
        var d = date
        for _ in 0..<7 {
            if calendar.component(.weekday, from: d) == calendarTarget { return d }
            d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return date
    }
}
