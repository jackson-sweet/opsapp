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
        
        // Log request for debugging
        print("API Request: \(method) \(url.absoluteString)")
        
        // Execute request with logging
        do {
            let (data, _) = try await session.data(for: request)
            
            // Print debug info to see exactly what's coming back
            printResponseDebugInfo(data, from: request.url!)
            
            // Now try to decode and handle specific errors
            do {
                return try decodeResponse(data: data)
            } catch {
                print("Decoding failed: \(error)")
                
                // For DecodingError, print more detailed debugging info
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, _):
                        print("Missing key: \(key)")
                    case .typeMismatch(let type, _):
                        print("Type mismatch for type: \(type)")
                    default:
                        print("Other decoding error: \(decodingError)")
                    }
                }
                
                throw APIError.decodingFailed
            }
        } catch {
            print("API request failed: \(error)")
            throw error
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
                let jsonData = try JSONSerialization.data(withJSONObject: constraints)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    queryItems.append(URLQueryItem(name: "constraints", value: jsonString))
                    
                    // Debug logging
                    print("🔍 Fetching \(objectType) with constraints: \(jsonString)")
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
        print("✅ Received \(wrapper.response.results.count) \(objectType) objects")
        
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
        print("🔍 Fetching \(objectType) with array constraints")
        
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
        
        // Execute the request
        let wrapper: BubbleObjectResponse<T> = try await executeRequest(
            endpoint: endpoint,
            requiresAuth: true  // Changed to true to ensure proper authentication
        )
        
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
                    return try decodeResponse(data: data)
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
            print("API Response from \(url.absoluteString):")
            print(responseString) // Print first 500 chars to avoid console flooding
            print("...")
        }
    }
}

// Bubble API response wrapper
struct BubbleResponseWrapper<T: Decodable>: Decodable {
    let response: T
}

// Empty response for endpoints that don't return data
struct EmptyResponse: Decodable {}

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
