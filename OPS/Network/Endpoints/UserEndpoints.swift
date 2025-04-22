//
//  UserEndpoints.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import Foundation

/// Extension for user-related API endpoints
extension APIService {
    
    /// Fetch all users in the organization
    /// - Returns: Array of user DTOs
    func fetchUsers() async throws -> [UserDTO] {
        return try await executeRequest(
            endpoint: "api/1.1/obj/user",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "cursor", value: "0")
            ]
        )
    }
    
    /// Fetch a single user by ID
    /// - Parameter id: The user ID
    /// - Returns: User DTO
    func fetchUser(id: String) async throws -> UserDTO {
        return try await executeRequest(endpoint: "api/1.1/obj/user/\(id)")
    }
    
    /// Update user data
    /// - Parameters:
    ///   - id: The user ID
    ///   - userData: Dictionary of user properties to update
    func updateUser(id: String, userData: [String: Any]) async throws {
        let bodyData = try JSONSerialization.data(withJSONObject: userData)
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/user/\(id)",
            method: "PATCH",
            body: bodyData
        )
    }
    
    /// Login a user and retrieve an authentication token
    /// - Parameters:
    ///   - username: User's email or username
    ///   - password: User's password
    /// - Returns: Authentication response containing token and user info
    func login(username: String, password: String) async throws -> AuthResponse {
        let loginData = ["username": username, "password": password]
        let bodyData = try JSONSerialization.data(withJSONObject: loginData)
        
        return try await executeRequest(
            endpoint: "api/1.1/wf/login",
            method: "POST",
            body: bodyData
        )
    }
}

/// Authentication response from login endpoint
struct AuthResponse: Decodable {
    let token: String
    let user: UserDTO
}
