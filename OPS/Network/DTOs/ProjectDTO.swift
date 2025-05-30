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
    let clientEmail: String?
    let clientPhone: String?
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
        case client = "Client" // This is the proejct's client, of type "Client" object. We do not need to store this at this point. We will use "Client Name" and "Client Email" and "Client Phone" instead of storing the whole client object. We do not need to store this field.
        case company = "Company" // This is the project's company, which is hypothetically the user's company if they are calling this prject. Type "Company" object.
        case completion = "Completion" // The completion date of the proejct. type date.
        case description = "Description" // description of the project, type string.
        case projectName = "Project Name" // Project's name, type string.
        case startDate = "Start Date" // starting date of the proejct, type date.
        case status = "Status" // Status of the project, Type "Job Status", which contains the fields Display (string), Index (number) and Color (string for hex color). Options are either RFQ, Estimated, Accepted, In Progress, Completed, Closed, or Archived.
        case teamNotes = "Team Notes" // Field to track notes, type string.
        case teamMembers = "Team Members" //the team members assigned to the project, a list of type User.
        case thumbnail = "Thumbnail" // A thumbnail image of the project, type image.
        case projectValue = "Project Value" // The net value of the project. We do not need to store this for now.
        case projectGrossCost = "Project Gross Cost" // The gross cost of the proejct. We dont need to store this for now.
        case balance = "Balance" // The outstanding project balance. Dont need to store this now.
        case slug = "Slug" // The project's URL slug. We don't need to store this in the app.
        case clientName = "Client Name" // The project's client's name. type string.
        case clientEmail = "Client Email" // The client's email address. type string.
        case clientPhone = "Client Phone" // The client's phone number. type string.
        case projectImages = "Project Images" // list of type image, that have been uploaded to the project object.
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
        project.clientEmail = clientEmail
        project.clientPhone = clientPhone
            
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
