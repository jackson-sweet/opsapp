//
//  LoginView.swift
//  OPS
//
//  Simple login form for returning users.
//  Shown when user taps "I already have an account" from the A/B test onboarding.
//  Contains email/password login + Google/Apple social sign-in.
//

import SwiftUI
import GoogleSignIn
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState

    /// Called when user taps back to return to previous screen
    var onBack: (() -> Void)?
    /// Called when login succeeds but user hasn't completed onboarding (no company)
    var onNeedsOnboarding: (() -> Void)?
    /// Called the instant a returning login is initiated — after credentials are
    /// accepted (email submitted, or a social provider returns), before the long
    /// initial sync. Lets the host arm the workspace-preload gate so the sync is
    /// covered, not the login button (bug 95bf7c82).
    var onLoginInitiated: (() -> Void)?
    /// Called when a login attempt ends WITHOUT entering the app — wrong
    /// password, cancelled social sign-in, or a route into onboarding — so the
    /// host can disarm the gate.
    var onLoginAbandoned: (() -> Void)?

    @State private var username = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var showForgotPassword = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

            VStack(spacing: OPSStyle.Layout.spacing4) {
                Spacer()

                // Login form
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3_5) {
                    // Back button
                    if let onBack = onBack {
                        Button(action: onBack) {
                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                Image(systemName: "chevron.left")
                                    .font(OPSStyle.Typography.caption.weight(.semibold))
                                Text("Back")
                                    .font(OPSStyle.Typography.button)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                    }

                    // Form title
                    Text("LOG IN")
                        .font(OPSStyle.Typography.title.weight(.bold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.bottom, OPSStyle.Layout.spacing3)

                    // Email field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email")
                            .font(OPSStyle.Typography.caption.weight(.medium))
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        TextField("", text: $username)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.vertical, OPSStyle.Layout.spacing2_5)
                            .autocapitalization(.none)
                            .autocorrectionDisabled(true)
                            .overlay(
                                VStack {
                                    Spacer()
                                    Rectangle()
                                        .frame(height: 1)
                                        .foregroundColor(username.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                                }
                            )
                    }
                    .padding(.bottom, OPSStyle.Layout.spacing2_5)

                    // Password field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .font(OPSStyle.Typography.caption.weight(.medium))
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        SecureField("", text: $password)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.vertical, OPSStyle.Layout.spacing2_5)
                            .overlay(
                                VStack {
                                    Spacer()
                                    Rectangle()
                                        .frame(height: 1)
                                        .foregroundColor(password.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                                }
                            )
                    }

                    // Login button
                    Button(action: login) {
                        HStack {
                            if isLoggingIn {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .padding(.trailing, OPSStyle.Layout.spacing2)
                            }

                            Text(isLoggingIn ? "Signing in..." : "Continue")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(OPSStyle.Colors.invertedText)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(OPSStyle.Colors.primaryText)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            !isLoggingIn ?
                            HStack {
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .foregroundColor(OPSStyle.Colors.invertedText)
                                    .font(OPSStyle.Typography.caption.weight(.semibold))
                                    .padding(.trailing, OPSStyle.Layout.spacing3_5)
                            } : nil
                        )
                        .disabledButtonStyle(isDisabled: isLoggingIn || username.isEmpty || password.isEmpty)
                    }
                    .disabled(isLoggingIn || username.isEmpty || password.isEmpty)
                    .padding(.top, OPSStyle.Layout.spacing3_5)

                    // Forgot password
                    Button(action: { showForgotPassword = true }) {
                        Text("Forgot password?")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.top, OPSStyle.Layout.spacing2_5)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    // OR divider
                    HStack {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(OPSStyle.Colors.tertiaryText.opacity(0.3))

                        Text("OR")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)

                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(OPSStyle.Colors.tertiaryText.opacity(0.3))
                    }
                    .padding(.vertical, OPSStyle.Layout.spacing3)

                    // Google Sign-In
                    GoogleSignInButton(onSignIn: handleGoogleSignIn)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)

                    // Apple Sign-In
                    AppleSignInButton(onSignIn: handleAppleSignIn)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                }

                Spacer()

                // Version info
                Text("[ VERSION \(AppConfiguration.AppInfo.version.uppercased()) ]")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                    .padding(.bottom, OPSStyle.Layout.spacing3_5)
            }
            .padding(40)
            .dismissKeyboardOnTap()

        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(prefilledEmail: username)
        }
        .errorToast($errorMessage, label: Feedback.Err.signInFailed)
    }

    // MARK: - Login

    private func login() {
        guard !username.isEmpty, !password.isEmpty else { return }

        isLoggingIn = true
        errorMessage = nil
        // Mark the returning login pending. ContentView arms the workspace gate
        // only when the initial sync actually begins — a wrong password never
        // gets that far, so the gate never wrongly appears (bug 95bf7c82).
        onLoginInitiated?()

        Task {
            let (success, loginError) = await dataController.login(username: username, password: password)

            await MainActor.run {
                isLoggingIn = false

                if success {
                    // The gate is already covering the initial sync (armed when it
                    // began); the deferred auth flip inside login() reveals the app.
                    // Setting auth here is a no-op for completed-onboarding users
                    // (already flipped) and the established fall-through otherwise.
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    dataController.isAuthenticated = true
                } else if loginError == nil && dataController.currentUser != nil {
                    // Login succeeded but user hasn't completed onboarding (no
                    // company). Disarm the gate and route them to onboarding.
                    onLoginAbandoned?()
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    onNeedsOnboarding?()
                } else {
                    onLoginAbandoned?()
                    errorMessage = loginError ?? "Incorrect email or password. Please try again."
                }
            }
        }
    }

    // MARK: - Apple Sign-In

    private func handleAppleSignIn() {
        isLoggingIn = true
        errorMessage = nil

        Task { @MainActor in
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else {
                errorMessage = "Cannot present Apple Sign-In"
                isLoggingIn = false
                return
            }

            do {
                let appleResult = try await AppleSignInManager.shared.signIn(presenting: window)
                // Provider accepted the user — mark the login pending so the gate
                // arms when loginWithApple's initial sync begins (bug 95bf7c82).
                onLoginInitiated?()
                let success = await dataController.loginWithApple(appleResult: appleResult)

                isLoggingIn = false

                if success {
                    dataController.isAuthenticated = true
                } else if dataController.currentUser != nil {
                    // Login succeeded but onboarding incomplete — disarm and route.
                    onLoginAbandoned?()
                    onNeedsOnboarding?()
                } else {
                    onLoginAbandoned?()
                    errorMessage = "No account found. Please sign up with your company first."
                }
            } catch {
                isLoggingIn = false
                onLoginAbandoned?()
                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    // User canceled — ignore
                } else {
                    errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Google Sign-In

    private func handleGoogleSignIn() {
        isLoggingIn = true
        errorMessage = nil

        Task { @MainActor in
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                errorMessage = "Cannot present Google Sign-In"
                isLoggingIn = false
                return
            }

            do {
                let googleUser = try await GoogleSignInManager.shared.signIn(presenting: rootViewController)
                // Provider accepted the user — mark the login pending so the gate
                // arms when loginWithGoogle's initial sync begins (bug 95bf7c82).
                onLoginInitiated?()
                let success = await dataController.loginWithGoogle(googleUser: googleUser)

                isLoggingIn = false

                if success {
                    dataController.isAuthenticated = true
                } else if dataController.currentUser != nil {
                    // Login succeeded but onboarding incomplete — disarm and route.
                    onLoginAbandoned?()
                    onNeedsOnboarding?()
                } else {
                    onLoginAbandoned?()
                    errorMessage = "No account found. Please sign up with your company first."
                }
            } catch {
                isLoggingIn = false
                onLoginAbandoned?()
                if let gidError = error as? GIDSignInError, gidError.code == .canceled {
                    // User canceled — ignore
                } else {
                    errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
