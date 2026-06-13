//
//  AuthManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import Foundation

/// Handles authentication and user lookup.
/// Authentication is delegated to FirebaseAuthService.
/// User data loading uses Supabase repositories (data access, not auth).
class AuthManager {
    private let keychain: KeychainManager

    // User information (from users table, not auth provider)
    private var userId: String?

    init(keychain: KeychainManager = KeychainManager(service: AppConfiguration.Auth.keychainService)) {
        self.keychain = keychain
        self.userId = keychain.retrieveUserId()
    }

    // MARK: - Public Methods

    /// Get the current user ID (from users table)
    func getUserId() -> String? {
        return userId
    }

    /// Set the user ID explicitly (used when sync-user API returns the proper UUID).
    func setUserId(_ id: String) {
        self.userId = id
        keychain.storeUserId(id)
    }

    /// Sign out — clear all credentials and tokens.
    ///
    /// Fix #7: Made async so Firebase sign-out completes before returning,
    /// preventing a race window where inflight requests could still get valid
    /// Firebase tokens after the app considers the user signed out.
    func signOut() async {
        userId = nil

        keychain.deleteToken()
        keychain.deleteTokenExpiration()
        keychain.deleteUserId()
        keychain.deleteUsername()
        keychain.deletePassword()

        // Sign out from Firebase Auth and Google on MainActor
        await MainActor.run {
            FirebaseAuthService.shared.signOut()
            GoogleSignInManager.shared.signOut()
        }
    }

    /// Clear keychain credentials synchronously (no Firebase/Google signout).
    /// Used by DataController.logout() which handles Firebase/Google signout directly.
    func clearCredentials() {
        userId = nil
        keychain.deleteToken()
        keychain.deleteTokenExpiration()
        keychain.deleteUserId()
        keychain.deleteUsername()
        keychain.deletePassword()
    }

    // MARK: - Email/Password Auth (Firebase)

    /// Sign in with email and password via Firebase Auth.
    /// Handles transparent migration from Supabase Auth for existing users.
    /// After successful sign-in, fetches the user record from the `users` table
    /// and stores `currentUserId` and `currentUserCompanyId` in UserDefaults.
    func loginWithEmail(_ email: String, password: String) async throws {
        try await FirebaseAuthService.shared.signIn(email: email, password: password)

        // Store in keychain
        let firebaseUID = FirebaseAuthService.shared.firebaseUID ?? ""
        keychain.storeUserId(firebaseUID)
        self.userId = firebaseUID

        // Fetch user + company data from Supabase users table and persist to UserDefaults
        try await loadUserFromSupabase(userId: firebaseUID, email: email)
    }

    /// Create a new account with email and password via Firebase Auth.
    ///
    /// Fix #3: Only stores the Firebase UID temporarily. The correct users-table ID
    /// is set later by OnboardingManager after creating the user row.
    /// Callers must NOT call backfillFirebaseUID until the users-table row exists.
    func signUpWithEmail(_ email: String, password: String) async throws {
        try await FirebaseAuthService.shared.createUser(email: email, password: password)

        let firebaseUID = FirebaseAuthService.shared.firebaseUID ?? ""

        // Store Firebase UID temporarily — OnboardingManager will overwrite
        // with the actual users-table ID after creating the row
        UserDefaults.standard.set(firebaseUID, forKey: "currentUserId")
        UserDefaults.standard.set(firebaseUID, forKey: "user_id")
        keychain.storeUserId(firebaseUID)
        self.userId = firebaseUID
    }

    /// Send a password reset email via Firebase Auth.
    func resetPassword(email: String) async throws {
        try await FirebaseAuthService.shared.resetPassword(email: email)
    }

