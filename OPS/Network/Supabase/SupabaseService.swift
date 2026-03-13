// OPS/Network/Supabase/SupabaseService.swift
import Foundation
import Supabase
import FirebaseAuth

/// Central Supabase data client that bridges Firebase Auth via the `accessToken` callback.
///
/// Authentication flow (post-migration):
/// 1. User signs in via Firebase Auth (email, Google, or Apple)
/// 2. The Supabase client's `accessToken` callback fetches the Firebase ID token
/// 3. Supabase validates the Firebase JWT against its configured JWKS endpoint
/// 4. All Supabase queries include the Firebase JWT for RLS policy evaluation
///
/// NOTE: With `accessToken` set, `client.auth` is NOT available.
/// All authentication operations go through `FirebaseAuthService`.
@MainActor
class SupabaseService: ObservableObject {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    accessToken: {
                        // Bridge Firebase Auth → Supabase
                        // Same pattern as OPS-Web/src/lib/supabase/client.ts
                        //
                        // Fix #10: Throw when unauthenticated instead of returning nil.
                        // Returning nil would send anonymous requests using the anon key,
                        // potentially bypassing RLS policies during sign-out transitions.
                        guard let user = Auth.auth().currentUser else {
                            throw SupabaseService.ServiceError.notAuthenticated
                        }
                        return try await user.getIDToken()
                    }
                )
            )
        )
    }

    // MARK: - Errors

    enum ServiceError: LocalizedError {
        case notAuthenticated
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Not authenticated"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            }
        }
    }
}
