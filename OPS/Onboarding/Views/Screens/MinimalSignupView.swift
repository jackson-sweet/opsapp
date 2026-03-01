//
//  MinimalSignupView.swift
//  OPS
//
//  Single-screen signup for onboarding A/B/C test.
//  Combines Apple Sign-In, Google Sign-In, email/password, and company name
//  into one view, replacing the multi-screen signup flow.
//

import SwiftUI
import GoogleSignIn
import AuthenticationServices

struct MinimalSignupView: View {
    @ObservedObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataController: DataController
    let variant: OnboardingVariant
    let onComplete: (String) -> Void  // passes crew code

    @State private var email = ""
    @State private var password = ""
    @State private var companyName = ""
    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            // Background
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

                    // MARK: - Input fields
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

                        // Company Name field
                        VStack(spacing: 8) {
                            TextField("", text: $companyName, prompt: Text("Company Name").foregroundColor(OPSStyle.Colors.secondaryText))
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .textContentType(.organizationName)
                                .disableAutocorrection(true)

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
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(OPSStyle.Colors.invertedText)
                                        .font(OPSStyle.Typography.caption.weight(.semibold))
                                        .padding(.trailing, 20)
                                }
                            }
                        )
                    }
                    .disabled(isLoading)

                    Spacer().frame(height: 20)
                }
                .padding(40)
            }
        }
        .onAppear {
            AnalyticsManager.shared.trackSignUp(userType: nil, method: .email)
        }
    }

    // MARK: - Email/Password Sign-Up

    private func handleEmailSignup() {
        // Validate inputs
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter your email address."
            return
        }
        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            return
        }
        guard !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter your company name."
            return
        }

        isLoading = true
        errorMessage = ""

        Task { @MainActor in
            do {
                // Set flow to company creator for the minimal signup
                onboardingManager.state.flow = .companyCreator

                // 1. Create the account
                try await onboardingManager.createAccount(email: email, password: password)

                // 2. Set company name
                onboardingManager.state.companyData.name = companyName.trimmingCharacters(in: .whitespacesAndNewlines)

                // 3. Create company and get crew code
                let crewCode = try await onboardingManager.createCompany()

                // 4. Store crew code
                UserDefaults.standard.set(crewCode, forKey: "company_code")

                // 5. Track analytics
                AnalyticsManager.shared.trackSignUp(userType: .company, method: .email)

                // 6. Migrate demo data if from pre-signup tutorial (Variant A)
                await migrateDemoDataIfNeeded()

                isLoading = false

                // 7. Complete
                onComplete(crewCode)
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
                // 1. Apple Sign-In
                let appleResult = try await AppleSignInManager.shared.signIn(presenting: window)

                // 2. Authenticate with Supabase via DataController
                let success = await dataController.loginWithApple(appleResult: appleResult)

                guard success else {
                    errorMessage = "Apple sign-in failed. Please try again."
                    isLoading = false
                    return
                }

                // 3. Set flow and handle social auth in onboarding manager
                onboardingManager.state.flow = .companyCreator

                let userId = UserDefaults.standard.string(forKey: "user_id") ?? ""
                let userEmail = appleResult.email ?? UserDefaults.standard.string(forKey: "user_email") ?? ""

                try await onboardingManager.handleSocialAuth(
                    userId: userId,
                    email: userEmail,
                    firstName: appleResult.givenName,
                    lastName: appleResult.familyName
                )

                // 4. Set company name and create company
                guard !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    errorMessage = "Please enter your company name before signing up."
                    isLoading = false
                    return
                }

                onboardingManager.state.companyData.name = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
                let crewCode = try await onboardingManager.createCompany()
                UserDefaults.standard.set(crewCode, forKey: "company_code")

                // 5. Track analytics
                AnalyticsManager.shared.trackSignUp(userType: .company, method: .apple)

                // 6. Migrate demo data if from pre-signup tutorial (Variant A)
                await migrateDemoDataIfNeeded()

                isLoading = false

                // 7. Complete
                onComplete(crewCode)
            } catch {
                isLoading = false

                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    // User canceled — silently ignore
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
                // 1. Google Sign-In
                let googleUser = try await GoogleSignInManager.shared.signIn(presenting: rootViewController)

                // 2. Authenticate with Supabase via DataController
                let success = await dataController.loginWithGoogle(googleUser: googleUser)

                guard success else {
                    errorMessage = "Google sign-in failed. Please try again."
                    isLoading = false
                    return
                }

                // 3. Set flow and handle social auth in onboarding manager
                onboardingManager.state.flow = .companyCreator

                let userId = UserDefaults.standard.string(forKey: "user_id") ?? ""
                let userEmail = googleUser.profile?.email ?? UserDefaults.standard.string(forKey: "user_email") ?? ""

                try await onboardingManager.handleSocialAuth(
                    userId: userId,
                    email: userEmail,
                    firstName: googleUser.profile?.givenName,
                    lastName: googleUser.profile?.familyName
                )

                // 4. Set company name and create company
                guard !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    errorMessage = "Please enter your company name before signing up."
                    isLoading = false
                    return
                }

                onboardingManager.state.companyData.name = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
                let crewCode = try await onboardingManager.createCompany()
                UserDefaults.standard.set(crewCode, forKey: "company_code")

                // 5. Track analytics
                AnalyticsManager.shared.trackSignUp(userType: .company, method: .google)

                // 6. Migrate demo data if from pre-signup tutorial (Variant A)
                await migrateDemoDataIfNeeded()

                isLoading = false

                // 7. Complete
                onComplete(crewCode)
            } catch {
                isLoading = false

                if let gidError = error as? GIDSignInError, gidError.code == .canceled {
                    // User canceled — silently ignore
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Demo Data Migration (Variant A)

    /// If the user completed a pre-signup tutorial, migrate demo data to their real account
    private func migrateDemoDataIfNeeded() async {
        guard UserDefaults.standard.bool(forKey: "pending_demo_data_migration") else { return }

        let realUserId = UserDefaults.standard.string(forKey: "user_id") ?? ""
        let realCompanyId = UserDefaults.standard.string(forKey: "company_id") ?? ""

        guard !realUserId.isEmpty, !realCompanyId.isEmpty else {
            print("[MINIMAL_SIGNUP] Cannot migrate demo data — missing real user/company ID")
            return
        }

        await TutorialDemoDataManager.migrateDemoDataToRealUser(
            dataController: dataController,
            realUserId: realUserId,
            realCompanyId: realCompanyId
        )
    }
}
