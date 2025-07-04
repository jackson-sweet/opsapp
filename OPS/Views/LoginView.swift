//
//  LoginView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//

import SwiftUI
import Combine
import GoogleSignIn

struct LoginView: View {
    @EnvironmentObject private var dataController: DataController
    // Always use consolidated onboarding flow
    
    // Login states
    @State private var username = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showOnboarding = false
    @State private var resumeFromCompanyStep = false
    
    // Used to check if we need to automatically resume onboarding
    private let resumeOnboarding = UserDefaults.standard.bool(forKey: "resume_onboarding")
    
    // UI states
    @State private var showLoginMode = false
    @State private var pageScale: CGFloat = 1.0
    @State private var showForgotPassword = false
    @State private var showLoginSuccess = false
    
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
                    
                    HStack(alignment: .bottom) {
                        
                        Image("LogoWhite")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                            .padding(.bottom, 8)
                        Text("OPS")
                            .font(OPSStyle.Typography.largeTitle.weight(.bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()
                        
                    }.padding(.leading, 4)
                    
                    Spacer()
                    
                    // Bold message inspired by your inspiration designs
                    VStack(alignment: .leading, spacing: 32) {
                        
                        
                        VStack(alignment: .leading) {
                            Text("BUILT BY TRADES,")
                                .font(OPSStyle.Typography.largeTitle.weight(.bold))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Text("FOR TRADES.")
                                .font(OPSStyle.Typography.largeTitle.weight(.bold))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        Text("Designed in the field, not in a tech office.")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.top, 4)
                        
                        Spacer()
                            .frame(height: 40)
                        
                    }
                    
                    // Login/Signup Options
                    
                    // Initial options (Sign In or Sign Up)
                    VStack(spacing: 16) {
                        Spacer()
                        // Primary action - Sign Up button
                        Button(action: {
                            // Clear any existing user data before starting new onboarding
                            UserDefaults.standard.removeObject(forKey: "resume_onboarding")
                            UserDefaults.standard.removeObject(forKey: "is_authenticated")
                            UserDefaults.standard.removeObject(forKey: "user_id")
                            UserDefaults.standard.removeObject(forKey: "user_email")
                            
                            // Show onboarding directly
                            withAnimation(.easeInOut(duration: 0.3)) {
                                resumeFromCompanyStep = false
                                showOnboarding = true
                            }
                        }) {
                            Text("GET SIGNED UP")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: OPSStyle.Layout.touchTargetStandard)
                                .background(Color.white)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    HStack {
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                            .foregroundColor(.black)
                                            .font(OPSStyle.Typography.caption.weight(.semibold))
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
                                    .font(OPSStyle.Typography.button)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                
                                Image(systemName: "arrow.right")
                                    .font(OPSStyle.Typography.caption.weight(.medium))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.clear)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    // Login form (once Sign In is selected)
                    VStack(alignment: .leading, spacing: 32) {
                        // Back button
                        Button(action: {
                            // Dismiss keyboard
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            
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
                                    .font(OPSStyle.Typography.caption.weight(.semibold))
                                Text("Back")
                                    .font(OPSStyle.Typography.button)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .padding(.bottom, 8)
                        
                        // Form title
                        Text("Enter your credentials")
                            .font(OPSStyle.Typography.title.weight(.bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.bottom, 24)
                        
                        // Username field with floating label design
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email")
                                .font(OPSStyle.Typography.caption.weight(.medium))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            TextField("", text: $username)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding(.vertical, 12)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .overlay(
                                    VStack {
                                        Spacer()
                                        Rectangle()
                                            .frame(height: 1)
                                            .foregroundColor(username.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                                    }
                                )
                        }
                        .padding(.bottom, 20)
                        
                        // Password field with floating label design
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(OPSStyle.Typography.caption.weight(.medium))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            SecureField("", text: $password)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding(.vertical, 12)
                                .overlay(
                                    VStack {
                                        Spacer()
                                        Rectangle()
                                            .frame(height: 1)
                                            .foregroundColor(password.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
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
                                    .font(OPSStyle.Typography.button)
                                    .foregroundColor(.black)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetStandard)
                            .background(
                                username.isEmpty || password.isEmpty || isLoggingIn ?
                                Color.white.opacity(0.7) : Color.white
                            )
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                !isLoggingIn ?
                                HStack {
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(.black)
                                        .font(OPSStyle.Typography.caption.weight(.semibold))
                                        .padding(.trailing, 20)
                                } : nil
                            )
                        }
                        .disabled(isLoggingIn || username.isEmpty || password.isEmpty)
                        .padding(.top, 36)
                        
                        // Forgot password link
                        Button(action: {
                            showForgotPassword = true
                        }) {
                            Text("Forgot password?")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.top, 16)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        
                        // Divider
                        HStack {
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(OPSStyle.Colors.tertiaryText.opacity(0.3))
                            
                            Text("OR")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .padding(.horizontal, 16)
                            
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(OPSStyle.Colors.tertiaryText.opacity(0.3))
                        }
                        .padding(.vertical, 24)
                        
                        // Google Sign-In button
                        GoogleSignInButton(onSignIn: handleGoogleSignIn)
                            .frame(height: OPSStyle.Layout.touchTargetStandard)
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                
                Spacer()
                
                // Version info
                Text("[ VERSION \(AppConfiguration.AppInfo.version.uppercased()) ]")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                    .padding(.bottom, 20)
            }
            .padding(40)
            .scaleEffect(pageScale)
            .dismissKeyboardOnTap()
            

            
            // Login success overlay
            if showLoginSuccess {
                LoginSuccessView()
                    .transition(.opacity)
                    .zIndex(2)
            }
            
            // Onboarding overlay
            if showOnboarding {
                // Determine the starting step based on existing data
                let startingStep: OnboardingStep = {
                    // If we have authenticated user with data, start from welcome to allow skip logic
                    if dataController.currentUser != nil {
                        return .welcome
                    } else if resumeFromCompanyStep {
                        return .organizationJoin
                    } else {
                        return .welcome
                    }
                }()
                
                // Use the consolidated flow with the appropriate starting step
                OnboardingView(
                    initialStep: startingStep,
                    onComplete: {
                        // Hide onboarding when complete
                        showOnboarding = false
                        
                        // Check if the onboarding set authentication flag directly
                        if UserDefaults.standard.bool(forKey: "is_authenticated") {
                            // Force update the dataController authentication state
                            DispatchQueue.main.async {
                                dataController.isAuthenticated = true
                            }
                        }
                        // Fallback to old behavior if needed
                        else if UserDefaults.standard.bool(forKey: "has_joined_company") {
                            // Attempt to log in again to enter the app
                            login()
                        }
                    }
                )
                .environmentObject(dataController)
                .transition(.opacity)
                .zIndex(3) // Ensure it appears above login content and success screen
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DismissOnboarding"))) { _ in
                    // Dismiss onboarding when notification is received
                    showOnboarding = false
                }
            }
            
            // Forgot password overlay
            if showForgotPassword {
                ForgotPasswordView(
                    isPresented: $showForgotPassword,
                    prefilledEmail: $username
                )
                .transition(.opacity)
                .zIndex(4)
            }
        }
        .animation(.easeInOut, value: showOnboarding)
        .animation(.easeInOut, value: showForgotPassword)
        .animation(.easeInOut, value: showLoginSuccess)
        .alert(isPresented: $showError, content: {
            Alert(
                title: Text("Sign In Failed"),
                message: Text(errorMessage ?? "Please check your credentials and try again."),
                dismissButton: .default(Text("OK"))
            )
        })
        .onAppear {
            checkResumeOnboarding()
        }
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
                        // Show login success screen first
                        showLoginSuccess = true
                        
                        // Dismiss keyboard
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        
                        // Wait a moment before proceeding
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showLoginSuccess = false
                            
                            // Check if the user has completed onboarding
                            let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "onboarding_completed")
                            
                            if !hasCompletedOnboarding {
                            
                            // Try to detect user type from the current user data
                            if let currentUser = dataController.currentUser {
                                // Only update user type if it's not already saved
                                let savedUserType = UserDefaults.standard.string(forKey: "selected_user_type")
                                
                                if savedUserType == nil {
                                    // First check if user has explicit userType
                                    if let userType = currentUser.userType {
                                        UserDefaults.standard.set(userType.rawValue, forKey: "selected_user_type")
                                        print("🔵 LoginView: Set user type from user model: \(userType.rawValue)")
                                    } else {
                                        // Fall back to determining from role
                                        if currentUser.role == .fieldCrew || currentUser.role == .officeCrew {
                                            UserDefaults.standard.set(UserType.employee.rawValue, forKey: "selected_user_type")
                                            print("🔵 LoginView: Defaulted to employee based on role")
                                        } else if currentUser.role == .admin {
                                            // Admin users might be company owners
                                            UserDefaults.standard.set(UserType.company.rawValue, forKey: "selected_user_type")
                                            print("🔵 LoginView: Defaulted to company based on admin role")
                                        }
                                    }
                                } else {
                                    print("🔵 LoginView: User type already saved as: \(savedUserType)")
                                }
                                
                                // Pre-populate user data if available
                                if !currentUser.firstName.isEmpty {
                                    UserDefaults.standard.set(currentUser.firstName, forKey: "user_first_name")
                                }
                                if !currentUser.lastName.isEmpty {
                                    UserDefaults.standard.set(currentUser.lastName, forKey: "user_last_name")
                                }
                                if let phone = currentUser.phone, !phone.isEmpty {
                                    UserDefaults.standard.set(phone, forKey: "user_phone_number")
                                }
                            }
                            
                            // Ensure all data is saved before showing onboarding
                            UserDefaults.standard.synchronize()
                            
                                // Reset any UI state before showing onboarding
                                showLoginMode = false
                                pageScale = 1.0
                                
                                // Check if they need to resume from company step
                                let hasJoinedCompany = UserDefaults.standard.bool(forKey: "has_joined_company") || 
                                                       (dataController.currentUser?.companyId != nil && !dataController.currentUser!.companyId!.isEmpty)
                                resumeFromCompanyStep = !hasJoinedCompany
                                
                                // Small delay to ensure UI is reset
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    // Show onboarding
                                    showOnboarding = true
                                }
                            }
                            // If user has completed onboarding, DataController will handle updating isAuthenticated
                            // and ContentView will automatically transition to the main app
                        }
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
    
    private func checkResumeOnboarding() {
        // If the resume flag is set, check what step to resume from
        if resumeOnboarding {
            
            // Check for authentication state
            let isAuthenticated = UserDefaults.standard.bool(forKey: "is_authenticated")
            let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
            
            // If onboarding is already completed but we somehow have the resume flag set,
            // just clear it and let the user proceed to the main app
            if isAuthenticated && onboardingCompleted {
                UserDefaults.standard.set(false, forKey: "resume_onboarding")
                
                // Set authentication in DataController
                DispatchQueue.main.async {
                    self.dataController.isAuthenticated = true
                }
                return
            }
            
            // Determine which step to resume from
            let hasUserId = UserDefaults.standard.string(forKey: "user_id") != nil
            let lastStepRaw = UserDefaults.standard.integer(forKey: "last_onboarding_step_v2")
            
            if hasUserId && isAuthenticated {
                
                // Resume from the appropriate step
                if lastStepRaw > 0 {
                    // Use the saved step if available
                    let lastStep = OnboardingStep(rawValue: lastStepRaw) ?? .organizationJoin
                    resumeFromCompanyStep = true
                    
                    // Show onboarding at the appropriate step
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.showOnboarding = true
                    }
                } else {
                    // Default to organization join if no step was saved
                    resumeFromCompanyStep = true
                    
                    // Show onboarding starting from organization join
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.showOnboarding = true
                    }
                }
                
                // Don't clear the resume flag until onboarding is completed
                // It will be cleared in CompletionView when onboarding is finished
            } else {
                // No user ID or not authenticated - this shouldn't happen, but clear the flag
                UserDefaults.standard.set(false, forKey: "resume_onboarding")
            }
        }
    }
    
    private func handleGoogleSignIn() {
        isLoggingIn = true
        errorMessage = nil
        
        Task { @MainActor in
            // Get the root view controller on main thread
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                errorMessage = "Cannot present Google Sign-In"
                showError = true
                isLoggingIn = false
                return
            }
            
            do {
                // Perform Google Sign-In on main thread
                let googleUser = try await GoogleSignInManager.shared.signIn(presenting: rootViewController)
                
                // Authenticate with Bubble backend
                let success = await dataController.loginWithGoogle(googleUser: googleUser)
                
                isLoggingIn = false
                
                if !success {
                    errorMessage = "No account found. Please sign up with your company first."
                    showError = true
                } else {
                    print("🟢 Google login successful")
                    
                    // Check if the user has completed onboarding
                    let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "onboarding_completed")
                    let hasCompany = !(dataController.currentUser?.companyId ?? "").isEmpty
                    
                    print("   Has completed onboarding: \(hasCompletedOnboarding)")
                    print("   Has company: \(hasCompany)")
                    
                    if !hasCompletedOnboarding || !hasCompany {
                        print("🟡 User needs onboarding after Google login")
                        
                        // Dismiss keyboard first
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        
                        // Reset any UI state before showing onboarding
                        showLoginMode = false
                        pageScale = 1.0
                        
                        // Small delay to ensure UI is reset and keyboard is dismissed
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showOnboarding = true
                        }
                    } else {
                        // Only now set isAuthenticated to trigger the transition
                        print("🟢 User has completed onboarding, transitioning to main app")
                        dataController.isAuthenticated = true
                    }
                }
            } catch {
                isLoggingIn = false
                
                // Check if it was a cancellation
                if let gidError = error as? GIDSignInError, gidError.code == .canceled {
                    // User canceled, don't show error
                    print("🟡 Google Sign-In canceled by user")
                } else {
                    errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                    showError = true
                    print("🔴 Google Sign-In error: \(error)")
                }
            }
        }
    }
}

