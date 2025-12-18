//
//  CredentialsScreen.swift
//  OPS
//
//  Account creation screen for onboarding v3.
//  Supports email/password signup and social auth (Google/Apple).
//

import SwiftUI
import GoogleSignIn
import AuthenticationServices

struct CredentialsScreen: View {
    @ObservedObject var manager: OnboardingManager
    @EnvironmentObject var dataController: DataController

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isSigningUp = false
    @State private var isSocialSignIn = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    private var isEmailValid: Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }

    private var isPasswordValid: Bool {
        password.count >= 8
    }

    private var isFormValid: Bool {
        isEmailValid && isPasswordValid
    }

    private var subtitle: String {
        manager.state.flow == .companyCreator
            ? "Takes 30 seconds. No credit card required."
            : "Join your crew on OPS."
    }

    var body: some View {
        OnboardingScaffold(
            title: "CREATE YOUR ACCOUNT",
            subtitle: subtitle,
            showBackButton: true,
            onBack: { manager.goBack() }
        ) {
            VStack(spacing: 20) {
                // Email field with validation
                VStack(alignment: .leading, spacing: 8) {
                    Text("EMAIL")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    HStack(spacing: 12) {
                        TextField("", text: $email)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .textContentType(.emailAddress)
                            .focused($focusedField, equals: .email)

                        if !email.isEmpty {
                            Image(systemName: isEmailValid ? "checkmark" : "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isEmailValid ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }

                // Password field with validation
                VStack(alignment: .leading, spacing: 8) {
                    Text("PASSWORD")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    HStack(spacing: 12) {
                        // Conditional TextField/SecureField based on showPassword
                        if showPassword {
                            TextField("", text: $password)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .textContentType(.newPassword)
                                .autocapitalization(.none)
                                .focused($focusedField, equals: .password)
                        } else {
                            SecureField("", text: $password)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .password)
                        }

                        // Show/hide password toggle
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }

                        // Validation indicator
                        if !password.isEmpty {
                            Image(systemName: isPasswordValid ? "checkmark" : "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isPasswordValid ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )

                    // Password hint
                    Text("8+ characters")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Create account button (above social auth)
                Button {
                    createAccount()
                } label: {
                    if isSigningUp {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        HStack {
                            Text("CREATE ACCOUNT")
                                .font(OPSStyle.Typography.bodyBold)

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isFormValid ? Color.white : Color.white.opacity(0.5))
                .foregroundColor(.black)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .disabled(!isFormValid || isSigningUp || isSocialSignIn)
                .padding(.bottom, 8)

                // Social auth options
                SocialAuthButtonStack(
                    isLoading: isSocialSignIn,
                    showDivider: true,
                    onGoogleSignIn: handleGoogleSignIn,
                    onAppleSignIn: handleAppleSignIn
                )
            }
        } footer: {
            EmptyView()
        }
        .disabled(isSigningUp || isSocialSignIn)
    }

    // MARK: - Account Creation

    private func createAccount() {
        guard isFormValid else { return }

        isSigningUp = true
        errorMessage = nil

        Task {
            do {
                try await manager.createAccount(email: email, password: password)

                await MainActor.run {
                    manager.goForward()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSigningUp = false
                }
            }
        }
    }

    // MARK: - Google Sign-In

    private func handleGoogleSignIn() {
        guard !isSocialSignIn else { return }

        isSocialSignIn = true
        errorMessage = nil

        Task { @MainActor in
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                errorMessage = "Cannot present Google Sign-In"
                isSocialSignIn = false
                return
            }

            do {
                let googleUser = try await GoogleSignInManager.shared.signIn(presenting: rootViewController)
                let success = await dataController.loginWithGoogle(googleUser: googleUser)

                if success {
                    // Extract user data
                    let userId = UserDefaults.standard.string(forKey: "user_id") ?? ""
                    let email = googleUser.profile?.email ?? ""
                    let firstName = googleUser.profile?.givenName
                    let lastName = googleUser.profile?.familyName

                    try await manager.handleSocialAuth(
                        userId: userId,
                        email: email,
                        firstName: firstName,
                        lastName: lastName
                    )

                    isSocialSignIn = false
                    manager.goForward()
                } else {
                    errorMessage = "Google sign-in failed. Please try again."
                    isSocialSignIn = false
                }
            } catch {
                isSocialSignIn = false

                if let gidError = error as? GIDSignInError, gidError.code == .canceled {
                    // User canceled - no error message needed
                } else {
                    errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Apple Sign-In

    private func handleAppleSignIn() {
        guard !isSocialSignIn else { return }

        isSocialSignIn = true
        errorMessage = nil

        Task { @MainActor in
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else {
                errorMessage = "Cannot present Apple Sign-In"
                isSocialSignIn = false
                return
            }

            do {
                let appleResult = try await AppleSignInManager.shared.signIn(presenting: window)
                let success = await dataController.loginWithApple(appleResult: appleResult)

                if success {
                    // Extract user data
                    let userId = UserDefaults.standard.string(forKey: "user_id") ?? ""

                    try await manager.handleSocialAuth(
                        userId: userId,
                        email: appleResult.email ?? "",
                        firstName: appleResult.givenName,
                        lastName: appleResult.familyName
                    )

                    isSocialSignIn = false
                    manager.goForward()
                } else {
                    errorMessage = "Apple sign-in failed. Please try again."
                    isSocialSignIn = false
                }
            } catch {
                isSocialSignIn = false

                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    // User canceled - no error message needed
                } else {
                    errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Preview

struct CredentialsScreen_Previews: PreviewProvider {
    static var previews: some View {
        let dataController = DataController()
        let manager = OnboardingManager(dataController: dataController)
        manager.selectFlow(.companyCreator)

        return CredentialsScreen(manager: manager)
            .environmentObject(dataController)
    }
}
