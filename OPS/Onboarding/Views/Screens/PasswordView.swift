//
//  PasswordView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI

struct PasswordView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var showPassword: Bool = false
    @State private var showConfirmPassword: Bool = false
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create a")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("password.")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.bottom, 12)
                    
                    Text("Use at least 8 characters for a strong password.")
                        .font(.system(size: 16))
                        .foregroundColor(Color.gray)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
                
                // Password input
                VStack(spacing: 20) {
                    // Password field
                    VStack(alignment: .leading, spacing: 8) {
                        InputFieldLabel(label: "PASSWORD")
                        
                        HStack {
                            if showPassword {
                                TextField("Password", text: $viewModel.password)
                                    .font(.system(size: 16))
                                    .disableAutocorrection(true)
                                    .transition(.opacity)
                            } else {
                                SecureField("Password", text: $viewModel.password)
                                    .font(.system(size: 16))
                                    .transition(.opacity)
                            }
                            
                            Button(action: { 
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showPassword.toggle() 
                                }
                            }) {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .onboardingTextFieldStyle()
                    }
                    
                    // Confirm password field
                    VStack(alignment: .leading, spacing: 8) {
                        InputFieldLabel(label: "CONFIRM PASSWORD")
                        
                        HStack {
                            if showConfirmPassword {
                                TextField("Confirm password", text: $viewModel.confirmPassword)
                                    .font(.system(size: 16))
                                    .disableAutocorrection(true)
                                    .transition(.opacity)
                            } else {
                                SecureField("Confirm password", text: $viewModel.confirmPassword)
                                    .font(.system(size: 16))
                                    .transition(.opacity)
                            }
                            
                            Button(action: { 
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showConfirmPassword.toggle() 
                                }
                            }) {
                                Image(systemName: showConfirmPassword ? "eye.slash.fill" : "eye.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .onboardingTextFieldStyle()
                    }
                }
                
                // Password validation indicators
                VStack(alignment: .leading, spacing: 8) {
                    ValidationIndicator(
                        isValid: viewModel.isPasswordValid,
                        text: "At least 8 characters"
                    )
                    
                    if !viewModel.password.isEmpty && !viewModel.confirmPassword.isEmpty {
                        ValidationIndicator(
                            isValid: viewModel.isPasswordMatching,
                            text: "Passwords match"
                        )
                    }
                }
                .padding(.top, 8)
                
                // Error message
                ErrorMessageView(message: viewModel.errorMessage)
                
                Spacer()
                
                // Buttons
                OnboardingNavigationButtons(
                    primaryText: "Continue",
                    secondaryText: "Back",
                    isPrimaryDisabled: !viewModel.isPasswordValid || !viewModel.isPasswordMatching,
                    isLoading: viewModel.isLoading,
                    onPrimaryTapped: {
                        // Attempt sign up with email/password
                        viewModel.errorMessage = ""
                        viewModel.isLoading = true
                        
                        Task {
                            // Submit to API - now handles errors internally and returns success/failure
                            let success = try await viewModel.submitEmailPasswordSignUp()
                            
                            await MainActor.run {
                                viewModel.isLoading = false
                                
                                if success {
                                    viewModel.moveTo(step: .organizationJoin) // Go to organization join screen
                                }
                            }
                        }
                    },
                    onSecondaryTapped: {
                        viewModel.moveToPreviousStep()
                    }
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 30)
        }
    }
}

// Helper for validation indicators
struct ValidationIndicator: View {
    var isValid: Bool
    var text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isValid ? Color("StatusSuccess") : Color("StatusError"))
                .font(.system(size: 14))
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(isValid ? Color("StatusSuccess") : Color("StatusError"))
        }
    }
}

// MARK: - Preview
#Preview("Password Setup") {
    let viewModel = OnboardingViewModel()
    viewModel.email = "user@example.com"
    viewModel.password = "password123"
    viewModel.confirmPassword = "password123"
    
    return PasswordView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}