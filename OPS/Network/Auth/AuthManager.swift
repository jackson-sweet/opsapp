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
        
        // Try to load existing token and user info
        self.token = keychain.retrieveToken()
        self.tokenExpiration = keychain.retrieveTokenExpiration()
        self.userId = keychain.retrieveUserId()
    }
    
    // MARK: - Public Methods
    
    /// Get a valid token or authenticate to get a new one
    /// - Returns: A valid authentication token
    /// - Throws: AuthError if authentication fails
    func getValidToken() async throws -> String {
        // Check if we have a valid token already
        if let token = token, let expiration = tokenExpiration, expiration > Date() {
            return token
        }
        
        // Otherwise authenticate to get a new token
        return try await authenticate()
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
        // Store credentials in keychain
        keychain.storeUsername(username)
        keychain.storePassword(password)
        
        // Authenticate with server
        return try await authenticate()
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
    private func authenticate() async throws -> String {
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
                    let token: String
                    let userId: String?
                }
                let response: Response
            }
            
            let loginResponse = try decoder.decode(LoginResponse.self, from: data)
            
            // Store the token and expiration
            let token = loginResponse.response.token
            // Set expiration based on configuration
            let expiration = Date().addingTimeInterval(AppConfiguration.Auth.tokenExpirationSeconds)
            
            self.token = token
            self.tokenExpiration = expiration
            self.userId = loginResponse.response.userId
            
            // Save to keychain
            keychain.storeToken(token)
            keychain.storeTokenExpiration(expiration)
            if let userId = loginResponse.response.userId {
                keychain.storeUserId(userId)
            }
            
            return token
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.networkError(error.localizedDescription)
        }
    }
}
