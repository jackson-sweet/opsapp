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
            
            // Client and company references - extract string IDs
            if let clientRef = client {
                project.clientId = clientRef.stringValue
                project.clientName = "Client" // We might need to fetch client details separately
            }
            
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
        
        // Assign team members - using string storage
        if let teamMemberIds = teamMembers {
            project.teamMemberIdsString = teamMemberIds.joined(separator: ",")
        }
        
        return project
    }
}

/// Bubble's geographic address structure
struct BubbleAddress: Codable {
    let formattedAddress: String
    let lat: Double?
    let lng: Double?
    
    enum CodingKeys: String, CodingKey {
        case formattedAddress = "address"  // Updated to match actual API response
        case lat, lng
    }
}

/// Bubble's reference type - updated to handle both string and object references
struct BubbleReference: Codable {
    let value: ReferenceValue
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try to decode as string first (direct ID reference)
        if let stringValue = try? container.decode(String.self) {
            value = .string(stringValue)
        }
        // Then try to decode as object reference
        else if let objectValue = try? container.decode(ObjectReference.self) {
            value = .object(objectValue)
        }
        // Fallback - treat as empty string
        else {
            value = .string("")
        }
    }
    
    func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch value {
            case .string(let stringValue):
                try container.encode(stringValue)
            case .object(let objectValue):
                try container.encode(objectValue)
            }
        }
    
    struct ObjectReference: Codable {
        let uniqueID: String
        let text: String?
        
        enum CodingKeys: String, CodingKey {
            case uniqueID = "unique_id"
            case text
        }
    }
    
    enum ReferenceValue {
        case string(String)
        case object(ObjectReference)
    }
    
    var stringValue: String {
        switch value {
        case .string(let id):
            return id
        case .object(let obj):
            return obj.uniqueID
        }
    }
}

// Add string conversion for BubbleReference
extension BubbleReference: ExpressibleByStringLiteral {
    typealias StringLiteralType = String
    
    init(stringLiteral value: String) {
        self.value = .string(value)
    }
}
