//
//  WelcomeView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI
import Combine
import GoogleSignIn
import AuthenticationServices

struct WelcomeView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var contentOpacity: Double = 0

    // Social sign-in states
    @State private var isSigningInWithSocial = false
    @State private var socialSignInError: String?

    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with logo and sign in link
                HStack(alignment: .bottom) {
                    Image("LogoWhite")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .padding(.bottom, 8)
                    Text("OPS")
                        .font(OPSStyle.Typography.largeTitle.weight(.bold))
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    Button(action: {
                        // Clear all user data before returning to login
                        let userDefaults = UserDefaults.standard
                        userDefaults.removeObject(forKey: "resume_onboarding")
                        userDefaults.removeObject(forKey: "is_authenticated")
                        userDefaults.removeObject(forKey: "user_id")
                        userDefaults.removeObject(forKey: "user_email")
                        userDefaults.removeObject(forKey: "user_password")
                        userDefaults.removeObject(forKey: "user_first_name")
                        userDefaults.removeObject(forKey: "user_last_name")
                        userDefaults.removeObject(forKey: "user_phone_number")
                        userDefaults.removeObject(forKey: "company_code")

                        // Dismiss onboarding and return to login page
                        NotificationCenter.default.post(name: Notification.Name("DismissOnboarding"), object: nil)
                    }) {
                        Text("Sign In")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                .padding(.leading, 4)

                Spacer()

                // Main content
                VStack(alignment: .leading, spacing: 32) {
                    // Headline
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FROM WHITEBOARD")
                            .font(OPSStyle.Typography.largeTitle.weight(.bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text("TO WORKFORCE.")
                            .font(OPSStyle.Typography.largeTitle.weight(.bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }

                    Text("Job management built by trades, for trades.")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .opacity(contentOpacity)

                Spacer()

                // Bottom actions
                VStack(spacing: 16) {
                    // Error message
                    if let error = socialSignInError {
                        Text(error)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .multilineTextAlignment(.center)
                    }

                    // Primary action - Continue with email
                    Button(action: {
                        viewModel.moveToNextStep()
                    }) {
                        Text("GET STARTED")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetStandard)
                            .background(Color.white)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                HStack {
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(.black)
                                        .font(OPSStyle.Typography.caption.weight(.semibold))
                                        .padding(.trailing, 20)
                                }
                            )
                    }

                    // OR Divider
                    HStack {
                        Rectangle()
                            .fill(OPSStyle.Colors.tertiaryText.opacity(0.3))
                            .frame(height: 1)

                        Text("OR")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .padding(.horizontal, 16)

                        Rectangle()
                            .fill(OPSStyle.Colors.tertiaryText.opacity(0.3))
                            .frame(height: 1)
                    }

                    // Social sign-in buttons
                    SignupGoogleButton(
                        isLoading: isSigningInWithSocial,
                        onSignIn: handleGoogleSignIn
                    )
                    .frame(height: OPSStyle.Layout.touchTargetStandard)

                    SignupAppleButton(
                        isLoading: isSigningInWithSocial,
                        onSignIn: handleAppleSignIn
                    )
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                }
                .opacity(contentOpacity)
                .padding(.bottom, 20)
            }
            .padding(40)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.5).delay(0.2)) {
                contentOpacity = 1.0
            }

            // Perform data health check when welcome flow starts
            Task {
                await viewModel.performDataHealthCheck()
            }
        }
    }

    // MARK: - Social Sign-In Handlers

    private func handleGoogleSignIn() {
        guard !isSigningInWithSocial else { return }

        isSigningInWithSocial = true
        socialSignInError = nil

        Task { @MainActor in
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                socialSignInError = "Cannot present Google Sign-In"
                isSigningInWithSocial = false
                return
            }

            do {
                let googleUser = try await GoogleSignInManager.shared.signIn(presenting: rootViewController)

                guard let dataController = viewModel.dataController else {
                    socialSignInError = "Unable to complete sign-in"
                    isSigningInWithSocial = false
                    return
                }

                let success = await dataController.loginWithGoogle(googleUser: googleUser)

                isSigningInWithSocial = false

                if success {
                    if let email = googleUser.profile?.email {
                        viewModel.email = email
                    }
                    if let givenName = googleUser.profile?.givenName {
                        viewModel.firstName = givenName
                    }
                    if let familyName = googleUser.profile?.familyName {
                        viewModel.lastName = familyName
                    }

                    viewModel.isSignedUp = true
                    viewModel.moveToNextStep()
                } else {
                    socialSignInError = "Google sign-in failed. Please try again."
                }
            } catch {
                isSigningInWithSocial = false

                if let gidError = error as? GIDSignInError, gidError.code == .canceled {
                    // User canceled
                } else {
                    socialSignInError = "Google Sign-In failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func handleAppleSignIn() {
        guard !isSigningInWithSocial else { return }

        isSigningInWithSocial = true
        socialSignInError = nil

        Task { @MainActor in
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else {
                socialSignInError = "Cannot present Apple Sign-In"
                isSigningInWithSocial = false
                return
            }

            do {
                let appleResult = try await AppleSignInManager.shared.signIn(presenting: window)

                guard let dataController = viewModel.dataController else {
                    socialSignInError = "Unable to complete sign-in"
                    isSigningInWithSocial = false
                    return
                }

                let success = await dataController.loginWithApple(appleResult: appleResult)

                isSigningInWithSocial = false

                if success {
                    if let email = appleResult.email {
                        viewModel.email = email
                    }
                    if let givenName = appleResult.givenName {
                        viewModel.firstName = givenName
                    }
                    if let familyName = appleResult.familyName {
                        viewModel.lastName = familyName
                    }

                    viewModel.isSignedUp = true
                    viewModel.moveToNextStep()
                } else {
                    socialSignInError = "Apple sign-in failed. Please try again."
                }
            } catch {
                isSigningInWithSocial = false

                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    // User canceled
                } else {
                    socialSignInError = "Apple Sign-In failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Social Sign-In Buttons

struct SignupGoogleButton: View {
    let isLoading: Bool
    let onSignIn: () -> Void

    var body: some View {
        Button(action: onSignIn) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                } else {
                    Image("google_logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)

                    Text("Continue with Google")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.tertiaryText.opacity(0.5), lineWidth: 1)
            )
        }
        .disabled(isLoading)
    }
}

struct SignupAppleButton: View {
    let isLoading: Bool
    let onSignIn: () -> Void

    var body: some View {
        Button(action: onSignIn) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                } else {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("Continue with Apple")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.tertiaryText.opacity(0.5), lineWidth: 1)
            )
        }
        .disabled(isLoading)
    }
}

// MARK: - Preview
#Preview("Welcome Screen") {
    let viewModel = OnboardingViewModel()
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()

    return WelcomeView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environmentObject(dataController)
        .environment(\.colorScheme, .dark)
}