    /// After authenticating, load the user row from the `users` table
    /// and persist critical identifiers (companyId) so repositories can be initialized.
    ///
    /// Fix #8: When email lookup fails (e.g., returning Apple Sign-In users),
    /// falls back to firebase_uid lookup.
    ///
    /// Fix #9: Logs explicitly when no user row is found instead of silently no-oping.
    func loadUserFromSupabase(userId: String, email: String) async throws {
        let userRepo = UserRepository(companyId: "")

        // Try email lookup first (works for most users)
        var dto: SupabaseUserDTO?
        if !email.isEmpty {
            dto = try await userRepo.fetchByEmail(email)
        }

        // Fallback: lookup by firebase_uid (handles returning Apple users with nil email)
        if dto == nil {
            dto = try await userRepo.fetchByFirebaseUID(userId)
        }

        guard let userDTO = dto else {
            print("[AUTH] No user row found for email='\(email)' or firebase_uid='\(userId)' — likely a new user")
            // Clear stale userId from any previous session to prevent
            // loginWithGoogle from using a different user's ID
            self.userId = nil
            keychain.deleteUserId()
            return
        }

        // Store companyId for repository initialization
        if let companyId = userDTO.companyId, !companyId.isEmpty {
            UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
            UserDefaults.standard.set(companyId, forKey: "company_id")
        }
        // Store the user's own ID from the users table
        // (may differ from Firebase UID — the users table ID is what repositories use)
        UserDefaults.standard.set(userDTO.id, forKey: "currentUserId")
        UserDefaults.standard.set(userDTO.id, forKey: "user_id")
        keychain.storeUserId(userDTO.id)
        self.userId = userDTO.id

        // Store name for display
        UserDefaults.standard.set(userDTO.firstName, forKey: "user_first_name")
        UserDefaults.standard.set(userDTO.lastName, forKey: "user_last_name")
    }

    // MARK: - Firebase UID Backfill

    /// Updates the user's `firebase_uid` and `auth_id` in the Supabase users table
    /// and verifies the write landed.
    ///
    /// This is the legacy-row repair path: server-side `/api/auth/sync-user` now
    /// stamps `firebase_uid` for new accounts, so this exists to fix older rows that
    /// predate that. The two RPCs (`create_company_for_owner`, `join_user_to_company`)
    /// resolve identity off `firebase_uid` = JWT `sub`, so a missing mapping breaks
    /// owner/employee onboarding for legacy accounts — hence the write is now
    /// verified (read back) with a small bounded retry instead of fire-and-forget.
    ///
    /// Best-effort by contract: it is awaited internally (the retry loop is awaited),
    /// but callers dispatch it off the login path so it never blocks user-visible
    /// auth. After `maxAttempts` it gives up silently — it must never raise.
    ///
    /// IMPORTANT: `usersTableId` must be the actual `users.id`, not the Firebase UID.
    /// Only call this after loadUserFromSupabase has resolved the correct users-table ID.
    func backfillFirebaseUID(usersTableId: String) async {
        guard let firebaseUID = FirebaseAuthService.shared.firebaseUID else { return }

        // Safety: don't backfill if we don't have a real users-table ID
        guard !usersTableId.isEmpty else {
            print("[AUTH] Skipping backfill — no users-table ID")
            return
        }

        // Decodes only the column we care about so verification doesn't depend on
        // the full user row shape.
        struct FirebaseUIDRow: Decodable { let firebase_uid: String? }

        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                try await SupabaseService.shared.client
                    .from("users")
                    .update([
                        "firebase_uid": firebaseUID,
                        "auth_id": firebaseUID
                    ])
                    .eq("id", value: usersTableId)
                    .execute()

                // Verify the value actually landed. An update that matches zero rows
                // (e.g. wrong id, RLS) succeeds without error but writes nothing, so
                // a read-back is the only way to know the mapping now exists.
                let rows: [FirebaseUIDRow] = try await SupabaseService.shared.client
                    .from("users")
                    .select("firebase_uid")
                    .eq("id", value: usersTableId)
                    .limit(1)
                    .execute()
                    .value

                if rows.first?.firebase_uid == firebaseUID {
                    print("[AUTH] Firebase UID backfill verified for user: \(usersTableId) (attempt \(attempt))")
                    return
                }

                print("[AUTH] Firebase UID backfill not yet verified for \(usersTableId) (attempt \(attempt)/\(maxAttempts))")
            } catch {
                // Non-fatal — backfill is best-effort
                print("[AUTH] Firebase UID backfill attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription)")
            }

            // Brief bounded backoff between attempts; never an unbounded wait.
            if attempt < maxAttempts {
                try? await Task.sleep(for: .milliseconds(300 * attempt))
            }
        }

        print("[AUTH] Firebase UID backfill gave up for user: \(usersTableId) after \(maxAttempts) attempts")
    }
}
