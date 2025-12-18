//
//  EmailView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI

struct EmailView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    // For confirm password functionality
    @State private var localConfirmPassword: String = ""
    @State private var currentFieldIndex: Int = 0 // 0: email, 1: password, 2: confirm password

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

    var body: some View {
        ZStack {
            // Background color
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top navigation
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
                                .font(OPSStyle.Typography.caption.weight(.semibold))
                            Text("Back")
                                .font(OPSStyle.Typography.button)
                        }
                        .foregroundColor(secondaryTextColor)
                    }

                    Spacer()

                    Button(action: {
                        viewModel.logoutAndReturnToLogin()
                    }) {
                        Text("Cancel")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(secondaryTextColor)
                    }
                }

                // Step indicator bars
                HStack(spacing: 4) {
                    let totalSteps = viewModel.selectedUserType == .employee ? 6 : 11
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Rectangle()
                            .fill(step == 0 ? OPSStyle.Colors.primaryText : secondaryTextColor.opacity(0.3))
                            .frame(height: 2)
                    }
                }
                .padding(.top, 16)

                Spacer()

                // Main content
                VStack(alignment: .leading, spacing: 24) {
                    // Header - changes based on current field
                    VStack(alignment: .leading, spacing: 8) {
                        if currentFieldIndex == 0 {
                            Text("CREATE YOUR")
                                .font(OPSStyle.Typography.largeTitle.weight(.bold))
                                .foregroundColor(primaryTextColor)
                            Text("ACCOUNT.")
                                .font(OPSStyle.Typography.largeTitle.weight(.bold))
                                .foregroundColor(primaryTextColor)
                        } else if currentFieldIndex == 1 {
                            Text("SET YOUR")
                                .font(OPSStyle.Typography.largeTitle.weight(.bold))
                                .foregroundColor(primaryTextColor)
                            Text("PASSWORD.")
                                .font(OPSStyle.Typography.largeTitle.weight(.bold))
                                .foregroundColor(primaryTextColor)
                        } else {
                            Text("CONFIRM YOUR")
                                .font(OPSStyle.Typography.largeTitle.weight(.bold))
                                .foregroundColor(primaryTextColor)
                            Text("PASSWORD.")
                                .font(OPSStyle.Typography.largeTitle.weight(.bold))
                                .foregroundColor(primaryTextColor)
                        }
                    }
                    .padding(.bottom, 8)

                    // Subtitle
                    Text(currentFieldIndex == 0 ? "Enter your email. That's it." :
                         currentFieldIndex == 1 ? "Minimum 8 characters." :
                         "One more time.")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(secondaryTextColor)

                    // Input field
                    VStack(spacing: 8) {
                        if currentFieldIndex == 0 {
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

                            // Validation indicator
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
                            }
                        } else if currentFieldIndex == 1 {
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

                            // Validation indicator
                            if !viewModel.password.isEmpty {
                                HStack {
                                    Image(systemName: viewModel.isPasswordValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(viewModel.isPasswordValid ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                                    Text(viewModel.isPasswordValid ? "Password meets requirements" : "At least 8 characters required")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(viewModel.isPasswordValid ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
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

                            // Validation indicator
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
                            }
                        }
                    }

                    // Error message
                    if !viewModel.errorMessage.isEmpty {
                        ErrorMessageView(message: viewModel.errorMessage)
                    }
                }

                Spacer()

                // Continue button
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
                .padding(.bottom, 20)
            }
            .padding(40)
        }
        .dismissKeyboardOnTap()
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
