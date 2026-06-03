//
//  ScheduleTypes.swift
//  OPS
//
//  Input/output types for AutoScheduleManager.
//  Pure value types — no SwiftData or UI imports.
//

import Foundation

// MARK: - Input Types

struct ScheduleRequest {
    enum Mode {
        /// Auto-schedule a single task
        case single(task: any SchedulableTask, teamMemberIds: Set<String>)
        /// Auto-schedule all unscheduled tasks in one project
        case projectBatch(projectId: String)
        /// Auto-schedule all unscheduled tasks across multiple projects
        case multiProjectBatch(projectIds: [String])
        /// Auto-schedule a flat, cross-project list of tasks in explicit priority order.
        case taskPriorityQueue(orderedTaskIds: [String], includeUnranked: Bool)
        /// Auto-schedule whole projects in an explicit (user-ranked) order.
        case projectPriorityQueue(orderedProjectIds: [String])
    }

    let mode: Mode
    let anchorDate: Date
    let constraints: ScheduleConstraints
}

struct ScheduleConstraints {
    let skipWeekends: Bool
    let preciseScheduling: Bool
    let schedulingWindow: SchedulingWindow
    let proximityRadiusKm: Double
    let weatherConstraints: WeatherConstraints?

    /// Build constraints from Company settings
    static func from(company: Company?) -> ScheduleConstraints {
        let c = company
        return ScheduleConstraints(
            skipWeekends: c?.skipWeekendsInAutoSchedule ?? true,
            preciseScheduling: c?.preciseSchedulingEnabled ?? false,
            schedulingWindow: SchedulingWindow.from(company: c),
            proximityRadiusKm: c?.proximityGroupingRadiusKm ?? 15.0,
            weatherConstraints: nil
        )
    }
}

enum SchedulingWindow {
    case companyHours(open: String, close: String)
    case custom(open: String, close: String)
    case daylight(bufferMinutes: Int)

    /// Build from Company settings
    static func from(company: Company?) -> SchedulingWindow {
        guard let c = company else {
            return .companyHours(open: "08:00", close: "17:00")
        }

        switch c.schedulingWindowMode {
        case "custom":
            return .custom(
                open: c.customSchedulingStartHour ?? "06:00",
                close: c.customSchedulingEndHour ?? "20:00"
            )
        case "daylight":
            return .daylight(bufferMinutes: c.daylightBufferMinutes)
        default:
            return .companyHours(
                open: c.openHour ?? "08:00",
                close: c.closeHour ?? "17:00"
            )
        }
    }

    /// Resolve to concrete start/end times for a given date and project location.
    /// Returns (startTime, endTime) as Dates on the given day.
    func resolvedHours(for date: Date, latitude: Double?, longitude: Double?) -> (open: Date, close: Date) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)

        switch self {
        case .companyHours(let open, let close):
            return (timeOnDate(startOfDay, timeString: open), timeOnDate(startOfDay, timeString: close))

        case .custom(let open, let close):
            return (timeOnDate(startOfDay, timeString: open), timeOnDate(startOfDay, timeString: close))

        case .daylight(let bufferMinutes):
            guard let lat = latitude, let lng = longitude,
                  lat != 0 || lng != 0 else {
                // Fallback to standard hours when no coordinates
                return (timeOnDate(startOfDay, timeString: "08:00"), timeOnDate(startOfDay, timeString: "17:00"))
            }
            let daylight = SolarCalculator.daylightHours(
                latitude: lat, longitude: lng, date: date, bufferMinutes: bufferMinutes
            )
            return (daylight.sunrise, daylight.sunset)
        }
    }

    /// Parse "HH:mm" string to a Date on the given day
    private func timeOnDate(_ startOfDay: Date, timeString: String) -> Date {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return startOfDay }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: startOfDay) ?? startOfDay
    }
}

struct WeatherConstraints {
    let isWeatherDependent: Bool
    let requiredConditions: [WeatherCondition]
}

enum WeatherCondition {
    case dry
    case noWind
    case aboveFreezing
    case belowTemperature(celsius: Double)
}

// MARK: - Output Types

struct SchedulePlan {
    let placements: [TaskPlacement]
    let conflicts: [ScheduleConflict]
    let metadata: ScheduleMetadata

    static let empty = SchedulePlan(placements: [], conflicts: [], metadata: .empty)
}

struct TaskPlacement: Identifiable {
    let id: String
    let taskTypeId: String
    let startDate: Date
    let endDate: Date
    let startTime: Date?
    let endTime: Date?
    let alternative: AlternativePlacement?
}

struct AlternativePlacement {
    let startDate: Date
    let endDate: Date
    let startTime: Date?
    let endTime: Date?
    let reason: AlternativeReason
    let deferralDays: Int
    let nearbyTaskCount: Int
    let estimatedDistanceSavedKm: Double
    let benefitingCrewMemberIds: Set<String>
}

enum AlternativeReason {
    case geographicGrouping
    case weatherDeferral
}

struct ScheduleConflict: Identifiable {
    let id: String
    let type: ConflictType
    let message: String
}

enum ConflictType {
    case noAvailableWindow
    case circularDependency
    case noCrewAssigned
    case missingProjectCoordinates
    case deactivatedCrewMember
}

struct ScheduleMetadata {
    let totalGapDays: Int
    let proximityGroupsFound: Int
    let weatherDependentTaskCount: Int
    let weatherDeferrals: Int
    let downstreamUnscheduledCount: Int
    let warnings: [String]

    static let empty = ScheduleMetadata(
        totalGapDays: 0, proximityGroupsFound: 0,
        weatherDependentTaskCount: 0, weatherDeferrals: 0,
        downstreamUnscheduledCount: 0, warnings: []
    )
}

// MARK: - Data Provider Protocol

/// Abstracts data access so AutoScheduleManager stays pure/testable.
/// DataController conforms to this in production; tests use MockScheduleDataProvider.
protocol ScheduleDataProvider {
    func tasksForProject(_ projectId: String) -> [any SchedulableTask]
    func allScheduledTasksForMembers(_ memberIds: Set<String>, from date: Date) -> [any SchedulableTask]
    func coordinatesForProject(_ projectId: String) -> (lat: Double, lng: Double)?
    func priorityDateForProject(_ projectId: String) -> Date?
    /// Resolve task ids to SchedulableTask, preserving input order. Missing ids dropped.
    func schedulableTasks(forIds ids: [String]) -> [any SchedulableTask]
    /// All active, unranked (priorityRank == nil) tasks, default (latest-edited) order.
    func unrankedActiveSchedulableTasks() -> [any SchedulableTask]
}
