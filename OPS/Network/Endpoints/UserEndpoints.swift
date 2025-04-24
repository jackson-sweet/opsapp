//
//  UserEndpoints.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import Foundation

/// Extension for user-related API endpoints
extension APIService {
    
    /// Update user data
    /// - Parameters:
    ///   - id: The user ID
    ///   - userData: Dictionary of user properties to update
    func login(username: String, password: String) async throws -> AuthResponse {
            let loginData = ["username": username, "password": password]
            let bodyData = try JSONSerialization.data(withJSONObject: loginData)
            
            // Use the executeRequest method defined in APIService
            return try await executeRequest(
                endpoint: "api/1.1/wf/login",
                method: "POST",
                body: bodyData
            )
        }
    
    /// Fetch a single user by ID
    /// - Parameter id: The user ID
    /// - Returns: User DTO
    func fetchUser(id: String) async throws -> UserDTO {
        return try await executeRequest(
            endpoint: "api/1.1/obj/user/\(id)",
            requiresAuth: false
        )
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

    func fetchUsers() async throws -> [UserDTO] {
        return try await executeRequest(
            endpoint: "user",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "cursor", value: "0")
            ]
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
