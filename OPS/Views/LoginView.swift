//
//  LoginView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//

import SwiftUI
import Combine
import GoogleSignIn
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager

    // Login states
    @State private var username = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showOnboarding = false

    // New onboarding manager (created when needed)
    @State private var onboardingManager: OnboardingManager?

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
                            // Clear any existing state and start fresh onboarding
                            OnboardingManager.clearState()
                            UserDefaults.standard.removeObject(forKey: "resume_onboarding")
                            UserDefaults.standard.removeObject(forKey: "is_authenticated")
                            UserDefaults.standard.removeObject(forKey: "user_id")

                            // Create fresh onboarding manager
                            onboardingManager = OnboardingManager(dataController: dataController)

                            // Show onboarding
                            withAnimation(.easeInOut(duration: 0.3)) {
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
                    VStack(alignment: .leading, spacing: 20) {
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
                        
                        // Form title
                        Text("Enter your credentials")
                            .font(OPSStyle.Typography.title.weight(.bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.bottom, 16)
                        
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
                                .autocorrectionDisabled(true)
                                .overlay(
                                    VStack {
                                        Spacer()
                                        Rectangle()
                                            .frame(height: 1)
                                            .foregroundColor(username.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                                    }
                                )
                        }
                        .padding(.bottom, 12)
                        
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
                            .background(Color.white)
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
                            .disabledButtonStyle(isDisabled: isLoggingIn || username.isEmpty || password.isEmpty)
                        }
                        .disabled(isLoggingIn || username.isEmpty || password.isEmpty)
                        .padding(.top, 20)
                        
                        // Forgot password link
                        Button(action: {
                            showForgotPassword = true
                        }) {
                            Text("Forgot password?")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.top, 12)
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
                        .padding(.vertical, 16)
                        
                        // Google Sign-In button
                        GoogleSignInButton(onSignIn: handleGoogleSignIn)
                            .frame(height: OPSStyle.Layout.touchTargetStandard)
                        
                        // Apple Sign-In button
                        AppleSignInButton(onSignIn: handleAppleSignIn)
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
            
            // Onboarding overlay - using new consolidated onboarding
            if showOnboarding, let manager = onboardingManager {
                OnboardingContainer(manager: manager) {
                    // Onboarding completed
                    showOnboarding = false
                    onboardingManager = nil

                    // User has completed onboarding, so they must be authenticated
                    DispatchQueue.main.async {
                        dataController.isAuthenticated = true
                    }
                }
                .environmentObject(dataController)
                .environmentObject(appState)
                .environmentObject(locationManager)
                .transition(.opacity)
                .zIndex(3)
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DismissOnboarding"))) { _ in
            // Dismiss onboarding and return to login
            withAnimation {
                showOnboarding = false
                onboardingManager = nil
            }
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

                            // Check if we need to show onboarding using new system
                            let (shouldShowOnboarding, manager) = OnboardingManager.shouldShowOnboarding(dataController: dataController)

                            if shouldShowOnboarding {
                                // Use manager from shouldShowOnboarding or create new one
                                onboardingManager = manager ?? OnboardingManager(dataController: dataController)

                                // Reset UI state before showing onboarding
                                showLoginMode = false
                                pageScale = 1.0

                                // Small delay to ensure UI is reset
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
        // Use the new OnboardingManager to check if we should show onboarding
        let (shouldShow, manager) = OnboardingManager.shouldShowOnboarding(dataController: dataController)

        if shouldShow {
            // Resume onboarding with the appropriate state
            onboardingManager = manager ?? OnboardingManager(dataController: dataController)

            // Show immediately - no delay needed
            self.showOnboarding = true
        } else {
            // Clear any stale resume flags
            UserDefaults.standard.removeObject(forKey: "resume_onboarding")
        }
    }
    
    private func handleAppleSignIn() {
        isLoggingIn = true
        errorMessage = nil
        
        Task { @MainActor in
            // Get the key window for presentation
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else {
                errorMessage = "Cannot present Apple Sign-In"
                showError = true
                isLoggingIn = false
                return
            }
            
            do {
                // Perform Apple Sign-In
                let appleResult = try await AppleSignInManager.shared.signIn(presenting: window)
                
                // Authenticate with Bubble backend
                let success = await dataController.loginWithApple(appleResult: appleResult)
                
                isLoggingIn = false
                
                if !success {
                    errorMessage = "No account found. Please sign up with your company first."
                    showError = true
                } else {
                    // Check if we need to show onboarding using new system
                    let (shouldShowOnboarding, _) = OnboardingManager.shouldShowOnboarding(dataController: dataController)

                    if shouldShowOnboarding {
                        // Create onboarding manager - it will prefill data from dataController
                        onboardingManager = OnboardingManager(dataController: dataController)

                        // Dismiss keyboard and reset UI state
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        showLoginMode = false
                        pageScale = 1.0

                        // Show onboarding
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showOnboarding = true
                        }
                    } else {
                        // Onboarding complete - proceed to app
                        dataController.isAuthenticated = true
                    }
                }
            } catch {
                isLoggingIn = false

                // Check if it was a cancellation
                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    // User canceled, don't show error
                } else {
                    errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
                    showError = true
                }
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
                    // Check if we need to show onboarding using new system
                    let (shouldShowOnboarding, _) = OnboardingManager.shouldShowOnboarding(dataController: dataController)

                    if shouldShowOnboarding {
                        // Create onboarding manager - it will prefill data from dataController
                        onboardingManager = OnboardingManager(dataController: dataController)

                        // Dismiss keyboard and reset UI state
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        showLoginMode = false
                        pageScale = 1.0

                        // Show onboarding
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showOnboarding = true
                        }
                    } else {
                        // Onboarding complete - proceed to app
                        dataController.isAuthenticated = true
                    }
                }
            } catch {
                isLoggingIn = false

                // Check if it was a cancellation
                if let gidError = error as? GIDSignInError, gidError.code == .canceled {
                    // User canceled, don't show error
                } else {
                    errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                    showError = true
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

// Custom Apple Sign-In button that matches OPS styling
struct AppleSignInButton: View {
    let onSignIn: () -> Void
    
    var body: some View {
        Button(action: onSignIn) {
            HStack(spacing: 12) {
                // Apple logo
                Image(systemName: "apple.logo")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text("Continue with Apple")
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
            // Pure black background with subtle opacity
            OPSStyle.Colors.darkBackground
                .edgesIgnoringSafeArea(.all)
            
            // Tactical content container
            VStack(spacing: 0) {
                // Top accent line
                Rectangle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(height: 2)
                    .opacity(0.8)
                
                // Main content
                VStack(spacing: 24) {
                    // Tactical success indicator
                    ZStack {
                        // Background circle with subtle accent
                        Circle()
                            .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 2)
                            .frame(width: 56, height: 56)
                            .scaleEffect(showCheckmark ? 1 : 0.8)
                        
                        // Inner checkmark
                        Image(systemName: "checkmark")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .scaleEffect(showCheckmark ? 1 : 0)
                            .rotationEffect(.degrees(showCheckmark ? 0 : -30))
                    }
                    .animation(.easeOut(duration: 0.3), value: showCheckmark)
                    
                    // Status text stack
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Text("STATUS:")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            
                            Text("ACCESS GRANTED")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        .opacity(showCheckmark ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2).delay(0.2), value: showCheckmark)
                        
                        Text("AUTHENTICATION SUCCESSFUL")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .opacity(showCheckmark ? 1 : 0)
                            .animation(.easeInOut(duration: 0.2).delay(0.3), value: showCheckmark)
                    }
                    
                    // User identifier (minimal info)
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        
                        Text("WELCOME BACK")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .opacity(showCheckmark ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2).delay(0.4), value: showCheckmark)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                
                // Bottom accent line
                Rectangle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(height: 2)
                    .opacity(0.8)
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorderSubtle, lineWidth: 1)
            )
            .padding(.horizontal, 60)
            .scaleEffect(showCheckmark ? 1 : 0.95)
            .opacity(showCheckmark ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: showCheckmark)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.15)) {
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
