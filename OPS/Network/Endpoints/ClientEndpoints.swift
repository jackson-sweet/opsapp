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
        
        let clientConstraint: [String: Any] = [
            "key": BubbleFields.SubClient.parentClient,
            "constraint_type": "equals",
            "value": clientId
        ]
        
        let subClients: [SubClientDTO] = try await fetchBubbleObjects(
            objectType: BubbleFields.Types.subClient,
            constraints: clientConstraint,
            limit: 100,
            sortField: BubbleFields.SubClient.name,
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

    /// Create a new client on Bubble
    /// - Parameter client: The local client to create
    /// - Returns: The Bubble-assigned client ID
    func createClient(_ client: Client) async throws -> String {
        print("[CREATE_CLIENT] Building client data for: \(client.name)")

        var clientData: [String: Any] = [
            BubbleFields.Client.name: client.name
        ]

        print("[CREATE_CLIENT] Required field - name: \(client.name)")

        if let companyId = client.companyId {
            clientData[BubbleFields.Client.parentCompany] = companyId
            print("[CREATE_CLIENT] Parent Company ID: \(companyId)")
        } else {
            print("[CREATE_CLIENT] ⚠️ No company ID - client will be created without company reference")
        }

        if let email = client.email, !email.isEmpty {
            clientData[BubbleFields.Client.emailAddress] = email
            print("[CREATE_CLIENT] Email: \(email)")
        }

        if let phoneNumber = client.phoneNumber, !phoneNumber.isEmpty {
            clientData[BubbleFields.Client.phoneNumber] = phoneNumber
            print("[CREATE_CLIENT] Phone: \(phoneNumber)")
        }

        if let address = client.address, !address.isEmpty {
            var addressObject: [String: Any] = ["address": address]

            if let lat = client.latitude {
                addressObject["lat"] = lat
            }

            if let lng = client.longitude {
                addressObject["lng"] = lng
            }

            clientData[BubbleFields.Client.address] = addressObject
            print("[CREATE_CLIENT] Address object: \(addressObject)")
        }

        if let notes = client.notes, !notes.isEmpty {
            clientData[BubbleFields.Client.notes] = notes
            print("[CREATE_CLIENT] Notes: \(notes)")
        }

        let bodyData = try JSONSerialization.data(withJSONObject: clientData)

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[CREATE_CLIENT] Request body JSON: \(jsonString)")
        }

        print("[CREATE_CLIENT] Sending POST to: api/1.1/obj/\(BubbleFields.Types.client)")

        struct CreateResponse: Codable {
            let id: String
        }

        do {
            let response: CreateResponse = try await executeRequest(
                endpoint: "api/1.1/obj/\(BubbleFields.Types.client)",
                method: "POST",
                body: bodyData,
                requiresAuth: false
            )

            print("[CREATE_CLIENT] ✅ Success! Bubble ID: \(response.id)")
            return response.id
        } catch {
            print("[CREATE_CLIENT] ❌ Error creating client: \(error)")
            throw error
        }
    }

    /// Delete a client from Bubble
    /// - Parameter id: The client ID to delete
    func deleteClient(id: String) async throws {
        print("[DELETE_CLIENT] Deleting client: \(id)")

        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.client)/\(id)",
            method: "DELETE",
            body: nil,
            requiresAuth: false
        )

        print("[DELETE_CLIENT] ✅ Client deleted successfully")
    }

    /// Link a client to a company's Client list
    /// - Parameters:
    ///   - companyId: The company ID
    ///   - clientId: The client ID to link
    func linkClientToCompany(companyId: String, clientId: String) async throws {
        print("[LINK_CLIENT_TO_COMPANY] 🔵 Linking client to company via workflow endpoint")
        print("[LINK_CLIENT_TO_COMPANY] Client ID: \(clientId)")
        print("[LINK_CLIENT_TO_COMPANY] Company ID: \(companyId)")

        let parameters: [String: Any] = [
            "client": clientId,
            "company": companyId
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: parameters)

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[LINK_CLIENT_TO_COMPANY] 📤 Workflow parameters: \(jsonString)")
        }

        print("[LINK_CLIENT_TO_COMPANY] 📡 Calling workflow endpoint...")
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/wf/add-client-to-company",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )
        print("[LINK_CLIENT_TO_COMPANY] ✅ Client successfully added to company list")
    }
}