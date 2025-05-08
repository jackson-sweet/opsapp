//
//  UserDetailsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import SwiftUI

struct UserDetailsView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Navigation header with step indicator
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
                    
                    Text("Step 3 of 7")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.gray)
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding(.horizontal, 24)
                
                // Step indicator bars
                HStack(spacing: 4) {
                    ForEach(0..<7) { step in
                        Rectangle()
                            .fill(step < 3 ? OPSStyle.Colors.primaryAccent : Color.gray.opacity(0.4))
                            .frame(height: 4)
                    }
                }
                .padding(.bottom, 16)
                .padding(.horizontal, 24)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tell us about")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("yourself.")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.bottom, 12)
                            
                            Text("This information helps your team identify you in the field and contact you about projects.")
                                .font(.system(size: 16))
                                .foregroundColor(Color.gray)
                                .lineSpacing(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 10)
                        
                        // First Name Field
                        VStack(alignment: .leading, spacing: 8) {
                            InputFieldLabel(label: "FIRST NAME")
                            
                            TextField("Your first name", text: $viewModel.firstName)
                                .font(.system(size: 16))
                                .textContentType(.givenName)
                                .disableAutocorrection(true)
                                .onboardingTextFieldStyle()
                                .transition(.opacity)
                                .animation(.easeInOut, value: viewModel.firstName)
                        }
                        
                        // Last Name Field
                        VStack(alignment: .leading, spacing: 8) {
                            InputFieldLabel(label: "LAST NAME")
                            
                            TextField("Your last name", text: $viewModel.lastName)
                                .font(.system(size: 16))
                                .textContentType(.familyName)
                                .disableAutocorrection(true)
                                .onboardingTextFieldStyle()
                                .transition(.opacity)
                                .animation(.easeInOut, value: viewModel.lastName)
                        }
                        
                        // Phone Number Field
                        VStack(alignment: .leading, spacing: 8) {
                            InputFieldLabel(label: "PHONE NUMBER")
                            
                            TextField("Your phone number", text: $viewModel.phoneNumber)
                                .font(.system(size: 16))
                                .textContentType(.telephoneNumber)
                                .keyboardType(.phonePad)
                                .disableAutocorrection(true)
                                .onboardingTextFieldStyle()
                                .transition(.opacity)
                                .animation(.easeInOut, value: viewModel.phoneNumber)
                                .onChange(of: viewModel.phoneNumber) { oldValue, newValue in
                                    viewModel.formatPhoneNumber()
                                }
                        }
                        
                        // Phone number hint
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.system(size: 14))
                            
                            Text("Your phone number will be used for team communications and site updates.")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.top, 8)
                        
                        // Error message
                        ErrorMessageView(message: viewModel.errorMessage)
                        
                        Spacer()
                        
                        // Navigation buttons
                        OnboardingNavigationButtons(
                            primaryText: "Continue",
                            isPrimaryDisabled: !viewModel.canProceedFromUserDetails,
                            onPrimaryTapped: {
                                print("UserDetailsView: Continue button tapped")
                                
                                if viewModel.canProceedFromUserDetails {
                                    // Store user details in UserDefaults for later use
                                    UserDefaults.standard.set(viewModel.firstName, forKey: "user_first_name")
                                    UserDefaults.standard.set(viewModel.lastName, forKey: "user_last_name")
                                    
                                    // Move to next step
                                    viewModel.moveToNextStepV2()
                                } else {
                                    // Show error if fields are not complete
                                    viewModel.errorMessage = "Please complete all fields to continue"
                                }
                            }
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                }
            }
        }
    }
}

#Preview {
    let viewModel = OnboardingViewModel()
    viewModel.firstName = "John"
    viewModel.lastName = "Doe"
    viewModel.phoneNumber = "5551234567"
    viewModel.isPhoneValid = true
    
    return UserDetailsView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}