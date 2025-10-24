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
            Color(OPSStyle.Colors.background)
            .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                // Logo in top corner
                HStack {
                    HStack(alignment: .bottom){
                        Image("LogoWhite")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                        Text("OPS")
                            .font(OPSStyle.Typography.title)
                            .frame(height: 24)
                    }
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
                        
                        // Dismiss onboarding and return to login page
                        NotificationCenter.default.post(name: Notification.Name("DismissOnboarding"), object: nil)
                    }) {
                        Text("Sign In")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .opacity(buttonOpacity)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, 40)
                
                // Main content with spacing
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                        .frame(height: 40)
                    
                    // Headline messaging
                    VStack(alignment: .leading, spacing: 24) {
                
                        // Key benefits
                        VStack(alignment: .leading, spacing: 16) {
                            Spacer()
                            BenefitRow(
                                icon: "bolt.shield",
                                text: "SCHEDULE, JOB BOARD AND ASSIGNMENTS".uppercased()
                            )
                            
                            BenefitRow(
                                icon: "person.2",
                                text: "JOB DETAILS, LOCATION AND CONTACT INFO".uppercased()
                            )
                            
                            BenefitRow(
                                icon: "iphone.motion",
                                text: "ALL IN YOUR CREW'S POCKETS.".uppercased()
                            )
                            Spacer()
                        }
                    }
                    .opacity(textOpacity)
                    
                    Spacer()
                    
                    Text("OPS.")
                        .font(OPSStyle.Typography.cardTitle)
                    // Builder message
                    Text("Built by trades, for trades.")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(Color.gray)
                        .padding(.bottom, 40)
                        .opacity(textOpacity)
                    
                    // Get Started Button
                    StandardContinueButton(
                        onTap: {
                            viewModel.moveToNextStep()
                        }
                    )
                    .opacity(buttonOpacity)
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
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
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    return WelcomeView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environmentObject(dataController)
        .environment(\.colorScheme, .dark)
}
