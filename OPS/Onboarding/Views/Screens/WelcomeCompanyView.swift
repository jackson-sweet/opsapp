//
//  WelcomeCompanyView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-06.
//

import SwiftUI

struct WelcomeCompanyView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 40) {
                Spacer()
                
                // Logo/icon (placeholder)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                
                // Welcome message
                VStack(spacing: 12) {
                    Text("Welcome to the")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("\(viewModel.companyName) OPS Center")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("\(viewModel.firstName)!")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.top, 4)
                }
                
                Spacer()
                
                // Buttons
                OnboardingNavigationButtons(
                    primaryText: "CONTINUE",
                    secondaryText: "",
                    isPrimaryDisabled: false,
                    isLoading: viewModel.isLoading,
                    onPrimaryTapped: {
                        print("WelcomeCompanyView: Continue button tapped")
                        // Proceed to permissions
                        viewModel.moveToNextStep()
                    },
                    onSecondaryTapped: { }
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 30)
        }
    }
}

// MARK: - Preview
#Preview("Welcome Company Screen") {
    let viewModel = OnboardingViewModel()
    viewModel.email = "user@example.com"
    viewModel.password = "password123"
    viewModel.firstName = "John"
    viewModel.lastName = "Doe"
    viewModel.phoneNumber = "5551234567"
    viewModel.companyCode = "DEMO123"
    viewModel.companyName = "Demo Company, Inc."
    viewModel.isCompanyJoined = true
    
    return WelcomeCompanyView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}