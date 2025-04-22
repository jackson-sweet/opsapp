//
//  KeychainManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//


import Foundation
import Security

/// Secure storage for credentials and tokens using iOS Keychain
class KeychainManager {
    // Service name for all keychain items
    private let service: String
    
    init(service: String = AppConfiguration.Auth.keychainService) {
        self.service = service
    }
    
    // MARK: - Username
    
    /// Store username in Keychain
    /// - Parameter username: The username to store
    func storeUsername(_ username: String) {
        let account = "username"
        save(value: username, account: account)
    }
    
    /// Retrieve username from Keychain
    /// - Returns: The stored username or nil if not found
    func retrieveUsername() -> String? {
        let account = "username"
        return retrieve(account: account)
    }
    
    /// Delete username from Keychain
    func deleteUsername() {
        let account = "username"
        delete(account: account)
    }
    
    // MARK: - Password
    
    /// Store password in Keychain
    /// - Parameter password: The password to store
    func storePassword(_ password: String) {
        let account = "password"
        save(value: password, account: account)
    }
    
    /// Retrieve password from Keychain
    /// - Returns: The stored password or nil if not found
    func retrievePassword() -> String? {
        let account = "password"
        return retrieve(account: account)
    }
    
    /// Delete password from Keychain
    func deletePassword() {
        let account = "password"
        delete(account: account)
    }
    
    // MARK: - Token
    
    /// Store authentication token in Keychain
    /// - Parameter token: The token to store
    func storeToken(_ token: String) {
        let account = "token"
        save(value: token, account: account)
    }
    
    /// Retrieve authentication token from Keychain
    /// - Returns: The stored token or nil if not found
    func retrieveToken() -> String? {
        let account = "token"
        return retrieve(account: account)
    }
    
    /// Delete token from Keychain
    func deleteToken() {
        let account = "token"
        delete(account: account)
    }
    
    // MARK: - Token Expiration
    
    /// Store token expiration date in Keychain
    /// - Parameter date: The expiration date
    func storeTokenExpiration(_ date: Date) {
        let account = "tokenExpiration"
        let timestamp = String(date.timeIntervalSince1970)
        save(value: timestamp, account: account)
    }
    
    /// Retrieve token expiration date from Keychain
    /// - Returns: The stored expiration date or nil if not found
    func retrieveTokenExpiration() -> Date? {
        let account = "tokenExpiration"
        guard let timestampString = retrieve(account: account),
              let timestamp = Double(timestampString) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }
    
    /// Delete token expiration from Keychain
    func deleteTokenExpiration() {
        let account = "tokenExpiration"
        delete(account: account)
    }
    
    // MARK: - User ID
    
    /// Store user ID in Keychain
    /// - Parameter userId: The user ID to store
    func storeUserId(_ userId: String) {
        let account = "userId"
        save(value: userId, account: account)
    }
    
    /// Retrieve user ID from Keychain
    /// - Returns: The stored user ID or nil if not found
    func retrieveUserId() -> String? {
        let account = "userId"
        return retrieve(account: account)
    }
    
    /// Delete user ID from Keychain
    func deleteUserId() {
        let account = "userId"
        delete(account: account)
    }
    
    // MARK: - Private Keychain Methods
    
    /// Save a string value to Keychain
    /// - Parameters:
    ///   - value: The string value to save
    ///   - account: The account identifier
    private func save(value: String, account: String) {
        // Convert string to data
        guard let data = value.data(using: .utf8) else { return }
        
        // Create query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        // Delete any existing item before adding
        SecItemDelete(query as CFDictionary)
        
        // Add the new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            print("Failed to save to keychain: \(status)")
        }
    }
    
    /// Retrieve a string value from Keychain
    /// - Parameter account: The account identifier
    /// - Returns: The stored string value or nil if not found
    private func retrieve(account: String) -> String? {
        // Create query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        // Query the keychain
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        // Check if the query was successful
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    /// Delete a value from Keychain
    /// - Parameter account: The account identifier
    private func delete(account: String) {
        // Create query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        // Delete the item
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            print("Failed to delete from keychain: \(status)")
        }
    }
}