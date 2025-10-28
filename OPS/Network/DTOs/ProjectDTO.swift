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
    let client: String?  // Changed from BubbleReference to String since API returns string ID
    
    // Custom initializer for debugging
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode all required fields
        self.id = try container.decode(String.self, forKey: .id)
        self.projectName = try container.decode(String.self, forKey: .projectName)
        self.status = try container.decode(String.self, forKey: .status)
        
        // Decode optional fields
        self.address = try container.decodeIfPresent(BubbleAddress.self, forKey: .address)
        self.allDay = try container.decodeIfPresent(Bool.self, forKey: .allDay)
        
        // Decode client field (debug logging removed to reduce console clutter)
        if container.contains(.client) {
            self.client = try container.decodeIfPresent(String.self, forKey: .client)
        } else {
            self.client = nil
        }
        
        self.company = try container.decodeIfPresent(BubbleReference.self, forKey: .company)
        self.completion = try container.decodeIfPresent(String.self, forKey: .completion)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
        self.teamNotes = try container.decodeIfPresent(String.self, forKey: .teamNotes)
        self.teamMembers = try container.decodeIfPresent([String].self, forKey: .teamMembers)
        self.thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        self.clientName = try container.decodeIfPresent(String.self, forKey: .clientName)
        self.clientEmail = try container.decodeIfPresent(String.self, forKey: .clientEmail)
        self.clientPhone = try container.decodeIfPresent(String.self, forKey: .clientPhone)
        self.projectImages = try container.decodeIfPresent([String].self, forKey: .projectImages)
        self.duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        self.projectValue = try container.decodeIfPresent(Double.self, forKey: .projectValue)
        self.projectGrossCost = try container.decodeIfPresent(Double.self, forKey: .projectGrossCost)
        self.balance = try container.decodeIfPresent(Double.self, forKey: .balance)
        self.slug = try container.decodeIfPresent(String.self, forKey: .slug)
        self.eventType = try container.decodeIfPresent(String.self, forKey: .eventType)
        self.tasks = try container.decodeIfPresent([BubbleReference].self, forKey: .tasks)
        
        // Log eventType for debugging
        if let eventTypeValue = self.eventType {
        } else {
        }
    }
    let company: BubbleReference?
    let completion: String?
    let description: String?
    let projectName: String
    let startDate: String?
    let status: String
    let teamNotes: String?
    let teamMembers: [String]?
    let thumbnail: String?
    // These fields are deprecated - using Client reference instead
    let clientName: String?
    let clientEmail: String?
    let clientPhone: String?
    let projectImages: [String]?  // Added this field
    let duration: Int? // Duration in days
    let eventType: String? // CalendarEventType - "Task" or "Project"
    let tasks: [BubbleReference]? // List of tasks associated with this project
    
    // Additional fields from the actual API response
    let projectValue: Double?
    let projectGrossCost: Double?
    let balance: Double?
    let slug: String?
    
    // Custom coding keys to match Bubble's field names exactly
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case address = "address"
        case allDay = "allDay"
        case client = "client" // This is the proejct's client, of type "Client" object. We do not need to store this at this point. We will use "Client Name" and "Client Email" and "Client Phone" instead of storing the whole client object. We do not need to store this field.
        case company = "company" // This is the project's company, which is hypothetically the user's company if they are calling this prject. Type "Company" object.
        case completion = "completion" // The completion date of the proejct. type date.
        case description = "description" // description of the project, type string.
        case projectName = "projectName" // Project's name, type string.
        case startDate = "startDate" // starting date of the proejct, type date.
        case status = "status" // Status of the project, Type "Job Status", which contains the fields Display (string), Index (number) and Color (string for hex color). Options are either RFQ, Estimated, Accepted, In Progress, Completed, Closed, or Archived.
        case teamNotes = "teamNotes" // Field to track notes, type string.
        case teamMembers = "teamMembers" //the team members assigned to the project, a list of type User.
        case thumbnail = "thumbnail" // A thumbnail image of the project, type image.
        case projectValue = "projectValue" // The net value of the project. We do not need to store this for now.
        case projectGrossCost = "projectGrossCost" // The gross cost of the proejct. We dont need to store this for now.
        case balance = "balance" // The outstanding project balance. Dont need to store this now.
        case slug = "Slug" // The project's URL slug (Bubble default field). We don't need to store this in the app.
        case clientName = "clientName" // The project's client's name. type string.
        case clientEmail = "clientEmail" // The client's email address. type string.
        case clientPhone = "clientPhone" // The client's phone number. type string.
        case projectImages = "projectImages" // list of type image, that have been uploaded to the project object.
        case duration = "duration" // Duration in days for the project. type number.
        case eventType = "eventType" // CalendarEventType - determines if project uses task-based or project scheduling
        case tasks = "tasks" // List of tasks associated with this project, type list of Task
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
            
        // Store client reference if available
        if let clientId = client {
            project.clientId = clientId
        } else {
            // Debug: Check if we at least have the deprecated text fields
            if let cName = clientName {
            }
        }
        
        // Store client info only as fallback if text fields exist (deprecated)
        // Client name now comes from Client relationship
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
        
        // Store duration for cases where end date is invalid
        project.duration = duration
        
        project.notes = teamNotes
        project.projectDescription = description
        project.allDay = allDay ?? false
        
        // Set eventType - default to .project if nil
        if let eventTypeString = eventType {
            project.eventType = CalendarEventType(rawValue: eventTypeString.lowercased()) ?? .project
        } else {
            project.eventType = .project // Default to project scheduling if not specified
        }
        
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
