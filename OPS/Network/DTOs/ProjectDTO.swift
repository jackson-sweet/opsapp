//
//  ProjectDTO.swift
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
    let teamMembers: [String]?
    let thumbnail: String?
    let clientName: String?
    let projectImages: [String]?  // Added this field
    
    // Additional fields from the actual API response
    let projectValue: Double?
    let projectGrossCost: Double?
    let balance: Double?
    let slug: String?
    
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
        case thumbnail = "Thumbnail"
        case projectValue = "Project Value"
        case projectGrossCost = "Project Gross Cost"
        case balance = "Balance"
        case slug = "Slug"
        case clientName = "Client Name"
        case projectImages = "Project Images"
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
            
        project.clientName = clientName ?? "Unknown Client"
            
        if let companyRef = company {
            project.companyId = companyRef.stringValue
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
        project.lastSyncedAt = Date()
        project.syncPriority = 1
        
        // Store project images
        if let images = projectImages {
            project.projectImagesString = images.joined(separator: ",")
        }
        
        // Assign team members - using string storage
        if let teamMemberIds = teamMembers {
            project.teamMemberIdsString = teamMemberIds.joined(separator: ",")
        }
        
        return project
    }
}
