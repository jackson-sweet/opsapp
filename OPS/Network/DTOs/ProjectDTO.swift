//
//  JobDTO.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
import Foundation

/// Data Transfer Object for Project from Bubble API
/// Designed to exactly match your Bubble data structure
struct ProjectDTO: Codable {
    // Use Bubble's exact field names in our CodingKeys
    
    // Project properties
    let id: String
    let address: BubbleAddress?
    let allDay: Bool?
    let client: BubbleReference?
    let company: BubbleReference?
    let completion: String?
    let description: String?
    let projectName: String
    let startDate: String?
    let status: String
    let teamNotes: String?
    let teamMembers: [BubbleReference]?
    
    // Bubble-specific nested structures
    var teams: [BubbleReference]?
    
    // Custom coding keys to match Bubble's field names exactly
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case address = "Address"
        case allDay = "All Day"
        case client = "Client"
        case company = "Company"
        case completion = "Completion"
        case description = "Description"
        case projectName = "Project Name"
        case startDate = "Start Date"
        case status = "Status"
        case teamNotes = "Team Notes"
        case teamMembers = "Team Members"
        case teams = "Teams"
    }
    
    /// Convert DTO to SwiftData model
    func toModel() -> Project {
        let project = Project(
            id: id,
            title: projectName,
            status: BubbleFields.JobStatus.toSwiftEnum(status)
        )
        
        // Geographic address needs special handling since Bubble uses a compound address type
        if let bubbleAddress = address {
            project.address = bubbleAddress.formattedAddress
            project.latitude = bubbleAddress.lat
            project.longitude = bubbleAddress.lng
        }
        
        // Client and company references
        if let clientRef = client {
            project.clientId = clientRef.uniqueID
            project.clientName = clientRef.text ?? "Unknown Client"
        }
        
        if let companyRef = company {
            project.companyId = companyRef.uniqueID
        }
        
        // Handle dates with robust parsing
        if let startDateString = startDate {
            project.startDate = DateFormatter.dateFromBubble(startDateString)
        }
        
        if let completionString = completion {
            project.endDate = DateFormatter.dateFromBubble(completionString)
        }
        
        project.notes = teamNotes
        project.projectDescription = description
        project.allDay = allDay ?? false
        project.allDay = allDay ?? false
        project.lastSyncedAt = Date()
        project.syncPriority = 1
        
        // Assign team members - these will be linked later
        project.teamMemberIds = teamMembers?.compactMap { $0.uniqueID } ?? []
        
        return project
    }
}

/// Bubble's geographic address structure
struct BubbleAddress: Codable {
    let formattedAddress: String
    let lat: Double?
    let lng: Double?
    
    enum CodingKeys: String, CodingKey {
        case formattedAddress = "formatted_address"
        case lat, lng
    }
}

/// Bubble's reference to other entities
struct BubbleReference: Codable {
    let uniqueID: String
    let text: String?
    
    enum CodingKeys: String, CodingKey {
        case uniqueID = "unique_id"
        case text
    }
}
