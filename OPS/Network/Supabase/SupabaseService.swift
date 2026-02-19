// OPS/Network/Supabase/SupabaseService.swift
import Foundation
import Supabase

/// Central Supabase client with native auth (Apple Sign-In + Google Sign-In).
///
/// Authentication flow:
/// 1. User signs in with Apple or Google via native SDK (existing flow)
/// 2. The same ID token is passed to Supabase Auth via `signInWithIdToken`
/// 3. Supabase creates/matches a user and returns a session
/// 4. All subsequent Supabase requests use the session JWT automatically
///
/// SETUP REQUIRED (Supabase Dashboard):
/// - Enable Apple provider in Authentication → Providers → Apple
/// - Enable Google provider in Authentication → Providers → Google
/// - Configure the same OAuth client IDs used by the iOS app
@MainActor
class SupabaseService: ObservableObject {
    static let shared = SupabaseService()

    let client: SupabaseClient

    @Published var isAuthenticated: Bool = false
    @Published var currentUserId: String?

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )

        // Check for existing session on init
        Task {
            await restoreSession()
        }
    }

    // MARK: - Session Restoration

    /// Attempt to restore a previous Supabase session from disk.
    func restoreSession() async {
        do {
            let session = try await client.auth.session
            isAuthenticated = true
            currentUserId = session.user.id.uuidString
        } catch {
            isAuthenticated = false
            currentUserId = nil
        }
    }

    // MARK: - Sign In

    /// Authenticate with Supabase using a Google ID token.
    /// Call this after GoogleSignIn completes successfully.
    /// - Parameter idToken: The Google ID token string from `GIDGoogleUser.idToken.tokenString`
    func signInWithGoogle(idToken: String) async throws {
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .google, idToken: idToken)
        )
        isAuthenticated = true
        currentUserId = session.user.id.uuidString
    }

    /// Authenticate with Supabase using an Apple identity token.
    /// Call this after Apple Sign-In completes successfully.
    /// - Parameter identityToken: The Apple identity token JWT string
    func signInWithApple(identityToken: String) async throws {
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: identityToken)
        )
        isAuthenticated = true
        currentUserId = session.user.id.uuidString
    }

    // MARK: - Sign Out

    /// Sign out of Supabase. Call alongside existing sign-out flow.
    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            print("[SupabaseService] Sign-out error: \(error.localizedDescription)")
        }
        isAuthenticated = false
        currentUserId = nil
    }

    // MARK: - Errors

    enum ServiceError: LocalizedError {
        case notAuthenticated
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Not authenticated with Supabase"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            }
        }
    }
}
