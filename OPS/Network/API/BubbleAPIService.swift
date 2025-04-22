//
//  BubbleAPIService.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//


import Foundation

// MARK: - Bubble API Service
// Interface to the Bubble.io backend

class BubbleAPIService {
    private let baseURL: URL
    private let session: URLSession
    private let authManager: AuthManager
    
    // Configurable request timeout - field workers may have poor connectivity
    private let timeoutInterval: TimeInterval = 30.0
    
    // Rate limiting to avoid hammering the server
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 0.5
    
    init(baseURL: URL, authManager: AuthManager, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.authManager = authManager
        
        if let customSession = session {
            self.session = customSession
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
    
    private func executeRequest<T: Decodable>(endpoint: String, method: String = "GET", 
                                             body: Data? = nil, queryItems: [URLQueryItem]? = nil) async throws -> T {
        // Rate limit requests
        await respectRateLimit()
        
        // Get authentication token
        let token = try await authManager.getValidToken()
        
        // Build URL with query parameters if provided
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: true)
        urlComponents?.queryItems = queryItems
        
        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }
        
        // Create and configure request
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = body
        }
        
        // Execute request with automatic retry
        return try await executeWithRetry(request: request, retries: 2)
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
    
    // MARK: - API Endpoints - Jobs
    
    func fetchJobs() async throws -> [ProjectDTO] {
        return try await executeRequest(
            endpoint: "api/1.1/obj/job",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "cursor", value: "0"),
                URLQueryItem(name: "sort_field", value: "start_date"),
                URLQueryItem(name: "sort_order", value: "asc"),
                URLQueryItem(name: "constraints", value: constructDateConstraint())
            ]
        )
    }
    
    func fetchJob(id: String) async throws -> ProjectDTO {
        return try await executeRequest(endpoint: "api/1.1/obj/job/\(id)")
    }
    
    func updateJobStatus(id: String, status: String) async throws {
        let statusData = ["status": status]
        let bodyData = try JSONSerialization.data(withJSONObject: statusData)
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/job/\(id)",
            method: "PATCH",
            body: bodyData
        )
    }
    
    // MARK: - API Endpoints - Users
    
    func fetchUsers() async throws -> [UserDTO] {
        return try await executeRequest(
            endpoint: "api/1.1/obj/user",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "cursor", value: "0")
            ]
        )
    }
    
    func fetchUser(id: String) async throws -> UserDTO {
        return try await executeRequest(endpoint: "api/1.1/obj/user/\(id)")
    }
    
    func updateUser(id: String, userData: [String: Any]) async throws {
        let bodyData = try JSONSerialization.data(withJSONObject: userData)
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/user/\(id)",
            method: "PATCH",
            body: bodyData
        )
    }
    
    // MARK: - API Endpoints - Organizations
    
    func fetchOrganization(id: String) async throws -> CompanyDTO {
        return try await executeRequest(endpoint: "api/1.1/obj/organization/\(id)")
    }
    
    // MARK: - Helper Methods
    
    private func constructDateConstraint() -> String {
        // Create a constraint to fetch jobs in a reasonable date range
        // For a field worker, we mainly care about:
        // 1. Recent past jobs (last 30 days)
        // 2. All upcoming jobs
        
        let calendar = Calendar.current
        let now = Date()
        
        // 30 days ago
        let pastDate = calendar.date(byAdding: .day, value: -30, to: now)!
        let dateFormatter = ISO8601DateFormatter()
        
        // JSON structure for Bubble's API
        let constraints: [String: Any] = [
            "or": [
                // All jobs with start_date >= 30 days ago
                ["key": "start_date", "constraint_type": "greater than", "value": dateFormatter.string(from: pastDate)],
                // Plus any in-progress jobs 
                ["key": "status", "constraint_type": "equals", "value": "inProgress"]
            ]
        ]
        
        // Convert to JSON string
        if let jsonData = try? JSONSerialization.data(withJSONObject: constraints),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        // Fallback - if JSON conversion fails
        return ""
    }
}
