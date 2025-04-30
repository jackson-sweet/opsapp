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
        let companyUserConstraint: [String: Any] = [
            "key": BubbleFields.User.company,
            "constraint_type": "equals",
            "value": companyId
        ]
        
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
