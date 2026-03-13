//
//  AppleSignInManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-01-27.
//

import Foundation
import AuthenticationServices
import SwiftUI

/// Manages Apple Sign-In authentication flow
@MainActor
class AppleSignInManager: NSObject, ObservableObject {
    static let shared = AppleSignInManager()

    @Published var isSigningIn = false
    @Published var errorMessage: String?

    // Store the continuation for async/await pattern
    private var signInContinuation: CheckedContinuation<AppleSignInResult, Error>?

    private override init() {
        super.init()
    }

    /// Result structure for Apple Sign-In
    struct AppleSignInResult {
        let userIdentifier: String
        let identityToken: String
        let email: String?
        let givenName: String?
        let familyName: String?
    }

    /// Sign in with Apple.
    /// Automatically generates a Firebase nonce for secure token exchange.
    func signIn(presenting window: UIWindow) async throws -> AppleSignInResult {
        isSigningIn = true
        errorMessage = nil

        // Generate nonce for Firebase Apple Sign-In verification
        let nonce = try FirebaseAuthService.shared.prepareAppleSignIn()

        return try await withCheckedThrowingContinuation { continuation in
            self.signInContinuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = nonce.hashed  // SHA256 hash for Apple's verification

            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            authorizationController.delegate = self
            authorizationController.presentationContextProvider = self
            authorizationController.performRequests()
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate
// Fix #4: Delegate methods explicitly dispatch to MainActor to ensure
// @Published property mutations and continuation resumption are thread-safe.
extension AppleSignInManager: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            isSigningIn = false

            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                let error = NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid credential type"])
                signInContinuation?.resume(throwing: error)
                signInContinuation = nil
                return
            }

            // Extract identity token
            guard let identityTokenData = appleIDCredential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                let error = NSError(domain: "AppleSignIn", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch identity token"])
                signInContinuation?.resume(throwing: error)
                signInContinuation = nil
                return
            }

            let result = AppleSignInResult(
                userIdentifier: appleIDCredential.user,
                identityToken: identityToken,
                email: appleIDCredential.email,
                givenName: appleIDCredential.fullName?.givenName,
                familyName: appleIDCredential.fullName?.familyName
            )

            signInContinuation?.resume(returning: result)
            signInContinuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            isSigningIn = false

            if let authError = error as? ASAuthorizationError {
                switch authError.code {
                case .canceled:
                    errorMessage = "Sign in was canceled"
                case .failed:
                    errorMessage = "Sign in failed"
                case .invalidResponse:
                    errorMessage = "Invalid response received"
                case .notHandled:
                    errorMessage = "Sign in request not handled"
                case .unknown:
                    errorMessage = "An unknown error occurred"
                case .notInteractive:
                    errorMessage = "Sign in not interactive"
                @unknown default:
                    errorMessage = "An unexpected error occurred"
                }
            } else {
                errorMessage = error.localizedDescription
            }

            signInContinuation?.resume(throwing: error)
            signInContinuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension AppleSignInManager: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Get the key window — must dispatch to MainActor for UIApplication access
        return MainActor.assumeIsolated {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else {
                fatalError("No key window found")
            }
            return window
        }
    }
}
