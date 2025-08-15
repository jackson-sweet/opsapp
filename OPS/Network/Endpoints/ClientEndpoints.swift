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
        print("🔵 APIService: Fetching client with ID: \(id)")
        
        let client: ClientDTO = try await fetchBubbleObject(
            objectType: BubbleFields.Types.client,
            id: id
        )
        
        print("🟢 APIService: Successfully fetched client:")
        print("  - Name: \(client.name ?? "nil")")
        print("  - Email: \(client.emailAddress ?? "nil")")
        print("  - Phone: \(client.phoneNumber ?? "nil")")
        print("  - Address: \(client.address?.formattedAddress ?? "nil")")
        print("  - Sub-client IDs: \(client.subClientIds ?? [])")
        
        return client
    }
    
    /// Fetch multiple clients by IDs
    /// - Parameter clientIds: Array of client IDs to fetch
    /// - Returns: Array of Client DTOs
    func fetchClientsByIds(clientIds: [String]) async throws -> [ClientDTO] {
        guard !clientIds.isEmpty else { return [] }
        
        print("🔵 APIService: Fetching \(clientIds.count) clients by IDs")
        
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
        
        print("🟢 APIService: Successfully fetched \(clients.count) clients")
        for client in clients.prefix(5) { // Log first 5 for debugging
            print("  - \(client.name ?? "Unknown"): \(client.emailAddress ?? "no email")")
        }
        if clients.count > 5 {
            print("  ... and \(clients.count - 5) more")
        }
        
        return clients
    }
    
    /// Fetch sub-clients for a specific client
    /// - Parameter clientId: The parent client ID
    /// - Returns: Array of SubClient DTOs
    func fetchSubClientsForClient(clientId: String) async throws -> [SubClientDTO] {
        print("🔵 APIService: Fetching sub-clients for client: \(clientId)")
        
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
        
        print("🟢 APIService: Successfully fetched \(subClients.count) sub-clients for client")
        for subClient in subClients.prefix(5) {
            print("  - \(subClient.name ?? "Unknown"): \(subClient.title ?? "no title")")
        }
        if subClients.count > 5 {
            print("  ... and \(subClients.count - 5) more")
        }
        
        return subClients
    }
    
    /// Fetch all clients for a company
    /// - Parameter companyId: The company ID
    /// - Returns: Array of Client DTOs
    func fetchCompanyClients(companyId: String) async throws -> [ClientDTO] {
        print("🔵 APIService: Fetching all clients for company: \(companyId)")
        
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
        
        print("🟢 APIService: Successfully fetched \(clients.count) clients for company")
        for client in clients.prefix(5) { // Log first 5 for debugging
            print("  - \(client.name ?? "Unknown"): \(client.emailAddress ?? "no email"), \(client.phoneNumber ?? "no phone")")
        }
        if clients.count > 5 {
            print("  ... and \(clients.count - 5) more")
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
        print("🔵 APIService: Updating client \(id)")
        
        var updateData: [String: Any] = [:]
        
        if let name = name {
            updateData[BubbleFields.Client.name] = name
            print("  - Updating name to: \(name)")
        }
        if let email = email {
            updateData[BubbleFields.Client.emailAddress] = email
            print("  - Updating email to: \(email)")
        }
        if let phone = phone {
            updateData[BubbleFields.Client.phoneNumber] = phone
            print("  - Updating phone to: \(phone)")
        }
        if let address = address {
            // Note: Address updates may require special handling depending on Bubble's address field format
            updateData[BubbleFields.Client.address] = address
            print("  - Updating address to: \(address)")
        }
        
        guard !updateData.isEmpty else { 
            print("⚠️ APIService: No client data to update")
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
        
        print("🟢 APIService: Successfully updated client \(id)")
    }
}