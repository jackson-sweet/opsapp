//
//  CreateAccountLiveBoundary.swift
//  OPS
//
//  The LIVE implementation of S3's `CreateAccountSignupBoundary`, backed by the
//  hardened `OnboardingManager` + `DataController`. This is the only place the
//  rebuilt create-account screen touches real auth — S3 itself stays dumb and
//  testable behind the protocol.
//
//  It REPLICATES the working invocation contract from the A/B `MinimalSignupView`
//  (Firebase signup via `OnboardingManager.createAccount`; Apple/Google via
//  `DataController.loginWith*` → `OnboardingManager.handleSocialAuth`), without
//  reinventing any of it. It only adapts the managers' return/throw signaling
//  into the `CreateAccountOutcome` surface the screen branches on.
//
//  EXISTING-ACCOUNT SIGNALING (traced from the managers):
//    • Email, existing + COMPLETE → `createAccount` logs the user in and throws
//      `OnboardingManagerError.existingUserLoggedIn` → `.existingComplete`.
//    • Email, existing but password/provider mismatch → `createAccount` throws a
//      `serverError`/wrong-method error whose message names the conflict →
//      `.emailAlreadyRegistered` (SIGN IN handoff).
//    • Social, existing + COMPLETE → `DataController.loginWith*` flips
//      `isAuthenticated = true` (only for `!needsOnboarding`) → `.existingComplete`.
//    • Social, existing but INCOMPLETE → `isAuthenticated` stays false but a
//      `currentUser` with a company exists → resume step via `OnboardingResume`.
//    • Social, brand-new but NO provider name → `.socialNeedsName`.
//

import SwiftUI
import GoogleSignIn
import AuthenticationServices

@MainActor
struct CreateAccountLiveBoundary: CreateAccountSignupBoundary {

    let manager: OnboardingManager
    let dataController: DataController

    /// The role chosen on S2 — drives the manager's flow (owner → companyCreator,
    /// crew → employee). Required: `OnboardingManager.createAccount` throws
    /// `noFlowSelected` without it, and `handleSocialAuth` keys its resume
    /// boundary off it.
    let selectedRole: OnboardingFlowRole?

    /// Maps the live user row into the resume facts (shared with the gateway).
    let resumeStepForCurrentUser: () -> OnboardingFlowStep?

    // MARK: - Email / password

    func signUpEmail(firstName: String, lastName: String, email: String, password: String) async -> CreateAccountOutcome {
        configureFlow()
        // Seed the names the manager carries forward into createCompany/join —
        // createAccount itself sync-users with nil names, so the later profile
        // write is what persists them server-side.
        manager.state.userData.firstName = firstName
        manager.state.userData.lastName = lastName
        manager.state.userData.email = email

        do {
            try await manager.createAccount(email: email, password: password)
            return .created
        } catch OnboardingManagerError.existingUserLoggedIn {
            // Existing + complete account — createAccount already logged them in.
            return .existingComplete
        } catch {
            // Distinguish "email already taken / wrong auth method" (→ SIGN IN
            // handoff) from a generic failure (→ inline error).
            if Self.indicatesExistingEmail(error) {
                return .emailAlreadyRegistered
            }
            return .failed(message: Self.userFacing(error))
        }
    }

    // MARK: - Apple

    func signUpApple() async -> CreateAccountOutcome {
        configureFlow()
        guard let window = Self.keyWindow() else {
            return .failed(message: "Can't open Apple sign-in. Try again.")
        }

        do {
            let appleResult = try await AppleSignInManager.shared.signIn(presenting: window)
            let success = await dataController.loginWithApple(appleResult: appleResult)
            guard success else {
                return .failed(message: "Apple sign-in failed. Try again.")
            }

            // Existing + complete → admit to the app.
            if dataController.isAuthenticated {
                return .existingComplete
            }

            // Existing but incomplete (has a company / partial progress) → resume.
            if let resume = resumeIfExistingIncomplete() {
                return .existingIncomplete(resumeStep: resume)
            }

            let userId = UserDefaults.standard.string(forKey: "user_id") ?? ""
            let userEmail = appleResult.email
                ?? UserDefaults.standard.string(forKey: "user_email")
                ?? ""

            // Apple returns a name only on the FIRST authorization ever. Cache it
            // in the Keychain (survives reinstall) AND keep reading the legacy
            // UserDefaults keys as a fallback for users cached before this change.
            let (firstName, lastName) = AppleNameCache.resolve(
                given: appleResult.givenName,
                family: appleResult.familyName
            )

            try await manager.handleSocialAuth(
                userId: userId,
                email: userEmail,
                firstName: firstName,
                lastName: lastName
            )

            // No usable name resolved → require it on-screen.
            if (firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .socialNeedsName(email: userEmail)
            }
            return .created
        } catch let authError as ASAuthorizationError where authError.code == .canceled {
            return .failed(message: nil) // user cancelled — no error surfaced
        } catch {
            return .failed(message: Self.userFacing(error))
        }
    }

    // MARK: - Google

