//
//  DemoProjects.swift
//  OPS
//
//  Demo project data for the interactive tutorial.
//  15 projects with 36 total tasks, distributed across status categories.
//

import Foundation

// MARK: - Demo Task Data

/// Data structure for demo tasks within a project
struct DemoTaskData {
    let taskTypeId: String
    let crewIds: [String]
    let daysFromCurrent: Int  // Negative = past, 0 = today, positive = future
    let durationDays: Int  // Number of days the task spans (1 = single day, 3 = three-day span)
    let notes: String?

    init(
        taskTypeId: String,
        crewIds: [String],
        daysFromCurrent: Int,
        durationDays: Int = 1,  // Default to single-day tasks
        notes: String? = nil
    ) {
        self.taskTypeId = taskTypeId
        self.crewIds = crewIds
        self.daysFromCurrent = daysFromCurrent
        self.durationDays = durationDays
        self.notes = notes
    }
}

// MARK: - Demo Project Data

/// Data structure for demo projects
struct DemoProjectData {
    let id: String
    let title: String
    let clientId: String
    let description: String?
    let notes: String?
    let imageAssets: [String]  // Asset names in Assets.xcassets/Images/Demo/
    let tasks: [DemoTaskData]

    init(
        id: String,
        title: String,
        clientId: String,
        description: String? = nil,
        notes: String? = nil,
        imageAssets: [String] = [],
        tasks: [DemoTaskData]
    ) {
        self.id = id
        self.title = title
        self.clientId = clientId
        self.description = description
        self.notes = notes
        self.imageAssets = imageAssets
        self.tasks = tasks
    }
}

// MARK: - All Demo Projects

extension DemoProjectData {
    /// All 15 demo projects
    static let all: [DemoProjectData] = [
        // COMPLETED (5)
        migDetailing,
        lockerRoomRenovation,
        officerHousingLandscape,
        charlieDrivewaySealing,
        oClubKitchenHood,

        // IN_PROGRESS (5)
        flightDeckCoating,
        oClubPatioResurface,
        hangarSidingRepair,
        charlieHomeOffice,
        parkingLotStriping,

        // ACCEPTED with future tasks (5)
        jetInteriorReupholstery,
        runwayCrackRepair,
        briefingRoomTechInstall,
        poolDeckSealing,
        oClubEntranceLandscaping
    ]

    // MARK: - Completed Projects

    /// MIG Detailing - Simple single-task completed project
    static let migDetailing = DemoProjectData(
        id: DemoIDs.migDetailing,
        title: "MIG Detailing",
        clientId: DemoIDs.fightertown,
        tasks: [
            DemoTaskData(
                taskTypeId: DemoIDs.cleaning,
                crewIds: [DemoIDs.mikeMetcalf],
                daysFromCurrent: -14
            )
        ]
    )

    /// Locker Room Renovation - Multi-task completed project
    static let lockerRoomRenovation = DemoProjectData(
        id: DemoIDs.lockerRoom,
        title: "Locker Room Renovation",
        clientId: DemoIDs.miramarFlight,
        description: "Full repaint and new lockers in pilot ready room.",
        tasks: [
            DemoTaskData(
                taskTypeId: DemoIDs.demolition,
                crewIds: [DemoIDs.tomKazansky],
                daysFromCurrent: -21,
                notes: "Old lockers hauled to Miramar Recycling"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.painting,
                crewIds: [DemoIDs.peteMitchell],
                daysFromCurrent: -18,
                notes: "SW Naval SW-6244, eggshell finish"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.installation,
                crewIds: [DemoIDs.nickBradshaw, DemoIDs.tomKazansky],
                daysFromCurrent: -15,
                notes: "24 new lockers, bolted to wall"
            )
        ]
    )

    /// Officer Housing Landscape Phase 1
    static let officerHousingLandscape = DemoProjectData(
        id: DemoIDs.housingLandscape,
        title: "Officer Housing Landscape Phase 1",
        clientId: DemoIDs.officerHousing,
        tasks: [
            DemoTaskData(
                taskTypeId: DemoIDs.removal,
                crewIds: [DemoIDs.nickBradshaw],
                daysFromCurrent: -12
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.planting,
                crewIds: [DemoIDs.rickHeatherly],
                daysFromCurrent: -10
            )
        ]
    )

