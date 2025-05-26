//
//  UserDetailsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import SwiftUI

struct UserDetailsView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @FocusState private var firstNameFocused: Bool
    @FocusState private var lastNameFocused: Bool
    
    var body: some View {
        ZStack {
            // Background color
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Minimal header with back button
                HStack {
                    Button(action: {
                        viewModel.moveToPreviousStepV2()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    // Header with larger text
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Tell us about\nyourself.")
                            .font(OPSStyle.Typography.largeTitle)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text("This helps your team identify you.")
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 24)
                        
                    // Name fields with larger font and no labels
                    VStack(spacing: 32) {
                        // First Name Field
                        VStack(spacing: 12) {
                            TextField("First name", text: $viewModel.firstName)
                                .font(OPSStyle.Typography.subtitle)
                                .foregroundColor(.white)
                                .textContentType(.givenName)
                                .disableAutocorrection(true)
                                .textFieldStyle(PlainTextFieldStyle())
                                .focused($firstNameFocused)
                            
                            Rectangle()
                                .fill(firstNameFocused || !viewModel.firstName.isEmpty ? OPSStyle.Colors.primaryAccent : Color.gray.opacity(0.3))
                                .frame(height: 1)
                                .animation(.easeInOut(duration: 0.2), value: firstNameFocused)
                        }
                        
                        // Last Name Field
                        VStack(spacing: 12) {
                            TextField("Last name", text: $viewModel.lastName)
                                .font(OPSStyle.Typography.subtitle)
                                .foregroundColor(.white)
                                .textContentType(.familyName)
                                .disableAutocorrection(true)
                                .textFieldStyle(PlainTextFieldStyle())
                                .focused($lastNameFocused)
                            
                            Rectangle()
                                .fill(lastNameFocused || !viewModel.lastName.isEmpty ? OPSStyle.Colors.primaryAccent : Color.gray.opacity(0.3))
                                .frame(height: 1)
                                .animation(.easeInOut(duration: 0.2), value: lastNameFocused)
                        }
                    }
                    .padding(.horizontal, 24)
                        
                        
                    // Error message
                    if !viewModel.errorMessage.isEmpty {
                        Text(viewModel.errorMessage)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    
                    Spacer()
                    
                    // Continue button - minimal style
                    VStack(spacing: 24) {
                        Button(action: {
                            let canProceed = !viewModel.firstName.isEmpty && !viewModel.lastName.isEmpty
                            if canProceed {
                                // Store user details
                                UserDefaults.standard.set(viewModel.firstName, forKey: "user_first_name")
                                UserDefaults.standard.set(viewModel.lastName, forKey: "user_last_name")
                                
                                // Move to next step
                                viewModel.moveToNextStepV2()
                            } else {
                                viewModel.errorMessage = "Please enter your first and last name"
                            }
                        }) {
                            Text("CONTINUE")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .fill((!viewModel.firstName.isEmpty && !viewModel.lastName.isEmpty) ? Color.white : Color.white.opacity(0.3))
                                )
                        }
                        .disabled(viewModel.firstName.isEmpty || viewModel.lastName.isEmpty)
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 40)
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