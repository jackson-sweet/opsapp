//
//  UserInfoView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-06.
//

import SwiftUI

// Function to format phone number
func formatPhoneNumber(_ phoneNumber: String) -> String {
    // Filter out non-numeric characters
    let digits = phoneNumber.filter { $0.isNumber }
    
    // Format according to pattern (XXX) XXX-XXXX
    var formattedPhone = ""
    
    for (index, digit) in digits.prefix(10).enumerated() {
        if index == 0 {
            formattedPhone.append("(\(digit)")
        } else if index == 2 {
            formattedPhone.append("\(digit)) ")
        } else if index == 5 {
            formattedPhone.append("\(digit)-")
        } else {
            formattedPhone.append(String(digit))
        }
    }
    
    return formattedPhone
}

struct UserInfoView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var isInConsolidatedFlow: Bool = false
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Navigation bar for consolidated flow
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
                        
                        Text("Step 2 of 6")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(Color.gray)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    
                    // Step indicator bars
                    HStack(spacing: 4) {
                        ForEach(0..<6) { step in
                            Rectangle()
                                .fill(step <= 1 ? OPSStyle.Colors.primaryAccent : Color.gray.opacity(0.4))
                                .frame(height: 4)
                        }
                    }
                    .padding(.bottom, 16)
                }
                
                // Content
                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isInConsolidatedFlow ? "Your" : "Tell us your")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                        
                        Text(isInConsolidatedFlow ? "information." : "name.")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                            .padding(.bottom, 12)
                        
                        Text(isInConsolidatedFlow ? 
                            "Tell us who you are so your team can recognize you." : 
                            "This will be used for your profile in the OPS app.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(Color.gray)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
                    
                    // First name field
                    VStack(alignment: .leading, spacing: 8) {
                        InputFieldLabel(label: "FIRST NAME")
                        
                        TextField("First name", text: $viewModel.firstName)
                            .font(OPSStyle.Typography.body)
                            .keyboardType(.namePhonePad)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                            .textContentType(.oneTimeCode) // Prevents autofill
                            .onboardingTextFieldStyle()
                            .transition(.opacity)
                            .animation(.easeInOut, value: viewModel.firstName)
                    }
                    
                    // Last name field
                    VStack(alignment: .leading, spacing: 8) {
                        InputFieldLabel(label: "LAST NAME")
                        
                        TextField("Last name", text: $viewModel.lastName)
                            .font(OPSStyle.Typography.body)
                            .keyboardType(.namePhonePad)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                            .textContentType(.oneTimeCode) // Prevents autofill
                            .onboardingTextFieldStyle()
                            .transition(.opacity)
                            .animation(.easeInOut, value: viewModel.lastName)
                    }
                    
                    // Phone number field for consolidated flow
                    if isInConsolidatedFlow {
                        VStack(alignment: .leading, spacing: 8) {
                            InputFieldLabel(label: "PHONE NUMBER")
                            
                            TextField("(___) ___-____", text: $viewModel.phoneNumber)
                                .font(OPSStyle.Typography.body)
                                .keyboardType(.phonePad)
                                .textContentType(.oneTimeCode) // Prevents autofill
                                .onChange(of: viewModel.phoneNumber) { oldValue, newValue in
                                    // Only keep digits and format
                                    let digits = newValue.filter { $0.isNumber }
                                    if digits.count <= 10 {
                                        viewModel.phoneNumber = formatPhoneNumber(newValue)
                                    } else {
                                        viewModel.phoneNumber = oldValue
                                    }
                                }
                                .onboardingTextFieldStyle()
                                .transition(.opacity)
                                .animation(.easeInOut, value: viewModel.phoneNumber)
                        }
                        
                        // Phone validation indicator
                        if !viewModel.phoneNumber.isEmpty {
                            HStack {
                                Image(systemName: viewModel.isPhoneValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(viewModel.isPhoneValid ? Color("StatusSuccess") : Color("StatusError"))
                                
                                Text(viewModel.isPhoneValid ? "Valid phone number" : "Please enter full 10-digit number")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(viewModel.isPhoneValid ? Color("StatusSuccess") : Color("StatusError"))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                        }
                    }
                    
                    // Error message
                    ErrorMessageView(message: viewModel.errorMessage)
                    
                    Spacer()
                    
                    // Different button actions for consolidated flow
                    if isInConsolidatedFlow {
                        Button(action: {
                            if viewModel.canProceedFromUserDetails {
                                viewModel.moveToNextStepV2()
                            }
                        }) {
                            ZStack {
                                HStack {
                                    Text("Continue")
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(.black)
                                    
                                    Spacer()
                                    
                                    if viewModel.canProceedFromUserDetails {
                                        Image(systemName: "arrow.right")
                                            .font(OPSStyle.Typography.captionBold)
                                            .foregroundColor(.black)
                                            .padding(.trailing, 20)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .frame(height: 52)
                            .frame(maxWidth: .infinity)
                            .background(viewModel.canProceedFromUserDetails ? Color.white : Color.white.opacity(0.7))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        .disabled(!viewModel.canProceedFromUserDetails)
                    } else {
                        // Original flow buttons
                        OnboardingNavigationButtons(
                            primaryText: "Continue",
                            secondaryText: "Back",
                            isPrimaryDisabled: viewModel.firstName.isEmpty || viewModel.lastName.isEmpty,
                            isLoading: viewModel.isLoading,
                            onPrimaryTapped: {
                                print("UserInfoView: Continue button tapped")
                                // Proceed to the next step
                                viewModel.moveToNextStep()
                            },
                            onSecondaryTapped: {
                                print("UserInfoView: Back button tapped")
                                // Go back to password step
                                viewModel.moveToPreviousStep()
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, isInConsolidatedFlow ? 0 : 20)
                .padding(.bottom, 30)
            }
            .padding(.horizontal, isInConsolidatedFlow ? OPSStyle.Layout.spacing3 : 0)
        }
    }
}

// MARK: - Preview
#Preview("User Info Screen") {
    let viewModel = OnboardingViewModel()
    viewModel.email = "user@example.com"
    viewModel.password = "password123"
    viewModel.firstName = "John"
    viewModel.lastName = "Doe"
    
    return UserInfoView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}