    func signUpGoogle() async -> CreateAccountOutcome {
        configureFlow()
        guard let rootVC = Self.rootViewController() else {
            return .failed(message: "Can't open Google sign-in. Try again.")
        }

        do {
            let googleUser = try await GoogleSignInManager.shared.signIn(presenting: rootVC)
            let success = await dataController.loginWithGoogle(googleUser: googleUser)
            guard success else {
                return .failed(message: "Google sign-in failed. Try again.")
            }

            if dataController.isAuthenticated {
                return .existingComplete
            }
            if let resume = resumeIfExistingIncomplete() {
                return .existingIncomplete(resumeStep: resume)
            }

            let userId = UserDefaults.standard.string(forKey: "user_id") ?? ""
            let userEmail = googleUser.profile?.email
                ?? UserDefaults.standard.string(forKey: "user_email")
                ?? ""
            let firstName = googleUser.profile?.givenName
            let lastName = googleUser.profile?.familyName

            try await manager.handleSocialAuth(
                userId: userId,
                email: userEmail,
                firstName: firstName,
                lastName: lastName
            )

            // Best-effort: pull the Google avatar in the background (mirrors the
            // A/B path). Non-fatal.
            if let photoURL = googleUser.profile?.imageURL(withDimension: 400) {
                Task { @MainActor in
                    if let (data, _) = try? await URLSession.shared.data(from: photoURL),
                       UIImage(data: data) != nil {
                        manager.state.userData.avatarData = data
                    }
                }
            }

            if (firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .socialNeedsName(email: userEmail)
            }
            return .created
        } catch let gidError as GIDSignInError where gidError.code == .canceled {
            return .failed(message: nil)
        } catch {
            return .failed(message: Self.userFacing(error))
        }
    }

    // MARK: - Finish a no-name social session

    func completeSocialName(firstName: String, lastName: String, email: String) async -> CreateAccountOutcome {
        // The user is already authenticated; persist the typed name. handleSocialAuth
        // is idempotent on an already-synced user and updates the name fields.
        let userId = manager.state.userData.userId
            ?? UserDefaults.standard.string(forKey: "user_id")
            ?? ""
        do {
            try await manager.handleSocialAuth(
                userId: userId,
                email: email,
                firstName: firstName,
                lastName: lastName
            )
            return .created
        } catch {
            return .failed(message: Self.userFacing(error))
        }
    }

    // MARK: - Helpers

    /// Set the manager's flow from the chosen role. Idempotent.
    private func configureFlow() {
        switch selectedRole {
        case .owner: manager.selectFlow(.companyCreator)
        case .crew:  manager.selectFlow(.employee)
        case .none:  break // createAccount will throw noFlowSelected → surfaced
        }
    }

    /// After a social login that did NOT flip `isAuthenticated`, decide whether
    /// the resolved user is an EXISTING but incomplete account (a company already
    /// exists) and, if so, where they resume.
    private func resumeIfExistingIncomplete() -> OnboardingFlowStep? {
        guard let user = dataController.currentUser else { return nil }
        let hasCompany = !(user.companyId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasCompany else { return nil } // brand-new row → normal create path
        return resumeStepForCurrentUser()
    }

    /// True when an email-signup error means the address is already taken / bound
    /// to a different auth method — the SIGN IN handoff case.
    private static func indicatesExistingEmail(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("already")          // "already in use" / "already registered" / "already exists"
            || msg.contains("registered with")  // wrong-method ("registered with Apple/Google")
            || msg.contains("doesn't match")     // existing account, password mismatch
    }

    /// A user-facing message for a generic failure. Empty/opaque descriptions
    /// collapse to a terse fallback (ops-copywriter voice).
    private static func userFacing(_ error: Error) -> String {
        let desc = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if desc.isEmpty { return "Couldn't create your account. Check your connection and try again." }
        return desc
    }

    // MARK: - Presentation anchors (UIKit bridges, mirrored from MinimalSignupView)

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    private static func rootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        return scene.windows.first?.rootViewController
    }
}

// MARK: - Apple name cache (Keychain-first, survives reinstall)

/// Apple returns the user's name ONLY on the first-ever authorization on a
/// device/account. We cache it so retries / reinstalls can still pre-fill.
///
/// Storage: Keychain (survives an app reinstall, unlike UserDefaults). For users
/// who were cached under the legacy UserDefaults keys BEFORE this change, the old
/// keys are still read as a fallback (and migrated up into the Keychain on read),
/// so no already-cached user loses their name. Additive and low-risk: write goes
/// to BOTH stores; the live Apple flow is unaffected if the Keychain is empty.
enum AppleNameCache {
    private static let keychain = KeychainManager()
    private static let legacyGivenKey = "apple_given_name"
    private static let legacyFamilyKey = "apple_family_name"

    /// Resolve the effective first/last name: prefer the values Apple just
    /// returned (caching them), else fall back to the cached values.
    static func resolve(given: String?, family: String?) -> (first: String?, last: String?) {
        let first = resolveOne(fresh: given, account: "apple_given_name", legacyKey: legacyGivenKey)
        let last = resolveOne(fresh: family, account: "apple_family_name", legacyKey: legacyFamilyKey)
        return (first, last)
    }

    /// For one name component: if Apple returned it, persist to Keychain (+ legacy
    /// UserDefaults for backward read-compat) and use it. Otherwise read the
    /// Keychain, then the legacy UserDefaults key (migrating it up on hit).
    private static func resolveOne(fresh: String?, account: String, legacyKey: String) -> String? {
        if let fresh, !fresh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            keychain.storeString(fresh, account: account)
            UserDefaults.standard.set(fresh, forKey: legacyKey) // keep legacy readers working
            return fresh
        }
        if let cached = keychain.retrieveString(account: account),
           !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cached
        }
        // Legacy fallback for users cached before the Keychain move — migrate up.
        if let legacy = UserDefaults.standard.string(forKey: legacyKey),
           !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            keychain.storeString(legacy, account: account)
            return legacy
        }
        return nil
    }
}
