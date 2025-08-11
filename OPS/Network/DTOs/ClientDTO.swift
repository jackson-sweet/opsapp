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
    
    // Custom coding keys to match Bubble's field names exactly
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case address = "Address"
        case emailAddress = "Email Address"
        case name = "Name"
        case phoneNumber = "Phone Number"
        case balance = "Balance"
        case clientIdNo = "Client ID No"
        case isCompany = "Is Company"
        case parentCompany = "Parent Company"
        case status = "Status"
        case thumbnail = "Thumbnail"
        case clientsList = "Clients List"
        case estimatesList = "Estimates List"
        case invoices = "Invoices"
        case projectsList = "Projects List"
        case createdDate = "_created_date"
        case modifiedDate = "_modified_date"
        case slug = "Slug"
        case subClientIds = "Sub Clients"
    }
    
    /// Convert DTO to SwiftData model
    func toModel() -> Client {
        // Enhanced debug logging to understand what we're receiving
        print("🔍 ClientDTO.toModel() - Converting client:")
        print("  - ID: \(id)")
        print("  - Name (raw): \(name ?? "nil")")
        print("  - Email Address (raw): \(emailAddress ?? "nil")")
        print("  - Phone Number (raw): \(phoneNumber ?? "nil")")
        print("  - Address: \(address?.formattedAddress ?? "nil")")
        
        // Also check alternative fields that might contain data
        print("  - Client ID No: \(clientIdNo ?? "nil")")
        print("  - Is Company: \(isCompany ?? false)")
        print("  - Status: \(status ?? "nil")")
        print("  - Balance: \(balance ?? "nil")")
        print("  - Thumbnail: \(thumbnail ?? "nil")")
        
        // Check if we're getting any data at all
        let hasAnyData = name != nil || emailAddress != nil || phoneNumber != nil || address != nil
        print("  - Has any data fields: \(hasAnyData)")
        
        let client = Client(
            id: id,
            name: name ?? "Unknown Client",
            email: emailAddress,
            phoneNumber: phoneNumber,
            address: address?.formattedAddress
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
            print("  - Sub-client IDs: \(ids)")
        }
        
        client.lastSyncedAt = Date()
        
        return client
    }
}