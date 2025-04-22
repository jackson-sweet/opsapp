//
//  OrganizationDTO.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import Foundation

/// Data Transfer Object for Company from Bubble API
/// Designed to exactly match your Bubble data structure
struct CompanyDTO: Codable {
    // Use Bubble's exact field names in our CodingKeys
    
    // Company properties
    let id: String
    let companyName: String?
    let companyID: String?
    let companyDescription: String?
    let location: BubbleAddress?
    let logo: BubbleImage?
    let projects: [BubbleReference]?
    let teams: [BubbleReference]?
    let openHour: String?
    let closeHour: String?
    
    // Custom coding keys to match Bubble's field names exactly
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case companyName = "Company Name"
        case companyID = "companyID"
        case companyDescription = "Company Description"
        case location = "Location"
        case logo = "Logo"
        case projects = "Projects"
        case teams = "Teams"
        case openHour = "Open Hour"
        case closeHour = "Close Hour"
    }
    
    /// Convert DTO to SwiftData model
    func toModel() -> Organization {
        // Create organization
        let organization = Organization(
            id: id,
            name: companyName ?? "Unknown Company"
        )
        
        // Handle Company ID
        organization.externalId = companyID
        
        // Handle description
        organization.description = companyDescription
        
        // Handle location
        if let loc = location {
            organization.address = loc.formattedAddress
            organization.latitude = loc.lat
            organization.longitude = loc.lng
        }
        
        // Handle logo
        if let logoImage = logo, let logoUrl = logoImage.url {
            organization.logoURL = logoUrl
            // Note: Actual image data will need to be downloaded separately
        }
        
        // Handle hours
        organization.openHour = openHour
        organization.closeHour = closeHour
        
        // Handle projects and teams
        organization.projectIds = projects?.compactMap { $0.uniqueID } ?? []
        organization.teamIds = teams?.compactMap { $0.uniqueID } ?? []
        
        organization.lastSyncedAt = Date()
        
        return organization
    }
}
