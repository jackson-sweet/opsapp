//
//  APIService.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import Foundation

// MARK: - Bubble Response Wrapper Types

/// Wrapper for Bubble list responses
struct BubbleListResponse<T: Decodable>: Decodable {
    let response: ResultsWrapper
    
    struct ResultsWrapper: Decodable {
        let cursor: Int
        let results: [T]
        let remaining: Int?
        let count: Int?
    }
}

/// Wrapper for Bubble single object responses
struct BubbleObjectResponse<T: Decodable>: Decodable {
    let response: T
}

/// Core API service for communicating with Bubble backend
/// Provides a reliable interface even in poor connectivity situations
class APIService {
    private let baseURL: URL
    private let session: URLSession
    private let authManager: AuthManager
    
    // Configurable request timeout - field workers may have poor connectivity
    private let timeoutInterval: TimeInterval = 30.0
    
    // Rate limiting to avoid hammering the server
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 0.5
    
    init(baseURL: URL = AppConfiguration.bubbleBaseURL, authManager: AuthManager, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.authManager = authManager
        
        if let session = session {
            self.session = session
        } else {
            // Create a custom URL session configuration optimized for field conditions
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = timeoutInterval
            config.timeoutIntervalForResource = timeoutInterval
            config.waitsForConnectivity = true  // Wait for connectivity rather than fail immediately
            config.httpMaximumConnectionsPerHost = 5
            
            // Use HTTP/2 for better performance when available
            config.httpAdditionalHeaders = [
                "Accept": "application/json",
                "User-Agent": "OPS-iOS/1.0"
            ]
            
            self.session = URLSession(configuration: config)
        }
    }
    
    // MARK: - User Management
    
    /// Delete a user account
    /// - Parameter id: The user's ID to delete
    /// - Returns: Response containing the deleted user ID
    func deleteUser(id: String) async throws -> DeleteUserResponse {
        
        // Create request body with user parameter
        let requestBody = ["user": id]
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Execute the request to the delete_user endpoint
        let response: DeleteUserResponse = try await executeRequest(
            endpoint: "api/1.1/wf/delete_user",
            method: "POST",
            body: jsonData,
            requiresAuth: false  // Bubble workflow endpoints typically don't require auth headers
        )
        
        return response
    }
    
    // MARK: - Core Request Method

