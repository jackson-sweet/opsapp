//
//  LoginScreen.swift
//  OPS
//
//  Full-page login screen for existing users.
//  Part of onboarding v3 flow.
//

import SwiftUI
import GoogleSignIn
import AuthenticationServices

struct LoginScreen: View {
    @ObservedObject var manager: OnboardingManager
    @EnvironmentObject var dataController: DataController

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showForgotPassword = false

    var body: some View {
        VStack(spacing: 0) {
            // Back button
            HStack {
                Button {
                    manager.goToScreen(.welcome)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: 44, height: 44)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)

            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("SIGN IN")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("Welcome back.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 24)

            Spacer()
                .frame(height: 40)

            // Form
            VStack(spacing: 20) {
                // Email field
                VStack(alignment: .leading, spacing: 8) {
                    Text("EMAIL")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    TextField("", text: $email)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }

                // Password field
                VStack(alignment: .leading, spacing: 8) {
                    Text("PASSWORD")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    SecureField("", text: $password)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Forgot password
                Button {
                    showForgotPassword = true
                } label: {
                    Text("Forgot Password?")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .underline()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                // Sign in button (above OR)
                Button {
                    login()
                } label: {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        HStack {
                            Text("SIGN IN")
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
                .background(canLogin ? Color.white : Color.white.opacity(0.5))
                .foregroundColor(.black)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .disabled(!canLogin || isLoading)
                .padding(.bottom, 8)

                // Divider
                HStack(spacing: 16) {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1)

                    Text("OR")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1)
                }
                .padding(.vertical, 8)

                // Social login buttons
                VStack(spacing: 12) {
                    // Google
                    Button {
                        handleGoogleSignIn()
                    } label: {
                        HStack(spacing: 12) {
                            Image("google_logo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)

                            Text("Continue With Google")
                                .font(OPSStyle.Typography.bodyBold)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }

                    // Apple
                    Button {
                        handleAppleSignIn()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 20))

                            Text("Continue With Apple")
                                .font(OPSStyle.Typography.bodyBold)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .background(OPSStyle.Colors.background)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(
                isPresented: $showForgotPassword,
                prefilledEmail: $email
            )
        }
    }

    // MARK: - Helpers

    private var canLogin: Bool {
        !email.isEmpty && !password.isEmpty
    }

    private func login() {
        isLoading = true
        errorMessage = nil

        Task {
            let success = await dataController.login(username: email, password: password)

            await MainActor.run {
                isLoading = false

                if success {
                    // Check if user needs to complete onboarding
                    manager.resume()
                } else {
                    errorMessage = "Wrong email or password. Try again."
                }
            }
        }
    }

    private func handleGoogleSignIn() {
        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                errorMessage = "Google sign-in unavailable right now."
                isLoading = false
                return
            }

            do {
                let googleUser = try await GoogleSignInManager.shared.signIn(presenting: rootViewController)
                let success = await dataController.loginWithGoogle(googleUser: googleUser)

                isLoading = false

                if success {
                    manager.resume()
                } else {
                    errorMessage = "No account found. Create one first."
                }
            } catch {
                isLoading = false
                if let gidError = error as? GIDSignInError, gidError.code == .canceled {
                    // User canceled
                } else {
                    errorMessage = "Google sign-in unavailable right now."
                }
            }
        }
    }

    private func handleAppleSignIn() {
        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else {
                errorMessage = "Apple sign-in unavailable right now."
                isLoading = false
                return
            }

            do {
                let appleResult = try await AppleSignInManager.shared.signIn(presenting: window)
                let success = await dataController.loginWithApple(appleResult: appleResult)

                isLoading = false

                if success {
                    manager.resume()
                } else {
                    errorMessage = "No account found. Create one first."
                }
            } catch {
                isLoading = false
                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    // User canceled
                } else {
                    errorMessage = "Apple sign-in unavailable right now."
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)

    LoginScreen(manager: manager)
        .environmentObject(dataController)
}
