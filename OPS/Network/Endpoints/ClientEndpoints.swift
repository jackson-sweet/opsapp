//
//  ClientEndpoints.swift
//  OPS
//
//  Client-related API endpoints
//

import Foundation

/// Extension for client-related API endpoints
extension APIService {
    
    /// Fetch a single client by ID
    /// - Parameter id: The client ID
    /// - Returns: Client DTO
    func fetchClient(id: String) async throws -> ClientDTO {
        
        let client: ClientDTO = try await fetchBubbleObject(
            objectType: BubbleFields.Types.client,
            id: id
        )
        
        
        return client
    }
    
    /// Fetch multiple clients by IDs
    /// - Parameter clientIds: Array of client IDs to fetch
    /// - Returns: Array of Client DTOs
    func fetchClientsByIds(clientIds: [String]) async throws -> [ClientDTO] {
        guard !clientIds.isEmpty else { return [] }
        
        
        // Create constraint for multiple IDs
        let idsConstraint: [String: Any] = [
            "key": "_id",
            "constraint_type": "in",
            "value": clientIds
        ]
        
        let clients: [ClientDTO] = try await fetchBubbleObjects(
            objectType: BubbleFields.Types.client,
            constraints: idsConstraint,
            limit: 100,
            sortField: nil,
            sortOrder: "desc"
        )
        
        for client in clients.prefix(5) { // Log first 5 for debugging
        }
        if clients.count > 5 {
        }
        
        return clients
    }
    
    /// Fetch sub-clients for a specific client
    /// - Parameter clientId: The parent client ID
    /// - Returns: Array of SubClient DTOs
    func fetchSubClientsForClient(clientId: String) async throws -> [SubClientDTO] {
        
        // Create constraint for parent client
        // Try "Parent Client" field name as indicated by the error
        let clientConstraint: [String: Any] = [
            "key": "Parent Client",  // Changed from "Client" based on error message
            "constraint_type": "equals",
            "value": clientId
        ]
        
        let subClients: [SubClientDTO] = try await fetchBubbleObjects(
            objectType: BubbleFields.Types.subClient,
            constraints: clientConstraint,
            limit: 100,
            sortField: "Name",
            sortOrder: "asc"
        )
        
        for subClient in subClients.prefix(5) {
        }
        if subClients.count > 5 {
        }
        
        return subClients
    }
    
    /// Fetch all clients for a company
    /// - Parameter companyId: The company ID
    /// - Returns: Array of Client DTOs
    func fetchCompanyClients(companyId: String) async throws -> [ClientDTO] {
        
        // Create constraint for parent company
        let companyConstraint: [String: Any] = [
            "key": BubbleFields.Client.parentCompany,
            "constraint_type": "equals",
            "value": companyId
        ]
        
        let clients: [ClientDTO] = try await fetchBubbleObjects(
            objectType: BubbleFields.Types.client,
            constraints: companyConstraint,
            limit: 500,
            sortField: BubbleFields.Client.name,
            sortOrder: "asc"
        )
        
        for client in clients.prefix(5) { // Log first 5 for debugging
        }
        if clients.count > 5 {
        }
        
        return clients
    }
    
    /// Update a client's information
    /// - Parameters:
    ///   - id: The client ID
    ///   - name: Updated name
    ///   - email: Updated email
    ///   - phone: Updated phone number
    ///   - address: Updated address
    func updateClient(
        id: String,
        name: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        address: String? = nil
    ) async throws {
        
        var updateData: [String: Any] = [:]
        
        if let name = name {
            updateData[BubbleFields.Client.name] = name
        }
        if let email = email {
            updateData[BubbleFields.Client.emailAddress] = email
        }
        if let phone = phone {
            updateData[BubbleFields.Client.phoneNumber] = phone
        }
        if let address = address {
            // Note: Address updates may require special handling depending on Bubble's address field format
            updateData[BubbleFields.Client.address] = address
        }
        
        guard !updateData.isEmpty else { 
            return 
        }
        
        let bodyData = try JSONSerialization.data(withJSONObject: updateData)
        
        // Format object type for API: lowercase, no spaces
        let apiObjectType = BubbleFields.Types.client.lowercased().replacingOccurrences(of: " ", with: "")
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(apiObjectType)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        
    }
}