    /// Charlie's Driveway Sealing
    static let charlieDrivewaySealing = DemoProjectData(
        id: DemoIDs.charlieDriveway,
        title: "Charlie's Driveway Sealing",
        clientId: DemoIDs.charlieBlackwood,
        description: "Prep and seal asphalt driveway. Small job, half day.",
        tasks: [
            DemoTaskData(
                taskTypeId: DemoIDs.pressureWash,
                crewIds: [DemoIDs.tomKazansky],
                daysFromCurrent: -8,
                notes: "Oil stain near garage needed degreaser"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.sealing,
                crewIds: [DemoIDs.peteMitchell],
                daysFromCurrent: -6,
                notes: "Coal tar emulsion, 24hr cure"
            )
        ]
    )

    /// O'Club Kitchen Hood Cleaning
    static let oClubKitchenHood = DemoProjectData(
        id: DemoIDs.oClubKitchen,
        title: "O'Club Kitchen Hood Cleaning",
        clientId: DemoIDs.oClub,
        tasks: [
            DemoTaskData(
                taskTypeId: DemoIDs.cleaning,
                crewIds: [DemoIDs.mikeMetcalf],
                daysFromCurrent: -5
            )
        ]
    )

    // MARK: - In Progress Projects

    /// Flight Deck Coating - Active project with images
    static let flightDeckCoating = DemoProjectData(
        id: DemoIDs.flightDeck,
        title: "Flight Deck Coating",
        clientId: DemoIDs.miramarFlight,
        description: "Recoat helicopter landing pad. Must meet military slip-resistance spec.",
        notes: "CO signed off on 48hr cure time. No flight ops until Friday.",
        imageAssets: ["flight_deck_before", "flight_deck_progress"],
        tasks: [
            DemoTaskData(
                taskTypeId: DemoIDs.removal,
                crewIds: [DemoIDs.nickBradshaw],
                daysFromCurrent: -3,
                durationDays: 2,  // 2-day removal job
                notes: "Old coating came up easier than expected"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.coating,
                crewIds: [DemoIDs.peteMitchell],
                daysFromCurrent: 0,
                durationDays: 3,  // 3-day coating process
                notes: "Using MIL-PRF-24667 gray, 2 coats"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.sealing,
                crewIds: [DemoIDs.peteMitchell],
                daysFromCurrent: 3,
                durationDays: 2,  // 2-day sealing
                notes: "Anti-slip aggregate in final coat"
            )
        ]
    )

    /// O'Club Patio Resurface
    static let oClubPatioResurface = DemoProjectData(
        id: DemoIDs.oClubPatio,
        title: "O'Club Patio Resurface",
        clientId: DemoIDs.oClub,
        description: "Demo old cracked patio, pour new stamped concrete. Pattern: Arizona flagstone.",
        notes: "Bar stays open during work. Keep debris away from entrance. Manager is Carole.",
        imageAssets: ["oclub_patio_area", "oclub_patio_demo"],
        tasks: [
            DemoTaskData(
                taskTypeId: DemoIDs.demolition,
                crewIds: [DemoIDs.tomKazansky],
                daysFromCurrent: -1,
                notes: "Rented 60lb breaker from Sunbelt"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.paving,
                crewIds: [DemoIDs.rickHeatherly],
                daysFromCurrent: 0,
                notes: "4\" slab, 3000 PSI mix"
            )
        ]
    )

    /// Hangar Siding Repair
    static let hangarSidingRepair = DemoProjectData(
        id: DemoIDs.hangarSiding,
        title: "Hangar Siding Repair",
        clientId: DemoIDs.fightertown,
        description: "Replace damaged corrugated panels on east wall. Forklift struck building last month.",
        imageAssets: ["hangar_exterior", "hangar_siding_damage"],
        tasks: [
            DemoTaskData(
                taskTypeId: DemoIDs.removal,
                crewIds: [DemoIDs.nickBradshaw],
                daysFromCurrent: -2,
                notes: "3 panels removed, saved fasteners"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.installation,
                crewIds: [DemoIDs.nickBradshaw],
                daysFromCurrent: 1,
                notes: "New panels are 26 gauge galvanized. Bring the Hilti"
            )
        ]
    )

