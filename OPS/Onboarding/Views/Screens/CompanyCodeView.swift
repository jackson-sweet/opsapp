//
//  CompanyCodeView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI
import Combine

struct CompanyCodeView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    // Determine if we're in V2 flow
    private var isInV2Flow: Bool {
        return AppConfiguration.UX.useConsolidatedOnboardingFlow
    }
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Navigation with back button for V2 flow
                if isInV2Flow {
                    HStack {
                        Button(action: {
                            viewModel.moveToPreviousStepV2()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Back")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        
                        Spacer()
                        
                        Text("Step 3 of 6")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.gray)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    
                    // Step indicator bars
                    HStack(spacing: 4) {
                        ForEach(0..<6) { step in
                            Rectangle()
                                .fill(step <= 2 ? OPSStyle.Colors.primaryAccent : Color.gray.opacity(0.4))
                                .frame(height: 4)
                        }
                    }
                    .padding(.bottom, 16)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                }
                
                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter company")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("code.")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.bottom, 12)
                        
                        Text("Your company code connects your account to your organization.")
                            .font(.system(size: 16))
                            .foregroundColor(Color.gray)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
                    
                    // Company code input
                    VStack(alignment: .leading, spacing: 8) {
                        InputFieldLabel(label: "COMPANY CODE")
                        
                        TextField("Enter code", text: $viewModel.companyCode)
                            .font(.system(size: 16))
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                            .onboardingTextFieldStyle()
                            .transition(.opacity)
                            .animation(.easeInOut, value: viewModel.companyCode)
                    }
                    
                    // Code explanation with icon
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 14))
                        
                        Text("Company codes are typically provided by your manager or in your welcome email.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 8)
                    
                    // Error message
                    ErrorMessageView(message: viewModel.errorMessage)
                    
                    Spacer()
                    
                    // Buttons
                    OnboardingNavigationButtons(
                        primaryText: "Continue",
                        secondaryText: "Need Help?",
                        isLoading: viewModel.isLoading,
                        onPrimaryTapped: {
                            print("CompanyCodeView: Continue button tapped with code: \(viewModel.companyCode)")
                            
                            // Set loading state
                            viewModel.isLoading = true
                            viewModel.errorMessage = ""
                            
                            // Call the API to join company with all user info
                            Task {
                                // Since we updated joinCompany() to handle errors internally,
                                // we don't need try/catch here anymore
                                let success = await viewModel.joinCompany()
                                
                                await MainActor.run {
                                    viewModel.isLoading = false
                                    
                                    if success {
                                        print("Company join successful! Company: \(viewModel.companyName)")
                                        // Store the fact that the user has successfully joined a company
                                        UserDefaults.standard.set(true, forKey: "has_joined_company")
                                        // Continue to next step based on flow
                                        if isInV2Flow {
                                            viewModel.moveToNextStepV2()
                                        } else {
                                            viewModel.moveToNextStep()
                                        }
                                    } else {
                                        // Error message is already set by the joinCompany method
                                        print("Company join failed: \(viewModel.errorMessage)")
                                        
                                        // Make sure error message is user-friendly
                                        if viewModel.errorMessage.isEmpty {
                                            viewModel.errorMessage = "Invalid company code. Please check and try again."
                                        }
                                        
                                        // Ensure user cannot skip company joining
                                        UserDefaults.standard.set(false, forKey: "has_joined_company")
                                    }
                                }
                            }
                        },
                        onSecondaryTapped: {
                            print("CompanyCodeView: Can't skip company code button tapped")
                            
                            // Show alert that company code is required
                            viewModel.errorMessage = "A valid company code is required to use the OPS app. Please contact your organization administrator for your code."
                            
                            // Ensure user cannot skip company joining
                            UserDefaults.standard.set(false, forKey: "has_joined_company")
                        }
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 30)
                
                // Loading overlay
                if viewModel.isLoading {
                    LoadingView(message: "Verifying...")
                }
            }
        }
    }
}

// MARK: - Preview
#Preview("Company Code Screen") {
    let viewModel = OnboardingViewModel()
    viewModel.email = "user@example.com"
    viewModel.password = "password123"
    viewModel.firstName = "John"
    viewModel.lastName = "Doe"
    viewModel.phoneNumber = "5551234567"
    viewModel.companyCode = "DEMO123"
    
    return CompanyCodeView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}
