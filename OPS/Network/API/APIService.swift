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
    
    /// Update client contact information
    /// - Parameters:
    ///   - clientId: The client's unique ID
    ///   - name: Updated client name
    ///   - email: Updated email address (optional)
    ///   - phone: Updated phone number (optional)
    ///   - address: Updated address (optional)
    /// - Returns: Updated ClientDTO from the API response
    func updateClientContact(clientId: String, name: String, email: String?, phone: String?, address: String?) async throws -> ClientDTO {
        
        // Create request body with client info
        var requestBody: [String: Any] = [
            "client": clientId,
            "name": name
        ]
        
        // Add optional fields if provided
        if let email = email {
            requestBody["email"] = email
        }
        if let phone = phone {
            requestBody["phone"] = phone
        }
        if let address = address {
            requestBody["address"] = address
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        
        // Execute the request to the update_client_contact endpoint
        // The response will contain the updated client object
        let response: UpdateClientResponse = try await executeRequest(
            endpoint: "api/1.1/wf/update_client_contact",
            method: "POST",
            body: jsonData,
            requiresAuth: false  // Bubble workflow endpoints typically don't require auth headers
        )
        
        
        return response.client
    }
    
    // MARK: - Company Management
    
    /// Update company seated employees on Bubble
    /// - Parameters:
    ///   - companyId: The company's unique ID
    ///   - seatedEmployeeIds: Array of user IDs who should have seats
    /// - Returns: Updated CompanyDTO from the API response
    func updateCompanySeatedEmployees(companyId: String, seatedEmployeeIds: [String]) async throws -> CompanyDTO {
        print("🔵 API REQUEST: Updating seated employees for company \(companyId)")
        print("📤 New seated employee IDs: \(seatedEmployeeIds)")
        
        // Create request body with seatedEmployees array
        // Bubble expects an array of strings for the seatedEmployees field
        let requestBody: [String: Any] = [
            "seatedEmployees": seatedEmployeeIds
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📤 Request payload: \(jsonString)")
        }
        
        // Use PATCH to update the company object
        let endpoint = "api/1.1/obj/company/\(companyId)"
        
        print("🔵 Executing PATCH request to: \(endpoint)")

        // Execute the PATCH request manually to log the raw response
        let baseURLString = baseURL.absoluteString.trimmingCharacters(in: ["/"])
        let fullURLString = baseURLString + "/" + endpoint

        guard let url = URL(string: fullURLString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Log the raw response
        print("📥 PATCH Response Status: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 PATCH Raw Response: \(responseString)")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ PATCH failed with status \(httpResponse.statusCode)")
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        // Try to decode the response
        do {
            let wrapper = try JSONDecoder().decode(BubbleObjectResponse<CompanyDTO>.self, from: data)
            print("✅ Successfully updated seated employees for company")
            print("📥 Updated company has \(wrapper.response.seatedEmployees?.count ?? 0) seated employees")
            return wrapper.response
        } catch {
            // For PATCH requests, Bubble might return just a success response without the full object
            // In that case, we need to fetch the updated company
            print("⚠️ PATCH response couldn't be decoded as full company: \(error)")
            print("⚠️ Fetching updated company...")
            
            // Wait a moment for Bubble to process the update
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Fetch the updated company
            return try await fetchCompany(id: companyId)
        }
    }
    
    /// Update user fields in Bubble
    /// - Parameters:
    ///   - userId: The user's unique ID
    ///   - fields: Dictionary of field names and values to update
    /// - Returns: Updated UserDTO from the API response
    func updateUser(userId: String, fields: [String: Any]) async throws {
        print("🔵 API REQUEST: Updating user \(userId)")
        print("📤 Fields to update: \(fields.keys.joined(separator: ", "))")

        let jsonData = try JSONSerialization.data(withJSONObject: fields)

        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📤 Request body: \(jsonString)")
        }

        // Use PATCH to update the user object
        let endpoint = "api/1.1/obj/user/\(userId)"

        print("🔵 Executing PATCH request to: \(endpoint)")

        // Create the full URL
        let fullURL = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: fullURL)
        request.httpMethod = "PATCH"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Execute the raw request - we only care about success, not the response body
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("🔵 PATCH response status: \(httpResponse.statusCode)")

        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 Response body: \(responseString)")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        print("✅ Successfully updated user")
    }

    /// Terminate an employee (remove from company)
    /// - Parameter userId: The user's unique ID to terminate
    func terminateEmployee(userId: String) async throws {
        print("🔵 API REQUEST: Terminating employee \(userId)")

        let endpoint = "api/1.1/wf/terminate_employee"
        let fullURL = baseURL.appendingPathComponent(endpoint)

        var request = URLRequest(url: fullURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: String] = [
            "user": userId
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        if let jsonString = String(data: request.httpBody!, encoding: .utf8) {
            print("📤 Request body: \(jsonString)")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("🔵 terminate_employee response status: \(httpResponse.statusCode)")

        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 Response body: \(responseString)")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        print("✅ Successfully terminated employee")
    }

    /// Update company fields in Bubble
    /// - Parameters:
    ///   - companyId: The company's unique ID
    ///   - fields: Dictionary of field names and values to update
    /// - Returns: Updated CompanyDTO from the API response
    func updateCompanyFields(companyId: String, fields: [String: Any]) async throws {
        print("🔵 API REQUEST: Updating company \(companyId)")
        print("📤 Fields to update: \(fields.keys.joined(separator: ", "))")

        let jsonData = try JSONSerialization.data(withJSONObject: fields)

        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📤 Request body: \(jsonString)")
        }

        // Use PATCH to update the company object
        let endpoint = "api/1.1/obj/company/\(companyId)"

        print("🔵 Executing PATCH request to: \(endpoint)")

        // Create the full URL
        let fullURL = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: fullURL)
        request.httpMethod = "PATCH"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Execute the raw request - we only care about success, not the response body
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("🔵 PATCH response status: \(httpResponse.statusCode)")

        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 Response body: \(responseString)")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        print("✅ Successfully updated company")
    }

    // MARK: - Sub-Client Methods

    func createSubClient(clientId: String, name: String, title: String?, email: String?, phone: String?, address: String?) async throws -> SubClientDTO {
        
        // Create request body
        var requestBody: [String: Any] = [
            "client": clientId,
            "name": name
        ]
        
        // Add optional fields
        if let title = title {
            requestBody["title"] = title
        }
        if let email = email {
            requestBody["email"] = email
        }
        if let phone = phone {
            requestBody["phone"] = phone
        }
        if let address = address {
            requestBody["address"] = address
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        
        let response: SubClientResponse = try await executeRequest(
            endpoint: "api/1.1/wf/create_sub_client",
            method: "POST",
            body: jsonData,
            requiresAuth: false
        )
        
        return response.response.subClient
    }
    
    func editSubClient(subClientId: String, name: String, title: String?, email: String?, phone: String?, address: String?) async throws -> SubClientDTO {
        
        // Create request body
        var requestBody: [String: Any] = [
            "subClient": subClientId,
            "name": name
        ]
        
        // Add optional fields
        if let title = title {
            requestBody["title"] = title
        }
        if let email = email {
            requestBody["email"] = email
        }
        if let phone = phone {
            requestBody["phone"] = phone
        }
        if let address = address {
            requestBody["address"] = address
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        
        let response: SubClientResponse = try await executeRequest(
            endpoint: "api/1.1/wf/edit_sub_client",
            method: "POST",
            body: jsonData,
            requiresAuth: false
        )
        
        return response.response.subClient
    }
    
    func deleteSubClient(subClientId: String) async throws {
        
        // Create request body
        let requestBody: [String: Any] = [
            "subClient": subClientId
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Note: Using struct just for the response structure, we don't need the data
        struct DeleteResponse: Decodable {
            struct Response: Decodable {
                let status: String?
            }
            let response: Response
        }
        
        let _: DeleteResponse = try await executeRequest(
            endpoint: "api/1.1/wf/delete_sub_client",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )

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
            
            
            
            
            
            
            // Check for success status codes
            guard (200...299).contains(httpResponse.statusCode) else {
                // Log error response body for debugging
                if let errorBody = String(data: data, encoding: .utf8) {
                    print("[API_ERROR] HTTP \(httpResponse.statusCode) - Response body: \(errorBody)")
                } else {
                    print("[API_ERROR] HTTP \(httpResponse.statusCode) - Unable to decode error body")
                }

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
            
            // Special logging for company fetches
            if request.url?.absoluteString.contains("/company/") == true {
                print("[SUBSCRIPTION] Raw API Response for Company:")
                if let jsonString = String(data: data, encoding: .utf8) {
                    // Try to parse and pretty print to see date fields
                    if let jsonData = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let response = json["response"] as? [String: Any] {
                        // Look for date fields
                        let dateFields = ["Created Date", "Modified Date", "billingPeriodEnd", "subscriptionEnd", 
                                        "trialStartDate", "trialEndDate", "seatGraceStartDate", "seatGraceEndDate",
                                        "dataSetupScheduledDate", "prioritySupportPurchDate"]
                        print("[SUBSCRIPTION] Date fields in response:")
                        for field in dateFields {
                            if let value = response[field] {
                                print("[SUBSCRIPTION]   \(field): \(value)")
                            }
                        }
                        // Also check seated employees
                        if let seatedEmployees = response["Seated Employees"] {
                            print("[SUBSCRIPTION] Seated Employees field: \(seatedEmployees)")
                        }
                        if let seatedEmployees = response["seatedEmployees"] {
                            print("[SUBSCRIPTION] seatedEmployees field: \(seatedEmployees)")
                        }
                    }
                    // Still print truncated full response
                    let maxLength = 3000
                    if jsonString.count > maxLength {
                        let truncated = String(jsonString.prefix(maxLength))
                        print("[SUBSCRIPTION] Response JSON (truncated): \(truncated)...")
                    } else {
                        print("[SUBSCRIPTION] Response JSON: \(jsonString)")
                    }
                }
            }
            
            // Try to decode the response for other success status codes
            do {
                let result: T = try decodeResponse(data: data)
                return result
            } catch let decodingError {
                print("[SUBSCRIPTION] Decoding failed for \(T.self)")
                if let decodingError = decodingError as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        print("[SUBSCRIPTION] Missing key: \(key.stringValue)")
                        print("[SUBSCRIPTION] Path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .typeMismatch(let type, let context):
                        print("[SUBSCRIPTION] Type mismatch: expected \(type)")
                        print("[SUBSCRIPTION] Path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .valueNotFound(let type, let context):
                        print("[SUBSCRIPTION] Value not found: \(type)")
                        print("[SUBSCRIPTION] Path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .dataCorrupted(let context):
                        print("[SUBSCRIPTION] Data corrupted: \(context.debugDescription)")
                    @unknown default:
                        print("[SUBSCRIPTION] Unknown decoding error")
                    }
                }
                
                throw APIError.decodingFailed
            }
        } catch let apiError as APIError {
            throw apiError
        } catch {
            print("[API_SERVICE] ❌ Unexpected error: \(error)")
            print("[API_SERVICE] ❌ Error type: \(type(of: error))")
            print("[API_SERVICE] ❌ Error description: \(error.localizedDescription)")
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
                throw APIError.invalidURL
            }
        }
        
        // Format object type for API: lowercase, no spaces
        let apiObjectType = objectType.lowercased().replacingOccurrences(of: " ", with: "")
        let endpoint = "api/1.1/obj/\(apiObjectType)"
        
        
        // Execute the request
        let wrapper: BubbleListResponse<T> = try await executeRequest(
            endpoint: endpoint,
            queryItems: queryItems,
            requiresAuth: true  // Changed to true to ensure proper authentication
        )
        
        
        
        
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
        // Format object type for API: lowercase, no spaces
        let apiObjectType = objectType.lowercased().replacingOccurrences(of: " ", with: "")
        let endpoint = "api/1.1/obj/\(apiObjectType)"
        
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

    /// Fetch all objects using pagination (automatically handles multiple pages)
    /// This function will keep fetching pages of 100 items until all items are retrieved
    func fetchBubbleObjectsWithArrayConstraintsPaginated<T: Decodable>(
        objectType: String,
        constraints: [[String: Any]]?,
        sortField: String? = nil,
        sortOrder: String = "asc"
    ) async throws -> [T] {
        var allResults: [T] = []
        var cursor = 0
        let pageSize = 100
        var pageNumber = 1

        print("[PAGINATION] 📊 Starting paginated fetch for \(objectType)")

        while true {
            // Fetch one page
            let pageResults: [T] = try await fetchBubbleObjectsWithArrayConstraints(
                objectType: objectType,
                constraints: constraints,
                limit: pageSize,
                cursor: cursor,
                sortField: sortField,
                sortOrder: sortOrder
            )

            let resultCount = pageResults.count
            allResults.append(contentsOf: pageResults)

            print("[PAGINATION] 📄 Page \(pageNumber): Fetched \(resultCount) \(objectType)s (Total: \(allResults.count))")

            // If we got fewer than pageSize results, we've reached the end
            if resultCount < pageSize {
                print("[PAGINATION] ✅ Completed: Total \(allResults.count) \(objectType)s fetched across \(pageNumber) page(s)")
                break
            }

            // Move to next page
            cursor += pageSize
            pageNumber += 1
        }

        return allResults
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
        // Format object type for API: lowercase, no spaces
        // Bubble API requires: "Sub Client" -> "subclient"
        let apiObjectType = objectType.lowercased().replacingOccurrences(of: " ", with: "")
        let endpoint = "api/1.1/obj/\(apiObjectType)/\(id)"
        
        print("[SUBSCRIPTION] Fetching \(apiObjectType) with ID: \(id)")
        print("[SUBSCRIPTION] Full URL: \(baseURL)/\(endpoint)")
        
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
        print("[API_SERVICE] 🌐 Making request to: \(request.url?.absoluteString ?? "unknown")")
        print("[API_SERVICE] 🌐 Method: \(request.httpMethod ?? "GET")")

        do {
            let (data, response) = try await session.data(for: request)

            print("[API_SERVICE] 📥 Received response, data size: \(data.count) bytes")
            
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
                    print("[API_SERVICE] ❌ Decoding failed for response")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("[API_SERVICE] 📄 Response body: \(responseString.prefix(500))")
                    }
                    print("[API_SERVICE] ❌ Decoding error: \(error)")
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
        } catch let urlError as URLError {
            print("[API_SERVICE] ⚠️ URLError: code=\(urlError.code.rawValue), \(urlError.localizedDescription)")
            print("[API_SERVICE] ⚠️ URL: \(request.url?.absoluteString ?? "unknown")")
            if urlError.code == .cancelled {
                print("[API_SERVICE] ⚠️ Request was CANCELLED - this may indicate a task cancellation or session issue")
            }
            // Network error - retry if possible
            if retries > 0 && urlError.code != .cancelled {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                return try await executeWithRetry(request: request, retries: retries - 1)
            } else {
                print("[API_SERVICE] ❌ Not retrying cancelled request")
                throw APIError.networkError
            }
        } catch {
            // Network error - retry if possible
            print("[API_SERVICE] ⚠️ Request failed (retries left: \(retries)): \(error)")
            if retries > 0 {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                return try await executeWithRetry(request: request, retries: retries - 1)
            } else {
                print("[API_SERVICE] ❌ All retries exhausted. Original error: \(error)")
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

        do {
            let wrapper = try decoder.decode(BubbleResponseWrapper<T>.self, from: data)
            return wrapper.response
        } catch {
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

// Response for update client contact API call
struct UpdateClientResponse: Decodable {
    let client: ClientDTO
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
