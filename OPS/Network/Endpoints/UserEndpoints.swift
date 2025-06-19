//
//  UserEndpoints.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import Foundation

/// Extension for user-related API endpoints
extension APIService {
    
    /// Fetch a single user by ID
    /// - Parameter id: The user ID
    /// - Returns: User DTO
    func fetchUser(id: String) async throws -> UserDTO {
        return try await fetchBubbleObject(
            objectType: BubbleFields.Types.user,
            id: id
        )
    }
    
    /// Update user data
    /// - Parameters:
    ///   - id: The user ID
    ///   - userData: Dictionary of user properties to update
    func updateUser(id: String, userData: [String: Any]) async throws {
        let bodyData = try JSONSerialization.data(withJSONObject: userData)
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.user)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
    }

    /// Fetch all users
    /// - Returns: Array of user DTOs
    func fetchUsers() async throws -> [UserDTO] {
        return try await fetchBubbleObjects(
            objectType: BubbleFields.Types.user,
            limit: 100
        )
    }
    
    /// Fetch users by role
    /// - Parameter role: The role to filter by (e.g., "fieldCrew", "officeCrew")
    /// - Returns: Array of user DTOs
    func fetchUsersByRole(role: String) async throws -> [UserDTO] {
        let roleConstraint: [String: Any] = [
            "key": BubbleFields.User.employeeType,
            "constraint_type": "equals",
            "value": role
        ]
        
        return try await fetchBubbleObjects(
            objectType: BubbleFields.Types.user,
            constraints: roleConstraint
        )
    }
    
    /// Fetch users belonging to a specific company
    /// - Parameter companyId: The company ID
    /// - Returns: Array of user DTOs
    func fetchCompanyUsers(companyId: String) async throws -> [UserDTO] {
        // For the Bubble API, constraints should be in an array format when sent to the server
        // Create a single constraint object for company ID
        let companyUserConstraint: [String: Any] = [
            "key": BubbleFields.User.company,
            "constraint_type": "equals",
            "value": companyId
        ]
        
        
        // Our API service will handle wrapping the constraint in the proper format
        return try await fetchBubbleObjects(
            objectType: BubbleFields.Types.user,
            constraints: companyUserConstraint
        )
    }
    
    /// Fetch users by company and role
    /// - Parameters:
    ///   - companyId: The company ID
    ///   - role: The role to filter by
    /// - Returns: Array of user DTOs
    func fetchCompanyUsersByRole(companyId: String, role: String) async throws -> [UserDTO] {
        let companyConstraint: [String: Any] = [
            "key": BubbleFields.User.company,
            "constraint_type": "equals",
            "value": companyId
        ]
        
        let roleConstraint: [String: Any] = [
            "key": BubbleFields.User.employeeType,
            "constraint_type": "equals",
            "value": role
        ]
        
        let combined = andConstraints([companyConstraint, roleConstraint])
        
        return try await fetchBubbleObjects(
            objectType: BubbleFields.Types.user,
            constraints: combined
        )
    }
    
    /// Fetch users by their IDs
    /// - Parameter userIds: Array of user IDs to fetch
    /// - Returns: Array of user DTOs
    func fetchUsersByIds(userIds: [String]) async throws -> [UserDTO] {
        guard !userIds.isEmpty else {
            return []
        }
        
        // Create a constraint for each ID using OR logic
        var idConstraints: [[String: Any]] = []
        
        for userId in userIds {
            let constraint: [String: Any] = [
                "key": "_id",
                "constraint_type": "equals",
                "value": userId
            ]
            idConstraints.append(constraint)
        }
        
        // Use OR constraint
        let orConstraint = ["or": idConstraints]
        
        // Execute the query
        return try await fetchBubbleObjects(
            objectType: BubbleFields.Types.user,
            constraints: orConstraint,
            limit: userIds.count > 100 ? 100 : userIds.count
        )
    }
}

/// Authentication response from login endpoint
struct AuthResponse: Decodable {
    let response: ResponseContent
    
    struct ResponseContent: Decodable {
        let token: String?
        let user: UserDTO?
    }
    
    // Add computed properties for easier access
    var token: String? { response.token }
    var user: UserDTO? { response.user }
    var userId: String? { user?.id }
}
