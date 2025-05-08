//
//  OrganizationJoinView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI

struct OrganizationJoinView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var isInConsolidatedFlow: Bool
    
    // Animation states
    @State private var iconScale: CGFloat = 0
    @State private var messageOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    
    init(viewModel: OnboardingViewModel, isInConsolidatedFlow: Bool = false) {
        self.viewModel = viewModel
        self._isInConsolidatedFlow = State(initialValue: isInConsolidatedFlow)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Progress indicator for consolidated flow
                    if isInConsolidatedFlow {
                        OnboardingStepIndicator(
                            currentStep: .accountSetup,
                            text: OnboardingStepV2.accountSetup.stepIndicator
                        )
                        .padding(.top, 20)
                        .padding(.bottom, 10)
                    }
                    
                    ScrollView {
                        VStack(spacing: 0) {
                            // Header
                            OnboardingHeaderView(
                                title: "Account Created Successfully",
                                subtitle: "Now let's connect you with your organization."
                            )
                            .padding(.bottom, 20)
                            
                            // Success icon and message
                            VStack(alignment: .leading, spacing: 40) {
                                // Check icon with circle in modern style
                                ZStack {
                                    // Outer circle
                                    Circle()
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        .frame(width: 80, height: 80)
                                    
                                    // Inner circle with accent color
                                    Circle()
                                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.15))
                                        .frame(width: 76, height: 76)
                                    
                                    // Icon
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                        .scaleEffect(iconScale)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 20)
                                
                                // Information message
                                VStack(alignment: .leading, spacing: 24) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Connect with your team")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(.white)
                                        
                                        Text("In the next steps, you'll connect to your organization's projects and team members.")
                                            .font(.system(size: 16))
                                            .foregroundColor(Color.gray)
                                            .lineSpacing(4)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    
                                    // Benefits of connecting
                                    VStack(alignment: .leading, spacing: 12) {
                                        FeatureItem(text: "Access to your organization's projects")
                                        FeatureItem(text: "Coordinate with your team members")
                                        FeatureItem(text: "Share updates and site photos")
                                    }
                                }
                                .opacity(messageOpacity)
                            }
                            .opacity(contentOpacity)
                            .frame(height: geometry.size.height * 0.5)
                            .frame(maxWidth: .infinity)
                            
                            Spacer(minLength: geometry.size.height * 0.1)
                        }
                        .frame(minHeight: geometry.size.height - 100)
                    }
                    
                    // Navigation buttons
                    OnboardingNavigationButtons(
                        primaryText: "CONTINUE",
                        onPrimaryTapped: {
                            print("OrganizationJoinView: Continue button tapped")
                            if isInConsolidatedFlow {
                                viewModel.moveToNextStepV2()
                            } else {
                                viewModel.moveToNextStep()
                            }
                        }
                    )
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 24)
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
                .font(.system(size: 16))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            
            // Feature text
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OnboardingStepIndicator: View {
    var currentStep: OnboardingStepV2
    var text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Preview
#Preview("Organization Join View") {
    let viewModel = OnboardingViewModel()
    viewModel.email = "user@example.com"
    
    return OrganizationJoinView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}

#Preview("Organization Join View - Consolidated") {
    let viewModel = OnboardingViewModel()
    viewModel.email = "user@example.com"
    
    return OrganizationJoinView(viewModel: viewModel, isInConsolidatedFlow: true)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}
