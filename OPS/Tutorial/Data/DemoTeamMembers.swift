//
//  DemoTeamMembers.swift
//  OPS
//
//  Demo team member data for the interactive tutorial.
//  Top Gun themed crew with specific specializations.
//

import Foundation

/// Data structure for demo team members
struct DemoTeamMemberData {
    let id: String
    let firstName: String
    let lastName: String
    let callsign: String
    let avatarAssetName: String  // Asset name in Assets.xcassets/Images/Demo/
    let specializations: [String]  // Task type IDs they can be assigned to

    /// Display name combining first and last name
    var fullName: String {
        "\(firstName) \(lastName)"
    }
}

// MARK: - All Demo Team Members

extension DemoTeamMemberData {
    /// All demo team members
    static let all: [DemoTeamMemberData] = [
        peteMitchell,
        nickBradshaw,
        tomKazansky,
        mikeMetcalf,
        rickHeatherly
    ]

    // MARK: - Individual Team Members

    /// Pete "Maverick" Mitchell - Finishes & Coatings Lead
    static let peteMitchell = DemoTeamMemberData(
        id: DemoIDs.peteMitchell,
        firstName: "Pete",
        lastName: "Mitchell",
        callsign: "Maverick",
        avatarAssetName: "pete",
        specializations: [
            DemoIDs.coating,
            DemoIDs.sealing,
            DemoIDs.painting
        ]
    )

    /// Nick "Goose" Bradshaw - Structural & Mechanical
    static let nickBradshaw = DemoTeamMemberData(
        id: DemoIDs.nickBradshaw,
        firstName: "Nick",
        lastName: "Bradshaw",
        callsign: "Goose",
        avatarAssetName: "nick",
        specializations: [
            DemoIDs.installation,
            DemoIDs.removal
        ]
    )

    /// Tom "Iceman" Kazansky - Heavy Work & Prep
    static let tomKazansky = DemoTeamMemberData(
        id: DemoIDs.tomKazansky,
        firstName: "Tom",
        lastName: "Kazansky",
        callsign: "Iceman",
        avatarAssetName: "tom",
        specializations: [
            DemoIDs.demolition,
            DemoIDs.pressureWash
        ]
    )

    /// Mike "Viper" Metcalf - Inspection & Detail
    static let mikeMetcalf = DemoTeamMemberData(
        id: DemoIDs.mikeMetcalf,
        firstName: "Mike",
        lastName: "Metcalf",
        callsign: "Viper",
        avatarAssetName: "mike",
        specializations: [
            DemoIDs.diagnostic,
            DemoIDs.cleaning
        ]
    )

    /// Rick "Jester" Heatherly - Exterior & Grounds
    static let rickHeatherly = DemoTeamMemberData(
        id: DemoIDs.rickHeatherly,
        firstName: "Rick",
        lastName: "Heatherly",
        callsign: "Jester",
        avatarAssetName: "rick",
        specializations: [
            DemoIDs.landscaping,
            DemoIDs.planting,
            DemoIDs.paving
        ]
    )

    // MARK: - Lookup Methods

    /// Find a team member by ID
    static func find(byId id: String) -> DemoTeamMemberData? {
        return all.first { $0.id == id }
    }

    /// Find team members who specialize in a given task type
    static func specialists(for taskTypeId: String) -> [DemoTeamMemberData] {
        return all.filter { $0.specializations.contains(taskTypeId) }
    }
}
