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
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.8

    // Social sign-in states
    @State private var isSigningInWithSocial = false
    @State private var socialSignInError: String?
    
    var body: some View {
        ZStack {
            // Background with subtle gradient
            Color(OPSStyle.Colors.background)
            .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                // Logo in top corner
                HStack {
                    HStack(alignment: .bottom){
                        Image("LogoWhite")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                        Text("OPS")
                            .font(OPSStyle.Typography.title)
                            .frame(height: 24)
                    }
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
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .opacity(buttonOpacity)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, 40)
                
                // Main content with spacing
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                        .frame(height: 40)
                    
                    // Headline messaging
                    VStack(alignment: .leading, spacing: 24) {
                
                        // Key benefits
                        VStack(alignment: .leading, spacing: 16) {
                            Spacer()
                            BenefitRow(
                                icon: "bolt.shield",
                                text: "SCHEDULE, JOB BOARD AND ASSIGNMENTS".uppercased()
                            )
                            
                            BenefitRow(
                                icon: "person.2",
                                text: "JOB DETAILS, LOCATION AND CONTACT INFO".uppercased()
                            )
                            
                            BenefitRow(
                                icon: "iphone.motion",
                                text: "ALL IN YOUR CREW'S POCKETS.".uppercased()
                            )
                            Spacer()
                        }
                    }
                    .opacity(textOpacity)
                    
                    Spacer()
                    
                    Text("OPS.")
                        .font(OPSStyle.Typography.cardTitle)
                    // Builder message
                    Text("Built by trades, for trades.")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(Color.gray)
                        .padding(.bottom, 40)
                        .opacity(textOpacity)
                    
                    // Get Started Button
                    StandardContinueButton(
                        onTap: {
                            viewModel.moveToNextStep()
                        }
                    )
                    .opacity(buttonOpacity)

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
                    .padding(.vertical, 16)
                    .opacity(buttonOpacity)

                    // Social sign-in buttons
                    VStack(spacing: 12) {
                        // Google Sign-In button
                        SignupGoogleButton(
                            isLoading: isSigningInWithSocial,
                            onSignIn: handleGoogleSignIn
                        )
                        .frame(height: OPSStyle.Layout.touchTargetStandard)

                        // Apple Sign-In button
                        SignupAppleButton(
                            isLoading: isSigningInWithSocial,
                            onSignIn: handleAppleSignIn
                        )
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                    }
                    .opacity(buttonOpacity)

                    // Error message
                    if let error = socialSignInError {
                        Text(error)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }

                    Spacer()
                        .frame(height: 30)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
        }
        .onAppear {
            animateContent()

            // Perform data health check when welcome flow starts
            Task {
                await viewModel.performDataHealthCheck()
            }
        }
    }
    
    private func animateContent() {
        // Logo animation
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
            logoScale = 1.0
        }

        // Text animation
        withAnimation(.easeIn(duration: 0.8).delay(0.3)) {
            textOpacity = 1.0
        }

        // Button animation
        withAnimation(.easeIn(duration: 0.6).delay(0.7)) {
            buttonOpacity = 1.0
        }
    }

    // MARK: - Social Sign-In Handlers

    private func handleGoogleSignIn() {
        guard !isSigningInWithSocial else { return }

        isSigningInWithSocial = true
        socialSignInError = nil

        Task { @MainActor in
            // Get the root view controller
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                socialSignInError = "Cannot present Google Sign-In"
                isSigningInWithSocial = false
                return
            }

            do {
                // Perform Google Sign-In
                let googleUser = try await GoogleSignInManager.shared.signIn(presenting: rootViewController)

                // Authenticate with Bubble backend (handles both signup and login)
                guard let dataController = viewModel.dataController else {
                    socialSignInError = "Unable to complete sign-in"
                    isSigningInWithSocial = false
                    return
                }

                let success = await dataController.loginWithGoogle(googleUser: googleUser)

                isSigningInWithSocial = false

                if success {
                    // Store user info from Google
                    if let email = googleUser.profile?.email {
                        viewModel.email = email
                    }
                    if let givenName = googleUser.profile?.givenName {
                        viewModel.firstName = givenName
                    }
                    if let familyName = googleUser.profile?.familyName {
                        viewModel.lastName = familyName
                    }

                    // Mark as signed up and move to next step
                    viewModel.isSignedUp = true
                    viewModel.moveToNextStep()
                } else {
                    socialSignInError = "Google sign-in failed. Please try again."
                }
            } catch {
                isSigningInWithSocial = false

                // Check if it was a cancellation
                if let gidError = error as? GIDSignInError, gidError.code == .canceled {
                    // User canceled, don't show error
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
            // Get the key window for presentation
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else {
                socialSignInError = "Cannot present Apple Sign-In"
                isSigningInWithSocial = false
                return
            }

            do {
                // Perform Apple Sign-In
                let appleResult = try await AppleSignInManager.shared.signIn(presenting: window)

                // Authenticate with Bubble backend (handles both signup and login)
                guard let dataController = viewModel.dataController else {
                    socialSignInError = "Unable to complete sign-in"
                    isSigningInWithSocial = false
                    return
                }

                let success = await dataController.loginWithApple(appleResult: appleResult)

                isSigningInWithSocial = false

                if success {
                    // Store user info from Apple (if provided)
                    if let email = appleResult.email {
                        viewModel.email = email
                    }
                    if let givenName = appleResult.givenName {
                        viewModel.firstName = givenName
                    }
                    if let familyName = appleResult.familyName {
                        viewModel.lastName = familyName
                    }

                    // Mark as signed up and move to next step
                    viewModel.isSignedUp = true
                    viewModel.moveToNextStep()
                } else {
                    socialSignInError = "Apple sign-in failed. Please try again."
                }
            } catch {
                isSigningInWithSocial = false

                // Check if it was a cancellation
                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    // User canceled, don't show error
                } else {
                    socialSignInError = "Apple Sign-In failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Social Sign-In Buttons

/// Google Sign-In button styled for signup flow
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
                    // Google logo
                    Image("google_logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)

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
                    .stroke(OPSStyle.Colors.tertiaryText, lineWidth: 1)
            )
        }
        .disabled(isLoading)
    }
}

/// Apple Sign-In button styled for signup flow
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
                    // Apple logo
                    Image(systemName: "apple.logo")
                        .font(.system(size: 20, weight: .medium))
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
                    .stroke(OPSStyle.Colors.tertiaryText, lineWidth: 1)
            )
        }
        .disabled(isLoading)
    }
}

// Modern benefit row with icon
struct BenefitRow: View {
    var icon: String
    var text: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: 30)
            
            Text(text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Helper view for info text items
struct InfoText: View {
    var text: String
    
    var body: some View {
        Text(text)
            .font(OPSStyle.Typography.body)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
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
