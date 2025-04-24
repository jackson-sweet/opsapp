//
//  AuthManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import Foundation

/// Handles all authentication with the Bubble backend
class AuthManager {
    private let baseURL: URL
    private let session: URLSession
    private let keychain: KeychainManager
    
    // Cache of authentication token
    private var token: String?
    private var tokenExpiration: Date?
    
    // User information
    private var userId: String?
    
    init(baseURL: URL = AppConfiguration.bubbleBaseURL,
         keychain: KeychainManager = KeychainManager(service: AppConfiguration.Auth.keychainService),
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.keychain = keychain
        
        // Initialize stored properties
        self.token = keychain.retrieveToken()
        self.tokenExpiration = keychain.retrieveTokenExpiration()
        self.userId = keychain.retrieveUserId()
        
    }
    
    // MARK: - Public Methods
    
    /// Get a valid token or authenticate to get a new one
    /// - Returns: A valid authentication token
    /// - Throws: AuthError if authentication fails
    func getValidToken() async throws -> String {
        return AppConfiguration.bubbleAPIToken
    }
    
    /// Get the current user ID (if authenticated)
    /// - Returns: User ID or nil if not authenticated
    func getUserId() -> String? {
        return userId
    }
    
    /// Sign in with username and password
    /// - Parameters:
    ///   - username: User's email or username
    ///   - password: User's password
    /// - Returns: Authentication token
    /// - Throws: AuthError if authentication fails
    func signIn(username: String, password: String) async throws -> String {
        do {
            // Ensure the baseURL doesn't end with a slash
            let baseURLString = baseURL.absoluteString.trimmingCharacters(in: ["/"])
            
            // Construct the correct URL with proper path separator
            let fullURLString = baseURLString + "/api/1.1/wf/generate-api-token"
            guard let url = URL(string: fullURLString) else {
                throw AuthError.invalidURL
            }
            
            print("Attempting login to: \(url.absoluteString)")
            
            // Create request
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Create login payload
            let loginPayload: [String: String] = [
                "email": username,
                "password": password
            ]
            
            print("Login payload: \(loginPayload)")
            request.httpBody = try JSONSerialization.data(withJSONObject: loginPayload)
            
            // Send request
            let (data, response) = try await session.data(for: request)
            
            // Debug response
            if let responseString = String(data: data, encoding: .utf8) {
                print("Login response: \(responseString)")
            }
            
            // Check HTTP status
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            print("Login HTTP status: \(httpResponse.statusCode)")
            
            // Handle authentication errors
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw AuthError.invalidCredentials
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw AuthError.serverError(httpResponse.statusCode)
            }
            
            // Parse response
            let decoder = JSONDecoder()
            // Don't use snake case conversion since we're mapping exact field names
            
            do {
                // Create struct that exactly matches the response format
                struct BubbleAuthResponse: Decodable {
                    let status: String
                    let response: ResponseDetails
                    
                    struct ResponseDetails: Decodable {
                        let token: String
                        let user_id: String
                        let expires: Int
                    }
                }
                
                let authResponse = try decoder.decode(BubbleAuthResponse.self, from: data)
                
                // Store token and user info
                self.token = authResponse.response.token
                self.userId = authResponse.response.user_id
                
                // Calculate expiration based on expires seconds
                let expiration = Date().addingTimeInterval(Double(authResponse.response.expires))
                self.tokenExpiration = expiration
                
                // Save credentials to keychain
                keychain.storeToken(authResponse.response.token)
                keychain.storeUserId(authResponse.response.user_id)
                keychain.storeTokenExpiration(expiration)
                
                return authResponse.response.token
            } catch {
                print("Failed to decode login response: \(error.localizedDescription)")
                print("Decoding error details: \(error)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Raw response: \(responseString)")
                }
                throw AuthError.decodingFailed
            }
        } catch {
            print("Login error details: \(error)")
            throw error
        }
    }
    
    /// Sign out - clear all credentials and tokens
    func signOut() {
        token = nil
        tokenExpiration = nil
        userId = nil
        
        keychain.deleteToken()
        keychain.deleteTokenExpiration()
        keychain.deleteUserId()
        keychain.deleteUsername()
        keychain.deletePassword()
    }
    
    // MARK: - Private Methods
    
    /// Authenticate with the server
    /// - Returns: Authentication token
    /// - Throws: AuthError if authentication fails
    func authenticate() async throws -> String {
        guard let username = keychain.retrieveUsername(),
              let password = keychain.retrievePassword() else {
            throw AuthError.credentialsNotFound
        }
        
        do {
            // Create the login URL
            let url = baseURL.appendingPathComponent("api/1.1/wf/login")
            
            // Create the request
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(AppConfiguration.bubbleAPIToken, forHTTPHeaderField: "Authorization")
            
            // Create the request body
            let loginPayload: [String: String] = [
                "username": username,
                "password": password
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: loginPayload)
            
            // Send the request
            let (data, response) = try await session.data(for: request)
            
            // Check for HTTP errors
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw AuthError.invalidCredentials
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw AuthError.serverError(httpResponse.statusCode)
            }
            
            // Parse the response
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            struct LoginResponse: Decodable {
                struct Response: Decodable {
                    let token: String?
                    let userId: String?
                    let user: UserResponseDTO?
                }
                let response: Response
            }
            
            struct UserResponseDTO: Decodable {
                let id: String
                // Include other user fields as needed
            }
            
            do {
                let loginResponse = try decoder.decode(LoginResponse.self, from: data)
                
                // Extract and store the user ID
                if let userId = loginResponse.response.userId {
                    self.userId = userId
                    keychain.storeUserId(userId)
                } else if let user = loginResponse.response.user {
                    self.userId = user.id
                    keychain.storeUserId(user.id)
                }
                
                // If Bubble returns a token, use it
                if let token = loginResponse.response.token, !token.isEmpty {
                    self.token = token
                    
                    // Set expiration based on configuration
                    let expiration = Date().addingTimeInterval(AppConfiguration.Auth.tokenExpirationSeconds)
                    self.tokenExpiration = expiration
                    
                    // Save to keychain
                    keychain.storeToken(token)
                    keychain.storeTokenExpiration(expiration)
                    
                    return token
                } else {
                    // Use the API token as fallback
                    return AppConfiguration.bubbleAPIToken
                }
            } catch {
                print("Failed to decode login response: \(error)")
                // Print the response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Raw response: \(responseString)")
                }
                throw AuthError.decodingFailed
            }
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.networkError(error.localizedDescription)
        }
    }
}
