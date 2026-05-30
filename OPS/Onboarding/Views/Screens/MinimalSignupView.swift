//
//  MinimalSignupView.swift
//  OPS
//
//  Single-screen signup for onboarding A/B/C test.
//  Handles authentication only (Apple, Google, email/password).
//  Company name is collected on a separate screen after auth.
//

import SwiftUI
import GoogleSignIn
import AuthenticationServices

struct MinimalSignupView: View {
    @ObservedObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataController: DataController
    let variant: OnboardingVariant
    let onAuthenticated: () -> Void       // called after successful auth (new user)
    var onExistingUserComplete: (() -> Void)?  // called when existing user detected (skip onboarding)
    var onShowLogin: (() -> Void)?        // navigate to login for existing users

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // MARK: - Header with logo
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
                    }
                    .padding(.leading, 4)

                    Spacer().frame(height: 40)

                    // MARK: - Headline
                    HStack {
                        Text("CREATE YOUR ACCOUNT")
                            .font(OPSStyle.Typography.heading)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()
                    }

                    Spacer().frame(height: 32)

                    // MARK: - Social sign-in buttons
                    VStack(spacing: 16) {
                        // Apple Sign-In
                        Button(action: handleAppleSignIn) {
                            HStack(spacing: 12) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                                } else {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
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
                                    .stroke(OPSStyle.Colors.tertiaryText.opacity(0.5), lineWidth: OPSStyle.Layout.Border.standard)
                            )
                        }
                        .disabled(isLoading)

                        // Google Sign-In
                        Button(action: handleGoogleSignIn) {
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
                                    .stroke(OPSStyle.Colors.tertiaryText.opacity(0.5), lineWidth: OPSStyle.Layout.Border.standard)
                            )
                        }
                        .disabled(isLoading)
                    }

                    Spacer().frame(height: 24)

                    // MARK: - OR Divider
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

                    Spacer().frame(height: 24)

                    // MARK: - Input fields (auth only — no company name)
                    VStack(spacing: 24) {
                        // Email field
                        VStack(spacing: 8) {
                            TextField("", text: $email, prompt: Text("Email").foregroundColor(OPSStyle.Colors.secondaryText))
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)

                            Rectangle()
                                .fill(OPSStyle.Colors.tertiaryText.opacity(0.3))
                                .frame(height: 1)
                        }

                        // Password field
                        VStack(spacing: 8) {
                            SecureField("", text: $password, prompt: Text("Password").foregroundColor(OPSStyle.Colors.secondaryText))
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .textContentType(.newPassword)

                            Rectangle()
                                .fill(OPSStyle.Colors.tertiaryText.opacity(0.3))
                                .frame(height: 1)
                        }
                    }

                    Spacer().frame(height: 32)

                    // MARK: - Error message
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 12)
                    }

                    // MARK: - Create Account button
                    Button(action: handleEmailSignup) {
                        ZStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText))
                            } else {
                                Text("CREATE ACCOUNT")
                                    .font(OPSStyle.Typography.button)
                                    .foregroundColor(OPSStyle.Colors.invertedText)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(OPSStyle.Colors.primaryText)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            HStack {
                                Spacer()
                                if !isLoading {
                                    Image("ops.arrow-right")
                                        .foregroundColor(OPSStyle.Colors.invertedText)
                                        .font(OPSStyle.Typography.caption.weight(.semibold))
                                        .padding(.trailing, 20)
                                }
                            }
                        )
                    }
                    .disabled(isLoading)

                    // "I already have an account" link
                    if let onShowLogin = onShowLogin {
                        Button(action: onShowLogin) {
                            Text("I ALREADY HAVE AN ACCOUNT")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .padding(.top, 8)
                    }

                    // Flow toggle — switch between Join/Create
                    Button {
                        let newFlow: OnboardingFlow = onboardingManager.state.flow == .employee ? .companyCreator : .employee
                        onboardingManager.selectFlow(newFlow)
                        errorMessage = ""
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    } label: {
                        Text(onboardingManager.state.flow == .employee ? "CREATE A COMPANY INSTEAD" : "JOIN A CREW INSTEAD")
                            .font(OPSStyle.Typography.smallCaption)
                            .tracking(0.5)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .underline()
                            .frame(minHeight: 44)
                    }
                    .padding(.top, 4)

                    Spacer().frame(height: 20)
                }
                .padding(40)
            }
        }
        .onAppear {
            AnalyticsManager.shared.trackSignupScreenShown(variant: variant.rawValue)
            OnboardingSupabaseAnalytics.shared.trackStepView("signup")
        }
    }

    // MARK: - Email/Password Sign-Up

    private func handleEmailSignup() {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter your email address."
            return
        }
        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            return
        }

        isLoading = true
        errorMessage = ""

        Task { @MainActor in
            do {
                try await onboardingManager.createAccount(email: email, password: password)

                isLoading = false
                onAuthenticated()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Apple Sign-In

    private func handleAppleSignIn() {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = ""

        Task { @MainActor in
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else {
                errorMessage = "Cannot present Apple Sign-In"
                isLoading = false
                return
            }

            do {
                let appleResult = try await AppleSignInManager.shared.signIn(presenting: window)
                let success = await dataController.loginWithApple(appleResult: appleResult)

                guard success else {
                    errorMessage = "Apple sign-in failed. Please try again."
                    isLoading = false
                    return
                }

                // Existing user with a company — skip onboarding entirely
                if dataController.isAuthenticated {
                    isLoading = false
                    onExistingUserComplete?()
                    return
                }

                let userId = UserDefaults.standard.string(forKey: "user_id") ?? ""
                let userEmail = appleResult.email ?? UserDefaults.standard.string(forKey: "user_email") ?? ""

                // Apple only provides name on FIRST sign-in ever.
                // Persist it so retries / re-installs can still pre-fill.
                var resolvedFirstName = appleResult.givenName
                var resolvedLastName = appleResult.familyName

                if let givenName = appleResult.givenName {
                    UserDefaults.standard.set(givenName, forKey: "apple_given_name")
                } else if let saved = UserDefaults.standard.string(forKey: "apple_given_name"), !saved.isEmpty {
                    resolvedFirstName = saved
                }

                if let familyName = appleResult.familyName {
                    UserDefaults.standard.set(familyName, forKey: "apple_family_name")
                } else if let saved = UserDefaults.standard.string(forKey: "apple_family_name"), !saved.isEmpty {
                    resolvedLastName = saved
                }

                try await onboardingManager.handleSocialAuth(
                    userId: userId,
                    email: userEmail,
                    firstName: resolvedFirstName,
                    lastName: resolvedLastName
                )

                AnalyticsManager.shared.trackSignUp(userType: .company, method: .apple)
                AnalyticsService.shared.track(eventType: .lifecycle, eventName: "sign_up", properties: ["method": "apple"])

                isLoading = false
                onAuthenticated()
            } catch {
                isLoading = false
                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    // User canceled
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Google Sign-In

    private func handleGoogleSignIn() {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = ""

        Task { @MainActor in
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                errorMessage = "Cannot present Google Sign-In"
                isLoading = false
                return
            }

            do {
                let googleUser = try await GoogleSignInManager.shared.signIn(presenting: rootViewController)
                let success = await dataController.loginWithGoogle(googleUser: googleUser)

                guard success else {
                    errorMessage = "Google sign-in failed. Please try again."
                    isLoading = false
                    return
                }

                // Existing user with a company — skip onboarding entirely
                if dataController.isAuthenticated {
                    isLoading = false
                    onExistingUserComplete?()
                    return
                }

                let userId = UserDefaults.standard.string(forKey: "user_id") ?? ""
                let userEmail = googleUser.profile?.email ?? UserDefaults.standard.string(forKey: "user_email") ?? ""

                try await onboardingManager.handleSocialAuth(
                    userId: userId,
                    email: userEmail,
                    firstName: googleUser.profile?.givenName,
                    lastName: googleUser.profile?.familyName
                )

                // Download Google profile photo in background
                if let photoURL = googleUser.profile?.imageURL(withDimension: 400) {
                    Task {
                        if let (data, _) = try? await URLSession.shared.data(from: photoURL),
                           UIImage(data: data) != nil {
                            await MainActor.run {
                                onboardingManager.state.userData.avatarData = data
                            }
                        }
                    }
                }

                AnalyticsManager.shared.trackSignUp(userType: .company, method: .google)
                AnalyticsService.shared.track(eventType: .lifecycle, eventName: "sign_up", properties: ["method": "google"])

                isLoading = false
                onAuthenticated()
            } catch {
                isLoading = false
                if let gidError = error as? GIDSignInError, gidError.code == .canceled {
                    // User canceled
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
