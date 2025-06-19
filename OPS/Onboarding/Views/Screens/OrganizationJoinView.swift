//
//  OrganizationJoinView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI

struct OrganizationJoinView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    // Animation states
    @State private var iconScale: CGFloat = 0
    @State private var messageOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 2
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 7 }
        return OnboardingStep.totalSteps(for: userType)
    }
    
    init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background - conditional theming
                (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.background : OPSStyle.Colors.background)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Navigation header with step indicator
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            viewModel.logoutAndReturnToLogin()
                        }) {
                            Text("Sign Out")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 24)
                    
                    // Step indicator bars
                    HStack(spacing: 4) {
                        ForEach(0..<totalSteps, id: \.self) { step in
                            Rectangle()
                                .fill(step < currentStepNumber ? 
                                    (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryAccent : OPSStyle.Colors.primaryAccent) : 
                                    (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText.opacity(0.4) : OPSStyle.Colors.secondaryText.opacity(0.4)))
                                .frame(height: 4)
                        }
                    }
                    .padding(.bottom, 16)
                    .padding(.horizontal, 24)
                    
                    // Fixed VStack instead of ScrollView since this content should fit on screen
                    VStack(spacing: 0) {
                        // Header
                        OnboardingHeaderView(
                            title: "Account Created.".uppercased(),
                            subtitle: "Now let's connect you with your organization.",
                            isLightTheme: viewModel.shouldUseLightTheme
                        )
                        .padding(.bottom, 20)
                        
                        
                        Spacer() // This will push content up and button to the bottom
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
                    
                    // Continue button
                    StandardContinueButton(
                        onTap: {
                            viewModel.moveToNextStep()
                        }
                    )
                    .padding(.bottom, 30)
                    .padding(.horizontal, 24)
                }
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Initial delay to let the view appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeIn(duration: 0.5)) {
                contentOpacity = 1.0
            }
            
            // Animate icon with spring effect
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.3)) {
                iconScale = 1.0
            }
            
            // Fade in message after icon appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.8)) {
                    messageOpacity = 1.0
                }
            }
        }
    }
}

// MARK: - Helper Components

struct FeatureItem: View {
    var text: String
    
    var body: some View {
        HStack(spacing: 10) {
            // Checkmark indicator
            Image(systemName: "checkmark.circle.fill")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            
            // Feature text
            Text(text)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OnboardingStepIndicator: View {
    var currentStep: OnboardingStep
    var text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Preview
#Preview("Organization Join View") {
    let viewModel = OnboardingViewModel()
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    viewModel.email = "user@example.com"
    
    return OrganizationJoinView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environmentObject(dataController)
        .environment(\.colorScheme, .dark)
}

#Preview("Organization Join View - Consolidated") {
    let viewModel = OnboardingViewModel()
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    viewModel.email = "user@example.com"
    
    return OrganizationJoinView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environmentObject(dataController)
        .environment(\.colorScheme, .dark)
}
