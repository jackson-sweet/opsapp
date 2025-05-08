//
//  AccountCreatedView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI

struct AccountCreatedView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    // Animation states
    @State private var checkmarkScale: CGFloat = 0
    @State private var messageOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // Background
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                // Header
                OnboardingHeaderView(
                    title: "Account Created",
                    subtitle: "Your OPS account has been successfully created. Let's set up your profile."
                )
                .padding(.top, 20)
                
                Spacer()
                
                // Success checkmark and message
                VStack(spacing: 30) {
                    // Checkmark in circle
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            .frame(width: 120, height: 120)
                        
                        Circle()
                            .fill(Color.black)
                            .frame(width: 116, height: 116)
                            .overlay(
                                Circle()
                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                            )
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 50, weight: .bold))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .scaleEffect(checkmarkScale)
                    }
                    
                    // Confirmation text
                    VStack(spacing: 12) {
                        Text("Welcome to OPS")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("Your account has been verified and is ready to use.")
                            .font(.system(size: 16))
                            .foregroundColor(Color.gray)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(messageOpacity)
                }
                .opacity(contentOpacity)
                
                Spacer()
                
                // Continue button
                OnboardingNavigationButtons(
                    primaryText: "CONTINUE",
                    secondaryText: "BACK",
                    onPrimaryTapped: {
                        print("AccountCreatedView: Continue button tapped")
                        viewModel.moveToNextStep()
                    },
                    onSecondaryTapped: {
                        print("AccountCreatedView: Back button tapped")
                        viewModel.moveToPreviousStep()
                    }
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
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
            
            // Animate checkmark with spring effect
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.3)) {
                checkmarkScale = 1.0
            }
            
            // Fade in message after checkmark appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.8)) {
                    messageOpacity = 1.0
                }
            }
        }
    }
}

// MARK: - Preview
#Preview("Account Created") {
    let viewModel = OnboardingViewModel()
    viewModel.email = "user@example.com"
    
    return AccountCreatedView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}