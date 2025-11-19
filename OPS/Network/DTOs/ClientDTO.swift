//
//  ClientDTO.swift
//  OPS
//
//  Data Transfer Object for Client from Bubble API
//

import Foundation

/// Data Transfer Object for Client from Bubble API
struct ClientDTO: Codable {
    // Client properties from Bubble
    let id: String
    let address: BubbleAddress?
    let emailAddress: String?
    let name: String?
    let phoneNumber: String?
    
    // Additional fields from Bubble (for future use if needed)
    let balance: String?
    let clientIdNo: String?
    let isCompany: Bool?
    let parentCompany: BubbleReference?
    let status: String?
    let thumbnail: String?
    
    // Lists (not needed immediately but part of the schema)
    let clientsList: [String]?
    let estimatesList: [String]?
    let invoices: [String]?
    let projectsList: [String]?
    
    // Sub-clients list (API returns array of IDs, not objects)
    let subClientIds: [String]?
    
    // Metadata
    let createdDate: String?
    let modifiedDate: String?
    let slug: String?

    // Soft delete support
    let deletedAt: String?

    // Custom coding keys to match Bubble's field names exactly
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case address = "address"
        case emailAddress = "emailAddress"
        case name = "name"
        case phoneNumber = "phoneNumber"
        case balance = "balance"
        case clientIdNo = "clientIdNo"
        case isCompany = "isCompany"
        case parentCompany = "parentCompany"
        case status = "status"
        case thumbnail = "avatar"  // Renamed from 'thumbnail' to 'avatar' in Bubble
        case clientsList = "clientsList"  // Not used - may be deleted in future
        case estimatesList = "estimates"  // Changed from 'estimatesList' to 'estimates' in Bubble
        case invoices = "invoices"
        case projectsList = "projectsList"
        case createdDate = "Created Date"  // Bubble default field
        case modifiedDate = "Modified Date"  // Bubble default field
        case slug = "Slug"  // Bubble default field
        case subClientIds = "subClients"  // Changed from 'Sub Clients' to 'subClients'
        case deletedAt = "deletedAt"  // Soft delete timestamp
    }
    
    /// Convert DTO to SwiftData model
    func toModel() -> Client {
        // Enhanced debug logging to understand what we're receiving
        
        // Also check alternative fields that might contain data
        
        // Check if we're getting any data at all
        let hasAnyData = name != nil || emailAddress != nil || phoneNumber != nil || address != nil
        
        let client = Client(
            id: id,
            name: name ?? "Unknown Client",
            email: emailAddress,
            phoneNumber: phoneNumber,
            address: address?.formattedAddress,
            companyId: nil,
            notes: nil
        )
        
        // Set profile image URL if available
        if let thumbnailURL = thumbnail {
            client.profileImageURL = thumbnailURL
        }
        
        // Set coordinates if available
        if let bubbleAddress = address {
            client.latitude = bubbleAddress.lat
            client.longitude = bubbleAddress.lng
        }
        
        // Set parent company if it's a company client
        if let parentRef = parentCompany {
            client.companyId = parentRef.stringValue
        }
        
        // Note: Sub-clients IDs are stored but need to be fetched separately
        // The actual sub-clients will be fetched during the refresh process
        if let ids = subClientIds {
        }

        // Parse deletedAt if present
        if let deletedAtString = deletedAt {
            let formatter = ISO8601DateFormatter()
            client.deletedAt = formatter.date(from: deletedAtString)
        }

        // Parse createdDate if present
        if let createdDateString = createdDate {
            let formatter = ISO8601DateFormatter()
            client.createdAt = formatter.date(from: createdDateString)
        }

        client.lastSyncedAt = Date()

        return client
    }
}