    /// Charlie's Home Office Remodel
    static let charlieHomeOffice = DemoProjectData(
        id: DemoIDs.charlieOffice,
        title: "Charlie's Home Office Remodel",
        clientId: DemoIDs.charlieBlackwood,
        description: "Convert spare bedroom to home office. New paint, built-in shelving unit.",
        notes: "Client works from home - keep noise to reasonable hours. Dog is friendly.",
        imageAssets: ["home_office_demo", "home_office_paint_samples"],
        tasks: [
            DemoTaskData(
                taskTypeId: DemoIDs.demolition,
                crewIds: [DemoIDs.tomKazansky],
                daysFromCurrent: -2,
                notes: "Old carpet removed, subfloor is solid"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.painting,
                crewIds: [DemoIDs.peteMitchell],
                daysFromCurrent: 0,
                notes: "Benjamin Moore Hale Navy HC-154"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.installation,
                crewIds: [DemoIDs.nickBradshaw],
                daysFromCurrent: 3,
                notes: "IKEA BILLY shelves, client purchased"
            )
        ]
    )

    /// Parking Lot Striping
    static let parkingLotStriping = DemoProjectData(
        id: DemoIDs.parkingLot,
        title: "Parking Lot Striping",
        clientId: DemoIDs.miramarFlight,
        description: "Repaint faded parking lines and add new handicap stalls near building entrance.",
        notes: "Use federal yellow for standard lines. Blue for handicap. Stencils in truck bed.",
        imageAssets: ["parking_lot_washed"],
        tasks: [
            DemoTaskData(
                taskTypeId: DemoIDs.pressureWash,
                crewIds: [DemoIDs.tomKazansky],
                daysFromCurrent: -1,
                notes: "Started at 0600 before lot got busy"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.painting,
                crewIds: [DemoIDs.peteMitchell],
                daysFromCurrent: 1,
                notes: "4\" lines, federal spec yellow"
            )
        ]
    )

    // MARK: - Accepted Projects (Future Tasks)

    /// Jet Interior Reupholstery
    static let jetInteriorReupholstery = DemoProjectData(
        id: DemoIDs.jetInterior,
        title: "Jet Interior Reupholstery",
        clientId: DemoIDs.fightertown,
        description: "Strip and reupholster 6 cabin seats. Leather provided by client.",
        notes: "Aircraft is Cessna Citation II, tail N429TG. Hangar 3, bay 2.",
        imageAssets: ["jet_interior_current"],
        tasks: [
            DemoTaskData(
                taskTypeId: DemoIDs.removal,
                crewIds: [DemoIDs.nickBradshaw],
                daysFromCurrent: 5,
                notes: "Unbolt seats, tag all hardware"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.cleaning,
                crewIds: [DemoIDs.mikeMetcalf],
                daysFromCurrent: 7,
                notes: "Degrease frames, clean trim panels"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.installation,
                crewIds: [DemoIDs.nickBradshaw],
                daysFromCurrent: 10,
                notes: "Torque specs in aircraft manual"
            )
        ]
    )

    /// Runway Crack Repair
    static let runwayCrackRepair = DemoProjectData(
        id: DemoIDs.runwayCrack,
        title: "Runway Crack Repair",
        clientId: DemoIDs.miramarFlight,
        description: "Seal and coat taxiway Charlie cracks. FAA inspection scheduled for end of month.",
        notes: "Work window is 0500-0800 only. Must be off taxiway by 0815 for flight ops.",
        imageAssets: ["runway_overview", "runway_cracks"],
        tasks: [
            DemoTaskData(
                taskTypeId: DemoIDs.diagnostic,
                crewIds: [DemoIDs.mikeMetcalf],
                daysFromCurrent: 4,
                notes: "Map all cracks over 1/4\", photo document"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.sealing,
                crewIds: [DemoIDs.peteMitchell],
                daysFromCurrent: 8,
                notes: "Crafco 34864 hot pour sealant"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.coating,
                crewIds: [DemoIDs.peteMitchell],
                daysFromCurrent: 11,
                notes: "P-608 coal tar emulsion, 2 coats"
            )
        ]
    )

    /// Briefing Room Tech Install
    static let briefingRoomTechInstall = DemoProjectData(
        id: DemoIDs.briefingRoom,
        title: "Briefing Room Tech Install",
        clientId: DemoIDs.miramarFlight,
        description: "Mount two 75\" displays and AV rack for new briefing system.",
        notes: "IT will run cables before we arrive. We just mount and secure.",
        imageAssets: ["briefing_room_current"],
        tasks: [
            DemoTaskData(
                taskTypeId: DemoIDs.installation,
                crewIds: [DemoIDs.nickBradshaw],
                daysFromCurrent: 6,
                notes: "Chief large tilting mounts (client provided)"
            )
        ]
    )

