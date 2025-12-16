//
//  EmailView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI
import GoogleSignIn
import AuthenticationServices

struct EmailView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    // For confirm password functionality
    @State private var localConfirmPassword: String = ""
    @State private var currentFieldIndex: Int = 0 // 0: email, 1: password, 2: confirm password

    // Social sign-in states
    @State private var isSigningInWithSocial = false
    @State private var socialSignInError: String?
    
    // Check if passwords match
    private var passwordsMatch: Bool {
        !viewModel.password.isEmpty && viewModel.password == localConfirmPassword
    }
    
    var canProceed: Bool {
        return viewModel.isEmailValid
    }
    
    // Color scheme based on user type
    private var backgroundColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.background : OPSStyle.Colors.background
    }
    
    private var primaryTextColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText
    }
    
    private var secondaryTextColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText
    }
    
    private var cardBackgroundColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.cardBackground : OPSStyle.Colors.cardBackground
    }
    
    var body: some View {
        ZStack {
            // Background color
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top navigation and progress section
                VStack(spacing: 0) {
                    // Navigation bar with back button and step indicator for consolidated flow
                    if true {
                        HStack {
                            Button(action: {
                                if currentFieldIndex > 0 {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        currentFieldIndex -= 1
                                    }
                                } else {
                                    viewModel.moveToPreviousStep()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(OPSStyle.Typography.captionBold)
                                    Text("Back")
                                        .font(OPSStyle.Typography.bodyBold)
                                }
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                viewModel.logoutAndReturnToLogin()
                            }) {
                                Text("Sign Out")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(secondaryTextColor)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                        
                        // Step indicator bars
                        HStack(spacing: 4) {
                            let totalSteps = viewModel.selectedUserType == .employee ? 6 : 11
                            ForEach(0..<totalSteps) { step in
                                Rectangle()
                                    .fill(step == 0 ? OPSStyle.Colors.primaryAccent : secondaryTextColor.opacity(0.4))
                                    .frame(height: 4)
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                
                // Main content area - top-justified alignment
                VStack(spacing: 0) {
                    // Main content
                    VStack(spacing: 24) {
                        // Header - changes based on current field
                        VStack(alignment: .leading, spacing: 8) {
                            if true {
                                if currentFieldIndex == 0 {
                                    Text("Create your")
                                        .font(OPSStyle.Typography.title)
                                        .foregroundColor(primaryTextColor)
                                    
                                    Text("account.")
                                        .font(OPSStyle.Typography.title)
                                        .foregroundColor(primaryTextColor)
                                        .padding(.bottom, 12)
                                    
                                    Text("Enter your email address to get started with OPS.")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(secondaryTextColor)
                                        .lineSpacing(4)
                                } else if currentFieldIndex == 1 {
                                    Text("Create a")
                                        .font(OPSStyle.Typography.title)
                                        .foregroundColor(primaryTextColor)
                                    
                                    Text("password.")
                                        .font(OPSStyle.Typography.title)
                                        .foregroundColor(primaryTextColor)
                                        .padding(.bottom, 12)
                                    
                                    Text("Use at least 8 characters for a strong password.")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(secondaryTextColor)
                                        .lineSpacing(4)
                                } else {
                                    Text("Confirm your")
                                        .font(OPSStyle.Typography.title)
                                        .foregroundColor(primaryTextColor)
                                    
                                    Text("password.")
                                        .font(OPSStyle.Typography.title)
                                        .foregroundColor(primaryTextColor)
                                        .padding(.bottom, 12)
                                    
                                    Text("Re-enter your password to confirm.")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(secondaryTextColor)
                                        .lineSpacing(4)
                                }
                            } else {
                                Text("What's your")
                                    .font(OPSStyle.Typography.title)
                                    .foregroundColor(primaryTextColor)
                                
                                Text("email address?")
                                    .font(OPSStyle.Typography.title)
                                    .foregroundColor(primaryTextColor)
                                    .padding(.bottom, 12)
                                
                                Text("We'll use this to sign you in and send important updates.")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(secondaryTextColor)
                                    .lineSpacing(4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Single field display based on currentFieldIndex
                        VStack(spacing: 16) {
                            if currentFieldIndex == 0 {
                                // Email input
                                UnderlineTextField(
                                    placeholder: "Email address",
                                    text: $viewModel.email,
                                    keyboardType: .emailAddress,
                                    viewModel: viewModel,
                                    onChange: { _ in
                                        viewModel.errorMessage = ""
                                    }
                                )
                                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

                                // Validation indicator for email
                                if !viewModel.email.isEmpty {
                                    HStack {
                                        Image(systemName: viewModel.isEmailValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(viewModel.isEmailValid ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)

                                        Text(viewModel.isEmailValid ? "Valid email" : "Invalid email format")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(viewModel.isEmailValid ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                                }

                                // OR Divider
                                HStack {
                                    Rectangle()
                                        .fill(secondaryTextColor.opacity(0.3))
                                        .frame(height: 1)

                                    Text("OR")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(secondaryTextColor)
                                        .padding(.horizontal, 16)

                                    Rectangle()
                                        .fill(secondaryTextColor.opacity(0.3))
                                        .frame(height: 1)
                                }
                                .padding(.vertical, 16)

                                // Social sign-in buttons
                                VStack(spacing: 12) {
                                    // Google Sign-In button
                                    SignupGoogleButton(
                                        isLoading: isSigningInWithSocial,
                                        isLightTheme: viewModel.shouldUseLightTheme,
                                        onSignIn: handleGoogleSignIn
                                    )
                                    .frame(height: OPSStyle.Layout.touchTargetStandard)

                                    // Apple Sign-In button
                                    SignupAppleButton(
                                        isLoading: isSigningInWithSocial,
                                        isLightTheme: viewModel.shouldUseLightTheme,
                                        onSignIn: handleAppleSignIn
                                    )
                                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                                }
                            } else if currentFieldIndex == 1 {
                                // Password input
                                UnderlineTextField(
                                    placeholder: "Password",
                                    text: $viewModel.password,
                                    isSecure: true,
                                    viewModel: viewModel,
                                    onChange: { _ in
                                        viewModel.errorMessage = ""
                                    }
                                )
                                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                                
                                // Password validation
                                if !viewModel.password.isEmpty {
                                    HStack {
                                        Image(systemName: viewModel.isPasswordValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(viewModel.isPasswordValid ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                                        
                                        Text(viewModel.isPasswordValid ? "Password meets requirements" : "Password must be at least 8 characters")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(viewModel.isPasswordValid ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                                }
                            } else {
                                // Confirm password input
                                UnderlineTextField(
                                    placeholder: "Confirm password",
                                    text: $localConfirmPassword,
                                    isSecure: true,
                                    viewModel: viewModel,
                                    onChange: { _ in
                                        viewModel.errorMessage = ""
                                    }
                                )
                                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                                
                                // Confirm password validation
                                if !localConfirmPassword.isEmpty {
                                    HStack {
                                        Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(passwordsMatch ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                                        
                                        Text(passwordsMatch ? "Passwords match" : "Passwords don't match")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(passwordsMatch ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                                }
                            }
                        }
                        
                        // Error message
                        if !viewModel.errorMessage.isEmpty {
                            ErrorMessageView(message: viewModel.errorMessage)
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, 40) // Add consistent top padding
                }
                
                Spacer() // Push buttons to bottom
                
                // Bottom button section
                VStack {
                    if true {
                        StandardContinueButton(
                            isDisabled: viewModel.isLoading ||
                                       (currentFieldIndex == 0 && !viewModel.isEmailValid) ||
                                       (currentFieldIndex == 1 && !viewModel.isPasswordValid) ||
                                       (currentFieldIndex == 2 && !passwordsMatch),
                            isLoading: viewModel.isLoading,
                            onTap: {
                                if currentFieldIndex == 0 && viewModel.isEmailValid {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        currentFieldIndex = 1
                                    }
                                } else if currentFieldIndex == 1 && viewModel.isPasswordValid {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        currentFieldIndex = 2
                                    }
                                } else if currentFieldIndex == 2 && passwordsMatch {
                                    Task {
                                        viewModel.isLoading = true
                                        viewModel.confirmPassword = localConfirmPassword
                                        
                                        let success = try? await viewModel.submitEmailPasswordSignUp()
                                        
                                        await MainActor.run {
                                            viewModel.isLoading = false
                                            
                                            if success == true {
                                                viewModel.moveToNextStep()
                                            }
                                        }
                                    }
                                }
                            }
                        )
                    } else {
                        OnboardingNavigationButtons(
                            primaryText: "CONTINUE",
                            secondaryText: "Back",
                            isPrimaryDisabled: !viewModel.isEmailValid,
                            isLoading: viewModel.isLoading,
                            isLightTheme: viewModel.shouldUseLightTheme,
                            onPrimaryTapped: {
                                viewModel.moveToNextStep()
                            },
                            onSecondaryTapped: {
                                viewModel.moveToPreviousStep()
                            }
                        )
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing3)
                .background(backgroundColor.opacity(0.7))
            }
        }
        .dismissKeyboardOnTap()
    }

    // MARK: - Social Sign-In Handlers

    private func handleGoogleSignIn() {
        guard !isSigningInWithSocial else { return }

        isSigningInWithSocial = true
        viewModel.errorMessage = ""

        Task { @MainActor in
            // Get the root view controller
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                viewModel.errorMessage = "Cannot present Google Sign-In"
                isSigningInWithSocial = false
                return
            }

            do {
                // Perform Google Sign-In
                let googleUser = try await GoogleSignInManager.shared.signIn(presenting: rootViewController)

                // Authenticate with Bubble backend (handles both signup and login)
                guard let dataController = viewModel.dataController else {
                    viewModel.errorMessage = "Unable to complete sign-in"
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
                    viewModel.errorMessage = "Google sign-in failed. Please try again."
                }
            } catch {
                isSigningInWithSocial = false

                // Check if it was a cancellation
                if let gidError = error as? GIDSignInError, gidError.code == .canceled {
                    // User canceled, don't show error
                } else {
                    viewModel.errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func handleAppleSignIn() {
        guard !isSigningInWithSocial else { return }

        isSigningInWithSocial = true
        viewModel.errorMessage = ""

        Task { @MainActor in
            // Get the key window for presentation
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else {
                viewModel.errorMessage = "Cannot present Apple Sign-In"
                isSigningInWithSocial = false
                return
            }

            do {
                // Perform Apple Sign-In
                let appleResult = try await AppleSignInManager.shared.signIn(presenting: window)

                // Authenticate with Bubble backend (handles both signup and login)
                guard let dataController = viewModel.dataController else {
                    viewModel.errorMessage = "Unable to complete sign-in"
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
                    viewModel.errorMessage = "Apple sign-in failed. Please try again."
                }
            } catch {
                isSigningInWithSocial = false

                // Check if it was a cancellation
                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    // User canceled, don't show error
                } else {
                    viewModel.errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Social Sign-In Buttons

/// Google Sign-In button styled for signup flow
struct SignupGoogleButton: View {
    let isLoading: Bool
    let isLightTheme: Bool
    let onSignIn: () -> Void

    private var textColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText
    }

    private var borderColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.tertiaryText
    }

    var body: some View {
        Button(action: onSignIn) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: textColor))
                } else {
                    // Google logo
                    Image("google_logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)

                    Text("Continue with Google")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(textColor)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .disabled(isLoading)
    }
}

/// Apple Sign-In button styled for signup flow
struct SignupAppleButton: View {
    let isLoading: Bool
    let isLightTheme: Bool
    let onSignIn: () -> Void

    private var textColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText
    }

    private var borderColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.tertiaryText
    }

    var body: some View {
        Button(action: onSignIn) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: textColor))
                } else {
                    // Apple logo
                    Image(systemName: "apple.logo")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(textColor)

                    Text("Continue with Apple")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(textColor)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .disabled(isLoading)
    }
}

// MARK: - Preview
#Preview("Email Screen") {
    let viewModel = OnboardingViewModel()
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    viewModel.email = "user@example.com"
    
    return EmailView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environmentObject(dataController)
        .environment(\.colorScheme, .dark)
}
