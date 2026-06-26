//
//  FirebaseAuthService.swift
//  OPS
//
//  Centralized Firebase Auth service for the OPS iOS app.
//  Replaces Supabase Auth as the primary authentication provider.
//  Includes transparent migration for existing Supabase Auth users.
//

import Foundation
import FirebaseAuth
import CryptoKit
import Supabase

/// Centralized Firebase Auth service.
/// All authentication flows (email/password, Google, Apple) go through here.
/// Provides ID token retrieval for API calls and Supabase data access.
@MainActor
class FirebaseAuthService: ObservableObject {
    static let shared = FirebaseAuthService()

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var currentUserEmail: String?

    /// The current Firebase user, if signed in.
    var firebaseUser: FirebaseAuth.User? {
        Auth.auth().currentUser
    }

    /// Current nonce for Apple Sign-In (generated fresh each attempt).
    private var currentNonce: String?

    /// Temporary Supabase client for validating legacy credentials during migration.
    /// This is a separate client from the data client — used ONLY for password validation.
    private lazy var legacyAuthClient: SupabaseClient = {
        SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
    }()

    // Fix #13: init() intentionally does NOT set state —
    // restoreSession() is the single source of truth for session restoration,
    // called explicitly by DataController at app launch.
    private init() {}

    // MARK: - Email / Password

