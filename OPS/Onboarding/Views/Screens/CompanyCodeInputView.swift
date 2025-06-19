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
            backgroundColor.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Navigation header with step indicator
                HStack {
                    Button(action: {
                        viewModel.previousStep()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(OPSStyle.Typography.caption)
                            Text("Back")
                                .font(OPSStyle.Typography.body)
                        }
                        .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryAccent : OPSStyle.Colors.primaryAccent)
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
                .padding(.horizontal, 24)
                
                // Step indicator bars
                HStack(spacing: 4) {
                    ForEach(0..<totalSteps) { step in
                        Rectangle()
                            .fill(step < currentStepNumber ? 
                                (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryAccent : OPSStyle.Colors.primaryAccent) : 
                                (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText.opacity(0.4) : OPSStyle.Colors.secondaryText.opacity(0.4)))
                            .frame(height: 4)
                    }
                }
                .padding(.bottom, 16)
                .padding(.horizontal, 24)
                
                // Main content - top-justified
                VStack(spacing: 0) {
                    if showWelcomePhase {
                        // Welcome phase after successful join
                        VStack(spacing: 24) {
                            VStack(spacing: 16) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 80))
                                    .foregroundColor(OPSStyle.Colors.successStatus)
                                
                                Text("WELCOME TO")
                                    .font(OPSStyle.Typography.title)
                                    .foregroundColor(primaryTextColor)
                                
                                Text("[ \(viewModel.companyName.uppercased()) ]")
                                    .font(OPSStyle.Typography.subtitle)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    .multilineTextAlignment(.center)
                                
                                Text("You've successfully joined your organization.")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(secondaryTextColor)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 8)
                            }
                            .opacity(welcomeOpacity)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 80) // Add padding for welcome phase
                    } else {
                        // Input form
                        VStack(spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ENTER COMPANY")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(primaryTextColor)
                            
                            Text("CODE")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(primaryTextColor)
                                .padding(.bottom, 12)
                            
                            Text("Your company code connects your account to your organization.")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(secondaryTextColor)
                                .lineSpacing(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 10)
                        
                        // Company code input with larger text
                        VStack(spacing: 12) {
                            ZStack(alignment: .leading) {
                                // Custom placeholder with proper color
                                if viewModel.companyCode.isEmpty {
                                    Text("Company code")
                                        .font(OPSStyle.Typography.subtitle)
                                        .foregroundColor(secondaryTextColor)
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
                                .fill(!viewModel.companyCode.isEmpty ? 
                                    (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryAccent : OPSStyle.Colors.primaryAccent) : 
                                    secondaryTextColor.opacity(0.3))
                                .frame(height: 1)
                                .animation(.easeInOut(duration: 0.2), value: viewModel.companyCode.isEmpty)
                        }
                        
                        // Code explanation with icon
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(primaryTextColor.opacity(0.7))
                                .font(OPSStyle.Typography.caption)
                            
                            Text("Obtain your company code from your manager or organization administrator.")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(primaryTextColor.opacity(0.6))
                        }
                        .padding(.top, 8)
                        
                        // Error message
                        if !viewModel.errorMessage.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(Color("StatusError"))
                                    .font(OPSStyle.Typography.caption)
                                
                                Text(viewModel.errorMessage)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(Color("StatusError"))
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color("StatusError").opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color("StatusError").opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 40) // Add consistent top padding
                    } // End of else block
                    
                    Spacer()
                }
                
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
                            // Show help or contact info
                            viewModel.errorMessage = "Contact your organization administrator for your company code."
                        }) {
                            Text("Need Help?")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(secondaryTextColor)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 34)
            }
        }
        .dismissKeyboardOnTap()
    }
    
    private func joinCompany() {
        // Check required fields
        guard !viewModel.companyCode.isEmpty else {
            viewModel.errorMessage = "Please enter your company code"
            return
        }
        
        guard !viewModel.email.isEmpty else {
            viewModel.errorMessage = "Email is missing. Please restart the onboarding process."
            return
        }
        
        guard !viewModel.password.isEmpty else {
            // Try to retrieve password from UserDefaults
            if let savedPassword = UserDefaults.standard.string(forKey: "user_password"), !savedPassword.isEmpty {
                viewModel.password = savedPassword
            } else {
                viewModel.errorMessage = "Password is missing. Please restart the onboarding process."
                return
            }
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
                    print("Company join successful! Company: \(viewModel.companyName)")
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
                    print("Company join failed: \(viewModel.errorMessage)")
                    
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