// Custom Google Sign-In button that matches OPS styling
struct GoogleSignInButton: View {
    let onSignIn: () -> Void
    
    var body: some View {
        Button(action: onSignIn) {
            HStack(spacing: 12) {
                // Google logo
                Image("google_logo") // You'll need to add this image to Assets
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                   // .background(Color.white)

                
                Text("Continue with Google")
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.tertiaryText, lineWidth: 1)
            )
        }
    }
}

// Login Success View
struct LoginSuccessView: View {
    @State private var animationProgress: CGFloat = 0
    @State private var showCheckmark = false
    
    var body: some View {
        ZStack {
            // Full screen background
            Color.black.opacity(0.8)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                // Success icon
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.primaryAccent)
                        .frame(width: 80, height: 80)
                        .scaleEffect(showCheckmark ? 1 : 0)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                        .scaleEffect(showCheckmark ? 1 : 0)
                        .rotationEffect(.degrees(showCheckmark ? 0 : -30))
                }
                .animation(.spring(response: 0.6, dampingFraction: 0.6, blendDuration: 0), value: showCheckmark)
                
                // Success text
                Text("Login Successful")
                    .font(OPSStyle.Typography.title.weight(.semibold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .opacity(showCheckmark ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3).delay(0.3), value: showCheckmark)
                
                Text("Welcome back!")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .opacity(showCheckmark ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3).delay(0.4), value: showCheckmark)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackground)
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .scaleEffect(showCheckmark ? 1 : 0.8)
            .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0), value: showCheckmark)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCheckmark = true
            }
        }
    }
}

#Preview("LoginView Preview") {
    LoginView()
        .environmentObject(DataController())
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}
