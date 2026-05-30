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
    /// Called at the exact moment a returning login flips authentication on
    /// (email/password, Apple, or Google). Lets the host arm the workspace
    /// preload gate so the user isn't dropped into the app mid-sync
    /// (bug 95bf7c82). Fired immediately before `isAuthenticated` is set true.
    var onAuthenticated: (() -> Void)?

    @State private var username = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showForgotPassword = false
    @State private var showLoginSuccess = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

            VStack(spacing: 24) {
                Spacer()

                // Login form
                VStack(alignment: .leading, spacing: 20) {
                    // Back button
                    if let onBack = onBack {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(OPSStyle.Icons.chevronLeft)
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
                        .padding(.bottom, 16)

                    // Email field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email")
                            .font(OPSStyle.Typography.caption.weight(.medium))
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        TextField("", text: $username)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.vertical, 12)
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
                    .padding(.bottom, 12)

                    // Password field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .font(OPSStyle.Typography.caption.weight(.medium))
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        SecureField("", text: $password)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.vertical, 12)
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
                                    .padding(.trailing, 8)
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
                                Image(OPSStyle.Icons.arrowRight)
                                    .foregroundColor(OPSStyle.Colors.invertedText)
                                    .font(OPSStyle.Typography.caption.weight(.semibold))
                                    .padding(.trailing, 20)
                            } : nil
                        )
                        .disabledButtonStyle(isDisabled: isLoggingIn || username.isEmpty || password.isEmpty)
                    }
                    .disabled(isLoggingIn || username.isEmpty || password.isEmpty)
                    .padding(.top, 20)

                    // Forgot password
                    Button(action: { showForgotPassword = true }) {
                        Text("Forgot password?")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.top, 12)
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
                            .padding(.horizontal, 16)

                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(OPSStyle.Colors.tertiaryText.opacity(0.3))
                    }
                    .padding(.vertical, 16)

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
                    .padding(.bottom, 20)
            }
            .padding(40)
            .dismissKeyboardOnTap()

            // Login success overlay
            if showLoginSuccess {
                LoginSuccessView()
                    .transition(.opacity)
                    .zIndex(2)
            }

        }
        .animation(.easeInOut, value: showLoginSuccess)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(prefilledEmail: username)
        }
        .alert(isPresented: $showError, content: {
            Alert(
                title: Text("Sign In Failed"),
                message: Text(errorMessage ?? "Please check your credentials and try again."),
                dismissButton: .default(Text("OK"))
            )
        })
    }

    // MARK: - Login

    private func login() {
        guard !username.isEmpty, !password.isEmpty else { return }

        isLoggingIn = true
        errorMessage = nil

        Task {
            let (success, loginError) = await dataController.login(username: username, password: password)

            await MainActor.run {
                isLoggingIn = false

                if success {
                    showLoginSuccess = true

                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showLoginSuccess = false
                        onAuthenticated?()
                        dataController.isAuthenticated = true
                    }
                } else if loginError == nil && dataController.currentUser != nil {
                    // Login succeeded but user hasn't completed onboarding (no company).
                    // Route them to onboarding to finish setup.
                    showLoginSuccess = true
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showLoginSuccess = false
                        onNeedsOnboarding?()
                    }
                } else {
                    errorMessage = loginError ?? "Incorrect email or password. Please try again."
                    showError = true
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
                showError = true
                isLoggingIn = false
                return
            }

            do {
                let appleResult = try await AppleSignInManager.shared.signIn(presenting: window)
                let success = await dataController.loginWithApple(appleResult: appleResult)

                isLoggingIn = false

                if success {
                    onAuthenticated?()
                    dataController.isAuthenticated = true
                } else if dataController.currentUser != nil {
                    // Login succeeded but onboarding incomplete — route to onboarding
                    onNeedsOnboarding?()
                } else {
                    errorMessage = "No account found. Please sign up with your company first."
                    showError = true
                }
            } catch {
                isLoggingIn = false
                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    // User canceled — ignore
                } else {
                    errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
                    showError = true
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
                showError = true
                isLoggingIn = false
                return
            }

            do {
                let googleUser = try await GoogleSignInManager.shared.signIn(presenting: rootViewController)
                let success = await dataController.loginWithGoogle(googleUser: googleUser)

                isLoggingIn = false

                if success {
                    onAuthenticated?()
                    dataController.isAuthenticated = true
                } else if dataController.currentUser != nil {
                    // Login succeeded but onboarding incomplete — route to onboarding
                    onNeedsOnboarding?()
                } else {
                    errorMessage = "No account found. Please sign up with your company first."
                    showError = true
                }
            } catch {
                isLoggingIn = false
                if let gidError = error as? GIDSignInError, gidError.code == .canceled {
                    // User canceled — ignore
                } else {
                    errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}
