//
//  PhoneNumberView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI

struct PhoneNumberView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                // Header
                OnboardingHeaderView(
                    title: "Start with your phone number.",
                    subtitle: "Your number will be used in your company's directory, and won't be shared with anyone outside your organization."
                )
                
                // Phone field
                VStack(alignment: .leading, spacing: 8) {
                    InputFieldLabel(label: "PHONE NUMBER")
                    
                    HStack(spacing: 12) {
                        // Country code (static +1 for US)
                        Text("+1")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .frame(width: 40)
                        
                        // Phone number input
                        TextField("Phone number", text: $viewModel.phoneNumber)
                            .font(.system(size: 16))
                            .keyboardType(.phonePad)
                            .onboardingTextFieldStyle()
                    }
                }
                
                // Error message
                ErrorMessageView(message: viewModel.errorMessage)
                
                Spacer()
                
                // Terms text
                Text("By continuing, you agree to our Terms and Privacy Policy")
                    .font(.system(size: 12))
                    .foregroundColor(Color.gray)
                    .multilineTextAlignment(.center)
                
                // Buttons
                OnboardingNavigationButtons(
                    primaryText: "CONTINUE",
                    secondaryText: "BACK",
                    isPrimaryDisabled: !viewModel.isPhoneValid,
                    isLoading: viewModel.isLoading,
                    onPrimaryTapped: {
                        print("PhoneNumberView: Continue button tapped with phone: \(viewModel.phoneNumber)")
                        // Format and save phone number
                        viewModel.formatPhoneNumber()
                        // Continue to next step
                        viewModel.moveToNextStep()
                    },
                    onSecondaryTapped: {
                        print("PhoneNumberView: Back button tapped")
                        // Go back to previous step (userInfo)
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

// MARK: - Preview
#Preview("Phone Number Screen") {
    let viewModel = OnboardingViewModel()
    viewModel.email = "user@example.com"
    viewModel.password = "password123"
    viewModel.firstName = "John"
    viewModel.lastName = "Doe"
    viewModel.phoneNumber = "555-123-4567"
    
    return PhoneNumberView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}