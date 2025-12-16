//
//  CompanyCodeInputView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-27.
//

import SwiftUI
import Combine
import SwiftData
import Foundation

struct CompanyCodeInputView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var showWelcomePhase = false
    @State private var welcomeOpacity = 0.0
    
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 4
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 7 }
        return OnboardingStep.totalSteps(for: userType)
    }
    
    // Color scheme based on user type (light for employees)
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
                // Navigation header
                HStack {
                    Button(action: {
                        viewModel.moveToPreviousStep()
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
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Rectangle()
                            .fill(step < currentStepNumber ?
                                (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText) :
                                (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText.opacity(0.3) : OPSStyle.Colors.secondaryText.opacity(0.3)))
                            .frame(height: 2)
                    }
                }
                .padding(.top, 16)
                
                Spacer()

                // Main content
                if showWelcomePhase {
                    // Welcome phase after successful join
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 60))
                            .foregroundColor(OPSStyle.Colors.successStatus)

                        Text("WELCOME TO")
                            .font(OPSStyle.Typography.largeTitle.weight(.bold))
                            .foregroundColor(primaryTextColor)

                        Text(viewModel.companyName.uppercased())
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(secondaryTextColor)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(welcomeOpacity)
                } else {
                    // Input form
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ENTER COMPANY")
                                .font(OPSStyle.Typography.largeTitle.weight(.bold))
                                .foregroundColor(primaryTextColor)
                            Text("CODE")
                                .font(OPSStyle.Typography.largeTitle.weight(.bold))
                                .foregroundColor(primaryTextColor)
                        }
                        .padding(.bottom, 8)

                        Text("Your company code connects your account to your organization.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(secondaryTextColor)

                        // Company code input
                        VStack(spacing: 12) {
                            ZStack(alignment: .leading) {
                                if viewModel.companyCode.isEmpty {
                                    Text("Company code")
                                        .font(OPSStyle.Typography.subtitle)
                                        .foregroundColor(secondaryTextColor.opacity(0.6))
                                }

                                TextField("", text: $viewModel.companyCode)
                                    .font(OPSStyle.Typography.subtitle)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .foregroundColor(primaryTextColor)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .onChange(of: viewModel.companyCode) { _, _ in
                                        viewModel.errorMessage = ""
                                    }
                            }

                            Rectangle()
                                .fill(!viewModel.companyCode.isEmpty ? primaryTextColor : secondaryTextColor.opacity(0.3))
                                .frame(height: 1)
                        }

                        // Code explanation
                        Text("Obtain your company code from your manager or organization administrator.")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(secondaryTextColor)

                        // Error message
                        if !viewModel.errorMessage.isEmpty {
                            Text(viewModel.errorMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                    }
                }

                Spacer()

                // Bottom button section
                VStack(spacing: 16) {
                    if showWelcomePhase {
                        StandardContinueButton(
                            onTap: {
                                viewModel.moveToNextStep()
                            }
                        )
                    } else {
                        StandardContinueButton(
                            isDisabled: viewModel.companyCode.isEmpty,
                            isLoading: viewModel.isLoading,
                            onTap: {
                                joinCompany()
                            }
                        )

                        Button(action: {
                            viewModel.errorMessage = "Contact your organization administrator for your company code."
                        }) {
                            Text("Need Help?")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(secondaryTextColor)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .padding(40)
        }
        .dismissKeyboardOnTap()
    }
    
    private func joinCompany() {
        // Check required fields
        guard !viewModel.companyCode.isEmpty else {
            viewModel.errorMessage = "Please enter your company code"
            return
        }
        
        // Check for user ID instead of email/password
        let userId = viewModel.userId.isEmpty ? UserDefaults.standard.string(forKey: "user_id") ?? "" : viewModel.userId
        guard !userId.isEmpty else {
            viewModel.errorMessage = "User ID is missing. Please restart the onboarding process."
            return
        }
        
        
        // Set loading state
        viewModel.isLoading = true
        viewModel.errorMessage = ""
        
        // Call the API to join company
        Task {
            let success = await viewModel.joinCompany()
            
            await MainActor.run {
                viewModel.isLoading = false
                
                if success {
                    // Store the fact that the user has successfully joined a company
                    UserDefaults.standard.set(true, forKey: "has_joined_company")
                    
                    // Show welcome phase
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showWelcomePhase = true
                    }
                    
                    // Animate welcome message
                    withAnimation(.easeIn(duration: 0.5).delay(0.2)) {
                        welcomeOpacity = 1.0
                    }
                } else {
                    // Error message is already set by the joinCompany method
                    
                    // Make sure error message is user-friendly
                    if viewModel.errorMessage.isEmpty {
                        viewModel.errorMessage = "Invalid company code. Please check and try again."
                    } else if viewModel.errorMessage.lowercased().contains("password") {
                        // Handle password-related errors
                        viewModel.errorMessage = "Authentication error. Please restart the onboarding process."
                    }
                    
                    // Ensure user cannot skip company joining
                    UserDefaults.standard.set(false, forKey: "has_joined_company")
                }
            }
        }
    }
}

// MARK: - Preview
#Preview("Company Code Input") {
    let viewModel = OnboardingViewModel()
    viewModel.email = "user@example.com"
    viewModel.password = "password123"
    viewModel.firstName = "John"
    viewModel.lastName = "Doe"
    viewModel.phoneNumber = "5551234567"
    viewModel.selectedUserType = .employee
    
    return CompanyCodeInputView(viewModel: viewModel)
        .environment(\.colorScheme, .dark)
}

#Preview("Company Code Input - Light") {
    let viewModel = OnboardingViewModel()
    viewModel.email = "user@example.com"
    viewModel.password = "password123"
    viewModel.firstName = "John"
    viewModel.lastName = "Doe"
    viewModel.phoneNumber = "5551234567"
    viewModel.selectedUserType = .employee
    viewModel.companyCode = "OPS"
    
    return CompanyCodeInputView(viewModel: viewModel)
        .environment(\.colorScheme, .light)
}
