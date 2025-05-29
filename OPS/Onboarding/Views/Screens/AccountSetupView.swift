//
//  AccountSetupView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import SwiftUI
import Combine

struct AccountSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    
    // Calculate the current step number and total steps based on user type
    private var currentStepNumber: Int {
        return 1 // First step for both flows
    }
    
    private var totalSteps: Int {
        if viewModel.selectedUserType == .employee {
            return 8 // Employee flow has 8 total steps
        } else {
            return 10 // Company flow has 10 total steps
        }
    }
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Navigation header with step indicator
                HStack {
                    Button(action: {
                        viewModel.moveToPreviousStep()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(OPSStyle.Typography.caption)
                            Text("Back")
                                .font(OPSStyle.Typography.bodyBold)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding(.horizontal, 24)
                
                // Step indicator bars
                HStack(spacing: 4) {
                    ForEach(0..<totalSteps) { step in
                        Rectangle()
                            .fill(step < currentStepNumber ? OPSStyle.Colors.primaryAccent : Color.gray.opacity(0.4))
                            .frame(height: 4)
                    }
                }
                .padding(.bottom, 16)
                .padding(.horizontal, 24)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CREATE YOUR")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(.white)
                            
                            Text("ACCOUNT")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(.white)
                                .padding(.bottom, 12)
                            
                            Text(OnboardingStep.accountSetup.subtitle)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(Color.gray)
                                .lineSpacing(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 10)
                        
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            InputFieldLabel(label: "EMAIL ADDRESS")
                            
                            TextField("Your email", text: $viewModel.email)
                                .font(OPSStyle.Typography.body)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .onboardingTextFieldStyle()
                        }
                        
                        // Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            InputFieldLabel(label: "PASSWORD")
                            
                            ZStack {
                                if isPasswordVisible {
                                    TextField("Your password", text: $viewModel.password)
                                        .font(OPSStyle.Typography.body)
                                        .textContentType(.newPassword)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .onboardingTextFieldStyle()
                                } else {
                                    SecureField("Your password", text: $viewModel.password)
                                        .font(OPSStyle.Typography.body)
                                        .textContentType(.newPassword)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .onboardingTextFieldStyle()
                                }
                                
                                // Visibility toggle button
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        isPasswordVisible.toggle()
                                    }) {
                                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                            .foregroundColor(.gray)
                                            .frame(width: 24, height: 24)
                                    }
                                    .padding(.trailing, 8)
                                }
                            }
                            
                            // Password requirements hint
                            Text("Must be at least 8 characters")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(viewModel.isPasswordValid ? Color.green : Color.gray.opacity(0.7))
                                .padding(.top, 4)
                        }
                        
                        // Confirm Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            InputFieldLabel(label: "CONFIRM PASSWORD")
                            
                            ZStack {
                                if isConfirmPasswordVisible {
                                    TextField("Confirm password", text: $viewModel.confirmPassword)
                                        .font(OPSStyle.Typography.body)
                                        .textContentType(.newPassword)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .onboardingTextFieldStyle()
                                } else {
                                    SecureField("Confirm password", text: $viewModel.confirmPassword)
                                        .font(OPSStyle.Typography.body)
                                        .textContentType(.newPassword)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .onboardingTextFieldStyle()
                                }
                                
                                // Visibility toggle button
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        isConfirmPasswordVisible.toggle()
                                    }) {
                                        Image(systemName: isConfirmPasswordVisible ? "eye.slash" : "eye")
                                            .foregroundColor(.gray)
                                            .frame(width: 24, height: 24)
                                    }
                                    .padding(.trailing, 8)
                                }
                            }
                            
                            // Password match hint
                            if !viewModel.confirmPassword.isEmpty {
                                Text(viewModel.isPasswordMatching ? "Passwords match" : "Passwords don't match")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(viewModel.isPasswordMatching ? Color.green : Color.red)
                                    .padding(.top, 4)
                            }
                        }
                        
                        // Error message
                        ErrorMessageView(message: viewModel.errorMessage)
                        
                        Spacer()
                        
                        // Continue button
                        StandardContinueButton(
                            isDisabled: !viewModel.canProceedFromAccountSetup,
                            isLoading: viewModel.isLoading,
                            onTap: {
                                submitAccountSetup()
                            }
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                }
                
                // Loading overlay
                if viewModel.isLoading {
                    LoadingView(message: "Creating Account...")
                }
            }
        }
    }
    
    private func submitAccountSetup() {
        print("AccountSetupView: Submit button tapped")
        
        // Set loading state
        viewModel.isLoading = true
        viewModel.errorMessage = ""
        
        // Submit account creation
        Task {
            do {
                let success = try await viewModel.submitEmailPasswordSignUp()
                
                await MainActor.run {
                    viewModel.isLoading = false
                    
                    if success {
                        print("Account creation successful!")
                        viewModel.moveToNextStep()
                    }
                    // Error message is already set by the signup method if it fails
                }
            } catch {
                await MainActor.run {
                    viewModel.isLoading = false
                    viewModel.errorMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    let viewModel = OnboardingViewModel()
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    viewModel.email = "user@example.com"
    viewModel.password = "password123"
    viewModel.confirmPassword = "password123"
    
    return AccountSetupView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environmentObject(dataController)
        .environment(\.colorScheme, .dark)
}