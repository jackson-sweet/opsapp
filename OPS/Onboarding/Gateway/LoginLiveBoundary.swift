//
//  LoginLiveBoundary.swift
//  OPS
//
//  The LIVE implementation of S4's `LoginBoundary`, backed by `DataController`
//  (the live auth methods) + `OnboardingManager` (sync-user for a brand-new
//  social identity). This is the only place the rebuilt LOGIN screen touches
//  real auth — `LoginStepView` itself stays dumb and testable behind the
//  protocol, exactly like S3's `CreateAccountLiveBoundary`.
//
//  It REPLICATES the working invocation contract from the legacy LandingView /
//  LoginView returning-login path (email via `DataController.login`; Apple/Google
//  via `AppleSignInManager`/`GoogleSignInManager` → `DataController.loginWith*`),
//  without reinventing any of it. It only adapts the controller's return signaling
//  into the `LoginOutcome` surface the screen branches on, and runs sync-user for
//  a brand-new social identity so the session is established before routing into
//  the flow at `.rolePick`.
//
//  OUTCOME SIGNALING (traced from `DataController` + the legacy login views):
//
//  EMAIL (`DataController.login(username:password:) -> (Bool, String?)`):
//    • `(true, _)` → Firebase auth + the Supabase user row both resolved. A
//      fully-onboarded user is "app-bound" (`DataController.isAppBound`) and the
//      deferred auth flip inside `fetchUserFromAPI` has already (or will) reveal
//      the app → `.complete`. An existing-but-not-onboarded user is NOT app-bound
//      → `.incomplete(resumeStep:)` at the derived step.
//    • `(false, <no-account sentinel>)` → Firebase auth succeeded but no Supabase
//      user row exists (the rare "Firebase user, no users row" edge) → `.noAccount`.
//      NOTE: Firebase Email-Enumeration-Protection deliberately COLLAPSES
//      "no such user" and "wrong password" into one `.invalidCredentials` error
//      (see `FirebaseAuthService`), so the far more common "email isn't registered"
//      case is indistinguishable from a wrong password at this layer and correctly
//      surfaces as `.failed("WRONG EMAIL OR PASSWORD.")` — matching the legacy,
//      shipping behavior. We never fabricate a no-account signal the auth layer
//      can't actually give us.
//    • `(false, <any other message>)` → wrong password / provider-conflict /
//      network / server → `.failed(message:)`.
//
//  SOCIAL (`DataController.loginWith{Apple,Google}(...) -> Bool`):
//    • Cancelled provider sheet → `.failed(message: nil)` (no error surfaced).
//    • Returned `false` → `.failed(message:)`.
//    • Returned `true` + `isAuthenticated` already flipped (loginWith* flips it
//      synchronously for `!needsOnboarding`) → `.complete`.
//    • Returned `true`, not authenticated, but an EXISTING row with a company
//      exists → `.incomplete(resumeStep:)`.
//    • Returned `true`, brand-new identity (no company / no row) → run
//      `OnboardingManager.handleSocialAuth` (sync-user establishes the Supabase
//      row + session), then `.newIdentity` → the gateway routes to `.rolePick`.
//
//  PRELOAD-GATE PARITY (bug 95bf7c82): the legacy LandingView/LoginView arm the
//  WorkspacePreloadGate the instant a RETURNING login is initiated and disarm it
//  if the attempt ends without entering the app. We mirror that here through
//  injected `onLoginInitiated`/`onLoginAbandoned` hooks: a returning login (an
//  email submit, or a social provider that returns a credential) arms; any
//  outcome that does NOT admit the user to the app disarms. Only the
//  `.complete` outcome keeps the gate up — that is the single case where the
//  authenticated app is about to mount behind the initial sync.
//

import SwiftUI
import GoogleSignIn
import AuthenticationServices

@MainActor
struct LoginLiveBoundary: LoginBoundary {

    let dataController: DataController

    /// Held so a brand-new social identity can run sync-user (establishes the
    /// Supabase row + session) before the flow routes to `.rolePick`. Mirrors S3.
    let manager: OnboardingManager

    /// Maps the live user row into the derived resume step (shared with the
    /// gateway's `serverState(for:)` mapping). Used for the existing-but-incomplete
    /// outcomes so Login resumes at the same step Create-account would.
    let resumeStepForCurrentUser: () -> OnboardingFlowStep?

    /// Armed the instant a RETURNING login is initiated (email submit accepted, or
    /// a social provider returns a credential) so the host's WorkspacePreloadGate
    /// covers the initial sync rather than freezing the CTA (bug 95bf7c82). The
    /// gateway wires this to `pendingReturningLogin = true`.
    let onLoginInitiated: () -> Void

    /// Fired when a login attempt ends WITHOUT entering the app — wrong password,
    /// cancelled social sheet, no-account, or a route into onboarding (incomplete /
    /// new identity). The gateway wires this to `disarmWorkspacePreload()`.
    let onLoginAbandoned: () -> Void

    /// The explicit no-account sentinel `DataController.login` returns when Firebase
    /// auth succeeds but no Supabase user row resolves. Matched case-insensitively
    /// on a stable prefix so a copy tweak to the tail doesn't silently reclassify
    /// the outcome as a generic failure.
    private static let noAccountSentinelPrefix = "no account found"

    // MARK: - Email / password

