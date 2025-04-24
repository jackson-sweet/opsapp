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
    func toModel() -> Company {
        // Create company
        let company = Company(
            id: id,
            name: companyName ?? "Unknown Company"
        )
        
        // Handle Company ID
        company.externalId = companyID
        
        // Handle description
        company.companyDescription = companyDescription
        
        // Handle location
        if let loc = location {
            company.address = loc.formattedAddress
            company.latitude = loc.lat
            company.longitude = loc.lng
        }
        
        // Handle logo
        if let logoImage = logo, let logoUrl = logoImage.url {
            company.logoURL = logoUrl
            // Note: Actual image data will need to be downloaded separately
        }
        
        // Handle hours
        company.openHour = openHour
        company.closeHour = closeHour
        
        // Handle projects and teams - using the string storage methods
        if let projectRefs = projects {
            let projectIds = projectRefs.compactMap { $0.stringValue }
            company.projectIdsString = projectIds.joined(separator: ",")
        }
        
        if let teamRefs = teams {
            let teamIds = teamRefs.compactMap { $0.stringValue }
            company.teamIdsString = teamIds.joined(separator: ",")
        }
        
        company.lastSyncedAt = Date()
        
        return company
    }
}
