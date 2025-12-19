//
//  DemoIDs.swift
//  OPS
//
//  Constants for all demo data entity IDs.
//  All IDs use the DEMO_ prefix for easy identification and cleanup.
//

import Foundation

/// All demo entity IDs with DEMO_ prefix for identification
struct DemoIDs {

    // MARK: - Company

    static let demoCompany = "DEMO_COMPANY_TOPGUN"

    // MARK: - Team Members (Users)

    static let peteMitchell = "DEMO_USER_MAVERICK"
    static let nickBradshaw = "DEMO_USER_GOOSE"
    static let tomKazansky = "DEMO_USER_ICEMAN"
    static let mikeMetcalf = "DEMO_USER_VIPER"
    static let rickHeatherly = "DEMO_USER_JESTER"

    /// All team member IDs
    static let allTeamMemberIds: [String] = [
        peteMitchell,
        nickBradshaw,
        tomKazansky,
        mikeMetcalf,
        rickHeatherly
    ]

    // MARK: - Clients

    static let miramarFlight = "DEMO_CLIENT_MIRAMAR"
    static let charlieBlackwood = "DEMO_CLIENT_CHARLIE"
    static let oClub = "DEMO_CLIENT_OCLUB"
    static let fightertown = "DEMO_CLIENT_FIGHTERTOWN"
    static let officerHousing = "DEMO_CLIENT_HOUSING"

    /// All client IDs
    static let allClientIds: [String] = [
        miramarFlight,
        charlieBlackwood,
        oClub,
        fightertown,
        officerHousing
    ]

    // MARK: - Task Types

    static let cleaning = "DEMO_TASKTYPE_CLEANING"
    static let demolition = "DEMO_TASKTYPE_DEMOLITION"
    static let painting = "DEMO_TASKTYPE_PAINTING"
    static let sealing = "DEMO_TASKTYPE_SEALING"
    static let paving = "DEMO_TASKTYPE_PAVING"
    static let landscaping = "DEMO_TASKTYPE_LANDSCAPING"
    static let installation = "DEMO_TASKTYPE_INSTALLATION"
    static let pressureWash = "DEMO_TASKTYPE_PRESSUREWASH"
    static let diagnostic = "DEMO_TASKTYPE_DIAGNOSTIC"
    static let removal = "DEMO_TASKTYPE_REMOVAL"
    static let coating = "DEMO_TASKTYPE_COATING"
    static let planting = "DEMO_TASKTYPE_PLANTING"

    /// All task type IDs
    static let allTaskTypeIds: [String] = [
        cleaning,
        demolition,
        painting,
        sealing,
        paving,
        landscaping,
        installation,
        pressureWash,
        diagnostic,
        removal,
        coating,
        planting
    ]

    // MARK: - Projects

    // Completed Projects
    static let migDetailing = "DEMO_PROJECT_MIG"
    static let lockerRoom = "DEMO_PROJECT_LOCKER"
    static let housingLandscape = "DEMO_PROJECT_LANDSCAPE1"
    static let charlieDriveway = "DEMO_PROJECT_DRIVEWAY"
    static let oClubKitchen = "DEMO_PROJECT_KITCHEN"

    // In Progress Projects
    static let flightDeck = "DEMO_PROJECT_FLIGHTDECK"
    static let oClubPatio = "DEMO_PROJECT_PATIO"
    static let hangarSiding = "DEMO_PROJECT_HANGAR"
    static let charlieOffice = "DEMO_PROJECT_OFFICE"
    static let parkingLot = "DEMO_PROJECT_PARKING"

    // Accepted (Future) Projects
    static let jetInterior = "DEMO_PROJECT_JET"
    static let runwayCrack = "DEMO_PROJECT_RUNWAY"
    static let briefingRoom = "DEMO_PROJECT_BRIEFING"
    static let poolDeck = "DEMO_PROJECT_POOL"
    static let oClubLandscape = "DEMO_PROJECT_LANDSCAPE2"

    /// All project IDs
    static let allProjectIds: [String] = [
        // Completed
        migDetailing,
        lockerRoom,
        housingLandscape,
        charlieDriveway,
        oClubKitchen,
        // In Progress
        flightDeck,
        oClubPatio,
        hangarSiding,
        charlieOffice,
        parkingLot,
        // Accepted (Future)
        jetInterior,
        runwayCrack,
        briefingRoom,
        poolDeck,
        oClubLandscape
    ]

    // MARK: - Utility Methods

    /// Checks if an ID belongs to demo data
    static func isDemoId(_ id: String) -> Bool {
        return id.hasPrefix("DEMO_")
    }

    /// Generates a task ID for a given project
    static func taskId(projectId: String, index: Int) -> String {
        return "\(projectId)_TASK_\(index)"
    }

    /// Generates a calendar event ID for a given task
    static func calendarEventId(taskId: String) -> String {
        return "\(taskId)_EVENT"
    }
}