    func logInEmail(email: String, password: String) async -> LoginOutcome {
        // A returning login is starting — arm the preload gate (parity with the
        // legacy LandingView/LoginView). Disarmed below for every non-admit outcome.
        onLoginInitiated()

        let (success, message) = await dataController.login(username: email, password: password)

        guard success else {
            onLoginAbandoned()
            if Self.indicatesNoAccount(message) {
                return .noAccount
            }
            return .failed(message: Self.userFacing(message))
        }

        // Auth resolved. App-bound (server-onboarded + company + user type) →
        // admit; the deferred flip inside fetchUserFromAPI reveals the app behind
        // the (now-armed) preload gate. Keep the gate up — this is the one admit
        // case.
        if DataController.isAppBound(dataController.currentUser) {
            return .complete
        }

        // Existing account, not finished onboarding → resume. Not an admit, so
        // disarm the gate and route into the flow.
        onLoginAbandoned()
        let resume = resumeStepForCurrentUser() ?? .rolePick
        return .incomplete(resumeStep: resume)
    }

    // MARK: - Apple

    func logInApple() async -> LoginOutcome {
        guard let window = Self.keyWindow() else {
            return .failed(message: "Can't open Apple sign-in. Try again.")
        }

        do {
            let appleResult = try await AppleSignInManager.shared.signIn(presenting: window)
            // Provider accepted the user — a returning login is now in flight.
            onLoginInitiated()

            let success = await dataController.loginWithApple(appleResult: appleResult)
            guard success else {
                onLoginAbandoned()
                return .failed(message: "Apple sign-in failed. Try again.")
            }

            let userEmail = appleResult.email
                ?? FirebaseAuthService.shared.currentUserEmail
                ?? UserDefaults.standard.string(forKey: "user_email")
                ?? ""
            let (firstName, lastName) = AppleNameCache.resolve(
                given: appleResult.givenName,
                family: appleResult.familyName
            )
            return await resolveSocialOutcome(email: userEmail, firstName: firstName, lastName: lastName)
        } catch let authError as ASAuthorizationError where authError.code == .canceled {
            // Cancel happens BEFORE onLoginInitiated, so the gate was never armed
            // — nothing to disarm. nil message = no error surfaced.
            return .failed(message: nil)
        } catch {
            onLoginAbandoned()
            return .failed(message: Self.userFacing(error.localizedDescription))
        }
    }

    // MARK: - Google

    func logInGoogle() async -> LoginOutcome {
        guard let rootVC = Self.rootViewController() else {
            return .failed(message: "Can't open Google sign-in. Try again.")
        }

        do {
            let googleUser = try await GoogleSignInManager.shared.signIn(presenting: rootVC)
            onLoginInitiated()

            let success = await dataController.loginWithGoogle(googleUser: googleUser)
            guard success else {
                onLoginAbandoned()
                return .failed(message: "Google sign-in failed. Try again.")
            }

            let userEmail = googleUser.profile?.email
                ?? FirebaseAuthService.shared.currentUserEmail
                ?? UserDefaults.standard.string(forKey: "user_email")
                ?? ""
            let firstName = googleUser.profile?.givenName
            let lastName = googleUser.profile?.familyName
            return await resolveSocialOutcome(email: userEmail, firstName: firstName, lastName: lastName)
        } catch let gidError as GIDSignInError where gidError.code == .canceled {
            return .failed(message: nil)
        } catch {
            onLoginAbandoned()
            return .failed(message: Self.userFacing(error.localizedDescription))
        }
    }

    // MARK: - Shared social resolution

    /// After a social `loginWith*` returned `true`, classify the session:
    /// complete (already admitted) → `.complete`; existing-but-incomplete →
    /// `.incomplete`; brand-new identity → run sync-user and return `.newIdentity`.
    private func resolveSocialOutcome(email: String, firstName: String?, lastName: String?) async -> LoginOutcome {
        // `loginWith*` flips `isAuthenticated` synchronously for fully-onboarded
        // accounts — that is the admit signal. Keep the gate up.
        if dataController.isAuthenticated {
            return .complete
        }

        // Existing account with a company but not yet onboarded → resume. Not an
        // admit, so disarm and route into the flow.
        if let resume = resumeIfExistingIncomplete() {
            onLoginAbandoned()
            return .incomplete(resumeStep: resume)
        }

        // Brand-new identity → establish the Supabase row + session via sync-user,
        // then route into the flow at `.rolePick`. Not an admit (the user still
        // has to onboard), so disarm the preload gate.
        onLoginAbandoned()
        let userId = UserDefaults.standard.string(forKey: "user_id") ?? ""
        do {
            try await manager.handleSocialAuth(
                userId: userId,
                email: email,
                firstName: firstName,
                lastName: lastName
            )
            return .newIdentity
        } catch {
            return .failed(message: Self.userFacing(error.localizedDescription))
        }
    }

    // MARK: - Helpers

    /// After a social login that did NOT flip `isAuthenticated`, decide whether the
    /// resolved user is an EXISTING but incomplete account (a company already
    /// exists) and, if so, where they resume. Mirrors `CreateAccountLiveBoundary`.
    private func resumeIfExistingIncomplete() -> OnboardingFlowStep? {
        guard let user = dataController.currentUser else { return nil }
        let hasCompany = !(user.companyId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasCompany else { return nil } // brand-new row → new-identity path
        return resumeStepForCurrentUser()
    }

    /// True when an email-login error message is the explicit no-account sentinel
    /// `DataController.login` returns (Firebase auth OK, no Supabase user row).
    static func indicatesNoAccount(_ message: String?) -> Bool {
        guard let message else { return false }
        return message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix(noAccountSentinelPrefix)
    }

    /// A user-facing failure message. `DataController` already returns terse,
    /// uppercase, ops-voice copy ("WRONG EMAIL OR PASSWORD."); an empty/absent
    /// message collapses to a connection fallback.
    static func userFacing(_ message: String?) -> String {
        let desc = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if desc.isEmpty { return "Couldn't sign you in. Check your connection and try again." }
        return desc
    }

    // MARK: - Presentation anchors (UIKit bridges, mirrored from the live login path)

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
