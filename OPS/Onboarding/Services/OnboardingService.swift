//
//  OnboardingService.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//
//  Provides invite-sending functionality via ops-web API routes.
//

import Foundation
import Supabase

class OnboardingService {

    init() {}

    // MARK: - Send Invites via ops-web

    /// Send team member invitations via ops-web /api/auth/send-invite
    /// - Parameters:
    ///   - emails: List of email addresses to invite
    ///   - companyId: Company ID to invite them to
    /// - Returns: Invitation response
    func sendInvites(emails: [String], companyId: String) async throws -> InviteResponse {
        let session: Session
        do {
            session = try await SupabaseService.shared.client.auth.session
        } catch {
            throw OnboardingServiceError.notAuthenticated
        }

        let idToken = session.accessToken

        let url = AppConfiguration.apiBaseURL.appendingPathComponent("/api/auth/send-invite")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "idToken": idToken,
            "emails": emails,
            "companyId": companyId
        ]

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
