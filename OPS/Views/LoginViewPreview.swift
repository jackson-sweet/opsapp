//
//  LoginViewPreview.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI

struct LoginViewPreview: View {
    // UI states to control preview
    @State private var showLoginMode = false
    @State private var isLoggingIn = false
    @State private var showError = false
    @State private var showOnboarding = false
    @State private var username = "demo"
    @State private var password = "password"
    @State private var useConsolidatedFlow = true
    
    var body: some View {
        ZStack {
            // Background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Preview controls panel
            VStack {
                // Title
                Text("LoginView Preview Controls")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top, 16)
                
                // Divider line
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 1)
                    .padding(.vertical, 8)
                
                // Controls grid
                VStack(spacing: 16) {
                    // Initial interface toggles
                    Toggle("Show Login Mode", isOn: $showLoginMode)
                        .foregroundColor(.white)
                    
                    Toggle("Show Onboarding", isOn: $showOnboarding)
                        .foregroundColor(.white)
                    
                    Divider()
                    
                    // Loading states
                    Toggle("Is Logging In", isOn: $isLoggingIn)
                        .foregroundColor(.white)
                        .disabled(!showLoginMode)
                    
                    Toggle("Show Error", isOn: $showError)
                        .foregroundColor(.white)
                        .disabled(!showLoginMode)
                    
                    Divider()
                    
                    // Reset button
                    Button("Reset Preview") {
                        withAnimation {
                            showLoginMode = false
                            isLoggingIn = false
                            showError = false
                            showOnboarding = false
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding(16)
                .background(Color.black.opacity(0.6))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                
                Spacer()
            }
            .frame(width: 240)
            .background(Color.black.opacity(0.8))
            .offset(x: -300)
            
            // Login view with mocked values
            LoginViewMock(
                showLoginMode: showLoginMode,
                isLoggingIn: isLoggingIn,
                showError: showError,
                showOnboarding: showOnboarding
            )
            .offset(x: 120)
        }
        .environmentObject(DataController())
        .environment(\.colorScheme, .dark)
    }
}

// Mock version of LoginView for preview
struct LoginViewMock: View {
    // States
    var showLoginMode: Bool
    var isLoggingIn: Bool
    var showError: Bool
    var showOnboarding: Bool
    
    @State private var username = "demo"
    @State private var password = "password"
    @State private var pageScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            // Main content
            VStack(spacing: 24) {
                Spacer()
                
                // Logo and app name
                VStack(spacing: OPSStyle.Layout.spacing4) {
                    Image("LogoWhite")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                    
                    Text("OPS")
                        .font(OPSStyle.Typography.largeTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.bottom, 8)
                    
                    Text("Job Site Management")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.bottom, 40)
                }
                
                // Login/Signup Options
                if !showLoginMode {
                    // Initial options (Sign In or Sign Up)
                    VStack(spacing: 16) {
                        // Sign In button
                        Button(action: {
                            // No action in preview
                        }) {
                            Text("SIGN IN")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(OPSStyle.Colors.primaryAccent)
                                .cornerRadius(OPSStyle.Layout.buttonRadius)
                        }
                        
                        // Sign Up button
                        Button(action: {
                            // No action in preview
                        }) {
                            Text("CREATE ACCOUNT")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.clear)
                                .cornerRadius(OPSStyle.Layout.buttonRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 40)
                } else {
                    // Login form (once Sign In is selected)
                    VStack(spacing: 24) {
                        // Username field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("USERNAME")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            TextField("", text: $username)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding()
                                .background(OPSStyle.Colors.cardBackground)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.primaryAccent.opacity(0.5), lineWidth: 1)
                                )
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        
                        // Password field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PASSWORD")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            SecureField("", text: $password)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding()
                                .background(OPSStyle.Colors.cardBackground)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.primaryAccent.opacity(0.5), lineWidth: 1)
                                )
                        }
                        
                        // Login button
                        Button(action: {
                            // No action in preview
                        }) {
                            HStack {
                                if isLoggingIn {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                                        .padding(.trailing, 8)
                                }
                                
                                Text(isLoggingIn ? "SIGNING IN..." : "SIGN IN")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(username.isEmpty || password.isEmpty || isLoggingIn ? 
                                       OPSStyle.Colors.primaryAccent.opacity(0.4) : 
                                       OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                        }
                        .disabled(isLoggingIn || username.isEmpty || password.isEmpty)
                        .padding(.top, 16)
                        
                        // Cancel button
                        Button(action: {
                            // No action in preview
                        }) {
                            Text("CANCEL")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 40)
                }
                
                Spacer()
                
                // Version info
                Text("v1.0.0")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                    .padding(.bottom, 20)
            }
            .scaleEffect(pageScale)
            
            // Error alert
            if showError {
                ZStack {
                    Color.black.opacity(0.5)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 16) {
                        Text("Sign In Failed")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("Invalid username or password")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        Button("OK") {
                            // No action in preview
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(OPSStyle.Colors.primaryAccent)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .padding(24)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .padding(30)
                }
            }
            
            // Onboarding placeholder
            if showOnboarding {
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 24) {
                        Text("Onboarding Flow")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent)
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                            )
                        
                        Text("Welcome to OPS")
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        Text("This is a placeholder for the onboarding flow. The actual flow has multiple steps.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 32)
                    }
                    .padding(40)
                }
            }
        }
    }
}

// MARK: - Preview
#Preview("LoginView Preview") {
    LoginViewPreview()
        .environmentObject(DataController())
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}