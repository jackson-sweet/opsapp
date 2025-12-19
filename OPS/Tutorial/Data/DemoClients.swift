//
//  DemoClients.swift
//  OPS
//
//  Demo client data for the interactive tutorial.
//  Top Gun themed clients in the San Diego area.
//

import Foundation

/// Data structure for demo clients
struct DemoClientData {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let clientType: ClientType

    /// Client type categories
    enum ClientType: String {
        case military = "Military/Aviation"
        case residential = "Residential"
        case commercial = "Commercial/Hospitality"
        case industrial = "Aviation/Industrial"
        case residentialComplex = "Residential Complex"
    }
}

// MARK: - All Demo Clients

extension DemoClientData {
    /// All demo clients
    static let all: [DemoClientData] = [
        miramarFlightAcademy,
        charlieBlackwood,
        oClubBarAndGrill,
        fightertownHangars,
        miramarOfficerHousing
    ]

    // MARK: - Individual Clients

    /// Miramar Flight Academy - Military/Aviation
    static let miramarFlightAcademy = DemoClientData(
        id: DemoIDs.miramarFlight,
        name: "Miramar Flight Academy",
        address: "9800 Anderson St, San Diego, CA 92126",
        latitude: 32.8734,
        longitude: -117.1439,
        clientType: .military
    )

    /// Charlie Blackwood - Residential
    static let charlieBlackwood = DemoClientData(
        id: DemoIDs.charlieBlackwood,
        name: "Charlie Blackwood",
        address: "10452 Scripps Lake Dr, San Diego, CA 92131",
        latitude: 32.9067,
        longitude: -117.1156,
        clientType: .residential
    )

    /// O'Club Bar & Grill - Commercial/Hospitality
    static let oClubBarAndGrill = DemoClientData(
        id: DemoIDs.oClub,
        name: "O'Club Bar & Grill",
        address: "8680 Miralani Dr, San Diego, CA 92126",
        latitude: 32.8945,
        longitude: -117.1423,
        clientType: .commercial
    )

    /// Fightertown Hangars LLC - Aviation/Industrial
    static let fightertownHangars = DemoClientData(
        id: DemoIDs.fightertown,
        name: "Fightertown Hangars LLC",
        address: "5915 Mira Mesa Blvd, San Diego, CA 92121",
        latitude: 32.9134,
        longitude: -117.1512,
        clientType: .industrial
    )

    /// Miramar Officer Housing - Residential Complex
    static let miramarOfficerHousing = DemoClientData(
        id: DemoIDs.officerHousing,
        name: "Miramar Officer Housing",
        address: "11056 Portobelo Dr, San Diego, CA 92124",
        latitude: 32.8523,
        longitude: -117.1012,
        clientType: .residentialComplex
    )

    // MARK: - Lookup Methods

    /// Find a client by ID
    static func find(byId id: String) -> DemoClientData? {
        return all.first { $0.id == id }
    }

    /// Find clients by type
    static func clients(ofType type: ClientType) -> [DemoClientData] {
        return all.filter { $0.clientType == type }
    }
}
