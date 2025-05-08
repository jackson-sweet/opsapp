//
//  LoginView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//

import SwiftUI
import Combine

struct LoginView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.useConsolidatedOnboarding) private var useConsolidatedOnboarding
    
    // Login states
    @State private var username = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showOnboarding = false
    @State private var resumeFromCompanyStep = false
    
    // UI states
    @State private var showLoginMode = false
    @State private var pageScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            // Main content
            VStack(spacing: 24) {
                
                Spacer()
                
                // Header content with inspirational message
                
                // Logo (smaller, just as an element)
                if !showLoginMode {
                    
                    HStack {
                        
                        Image("LogoWhite")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                            .padding(.bottom, 8)
                        Spacer()
                        
                    }.padding(.leading, 32)
                    
                    Spacer()
                    
                    // Bold message inspired by your inspiration designs
                    VStack(alignment: .leading, spacing: 32) {
                        
                        Text("OPS.")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("BUILT BY TRADES, FOR TRADES.")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("The job managment app that gets out of the way.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.top, 4)
                        
                        Spacer()
                            .frame(height: 40)
                        
                    }.padding(.leading, 32)
                    
                    // Login/Signup Options
                    
                    // Initial options (Sign In or Sign Up)
                    VStack(spacing: 16) {
                        Spacer()
                        // Primary action - Sign Up button
                        Button(action: {
                            // Show onboarding directly
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showOnboarding = true
                            }
                        }) {
                            Text("GET SIGNED UP")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.white)
                                .cornerRadius(26)
                                .overlay(
                                    HStack {
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                            .foregroundColor(.black)
                                            .font(.system(size: 15, weight: .semibold))
                                            .padding(.trailing, 20)
                                    }
                                )
                        }
                        .padding(.bottom, 4)
                        
                        // Secondary action - Log In button
                        Button(action: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                showLoginMode = true
                                pageScale = 0.98
                                
                                // Return to normal scale after small delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                        pageScale = 1.0
                                    }
                                }
                            }
                           
                        }) {
                            HStack {
                                Text("LOG INTO ACCOUNT")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.clear)
                        }
                    }
                    .padding(.horizontal, 40)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    // Login form (once Sign In is selected)
                    VStack(alignment: .leading, spacing: 32) {
                        // Back button
                        Button(action: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                showLoginMode = false
                                pageScale = 0.98
                                
                                // Return to normal scale after small delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                        pageScale = 1.0
                                    }
                                }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundColor(.white)
                        }
                        .padding(.bottom, 8)
                        
                        // Form title
                        Text("Enter your credentials")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.bottom, 24)
                        
                        // Username field with floating label design
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Username or email")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.gray)
                            
                            TextField("", text: $username)
                                .font(.system(size: 17))
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .overlay(
                                    VStack {
                                        Spacer()
                                        Rectangle()
                                            .frame(height: 1)
                                            .foregroundColor(username.isEmpty ? Color.gray.opacity(0.5) : Color.white)
                                    }
                                )
                        }
                        .padding(.bottom, 20)
                        
                        // Password field with floating label design
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.gray)
                            
                            SecureField("", text: $password)
                                .font(.system(size: 17))
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .overlay(
                                    VStack {
                                        Spacer()
                                        Rectangle()
                                            .frame(height: 1)
                                            .foregroundColor(password.isEmpty ? Color.gray.opacity(0.5) : Color.white)
                                    }
                                )
                        }
                        
                        // Login button - modern design
                        Button(action: login) {
                            HStack {
                                if isLoggingIn {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .padding(.trailing, 8)
                                }
                                
                                Text(isLoggingIn ? "Signing in..." : "Continue")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(.black)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                username.isEmpty || password.isEmpty || isLoggingIn ?
                                Color.white.opacity(0.7) : Color.white
                            )
                            .cornerRadius(26)
                            .overlay(
                                !isLoggingIn ?
                                HStack {
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(.black)
                                        .font(.system(size: 15, weight: .semibold))
                                        .padding(.trailing, 20)
                                } : nil
                            )
                        }
                        .disabled(isLoggingIn || username.isEmpty || password.isEmpty)
                        .padding(.top, 36)
                        
                        // Forgot password link
                        Button(action: {
                            // Forgot password action
                        }) {
                            Text("Forgot password?")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Color.gray)
                                .padding(.top, 16)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, 40)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                
                Spacer()
                
                // Version info
                Text("v1.0.0")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                    .padding(.bottom, 20)
            }
            .scaleEffect(pageScale)
            .dismissKeyboardOnTap()
            

            
            // Onboarding overlay
            if showOnboarding {
                if useConsolidatedOnboarding || AppConfiguration.UX.useConsolidatedOnboardingFlow {
                    // Use the new consolidated flow
                    OnboardingView(
                        initialStep: resumeFromCompanyStep ? .companyCode : .welcome,
                        onComplete: {
                            // Hide onboarding when complete
                            print("LoginView: Consolidated onboarding complete callback received")
                            showOnboarding = false
                            
                            // Check if the onboarding set authentication flag directly
                            if UserDefaults.standard.bool(forKey: "is_authenticated") {
                                // Force update the dataController authentication state
                                print("LoginView: Onboarding set is_authenticated=true, updating dataController")
                                DispatchQueue.main.async {
                                    dataController.isAuthenticated = true
                                }
                            }
                            // Fallback to old behavior if needed
                            else if UserDefaults.standard.bool(forKey: "has_joined_company") {
                                // Attempt to log in again to enter the app
                                print("LoginView: Falling back to login attempt to authenticate")
                                login()
                            }
                        }
                    )
                    .environmentObject(dataController)
                    .transition(.opacity)
                    .zIndex(2) // Ensure it appears above login content
                } else {
                    // Use the original flow
                    OnboardingView(
                        initialStep: resumeFromCompanyStep ? .companyCode : .welcome,
                        onComplete: {
                            // Hide onboarding when complete
                            print("LoginView: Onboarding complete callback received")
                            showOnboarding = false
                            
                            // Check if the onboarding set authentication flag directly
                            if UserDefaults.standard.bool(forKey: "is_authenticated") {
                                // Force update the dataController authentication state
                                print("LoginView: Onboarding set is_authenticated=true, updating dataController")
                                DispatchQueue.main.async {
                                    dataController.isAuthenticated = true
                                }
                            }
                            // Fallback to old behavior if needed
                            else if UserDefaults.standard.bool(forKey: "has_joined_company") {
                                // Attempt to log in again to enter the app
                                print("LoginView: Falling back to login attempt to authenticate")
                                login()
                            }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(2) // Ensure it appears above login content
                }
            }
        }
        .animation(.easeInOut, value: showOnboarding)
        .alert(isPresented: $showError, content: {
            Alert(
                title: Text("Sign In Failed"),
                message: Text(errorMessage ?? "Please check your credentials and try again."),
                dismissButton: .default(Text("OK"))
            )
        })
    }
    
    private func login() {
        guard !username.isEmpty, !password.isEmpty else { return }
        
        isLoggingIn = true
        errorMessage = nil
        
        Task {
            do {
                // Convert this to a throwing function call
                let success = try await attemptLogin(username: username, password: password)
                
                await MainActor.run {
                    isLoggingIn = false
                    
                    if success {
                        // Check if the user has completed the company join step
                        let hasJoinedCompany = UserDefaults.standard.bool(forKey: "has_joined_company")
                        
                        if !hasJoinedCompany {
                            print("Login: User authenticated but needs to complete company onboarding")
                            // Show onboarding starting at company code step
                            resumeFromCompanyStep = true
                            showOnboarding = true
                        }
                        // If user has a company, DataController will handle updating isAuthenticated
                        // and ContentView will automatically transition to the main app
                    } else {
                        errorMessage = "Invalid username or password. Please try again."
                        showError = true
                    }
                }
            } catch let authError as AuthError {
                // Now this catch block is reachable
                await MainActor.run {
                    isLoggingIn = false
                    errorMessage = authError.localizedDescription
                    showError = true
                }
            } catch let apiError as APIError {
                await MainActor.run {
                    isLoggingIn = false
                    errorMessage = apiError.localizedDescription
                    showError = true
                }
            } catch {
                await MainActor.run {
                    isLoggingIn = false
                    errorMessage = "Login failed: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    // Helper method that can throw errors
    private func attemptLogin(username: String, password: String) async throws -> Bool {
        // This will propagate any errors from dataController.login
        return await dataController.login(username: username, password: password)
    }
    
}

#Preview("LoginView Preview") {
    LoginView()
        .environmentObject(DataController())
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}
