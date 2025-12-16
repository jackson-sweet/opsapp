//
//  UserTypeSelectionView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-23.
//

import SwiftUI
import GoogleSignIn
import AuthenticationServices

struct UserTypeSelectionView: View {
    @EnvironmentObject var viewModel: OnboardingViewModel

    // Social sign-in states
    @State private var isSigningInWithSocial = false
    @State private var socialSignInError: String?
    
    // Color scheme based on selected user type
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
            // Background - changes based on selection
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Header
                HStack(alignment: .bottom, spacing: 16) {
                    Image("LogoWhite")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 60)
                        .colorMultiply(viewModel.shouldUseLightTheme ? .black : .white) // Adjust logo color
                    
                    Text("OPS")
                        .font(OPSStyle.Typography.largeTitle)
                        .foregroundColor(primaryTextColor)
                    Spacer()
                }
                .padding(.top, 60)
                
                Spacer()
                
                // Content
                VStack(spacing: 24) {

                    // User type options
                    VStack(spacing: 16) {
                        UserTypeOption(
                            type: .company,
                            title: "COMPANY LEAD",
                            description: "Command operations. Coordinate teams. Control the outcomes.",
                            isSelected: viewModel.selectedUserType == .company,
                            isLightTheme: viewModel.shouldUseLightTheme,
                            action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    viewModel.selectedUserType = .company
                                }
                            }
                        )

                        UserTypeOption(
                            type: .employee,
                            title: "TEAM MEMBER",
                            description: "Execute plans. Crush projects. Rise through the ranks.",
                            isSelected: viewModel.selectedUserType == .employee,
                            isLightTheme: viewModel.shouldUseLightTheme,
                            action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    viewModel.selectedUserType = .employee
                                }
                            }
                        )
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

                    // Error message
                    if let error = socialSignInError {
                        Text(error)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()
                
                // Continue button
                StandardContinueButton(
                    isDisabled: viewModel.selectedUserType == nil,
                    onTap: {
                        if viewModel.selectedUserType != nil {
                            viewModel.moveToNextStep()
                        }
                    }
                )
                .padding(.bottom, 50)
            }
            .padding(OPSStyle.Layout.spacing3)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.selectedUserType)
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

struct UserTypeOption: View {
    let type: UserType
    let title: String
    let description: String
    let isSelected: Bool
    let isLightTheme: Bool
    let action: () -> Void
    @EnvironmentObject var viewModel: OnboardingViewModel
    
    private var primaryTextColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText
    }
    
    private var secondaryTextColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText
    }
    
    private var cardBackgroundColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.cardBackground : OPSStyle.Colors.cardBackground
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(isSelected ? (isLightTheme ? .white : .black) : primaryTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(description)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(isSelected ? (isLightTheme ? OPSStyle.Colors.Light.tertiaryText : OPSStyle.Colors.tertiaryText) : secondaryTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(nil)
                }
                
                Spacer()
                
                // Selection indicator
                Image(systemName: "rectangle.portrait.and.arrow.forward")
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? (isLightTheme ? .white : .black) : primaryTextColor)
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(isSelected ?
                          (isLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText) :
                          cardBackgroundColor.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(isSelected ? OPSStyle.Colors.secondaryText : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    UserTypeSelectionView()
        .environmentObject(OnboardingViewModel())
        .environmentObject(dataController)
        .preferredColorScheme(.dark)
}