    /// Pool Deck Sealing
    static let poolDeckSealing = DemoProjectData(
        id: DemoIDs.poolDeck,
        title: "Pool Deck Sealing",
        clientId: DemoIDs.officerHousing,
        description: "Pressure wash and seal community pool deck before summer season.",
        notes: "Pool will be drained and closed. HOA contact is Lt. Davis.",
        tasks: [
            DemoTaskData(
                taskTypeId: DemoIDs.pressureWash,
                crewIds: [DemoIDs.tomKazansky],
                daysFromCurrent: 9,
                notes: "3000 PSI, surface cleaner attachment"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.sealing,
                crewIds: [DemoIDs.peteMitchell],
                daysFromCurrent: 12,
                notes: "Behr wet-look concrete sealer, 2 coats"
            )
        ]
    )

    /// O'Club Entrance Landscaping
    static let oClubEntranceLandscaping = DemoProjectData(
        id: DemoIDs.oClubLandscape,
        title: "O'Club Entrance Landscaping",
        clientId: DemoIDs.oClub,
        description: "Remove dead hedges, install drought-tolerant plants and rock mulch.",
        notes: "This is phase 2 after patio job. Same contact - Carole.",
        tasks: [
            DemoTaskData(
                taskTypeId: DemoIDs.removal,
                crewIds: [DemoIDs.nickBradshaw],
                daysFromCurrent: 7,
                notes: "12 dead boxwoods, roots and all"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.landscaping,
                crewIds: [DemoIDs.rickHeatherly],
                daysFromCurrent: 10,
                notes: "Grade for drainage away from building"
            ),
            DemoTaskData(
                taskTypeId: DemoIDs.planting,
                crewIds: [DemoIDs.rickHeatherly],
                daysFromCurrent: 14,
                notes: "8 agave, 6 lavender, desert gold gravel"
            )
        ]
    )

    // MARK: - Lookup Methods

    /// Find a project by ID
    static func find(byId id: String) -> DemoProjectData? {
        return all.first { $0.id == id }
    }

    /// Get projects for a specific client
    static func projects(forClient clientId: String) -> [DemoProjectData] {
        return all.filter { $0.clientId == clientId }
    }

    /// Get completed projects (all tasks in the past)
    static var completedProjects: [DemoProjectData] {
        return all.filter { project in
            project.tasks.allSatisfy { $0.daysFromCurrent < -1 }
        }
    }

    /// Get in-progress projects (at least one task within ±1 day)
    static var inProgressProjects: [DemoProjectData] {
        return all.filter { project in
            project.tasks.contains { abs($0.daysFromCurrent) <= 1 }
        }
    }

    /// Get accepted/scheduled projects (all tasks in the future)
    static var acceptedProjects: [DemoProjectData] {
        return all.filter { project in
            project.tasks.allSatisfy { $0.daysFromCurrent > 1 }
        }
    }
}

// MARK: - Date Calculator

/// Helper for calculating dates relative to seed time
struct DemoDateCalculator {
    private let seedDate: Date

    init(seedDate: Date = Date()) {
        self.seedDate = Calendar.current.startOfDay(for: seedDate)
    }

    /// Get date for a given offset from seed date
    func date(for offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: seedDate)!
    }

    /// Past date: current - N days
    func past(days: Int) -> Date {
        date(for: -days)
    }

    /// Current date (today)
    var current: Date { seedDate }

    /// Future date: current + N days
    func future(days: Int) -> Date {
        date(for: days)
    }

    /// Determine task status based on scheduled date
    func taskStatus(for daysFromCurrent: Int) -> TaskStatus {
        if daysFromCurrent < -1 {
            return .completed
        } else {
            // Current or future tasks are "active"
            return .active
        }
    }

    /// Determine project status based on task dates
    func projectStatus(for tasks: [DemoTaskData]) -> Status {
        if tasks.isEmpty { return .accepted }

        let hasInProgress = tasks.contains { abs($0.daysFromCurrent) <= 1 }
        let allCompleted = tasks.allSatisfy { $0.daysFromCurrent < -1 }
        let allFuture = tasks.allSatisfy { $0.daysFromCurrent > 1 }

        if allCompleted {
            return .completed
        } else if hasInProgress {
            return .inProgress
        } else if allFuture {
            return .accepted  // SCHEDULED maps to .accepted with future tasks
        } else {
            return .accepted
        }
    }
}
