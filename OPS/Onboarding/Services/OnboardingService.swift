//
//  OnboardingService.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//
//  Provides invite-sending functionality via ops-web API routes.
//

import Foundation
// FirebaseAuthService used for token retrieval (Firebase Auth migration)

class OnboardingService {

    init() {}

    // MARK: - Sync User via ops-web

    /// Creates or looks up a user via the ops-web /api/auth/sync-user endpoint.
    /// This endpoint uses the service role client (bypasses RLS) and generates
    /// a proper UUID for the user's id — fixing the Firebase UID ≠ UUID mismatch.
    ///
    /// - Parameters:
    ///   - email: User's email address
    ///   - firstName: Optional first name
    ///   - lastName: Optional last name
    ///   - photoURL: Optional profile photo URL
    /// - Returns: SyncUserResponse containing the user with a proper UUID id
    func syncUser(email: String, firstName: String? = nil, lastName: String? = nil, photoURL: String? = nil) async throws -> SyncUserResponse {
        let idToken: String
        do {
            idToken = try await FirebaseAuthService.shared.getIDToken()
        } catch {
            throw OnboardingServiceError.notAuthenticated
        }

        let url = AppConfiguration.apiBaseURL.appendingPathComponent("/api/auth/sync-user")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "idToken": idToken,
            "email": email
        ]
        if let firstName = firstName { body["firstName"] = firstName }
        if let lastName = lastName { body["lastName"] = lastName }
        if let photoURL = photoURL { body["photoURL"] = photoURL }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnboardingServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[ONBOARDING_SERVICE] sync-user error \(httpResponse.statusCode): \(errorMessage)")
            throw OnboardingServiceError.serverError("User sync failed with status \(httpResponse.statusCode)")
        }

        let syncResponse = try JSONDecoder().decode(SyncUserResponse.self, from: data)
        print("[ONBOARDING_SERVICE] User synced — Supabase ID: \(syncResponse.user.id)")
        return syncResponse
    }

    // MARK: - Send Invites via ops-web

    /// Send team member invitations via ops-web /api/auth/send-invite
    /// - Parameters:
    ///   - emails: List of email addresses to invite
    ///   - phones: Optional list of phone numbers to invite via SMS
    ///   - companyId: Company ID to invite them to
    ///   - roleId: Optional role ID to assign to invited members (defaults to Unassigned on server)
    /// - Returns: Invitation response
    func sendInvites(emails: [String], phones: [String]? = nil, companyId: String, roleId: String? = nil) async throws -> InviteResponse {
        let idToken: String
        do {
            idToken = try await FirebaseAuthService.shared.getIDToken()
        } catch {
            throw OnboardingServiceError.notAuthenticated
        }

        let url = AppConfiguration.apiBaseURL.appendingPathComponent("/api/auth/send-invite")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "idToken": idToken,
            "emails": emails,
            "companyId": companyId
        ]

        if let phones = phones, !phones.isEmpty {
            body["phones"] = phones
        }

        if let roleId = roleId {
            body["roleId"] = roleId
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnboardingServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[ONBOARDING_SERVICE] Error \(httpResponse.statusCode): \(errorMessage)")
            throw OnboardingServiceError.serverError("Invite sending failed with status \(httpResponse.statusCode)")
        }

        let inviteResponse = try JSONDecoder().decode(InviteResponse.self, from: data)
        return inviteResponse
    }
}

// MARK: - Errors

enum OnboardingServiceError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please sign in again."
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let message):
            return message
        }
    }
}
