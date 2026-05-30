//
//  AutoScheduleFailureRecovery.swift
//  OPS
//
//  Operator-readable recovery copy for auto-schedule placement failures.
//

import Foundation

enum AutoScheduleFailureRecoveryAction: Equatable {
    case manualSchedule
    case assignCrew
}

enum AutoScheduleFailureRecovery {
    static func offersManualSchedule(for plan: SchedulePlan) -> Bool {
        recoveryAction(for: plan) == .manualSchedule
    }

    static func recoveryAction(for plan: SchedulePlan) -> AutoScheduleFailureRecoveryAction? {
        guard plan.placements.isEmpty else { return nil }
        guard let conflict = plan.conflicts.first else {
            return .manualSchedule
        }

        switch conflict.type {
        case .noCrewAssigned:
            return .assignCrew
        case .noAvailableWindow,
             .missingProjectCoordinates,
             .deactivatedCrewMember,
             .circularDependency:
            return .manualSchedule
        }
    }

    static func message(for plan: SchedulePlan) -> String {
        guard plan.placements.isEmpty else { return "" }
        guard let conflict = plan.conflicts.first else {
            return "NO SLOT FOUND — SCHEDULE MANUALLY"
        }

        switch conflict.type {
        case .noAvailableWindow:
            return "NO SLOT FOUND — SCHEDULE MANUALLY"
        case .noCrewAssigned:
            return "CREW MISSING — ASSIGN CREW"
        case .missingProjectCoordinates:
            return "ADDRESS MISSING — SCHEDULE MANUALLY"
        case .deactivatedCrewMember:
            return "CREW UNAVAILABLE — CHECK TEAM"
        case .circularDependency:
            return "TASK ORDER BLOCKED — CHECK DEPENDENCIES"
        }
    }
}
