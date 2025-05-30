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
    let phone: String?
    let officeEmail: String?
    let industry: [String]?
    let companySize: String?
    let companyAge: String?
    let employees: [BubbleReference]?
    let admin: [BubbleReference]?
    
    
    // Custom coding keys to match Bubble's field names exactly
    enum CodingKeys: String, CodingKey {
        case id = "_id" // The company's unique id, assigned by bubble. We pass this in to bubble to fetch a specific company.
        case companyName = "Company Name" // The company name, type string.
        case companyID = "company id" // Company code/ company ID. THis is the unique code that employees use to join a company. The default value is the comapny's unique id, "_id" CodingKey, or "id" in our object.
        case companyDescription = "Company Description" // Company Description. Type string.
        case location = "Location" // Company's office address. Type 'geographic address'.
        case logo = "Logo" // Company logo of type "image".
        case projects = "Projects" // A list of "Project" objects.
        case teams = "Teams" // A list of "Team" objects. Not used yet in this version. In version X (a future version), we will use this. "Team" object contains a 'teamColor' (string of a hex color), 'teamName' string denoting name of the team, and a list of Users, who are the team members.
        case openHour = "Open Hour" // Opening hour for the company. Type string. Not used in the app.
        case closeHour = "Close Hour" // Closing hour for the company. Type of string. Not used in the app.
        case phone = "phone" // Customer facing contact phone for the company. Type String
        case officeEmail = "Office Email" // Customer facing contact email for the company. Type string
        case industry = "Industry" // industry of company. This is used for development data collection. Type "Industry", which is a string.
        case companySize = "company_size" //size of company. This is used for development data collection. Type string.
        case companyAge = "company_age" // age range of the company. This is used for development data collection. Type string.
        case employees = "Employees" // A list of all the employees in the company. Type is a list of User objects.
        case admin = "Admin" // This is the list of admins in the company. The type is a list of User objects.
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
        
        // Handle contact information
        company.phone = phone
        company.email = officeEmail
        
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
        
        // Note: industry, companySize, companyAge, employees, and admin are not stored in the Company model
        // If needed, these should be added to the Company model first
        
        company.lastSyncedAt = Date()
        
        return company
    }
}
