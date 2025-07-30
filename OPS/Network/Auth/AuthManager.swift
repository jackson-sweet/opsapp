//
//  AuthManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import Foundation
import GoogleSignIn

/// Structure to hold Google login response with user and company
struct GoogleLoginResult {
    let user: UserDTO
    let company: CompanyDTO?
}

/// Structure to hold Apple login response with user data
struct AppleLoginResult {
    let user: UserDTO
}

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
        // Check if we have a cached token that's still valid
        if let token = token, 
           let expiration = tokenExpiration, 
           expiration > Date().addingTimeInterval(300) { // 5-minute buffer
            return token
        }
        
        // Check if we have stored credentials to authenticate
        if keychain.retrieveUsername() != nil && keychain.retrievePassword() != nil {
            do {
                // Try to authenticate and get a new token
                return try await authenticate()
            } catch {
                // If authentication fails, fall back to API token
                print("Authentication failed, falling back to API token: \(error.localizedDescription)")
                return AppConfiguration.bubbleAPIToken
            }
        }
        
        // If no credentials available, use the API token
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
            
            
            // Create request
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Create login payload
            let loginPayload: [String: String] = [
                "email": username,
                "password": password
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: loginPayload)
            
            // Send request
            let (data, response) = try await session.data(for: request)
            
            // Debug response
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔵 Google Login Response: \(responseString)")
            }
            
            // Check HTTP status
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            
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
        
        // Also sign out from Google if applicable
        GoogleSignInManager.shared.signOut()
    }
    
    /// Sign in with Apple
    /// - Parameters:
    ///   - identityToken: Apple identity token (JWT)
    ///   - userIdentifier: Apple's unique user identifier
    ///   - email: User's email (may be relay address or nil)
    ///   - givenName: User's first name (only on first auth)
    ///   - familyName: User's last name (only on first auth)
    /// - Returns: AppleLoginResult containing user data from Bubble
    /// - Throws: AuthError if authentication fails
    func signInWithApple(identityToken: String, userIdentifier: String, email: String?, givenName: String?, familyName: String?) async throws -> AppleLoginResult {
        do {
            // Ensure the baseURL doesn't end with a slash
            let baseURLString = baseURL.absoluteString.trimmingCharacters(in: ["/"])
            
            // Construct the Apple login endpoint URL
            let fullURLString = baseURLString + "/api/1.1/wf/login_apple"
            guard let url = URL(string: fullURLString) else {
                throw AuthError.invalidURL
            }
            
            print("🔵 Apple Sign-In Request:")
            print("   URL: \(fullURLString)")
            print("   User Identifier: \(userIdentifier)")
            print("   Email: \(email ?? "not provided")")
            
            // Create request
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Create payload
            var payload: [String: Any] = [
                "identity_token": identityToken,
                "user_identifier": userIdentifier
            ]
            
            // Add optional fields if available
            if let email = email {
                payload["email"] = email
            }
            if let givenName = givenName {
                payload["given_name"] = givenName
            }
            if let familyName = familyName {
                payload["family_name"] = familyName
            }
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            // Execute request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Log response details
            if let httpResponse = response as? HTTPURLResponse {
                print("🔶 API RESPONSE: Status \(httpResponse.statusCode)")
            }
            
            // Debug: Print raw response
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔵 Apple Login Response: \(responseString)")
            }
            
            // Parse response
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            // Response structures for Apple login
            struct AppleLoginResponse: Codable {
                let status: String
                let response: AppleLoginData?
            }
            
            struct AppleLoginData: Codable {
                let user: UserDTO
            }
            
            do {
                let loginResponse = try decoder.decode(AppleLoginResponse.self, from: data)
                
                // Check status
                guard loginResponse.status == "success" else {
                    print("🔴 Apple login failed: Status not success")
                    throw AuthError.invalidCredentials
                }
                
                // Parse the response - we only expect user data, no company
                if let userDTO = loginResponse.response?.user {
                    print("🟢 Successfully parsed Apple login response")
                    print("   User ID: \(userDTO.id)")
                    print("   Has completed onboarding: \(userDTO.hasCompletedAppOnboarding)")
                    
                    return AppleLoginResult(user: userDTO)
                } else {
                    print("🔴 No user data in Apple login response")
                    throw AuthError.invalidResponse
                }
                
            } catch DecodingError.keyNotFound(let key, let context) {
                print("🔴 Decoding error - missing key: \(key.stringValue)")
                print("   Context: \(context.debugDescription)")
                throw AuthError.decodingFailed
            } catch DecodingError.typeMismatch(let type, let context) {
                print("🔴 Decoding error - type mismatch: \(type)")
                print("   Context: \(context.debugDescription)")
                throw AuthError.decodingFailed
            } catch DecodingError.valueNotFound(let type, let context) {
                print("🔴 Decoding error - value not found: \(type)")
                print("   Context: \(context.debugDescription)")
                throw AuthError.decodingFailed
            } catch {
                print("🔴 Unexpected decoding error: \(error)")
                throw error
            }
        } catch {
            print("🔴 Apple login error: \(error)")
            throw error
        }
    }
    
    /// Sign in with Google ID token
    /// - Parameters:
    ///   - idToken: Google ID token
    ///   - email: User's email from Google
    ///   - name: User's full name
    ///   - givenName: User's first name
    ///   - familyName: User's last name
    /// - Returns: GoogleLoginResult containing user and company data from Bubble
    /// - Throws: AuthError if authentication fails
    func signInWithGoogle(idToken: String, email: String, name: String, givenName: String?, familyName: String?) async throws -> GoogleLoginResult {
        do {
            // Ensure the baseURL doesn't end with a slash
            let baseURLString = baseURL.absoluteString.trimmingCharacters(in: ["/"])
            
            // Construct the Google login endpoint URL
            let fullURLString = baseURLString + "/api/1.1/wf/login_google"
            guard let url = URL(string: fullURLString) else {
                throw AuthError.invalidURL
            }
            
            
            // Create request
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Create login payload matching Apple endpoint
            var loginPayload: [String: String] = [
                "id_token": idToken,
                "email": email,
                "name": name
            ]
            
            // Add optional name fields
            if let givenName = givenName, !givenName.isEmpty {
                loginPayload["given_name"] = givenName
            }
            if let familyName = familyName, !familyName.isEmpty {
                loginPayload["family_name"] = familyName
            }
            
            request.httpBody = try JSONSerialization.data(withJSONObject: loginPayload)
            
            // Send request
            let (data, response) = try await session.data(for: request)
            
            // Debug response
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔵 Google Login Response: \(responseString)")
            }
            
            // Check HTTP status
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            
            // Handle authentication errors
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw AuthError.invalidCredentials
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw AuthError.serverError(httpResponse.statusCode)
            }
            
            // Parse response - expecting a user object
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            do {
                // Try to decode the response with both user and company
                struct GoogleLoginResponse: Decodable {
                    let status: String?
                    let response: ResponseData?
                    
                    struct ResponseData: Decodable {
                        let user: UserDTO?
                        let company: CompanyDTO?
                    }
                }
                
                // First try the wrapped response format
                if let loginResponse = try? decoder.decode(GoogleLoginResponse.self, from: data),
                   let userData = loginResponse.response?.user {
                    
                    print("🟢 Successfully parsed Google login wrapped response")
                    print("   User ID: \(userData.id)")
                    print("   User Email: \(userData.email ?? "none")")
                    print("   Company ID: \(userData.company ?? "none")")
                    print("   Has Company in response: \(loginResponse.response?.company != nil)")
                    
                    // Store user info
                    self.userId = userData.id
                    keychain.storeUserId(userData.id)
                    
                    // Store email as username for consistency
                    keychain.storeUsername(email)
                    
                    // For Google Sign-In, we don't get a separate API token
                    // The authentication is handled by the Google ID token
                    
                    return GoogleLoginResult(
                        user: userData,
                        company: loginResponse.response?.company
                    )
                }
                
                // Try direct format with user and company at root level
                struct DirectGoogleLoginResponse: Decodable {
                    let user: UserDTO
                    let company: CompanyDTO?
                }
                
                if let directResponse = try? decoder.decode(DirectGoogleLoginResponse.self, from: data) {
                    print("🟢 Successfully parsed Google login direct response")
                    print("   User ID: \(directResponse.user.id)")
                    print("   User Email: \(directResponse.user.email ?? "none")")
                    print("   Company ID: \(directResponse.user.company ?? "none")")
                    print("   Has Company object: \(directResponse.company != nil)")
                    
                    // Store user info
                    self.userId = directResponse.user.id
                    keychain.storeUserId(directResponse.user.id)
                    keychain.storeUsername(email)
                    
                    return GoogleLoginResult(
                        user: directResponse.user,
                        company: directResponse.company
                    )
                }
                
                // If we can't decode, throw an error
                print("🔴 Failed to parse Google login response with either format")
                throw AuthError.decodingFailed
                
            } catch {
                print("🔴 Failed to decode Google login response: \(error.localizedDescription)")
                print("Decoding error details: \(error)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("🔵 Raw response that failed to parse: \(responseString)")
                }
                throw AuthError.decodingFailed
            }
        } catch {
            print("Google login error details: \(error)")
            throw error
        }
    }
    
    /// Request a password reset email for the specified email address
    /// - Parameter email: The user's email address
    /// - Returns: Boolean indicating if the request was successfully sent
    func requestPasswordReset(email: String) async throws -> Bool {
        do {
            // Create the reset password URL
            let baseURLString = baseURL.absoluteString.trimmingCharacters(in: ["/"])
            let fullURLString = baseURLString + "/api/1.1/wf/reset_password"
            
            guard let url = URL(string: fullURLString) else {
                throw AuthError.invalidURL
            }
            
            // Create request
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Create reset password payload with just the email
            let resetPayload: [String: String] = [
                "user_email": email
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: resetPayload)
            
            // Send request
            let (data, response) = try await session.data(for: request)
            
            // Debug: Print response
            if let responseString = String(data: data, encoding: .utf8) {
            }
            
            // Check HTTP status
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            // Handle errors
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw AuthError.invalidCredentials
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw AuthError.serverError(httpResponse.statusCode)
            }
            
            return true
        } catch {
            print("Password reset request error: \(error.localizedDescription)")
            throw error
        }
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