    /// Sign in with email and password.
    /// Handles transparent migration from Supabase Auth:
    /// if Firebase sign-in fails with credentials that may belong to a Supabase-only user,
    /// validates against Supabase Auth and creates a Firebase account.
    ///
    /// Fix #1: Handles both `.userNotFound` and `.invalidCredential` error codes.
    /// Firebase projects with Email Enumeration Protection (default since 2023)
    /// collapse both errors into `.invalidCredential`. We attempt migration for either,
    /// letting Supabase credential validation be the source of truth.
    func signIn(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            isAuthenticated = true
            currentUserEmail = result.user.email
            print("[FIREBASE AUTH] Email sign-in successful: \(email)")
        } catch let error as NSError {
            let authErrorCode = AuthErrorCode(rawValue: error.code)

            // Migration gate: attempt Supabase migration for errors that could
            // indicate the user exists in Supabase but not Firebase.
            // - .userNotFound: Email Enumeration Protection OFF
            // - .invalidCredential: Email Enumeration Protection ON (collapses userNotFound + wrongPassword)
            if authErrorCode == .userNotFound || authErrorCode == .invalidCredential {
                print("[FIREBASE AUTH] Firebase sign-in failed (code: \(error.code)), attempting Supabase migration...")
                try await migrateFromSupabase(email: email, password: password)
            } else {
                print("[FIREBASE AUTH] Sign-in failed: \(error.localizedDescription)")
                throw error
            }
        }
    }

    /// Create a new account with email and password.
    func createUser(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        isAuthenticated = true
        currentUserEmail = result.user.email
        print("[FIREBASE AUTH] Account created: \(email)")
    }

    /// Send a password reset email.
    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
        print("[FIREBASE AUTH] Password reset email sent to: \(email)")
    }

    // MARK: - Google Sign-In

    /// Sign in with Google credentials.
    /// Called after GoogleSignInManager completes the native Google sign-in flow.
    /// - Parameters:
    ///   - idToken: The Google ID token from `GIDGoogleUser.idToken.tokenString`
    ///   - accessToken: The Google access token from `GIDGoogleUser.accessToken.tokenString`
    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: accessToken
        )
        let result = try await Auth.auth().signIn(with: credential)
        isAuthenticated = true
        currentUserEmail = result.user.email
        print("[FIREBASE AUTH] Google sign-in successful: \(result.user.email ?? "no email")")
    }

    // MARK: - Apple Sign-In

    /// Generates a nonce and returns both the raw nonce (for Firebase) and SHA256 hash (for Apple).
    /// Call this BEFORE initiating the Apple Sign-In request.
    /// - Returns: Tuple of (rawNonce, sha256HashedNonce)
    /// - Throws: `FirebaseAuthServiceError.nonceGenerationFailed` if secure random bytes cannot be generated
    func prepareAppleSignIn() throws -> (raw: String, hashed: String) {
        let nonce = try generateSecureNonce()
        currentNonce = nonce
        return (raw: nonce, hashed: sha256(nonce))
    }

    /// Sign in with Apple credentials.
    /// Called after AppleSignInManager completes the native Apple sign-in flow.
    /// Uses the nonce generated by `prepareAppleSignIn()`.
    /// - Parameter identityToken: The Apple identity token JWT string
    func signInWithApple(identityToken: String) async throws {
        guard let nonce = currentNonce else {
            throw FirebaseAuthServiceError.missingNonce
        }

        // Fix #12: Clear nonce immediately — it's single-use regardless of outcome.
        // A new nonce is generated for each attempt via prepareAppleSignIn().
        currentNonce = nil

        let credential = OAuthProvider.appleCredential(
            withIDToken: identityToken,
            rawNonce: nonce,
            fullName: nil
        )
        let result = try await Auth.auth().signIn(with: credential)
        isAuthenticated = true
        currentUserEmail = result.user.email
        print("[FIREBASE AUTH] Apple sign-in successful: \(result.user.email ?? "no email")")
    }

    // MARK: - Token Retrieval

    /// Get the current Firebase ID token for API authentication.
    /// This token is sent as Bearer token to web API endpoints
    /// and used by the Supabase `accessToken` callback for data queries.
    /// Returns a cached token or refreshes if expired, unless forced.
    ///
    /// Fix #11: This method is nonisolated to avoid forcing a MainActor hop
    /// on every API call from background contexts.
    nonisolated func getIDToken(forcingRefresh forceRefresh: Bool = false) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw FirebaseAuthServiceError.notAuthenticated
        }
        return try await user.getIDToken(forcingRefresh: forceRefresh)
    }

    /// Like `getIDToken()` but also returns the token's absolute expiry. Used by
    /// the session bridge so the share extension can tell whether the cached
    /// token still has enough life to presign an upload itself (it must never
    /// refresh tokens). Returns a cached token or refreshes if expired — same
    /// semantics as `getIDToken()`.
    nonisolated func getIDTokenResult(forcingRefresh forceRefresh: Bool = false) async throws -> (token: String, expiresAt: Date) {
        guard let user = Auth.auth().currentUser else {
            throw FirebaseAuthServiceError.notAuthenticated
        }
        let result = try await user.getIDTokenResult(forcingRefresh: forceRefresh)
        return (result.token, result.expirationDate)
    }

    /// Get the Firebase UID of the current user.
    /// Nonisolated because Auth.auth().currentUser is thread-safe in Firebase SDK.
    nonisolated var firebaseUID: String? {
        Auth.auth().currentUser?.uid
    }

    // MARK: - Session

    /// Check if there's an existing Firebase session (app launch restoration).
    /// Firebase Auth persists sessions automatically — this syncs our @Published state.
    /// This is the single entry point for session state initialization.
    func restoreSession() {
        if let user = Auth.auth().currentUser {
            isAuthenticated = true
            currentUserEmail = user.email
            print("[FIREBASE AUTH] Session restored for: \(user.email ?? "unknown")")
        } else {
            isAuthenticated = false
            currentUserEmail = nil
            print("[FIREBASE AUTH] No existing session")
        }
    }

    // MARK: - Sign Out

    /// Sign out of Firebase Auth.
    func signOut() {
        do {
            try Auth.auth().signOut()
            isAuthenticated = false
            currentUserEmail = nil
            currentNonce = nil
            print("[FIREBASE AUTH] Signed out")
        } catch {
            print("[FIREBASE AUTH] Sign-out error: \(error.localizedDescription)")
        }
    }

    // MARK: - Account Deletion

    /// Delete the current Firebase Auth account permanently.
    /// Must be called BEFORE signing out, since it requires an authenticated user.
    /// Recent authentication may be required — Firebase will throw
    /// `.requiresRecentLogin` if the session is too old.
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw FirebaseAuthServiceError.notAuthenticated
        }
        try await user.delete()
        isAuthenticated = false
        currentUserEmail = nil
        currentNonce = nil
        print("[FIREBASE AUTH] Account deleted permanently")
    }

    // MARK: - Migration (Supabase → Firebase)

    /// Validates credentials against Supabase Auth, then creates a Firebase account.
    /// Used for transparent migration of existing users on first login after the switch.
    ///
    /// Fix #2: Signs out of the legacy Supabase auth client after migration
    /// to prevent session leaks and stale keychain tokens.
    private func migrateFromSupabase(email: String, password: String) async throws {
        // Validate credentials against Supabase Auth
        do {
            _ = try await legacyAuthClient.auth.signIn(email: email, password: password)
            print("[FIREBASE AUTH] Supabase credentials valid, creating Firebase account...")
        } catch {
            // Credentials invalid in both Firebase and Supabase.
            // Check if the user exists in the users table — if so, they may have
            // signed up with Google or Apple and need to use that method instead.
            print("[FIREBASE AUTH] Supabase validation failed — checking if user exists with different auth method")
            let userExists = await checkUserExistsByEmail(email)
            if userExists {
                throw await wrongAuthMethodError(for: email)
            }
            throw FirebaseAuthServiceError.invalidCredentials
        }

        // Clean up the Supabase auth session immediately — we only needed it for validation
        defer {
            Task { [legacyAuthClient] in
                try? await legacyAuthClient.auth.signOut()
                print("[FIREBASE AUTH] Legacy Supabase auth session cleaned up")
            }
        }

        // Credentials are valid — create Firebase account
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            isAuthenticated = true
            currentUserEmail = result.user.email
            print("[FIREBASE AUTH] Migration complete — Firebase account created for: \(email)")
        } catch let error as NSError {
            let authErrorCode = AuthErrorCode(rawValue: error.code)
            if authErrorCode == .emailAlreadyInUse {
                // Account exists in Firebase with a different provider (Google/Apple).
                // The user needs to sign in with that provider, not email+password.
                print("[FIREBASE AUTH] Firebase account exists with different provider for: \(email)")
                throw await wrongAuthMethodError(for: email)
            } else {
                throw error
            }
        }
    }

    /// Resolves the most specific `wrongAuthMethod` variant for a given email by
    /// calling the ops-web `/api/auth/method-hint` endpoint, which uses the
    /// Firebase Admin SDK to inspect `providerData`. Falls back to the generic
    /// `wrongAuthMethod` error when the lookup fails or the provider is unknown.
    private func wrongAuthMethodError(for email: String) async -> FirebaseAuthServiceError {
        let providers = await fetchAuthMethodHint(email: email)
        if providers.contains("apple.com") {
            return .registeredWithApple
        }
        if providers.contains("google.com") {
            return .registeredWithGoogle
        }
        return .wrongAuthMethod
    }

    /// Query the ops-web method-hint endpoint for a list of Firebase provider IDs
    /// tied to the given email. Returns an empty array on any failure — callers
    /// must treat "no hint" identically to "lookup failed" to avoid enumeration.
    private func fetchAuthMethodHint(email: String) async -> [String] {
        let url = AppConfiguration.apiBaseURL.appendingPathComponent("/api/auth/method-hint")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 6

        let payload: [String: String] = ["email": email]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return []
        }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            let decoded = try JSONDecoder().decode(MethodHintResponse.self, from: data)
            return decoded.providers
        } catch {
            print("[FIREBASE AUTH] method-hint lookup failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Check if a user with this email exists in the users table.
    /// Used to distinguish "wrong password" from "wrong auth method" errors.
    private func checkUserExistsByEmail(_ email: String) async -> Bool {
        do {
            // Use a temporary anon-key-only client since the user isn't authenticated
            // and the main SupabaseService client's accessToken would throw.
            // The check_user_exists_by_email RPC is SECURITY DEFINER.
            let result: [UserExistsResponse] = try await legacyAuthClient
                .rpc("check_user_exists_by_email", params: ["p_email": email])
                .execute()
                .value
            return result.first?.userExists ?? false
        } catch {
            print("[FIREBASE AUTH] User existence check failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Nonce Helpers (Apple Sign-In)

    /// Generates a cryptographically secure random nonce string for Apple Sign-In.
    ///
    /// Fix #5: Throws instead of fatalError if SecRandomCopyBytes fails.
    /// Fix #6: Uses bitmask (& 0x3F) for uniform distribution over 64-char charset
    /// instead of modulo which introduces bias (256 is not evenly divisible by 64...
    /// actually 256/64 = 4 exactly, but the bitmask is still cleaner and canonical).
    private func generateSecureNonce(length: Int = 32) throws -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard errorCode == errSecSuccess else {
            throw FirebaseAuthServiceError.nonceGenerationFailed
        }
        // 64-character charset — exactly 2^6, so masking 6 bits gives uniform distribution
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0 & 0x3F)] })
    }

    /// SHA256 hash of a string, returned as a hex string.
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Errors

    enum FirebaseAuthServiceError: LocalizedError {
        case notAuthenticated
        case missingNonce
        case nonceGenerationFailed
        case invalidCredentials
        case wrongAuthMethod
        case registeredWithApple
        case registeredWithGoogle
        case migrationFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "NOT SIGNED IN. LOG IN TO CONTINUE."
            case .missingNonce:
                return "APPLE SIGN IN FAILED. TRY AGAIN."
            case .nonceGenerationFailed:
                return "COULDN'T GENERATE SECURE TOKEN. TRY AGAIN."
            case .invalidCredentials:
                return "WRONG EMAIL OR PASSWORD."
            case .wrongAuthMethod:
                return "EMAIL REGISTERED WITH APPLE OR GOOGLE. USE THAT METHOD TO SIGN IN."
            case .registeredWithApple:
                return "EMAIL REGISTERED WITH APPLE. SIGN IN WITH APPLE TO CONTINUE."
            case .registeredWithGoogle:
                return "EMAIL REGISTERED WITH GOOGLE. SIGN IN WITH GOOGLE TO CONTINUE."
            case .migrationFailed(let message):
                return "ACCOUNT MIGRATION FAILED. \(message.uppercased())"
            }
        }
    }
}

/// Response type for check_user_exists_by_email RPC
private struct UserExistsResponse: Decodable {
    let userExists: Bool

    enum CodingKeys: String, CodingKey {
        case userExists = "user_exists"
    }
}

/// Response type for the ops-web `/api/auth/method-hint` endpoint.
private struct MethodHintResponse: Decodable {
    let providers: [String]
}
