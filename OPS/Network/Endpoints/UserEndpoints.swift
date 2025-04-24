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
        // Create wrapper to match Bubble's response format
        struct UserResponseWrapper: Decodable {
            let response: UserDTO
        }
        
        // Fetch the user without requiring auth
        let wrapper: UserResponseWrapper = try await executeRequest(
            endpoint: "api/1.1/obj/user/\(id)",
            requiresAuth: false
        )
        return wrapper.response
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
            body: bodyData,
            requiresAuth: false
        )
    }

    func fetchUsers() async throws -> [UserDTO] {
        // Create wrapper to match Bubble's response format
        struct UsersResponseWrapper: Decodable {
            let response: [UserDTO]
        }
        
        // Fetch all users without requiring auth
        let wrapper: UsersResponseWrapper = try await executeRequest(
            endpoint: "api/1.1/obj/user",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "cursor", value: "0")
            ],
            requiresAuth: false
        )
        return wrapper.response
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

