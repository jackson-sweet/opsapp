//
//  EmailView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI

struct EmailView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var isInConsolidatedFlow: Bool = false
    
    // For confirm password functionality
    @State private var localConfirmPassword: String = ""
    
    // Check if passwords match
    private var passwordsMatch: Bool {
        !viewModel.password.isEmpty && viewModel.password == localConfirmPassword
    }
    
    var canProceed: Bool {
        if isInConsolidatedFlow {
            return viewModel.isEmailValid && viewModel.isPasswordValid && passwordsMatch
        } else {
            return viewModel.isEmailValid
        }
    }
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Top navigation and progress section
                VStack(spacing: 0) {
                    // Navigation bar with back button and step indicator for consolidated flow
                    if isInConsolidatedFlow {
                        HStack {
                            Button(action: {
                                viewModel.moveToPreviousStepV2()
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
                            
                            Text("Step 1 of 6")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(Color.gray)
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                        
                        // Step indicator bars
                        HStack(spacing: 4) {
                            ForEach(0..<6) { step in
                                Rectangle()
                                    .fill(step == 0 ? OPSStyle.Colors.primaryAccent : Color.gray.opacity(0.4))
                                    .frame(height: 4)
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
                .padding(.horizontal, isInConsolidatedFlow ? OPSStyle.Layout.spacing3 : 0)
                
                // Main centered content area
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 0) {
                            // Center content vertically in available space
                            Spacer()
                                .frame(height: max(20, geometry.size.height * 0.1))
                            
                            // Main content
                            VStack(spacing: 24) {
                                // Header
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(isInConsolidatedFlow ? "Create your" : "What's your")
                                        .font(OPSStyle.Typography.title)
                                        .foregroundColor(.white)
                                    
                                    Text(isInConsolidatedFlow ? "account." : "email address?")
                                        .font(OPSStyle.Typography.title)
                                        .foregroundColor(.white)
                                        .padding(.bottom, 12)
                                    
                                    Text(isInConsolidatedFlow ? 
                                        "Enter your email and create a password to get started with OPS." : 
                                        "We'll use this to sign you in and send important updates.")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(Color.gray)
                                        .lineSpacing(4)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 20)
                                
                                // Email input
                                VStack(alignment: .leading, spacing: 8) {
                                    InputFieldLabel(label: "EMAIL ADDRESS")
                                    
                                    TextField("Email", text: $viewModel.email)
                                        .font(OPSStyle.Typography.body)
                                        .keyboardType(.emailAddress)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .textContentType(.oneTimeCode) // Prevents autofill
                                        .onboardingTextFieldStyle()
                                        .transition(.opacity)
                                        .animation(.easeInOut, value: isInConsolidatedFlow)
                                }
                                
                                // Validation indicator
                                if !viewModel.email.isEmpty {
                                    HStack {
                                        Image(systemName: viewModel.isEmailValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(viewModel.isEmailValid ? Color("StatusSuccess") : Color("StatusError"))
                                        
                                        Text(viewModel.isEmailValid ? "Valid email" : "Invalid email format")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(viewModel.isEmailValid ? Color("StatusSuccess") : Color("StatusError"))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                                }
                                
                                // Password section for consolidated flow
                                if isInConsolidatedFlow {
                                    // Password input
                                    VStack(alignment: .leading, spacing: 8) {
                                        InputFieldLabel(label: "PASSWORD")
                                        
                                        SecureField("Password (8+ characters)", text: $viewModel.password)
                                            .font(OPSStyle.Typography.body)
                                            .textContentType(.oneTimeCode) // Prevents autofill
                                            .onboardingTextFieldStyle()
                                            .transition(.opacity)
                                            .animation(.easeInOut, value: isInConsolidatedFlow)
                                    }
                                    .padding(.top, 16)
                                    
                                    // Password validation
                                    if !viewModel.password.isEmpty {
                                        HStack {
                                            Image(systemName: viewModel.isPasswordValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(viewModel.isPasswordValid ? Color("StatusSuccess") : Color("StatusError"))
                                            
                                            Text(viewModel.isPasswordValid ? "Password meets requirements" : "Password must be at least 8 characters")
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(viewModel.isPasswordValid ? Color("StatusSuccess") : Color("StatusError"))
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 4)
                                    }
                                    
                                    // Confirm password 
                                    VStack(alignment: .leading, spacing: 8) {
                                        InputFieldLabel(label: "CONFIRM PASSWORD")
                                        
                                        SecureField("Re-enter password", text: $localConfirmPassword)
                                            .font(OPSStyle.Typography.body)
                                            .textContentType(.oneTimeCode) // Prevents autofill
                                            .onboardingTextFieldStyle()
                                            .transition(.opacity)
                                            .animation(.easeInOut, value: isInConsolidatedFlow)
                                    }
                                    .padding(.top, 16)
                                    
                                    // Confirm password validation
                                    if !localConfirmPassword.isEmpty {
                                        HStack {
                                            Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(passwordsMatch ? Color("StatusSuccess") : Color("StatusError"))
                                            
                                            Text(passwordsMatch ? "Passwords match" : "Passwords don't match")
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(passwordsMatch ? Color("StatusSuccess") : Color("StatusError"))
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 4)
                                    }
                                    
                                    // Info message
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "info.circle.fill")
                                            .foregroundColor(.white.opacity(0.7))
                                            .font(OPSStyle.Typography.caption)
                                        
                                        Text("Your password should have at least 8 characters and include a mix of letters, numbers and symbols.")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    .padding(.top, 8)
                                }
                                
                                // Error message
                                if !viewModel.errorMessage.isEmpty {
                                    ErrorMessageView(message: viewModel.errorMessage)
                                        .padding(.top, 16)
                                }
                            }
                            .padding(.horizontal, 24)
                            
                            // Add spacer to push content up
                            Spacer()
                                .frame(height: max(20, geometry.size.height * 0.1))
                        }
                        .frame(minHeight: geometry.size.height)
                    }
                }
                
                // Bottom button section
                VStack {
                    // Button actions differ based on flow
                    if isInConsolidatedFlow {
                        // Account setup action (email + password)
                        Button(action: {
                            Task {
                                viewModel.isLoading = true
                                // Since we've added confirm password, set it in viewModel too
                                viewModel.confirmPassword = localConfirmPassword
                                
                                let success = try? await viewModel.submitEmailPasswordSignUp()
                                
                                await MainActor.run {
                                    viewModel.isLoading = false
                                    
                                    if success == true {
                                        // Proceed to next step if signup successful
                                        viewModel.moveToNextStepV2()
                                    }
                                }
                            }
                        }) {
                            ZStack {
                                HStack {
                                    Text("Continue")
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(.black)
                                        .opacity(viewModel.isLoading ? 0 : 1)
                                    
                                    Spacer()
                                    
                                    if !viewModel.isLoading && canProceed {
                                        Image(systemName: "arrow.right")
                                            .font(OPSStyle.Typography.captionBold)
                                            .foregroundColor(.black)
                                            .padding(.trailing, 20)
                                    }
                                }
                                
                                if viewModel.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                }
                            }
                            .padding(.horizontal, 20)
                            .frame(height: 52)
                            .frame(maxWidth: .infinity)
                            .background(canProceed && !viewModel.isLoading ? Color.white : Color.white.opacity(0.7))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        .disabled(!canProceed || viewModel.isLoading)
                    } else {
                        // Standard flow navigation
                        OnboardingNavigationButtons(
                            primaryText: "Continue",
                            secondaryText: "Back",
                            isPrimaryDisabled: !viewModel.isEmailValid,
                            isLoading: viewModel.isLoading,
                            onPrimaryTapped: {
                                viewModel.moveToNextStep()
                            },
                            onSecondaryTapped: {
                                viewModel.moveToPreviousStep()
                            }
                        )
                    }
                }
                .padding(.horizontal, isInConsolidatedFlow ? OPSStyle.Layout.spacing3 : 24)
                .padding(.vertical, 20)
                .background(Color.black.opacity(0.7))
            }
        }
    }
}

// MARK: - Preview
#Preview("Email Screen") {
    let viewModel = OnboardingViewModel()
    viewModel.email = "user@example.com"
    
    return EmailView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}