    func executeRequest<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem]? = nil,
        requiresAuth: Bool = false
    ) async throws -> T {
        // Ensure proper URL construction with path separator
        let baseURLString = baseURL.absoluteString.trimmingCharacters(in: ["/"])
        var fullURLString = baseURLString + "/" + endpoint
        
        // Add query parameters if provided
        if let queryItems = queryItems, !queryItems.isEmpty {
            var components = URLComponents(string: fullURLString)
            components?.queryItems = queryItems
            if let url = components?.url {
                fullURLString = url.absoluteString
            }
        }
        
        guard let url = URL(string: fullURLString) else {
            throw APIError.invalidURL
        }
        
        // Create and configure request
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // No authentication token needed for this Bubble API
        
        // Add content type for POST/PUT/PATCH requests
        if method != "GET" {
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        // Add body data for non-GET requests
        if let body = body {
            request.httpBody = body
        }
        
        // Enhanced request logging
        
        // Log query parameters and request body for better debugging
        if let queryItems = queryItems, !queryItems.isEmpty {
            for item in queryItems {
            }
        }
        
        if let body = body, method != "GET" {
            if let bodyString = String(data: body, encoding: .utf8) {
            } else {
            }
        }
        
        // Execute request with enhanced logging
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            print("🔶 API RESPONSE: Status \(httpResponse.statusCode) (\((200...299).contains(httpResponse.statusCode) ? "Success" : "Error"))")
            
            // Check for success status codes
            guard (200...299).contains(httpResponse.statusCode) else {
                print("🔴 HTTP Error: \(httpResponse.statusCode)")
                throw APIError.httpError(statusCode: httpResponse.statusCode)
            }
            
            // Handle HTTP 204 No Content responses (empty body)
            if httpResponse.statusCode == 204 {
                // For 204 responses, return EmptyResponse without trying to decode
                if T.self == EmptyResponse.self {
                    return EmptyResponse() as! T
                } else {
                    // If expecting a different type but got 204, this might be an API issue
                    throw APIError.decodingFailed
                }
            }
            
            // Handle empty response bodies (can happen with HTTP 200 for some update operations)
            if data.isEmpty {
                if T.self == EmptyResponse.self {
                    return EmptyResponse() as! T
                } else {
                    throw APIError.decodingFailed
                }
            }
            
            // Print debug info for non-empty responses
            printResponseDebugInfo(data, from: request.url!)
            
            // Try to decode the response for other success status codes
            do {
                let result: T = try decodeResponse(data: data)
                return result
            } catch {
                print("🔴 Decoding failed: \(error)")
                
                // For DecodingError, print more detailed debugging info
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, _):
                        break
                    case .typeMismatch(let type, _):
                        break
                    case .dataCorrupted(let context):
                        // Also check if this is due to an empty response that should be handled
                        if context.debugDescription.contains("Unexpected end of file") {
                            if T.self == EmptyResponse.self {
                                return EmptyResponse() as! T
                            }
                        }
                    default:
                        print("Other decoding error: \(decodingError)")
                    }
                }
                
                throw APIError.decodingFailed
            }
        } catch let apiError as APIError {
            throw apiError
        } catch {
            print("🔴 API request failed: \(error)")
            throw APIError.networkError
        }
    }
    
    // MARK: - Centralized Bubble API Methods
    
    /// Centralized method for fetching objects from Bubble with dynamic constraints
    /// - Parameters:
    ///   - objectType: The type of object to fetch (e.g., "Project", "User")
    ///   - constraints: Optional constraints to filter results
    ///   - limit: Maximum number of results to return (default: 100)
    ///   - cursor: Pagination cursor (default: 0)
    ///   - sortField: Optional field to sort by
    ///   - sortOrder: Sort direction ("asc" or "desc")
    /// - Returns: Array of objects matching the specified type and constraints
    func fetchBubbleObjects<T: Decodable>(
        objectType: String,
        constraints: [String: Any]? = nil,
        limit: Int = 100,
        cursor: Int = 0,
        sortField: String? = nil,
        sortOrder: String = "asc"
    ) async throws -> [T] {
        // Build query parameters
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "cursor", value: "\(cursor)")
        ]
        
        // Add sorting if specified
        if let sortField = sortField {
            queryItems.append(URLQueryItem(name: "sort_field", value: sortField))
            queryItems.append(URLQueryItem(name: "sort_order", value: sortOrder))
        }
        
        // Add constraints if provided
        if let constraints = constraints {
            do {
                // Determine if this is a direct constraint or a nested one
                var constraintsObject: Any
                
                // Check if we need to convert to Bubble's expected array format
                if let key = constraints["key"] as? String,
                   let _ = constraints["constraint_type"] as? String,
                   constraints["value"] != nil {
                    // This is a single constraint object that needs to be wrapped in an array
                    constraintsObject = [constraints]
                } else if constraints["and"] != nil || constraints["or"] != nil {
                    // This is already a complex constraint, use as is
                    constraintsObject = constraints
                } else {
                    // Use as provided
                    constraintsObject = constraints
                }
                
                // Convert to JSON
                let jsonData = try JSONSerialization.data(withJSONObject: constraintsObject)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    queryItems.append(URLQueryItem(name: "constraints", value: jsonString))
                    
                    // Enhanced debug logging
                    
                    // Try to pretty print the constraints for better debugging
                    if let prettyData = try? JSONSerialization.data(withJSONObject: constraintsObject, options: [.prettyPrinted]),
                       let prettyString = String(data: prettyData, encoding: .utf8) {
                    }
                    
                    // Log specific constraint types for debugging
                    if let andConstraints = constraints["and"] as? [[String: Any]] {
                    } else if let orConstraints = constraints["or"] as? [[String: Any]] {
                    } else if let key = constraints["key"] as? String, 
                              let constraintType = constraints["constraint_type"] as? String,
                              let value = constraints["value"] {
                    }
                }
            } catch {
                print("❌ Error serializing constraints: \(error)")
                throw APIError.invalidURL
            }
        }
        
        // Construct endpoint
        let endpoint = "api/1.1/obj/\(objectType)"
        
        // Execute the request
        let wrapper: BubbleListResponse<T> = try await executeRequest(
            endpoint: endpoint,
            queryItems: queryItems,
            requiresAuth: true  // Changed to true to ensure proper authentication
        )
        
        // Log results
        
        return wrapper.response.results
    }
    
    /// Fetch objects using array-style constraints format
    func fetchBubbleObjectsWithArrayConstraints<T: Decodable>(
        objectType: String,
        constraints: [[String: Any]]?,
        limit: Int = 100,
        cursor: Int = 0,
        sortField: String? = nil,
        sortOrder: String = "asc"
    ) async throws -> [T] {
        // Build endpoint
        let endpoint = "api/1.1/obj/\(objectType)"
        
        // Build query items
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "cursor", value: "\(cursor)")
        ]
        
        // Add sort parameters if provided
        if let sortField = sortField {
            queryItems.append(URLQueryItem(name: "sort_field", value: sortField))
            queryItems.append(URLQueryItem(name: "sort_order", value: sortOrder))
        }
        
        // Add constraints as an array
        if let constraints = constraints {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: constraints)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    queryItems.append(URLQueryItem(name: "constraints", value: jsonString))
                }
            } catch {
                print("Failed to serialize constraints: \(error)")
            }
        }
        
        // Log request details
        
        // Execute request
        let wrapper: BubbleListResponse<T> = try await executeRequest(
            endpoint: endpoint,
            queryItems: queryItems,
            requiresAuth: true  // Changed to true to ensure proper authentication
        )
        
        return wrapper.response.results
    }
    
    /// Fetch a single object by ID
    /// - Parameters:
    ///   - objectType: The type of object to fetch
    ///   - id: The object's unique ID
    /// - Returns: The requested object
    func fetchBubbleObject<T: Decodable>(
        objectType: String,
        id: String
    ) async throws -> T {
        let endpoint = "api/1.1/obj/\(objectType)/\(id)"
        
        print("🔵 Fetching \(objectType) with ID: \(id)")
        
        // Execute the request
        let wrapper: BubbleObjectResponse<T> = try await executeRequest(
            endpoint: endpoint,
            requiresAuth: true  // Changed to true to ensure proper authentication
        )
        
        // Log the response for debugging
        if objectType == BubbleFields.Types.user {
            print("🟢 User fetch successful")
            // Try to print company info if it's a user object
            if let userData = wrapper.response as? UserDTO {
                print("   User company ID: \(userData.company ?? "none")")
                print("   User email: \(userData.email ?? "none")")
                print("   User type: \(userData.userType ?? "none")")
            }
        }
        
        return wrapper.response
    }
    
    
    // MARK: - Constraint Builders
    
    /// Create a constraint for objects associated with a specific user
    /// - Parameter userId: The user's ID
    /// - Returns: A constraint dictionary
    func userConstraint(userId: String) -> [String: Any] {
        return [
            "key": BubbleFields.Project.teamMembers,
            "constraint_type": "contains",
            "value": userId
        ]
    }
    
    /// Create a constraint for objects within a date range
    /// - Parameters:
    ///   - field: The date field to check
    ///   - startDate: Range start date
    ///   - endDate: Range end date
    /// - Returns: A constraint dictionary
    func dateRangeConstraint(field: String, startDate: Date, endDate: Date) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        return [
            "key": field,
            "constraint_type": "is between",
            "value": [
                formatter.string(from: startDate),
                formatter.string(from: endDate)
            ]
        ]
    }
    
    /// Create a constraint for objects matching a specific company
    /// - Parameter companyId: The company's ID
    /// - Returns: A constraint dictionary
    func companyConstraint(companyId: String) -> [String: Any] {
        return [
            "key": BubbleFields.Project.company,
            "constraint_type": "equals",
            "value": companyId
        ]
    }
    
    /// Combine multiple constraints with AND logic
    /// - Parameter constraints: Array of constraint dictionaries
    /// - Returns: A combined constraint dictionary
    func andConstraints(_ constraints: [[String: Any]]) -> [String: Any] {
        return ["and": constraints]
    }
    
    /// Combine multiple constraints with OR logic
    /// - Parameter constraints: Array of constraint dictionaries
    /// - Returns: A combined constraint dictionary
    func orConstraints(_ constraints: [[String: Any]]) -> [String: Any] {
        return ["or": constraints]
    }
    
    // MARK: - Request Helper Methods
    
    private func executeWithRetry<T: Decodable>(request: URLRequest, retries: Int) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            
            // Record last request time for rate limiting
            lastRequestTime = Date()
            
            // Check for HTTP errors
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200..<300:
                // Success, attempt to decode
                do {
                    // Explicitly specify the generic type to help Swift with type inference
                    return try decodeResponse(data: data) as T
                } catch {
                    print("Decoding failed: \(error)")
                    throw APIError.decodingFailed
                }
                
            case 401, 403:
                // Authentication issue
                throw APIError.unauthorized
                
            case 429:
                // Rate limited - back off and retry if possible
                if retries > 0 {
                    // Wait a bit before retrying
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    return try await executeWithRetry(request: request, retries: retries - 1)
                } else {
                    throw APIError.rateLimited
                }
                
            case 500..<600:
                // Server error - retry if possible
                if retries > 0 {
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    return try await executeWithRetry(request: request, retries: retries - 1)
                } else {
                    throw APIError.serverError
                }
                
            default:
                throw APIError.httpError(statusCode: httpResponse.statusCode)
            }
            
        } catch let error as APIError {
            throw error
        } catch {
            // Network error - retry if possible
            if retries > 0 {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                return try await executeWithRetry(request: request, retries: retries - 1)
            } else {
                throw APIError.networkError
            }
        }
    }
    
    private func respectRateLimit() async {
        guard let lastRequest = lastRequestTime else { return }
        
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < minRequestInterval {
            let delayTime = UInt64((minRequestInterval - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayTime)
        }
    }
    
    private func decodeResponse<T: Decodable>(data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        
        // Bubble API wraps responses in a "response" field
        // First try to decode as a wrapper
        do {
            let wrapper = try decoder.decode(BubbleResponseWrapper<T>.self, from: data)
            return wrapper.response
        } catch {
            // If that fails, try to decode directly
            return try decoder.decode(T.self, from: data)
        }
    }
    
    private func printResponseDebugInfo(_ data: Data, from url: URL) {
        if let responseString = String(data: data, encoding: .utf8) {
            let endpoint = url.lastPathComponent
            
            
            // Try to pretty print JSON for better readability
            if let jsonObject = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                
                // Print a preview with truncation for very large responses
                let maxPreviewLength = 1000
                if prettyString.count > maxPreviewLength {
                    let preview = prettyString.prefix(maxPreviewLength)
                } else {
                }
            } else {
                // Fallback if pretty printing fails
                let maxPreviewLength = 500
                if responseString.count > maxPreviewLength {
                    let preview = responseString.prefix(maxPreviewLength)
                } else {
                }
            }
        } else {
        }
    }
}

// Bubble API response wrapper
struct BubbleResponseWrapper<T: Decodable>: Decodable {
    let response: T
}

// Empty response for endpoints that don't return data
struct EmptyResponse: Decodable {}

// Response for delete user API call
struct DeleteUserResponse: Decodable {
    let deleted: String?
}

// Helper enum to distinguish between API types
enum BubbleAPIType {
    case data
    case workflow
    
    var path: String {
        switch self {
        case .data:
            return AppConfiguration.bubbleDataAPIPath
        case .workflow:
            return AppConfiguration.bubbleWorkflowAPIPath
        }
    }
}
