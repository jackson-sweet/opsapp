//
//  WelcomeView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI
import Combine

struct WelcomeView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.8
    
    var body: some View {
        ZStack {
            // Background with subtle gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(red: 0.05, green: 0.05, blue: 0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading, spacing: 0) {
                // Logo in top corner
                HStack {
                    Image("LogoWhite")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .scaleEffect(logoScale)
                    
                    Spacer()
                    
                    Button(action: {
                        // Clear all user data before returning to login
                        let userDefaults = UserDefaults.standard
                        userDefaults.removeObject(forKey: "resume_onboarding")
                        userDefaults.removeObject(forKey: "is_authenticated")
                        userDefaults.removeObject(forKey: "user_id")
                        userDefaults.removeObject(forKey: "user_email")
                        userDefaults.removeObject(forKey: "user_password")
                        userDefaults.removeObject(forKey: "user_first_name")
                        userDefaults.removeObject(forKey: "user_last_name")
                        userDefaults.removeObject(forKey: "user_phone_number")
                        userDefaults.removeObject(forKey: "company_code")
                        print("WelcomeView: Cleared all user data before dismissing")
                        
                        // Dismiss onboarding and return to login page
                        NotificationCenter.default.post(name: Notification.Name("DismissOnboarding"), object: nil)
                    }) {
                        Text("Sign In")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .opacity(buttonOpacity)
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
                
                // Main content with spacing
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                        .frame(height: 40)
                    
                    // Headline messaging
                    VStack(alignment: .leading, spacing: 24) {
                        // Bold headline
                        Text("Your jobsite streamlined.")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                        
                        // Key benefits
                        VStack(alignment: .leading, spacing: 16) {
                            Spacer()
                            BenefitRow(
                                icon: "list.clipboard",
                                text: "Track projects from estimate to completion"
                            )
                            
                            BenefitRow(
                                icon: "person.2",
                                text: "Coordinate your entire crew in one place"
                            )
                            
                            BenefitRow(
                                icon: "doc.text.image",
                                text: "Document jobsite conditions with photos"
                            )
                            Spacer()
                        }
                    }
                    .opacity(textOpacity)
                    
                    Spacer()
                    
                    Text("OPS.")
                    // Builder message
                    Text("Built by trades, for trades.")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(Color.gray)
                        .padding(.bottom, 40)
                        .opacity(textOpacity)
                    
                    // Get Started Button - modern style
                    Button(action: {
                        print("WelcomeView: Get Started button tapped")
                        
                        // Use the appropriate method for the flow
                        if AppConfiguration.UX.useConsolidatedOnboardingFlow {
                            viewModel.moveToNextStepV2()
                            print("WelcomeView: Moving to next V2 step: \(viewModel.currentStepV2.title)")
                        } else {
                            viewModel.moveToNextStep()
                            print("WelcomeView: Moving to next step: \(viewModel.currentStep.title)")
                        }
                    }) {
                        HStack {
                            Text("Continue")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                            
                            Image(systemName: "arrow.right")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(.black)
                        }
                        .frame(height: 52)
                        .background(Color.white)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .padding(.horizontal, 24)
                    }
                    .opacity(buttonOpacity)
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 24)
            }
        }
        .onAppear {
            animateContent()
        }
    }
    
    private func animateContent() {
        // Logo animation
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
            logoScale = 1.0
        }
        
        // Text animation
        withAnimation(.easeIn(duration: 0.8).delay(0.3)) {
            textOpacity = 1.0
        }
        
        // Button animation
        withAnimation(.easeIn(duration: 0.6).delay(0.7)) {
            buttonOpacity = 1.0
        }
    }
}

// Modern benefit row with icon
struct BenefitRow: View {
    var icon: String
    var text: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: 30)
            
            Text(text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Helper view for info text items
struct InfoText: View {
    var text: String
    
    var body: some View {
        Text(text)
            .font(OPSStyle.Typography.body)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview
#Preview("Welcome Screen") {
    let viewModel = OnboardingViewModel()
    
    return WelcomeView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}
