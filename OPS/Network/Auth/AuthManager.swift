//
//  AuthManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import Foundation
import GoogleSignIn
import Supabase

/// Handles authentication via Supabase Auth
class AuthManager {
    private let session: URLSession
    private let keychain: KeychainManager

    // User information
    private var userId: String?

    init(keychain: KeychainManager = KeychainManager(service: AppConfiguration.Auth.keychainService),
         session: URLSession = .shared) {
        self.session = session
        self.keychain = keychain

        // Initialize stored properties
        self.userId = keychain.retrieveUserId()
    }

    // MARK: - Public Methods

    /// Get the current user ID (if authenticated)
    func getUserId() -> String? {
        return userId
    }

    /// Sign out - clear all credentials and tokens
    func signOut() {
        userId = nil

        keychain.deleteToken()
        keychain.deleteTokenExpiration()
        keychain.deleteUserId()
        keychain.deleteUsername()
        keychain.deletePassword()

        // Also sign out from Google if applicable
        GoogleSignInManager.shared.signOut()
    }

    // MARK: - Email/Password Auth (Supabase)

    /// Sign in with email and password via Supabase Auth.
    /// After successful sign-in, fetches the user record from the `users` table
    /// and stores `currentUserId` and `currentUserCompanyId` in UserDefaults.
    func loginWithEmail(_ email: String, password: String) async throws {
        let session = try await SupabaseService.shared.client.auth
            .signIn(email: email, password: password)

        let supabaseUserId = session.user.id.uuidString.lowercased()

        // Store in UserDefaults (same keys the app uses elsewhere)
        UserDefaults.standard.set(supabaseUserId, forKey: "currentUserId")
        UserDefaults.standard.set(supabaseUserId, forKey: "user_id")

        // Store in keychain
        keychain.storeUserId(supabaseUserId)
        self.userId = supabaseUserId

        // Fetch user + company data from Supabase and persist to UserDefaults
        try await loadUserFromSupabase(userId: supabaseUserId, email: email)
    }

    /// Create a new account with email and password via Supabase Auth.
    func signUpWithEmail(_ email: String, password: String) async throws {
        let response = try await SupabaseService.shared.client.auth
            .signUp(email: email, password: password)

        let supabaseUserId = response.user.id.uuidString.lowercased()

        UserDefaults.standard.set(supabaseUserId, forKey: "currentUserId")
        UserDefaults.standard.set(supabaseUserId, forKey: "user_id")
        keychain.storeUserId(supabaseUserId)
        self.userId = supabaseUserId
    }

    /// Send a password reset email via Supabase Auth.
    func resetPassword(email: String) async throws {
        try await SupabaseService.shared.client.auth.resetPasswordForEmail(email)
    }

    /// After authenticating with Supabase, load the user row from the `users` table
    /// and persist critical identifiers (companyId) so repositories can be initialized.
    func loadUserFromSupabase(userId: String, email: String) async throws {
        // UserRepository needs a companyId but we don't have it yet.
        // Use an empty-string companyId to perform the email lookup
        // (fetchByEmail queries `users` table globally, not filtered by company).
        let userRepo = UserRepository(companyId: "")
        if let dto = try await userRepo.fetchByEmail(email) {
            // Store companyId for repository initialization
            if let companyId = dto.companyId, !companyId.isEmpty {
                UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
                UserDefaults.standard.set(companyId, forKey: "company_id")
            }
            // Store the user's own ID from the users table
            // (may differ from auth UUID if migrated from legacy system)
            UserDefaults.standard.set(dto.id, forKey: "currentUserId")
            UserDefaults.standard.set(dto.id, forKey: "user_id")
            keychain.storeUserId(dto.id)
            self.userId = dto.id

            // Store name for display
            UserDefaults.standard.set(dto.firstName, forKey: "user_first_name")
            UserDefaults.standard.set(dto.lastName, forKey: "user_last_name")
        }
    }

}
