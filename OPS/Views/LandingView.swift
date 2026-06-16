//
//  LandingView.swift
//  OPS
//
//  Landing page for unauthenticated users.
//  Shows branding + "GET SIGNED UP" and "LOG INTO ACCOUNT" options.
//  When "LOG INTO ACCOUNT" is tapped, shows the login form inline.
//
//  Formerly named LoginView — renamed to avoid confusion with the
//  simple LoginView used by the A/B test onboarding flow.
//

import SwiftUI
import Combine
import GoogleSignIn
import AuthenticationServices

struct LandingView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var variantManager: OnboardingVariantManager

    /// Fired the instant a returning login is initiated — after the credentials
    /// are accepted (email submitted, or a social provider returns), before the
    /// long initial sync. Lets the host (ContentView) arm the workspace-preload
    /// gate so the sync is covered, not the login button (bug 95bf7c82).
    var onLoginInitiated: (() -> Void)? = nil
    /// Fired when a login attempt ends WITHOUT entering the app — wrong password,
    /// cancelled social sign-in, or a route into onboarding — so the host can
    /// disarm the gate. Optional + nil-default so other call sites are unaffected.
    var onLoginAbandoned: (() -> Void)? = nil

    // Login states
    @State private var username = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var showOnboarding = false

    // New onboarding manager (created when needed)
    @State private var onboardingManager: OnboardingManager?

    // UI states
    @State private var showLoginMode = false
    @State private var pageScale: CGFloat = 1.0
    @State private var showForgotPassword = false
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

            // Main content
            VStack(spacing: OPSStyle.Layout.spacing4) {

                Spacer()

                // Header content with inspirational message

                // Logo (smaller, just as an element)
                if !showLoginMode {

                    HStack(alignment: .bottom) {

                        Image("LogoWhite")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                            .padding(.bottom, OPSStyle.Layout.spacing2)
                        Text("OPS")
                            .font(OPSStyle.Typography.largeTitle.weight(.bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()

                    }.padding(.leading, OPSStyle.Layout.spacing1)

                    Spacer()

                    // Bold message inspired by your inspiration designs
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing5) {


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
                            .padding(.top, OPSStyle.Layout.spacing1)

                        Spacer()
                            .frame(height: 40)

                    }

                    // Login/Signup Options

                    // Initial options (Sign In or Sign Up)
                    VStack(spacing: OPSStyle.Layout.spacing3) {
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
                            withAnimation(OPSStyle.Animation.standard) {
                                showOnboarding = true
                            }
                        }) {
                            Text("GET SIGNED UP")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(OPSStyle.Colors.invertedText)
                                .frame(maxWidth: .infinity)
                                .frame(height: OPSStyle.Layout.touchTargetStandard)
                                .background(OPSStyle.Colors.primaryText)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    HStack {
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                            .foregroundColor(OPSStyle.Colors.invertedText)
                                            .font(OPSStyle.Typography.caption.weight(.semibold))
                                            .padding(.trailing, OPSStyle.Layout.spacing3_5)
                                    }
                                )
                        }
                        .padding(.bottom, OPSStyle.Layout.spacing1)

                        // Secondary action - Log In button
                        Button(action: {
                            withAnimation(OPSStyle.Animation.standard) {
                                showLoginMode = true
                                pageScale = 0.98

                                // Return to normal scale after small delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    withAnimation(OPSStyle.Animation.standard) {
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
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3_5) {
                        // Back button
                        Button(action: {
                            // Dismiss keyboard
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

                            withAnimation(OPSStyle.Animation.standard) {
                                showLoginMode = false
                                pageScale = 0.98

                                // Return to normal scale after small delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(OPSStyle.Animation.standard) {
                                        pageScale = 1.0
                                    }
                                }
                            }
                        }) {
                            HStack(spacing: OPSStyle.Layout.spacing1) {
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
                            .padding(.bottom, OPSStyle.Layout.spacing3)

                        // Username field with floating label design
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email")
                                .font(OPSStyle.Typography.caption.weight(.medium))
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            TextField("", text: $username)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding(.vertical, OPSStyle.Layout.spacing2_5)
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
                        .padding(.bottom, OPSStyle.Layout.spacing2_5)

                        // Password field with floating label design
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(OPSStyle.Typography.caption.weight(.medium))
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            SecureField("", text: $password)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding(.vertical, OPSStyle.Layout.spacing2_5)
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
                                        .padding(.trailing, OPSStyle.Layout.spacing2)
                                }

                                Text(isLoggingIn ? "Signing in..." : "Continue")
                                    .font(OPSStyle.Typography.button)
                                    .foregroundColor(OPSStyle.Colors.invertedText)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetStandard)
                            .background(OPSStyle.Colors.primaryText)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                !isLoggingIn ?
                                HStack {
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(OPSStyle.Colors.invertedText)
                                        .font(OPSStyle.Typography.caption.weight(.semibold))
                                        .padding(.trailing, OPSStyle.Layout.spacing3_5)
                                } : nil
                            )
                            .disabledButtonStyle(isDisabled: isLoggingIn || username.isEmpty || password.isEmpty)
                        }
                        .disabled(isLoggingIn || username.isEmpty || password.isEmpty)
                        .padding(.top, OPSStyle.Layout.spacing3_5)

                        // Forgot password link
                        Button(action: {
                            showForgotPassword = true
                        }) {
                            Text("Forgot password?")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.top, OPSStyle.Layout.spacing2_5)
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
                                .padding(.horizontal, OPSStyle.Layout.spacing3)

                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(OPSStyle.Colors.tertiaryText.opacity(0.3))
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing3)

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
                    .padding(.bottom, OPSStyle.Layout.spacing3_5)
            }
            .padding(40)
            .scaleEffect(pageScale)
            .dismissKeyboardOnTap()



            // Onboarding overlay - streamlined A/B test flow
            if showOnboarding, let manager = onboardingManager {
                OnboardingABTestCoordinator(
                    variantManager: variantManager,
                    onboardingManager: manager,
                    onComplete: {
                        manager.completeOnboarding()
                        dataController.isAuthenticated = true
                        UserDefaults.standard.set(true, forKey: "onboarding_completed")
                        UserDefaults.standard.set(true, forKey: "is_authenticated")
                        showOnboarding = false
                        onboardingManager = nil
                    },
                    onShowLogin: {
                        showOnboarding = false
                        onboardingManager = nil
                        withAnimation(OPSStyle.Animation.standard) {
                            showLoginMode = true
                        }
                    }
                )
                .environmentObject(dataController)
                .environmentObject(appState)
                .environmentObject(locationManager)
                .transition(.opacity)
                .zIndex(3)
            }

        }
        .animation(hasAppeared ? OPSStyle.Animation.standard : nil, value: showLoginMode)
        .animation(.easeInOut, value: showOnboarding)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(prefilledEmail: username)
        }
        .errorToast($errorMessage, label: Feedback.Err.signInFailed)
        .onAppear {
            checkResumeOnboarding()
            // Delay enabling animation to prevent initial mount transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
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
        // Mark the returning login pending. ContentView arms the workspace gate
        // only when the initial sync actually begins — a wrong password never
        // gets that far, so the gate never wrongly appears (bug 95bf7c82).
        onLoginInitiated?()

        Task {
            do {
                let (success, loginError) = try await attemptLogin(username: username, password: password)

                await MainActor.run {
                    isLoggingIn = false

                    if success {
                        // A login can also succeed for a user who still needs to
                        // finish onboarding — route them there and disarm the gate.
                        // The completed-onboarding case needs nothing here: the gate
                        // is already covering the sync (armed when it began) and the
                        // deferred auth flip at the end of the sync reveals the app.
                        let (shouldShowOnboarding, manager) = OnboardingManager.shouldShowOnboarding(dataController: dataController)
                        if shouldShowOnboarding {
                            onLoginAbandoned?()
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            onboardingManager = manager ?? OnboardingManager(dataController: dataController)
                            showLoginMode = false
                            pageScale = 1.0

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showOnboarding = true
                            }
                        }
                    } else {
                        onLoginAbandoned?()
                        errorMessage = loginError ?? "Incorrect email or password. Please try again."
                    }
                }
            } catch let authError as AuthError {
                await MainActor.run {
                    isLoggingIn = false
                    onLoginAbandoned?()
                    errorMessage = authError.localizedDescription
                }
            } catch {
                await MainActor.run {
                    isLoggingIn = false
                    onLoginAbandoned?()
                    errorMessage = "Login failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func attemptLogin(username: String, password: String) async throws -> (Bool, String?) {
        return await dataController.login(username: username, password: password)
    }

    private func checkResumeOnboarding() {
        // Only resume onboarding if there's actual saved state from a previous
        // incomplete onboarding session. Do NOT auto-trigger onboarding just
        // because the user is unauthenticated — the LandingView itself is the
        // correct screen for unauthenticated users. The "GET SIGNED UP" button
        // handles fresh onboarding starts.
        guard OnboardingState.load() != nil else {
            UserDefaults.standard.removeObject(forKey: "resume_onboarding")
            return
        }

        let (shouldShow, manager) = OnboardingManager.shouldShowOnboarding(dataController: dataController)

        if shouldShow {
            onboardingManager = manager ?? OnboardingManager(dataController: dataController)
            self.showOnboarding = true
        } else {
            UserDefaults.standard.removeObject(forKey: "resume_onboarding")
        }
    }

    private func handleAppleSignIn() {
        isLoggingIn = true
        errorMessage = nil

        Task { @MainActor in
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else {
                errorMessage = "Cannot present Apple Sign-In"
                isLoggingIn = false
                return
            }

            do {
                let appleResult = try await AppleSignInManager.shared.signIn(presenting: window)
                // Provider accepted the user — mark the login pending so the gate
                // arms when loginWithApple's initial sync begins (bug 95bf7c82).
                onLoginInitiated?()
                let success = await dataController.loginWithApple(appleResult: appleResult)

                isLoggingIn = false

                if !success {
                    onLoginAbandoned?()
                    errorMessage = "No account found. Please sign up with your company first."
                } else {
                    let (shouldShowOnboarding, _) = OnboardingManager.shouldShowOnboarding(dataController: dataController)

                    if shouldShowOnboarding {
                        onLoginAbandoned?()
                        onboardingManager = OnboardingManager(dataController: dataController)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        showLoginMode = false
                        pageScale = 1.0

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showOnboarding = true
                        }
                    } else {
                        dataController.isAuthenticated = true
                    }
                }
            } catch {
                isLoggingIn = false
                onLoginAbandoned?()
                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    // User canceled
                } else {
                    errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func handleGoogleSignIn() {
        isLoggingIn = true
        errorMessage = nil

        Task { @MainActor in
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                errorMessage = "Cannot present Google Sign-In"
                isLoggingIn = false
                return
            }

            do {
                let googleUser = try await GoogleSignInManager.shared.signIn(presenting: rootViewController)
                // Provider accepted the user — mark the login pending so the gate
                // arms when loginWithGoogle's initial sync begins (bug 95bf7c82).
                onLoginInitiated?()
                let success = await dataController.loginWithGoogle(googleUser: googleUser)

                isLoggingIn = false

                if !success {
                    onLoginAbandoned?()
                    errorMessage = "No account found. Please sign up with your company first."
                } else {
                    let (shouldShowOnboarding, _) = OnboardingManager.shouldShowOnboarding(dataController: dataController)

                    if shouldShowOnboarding {
                        onLoginAbandoned?()
                        onboardingManager = OnboardingManager(dataController: dataController)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        showLoginMode = false
                        pageScale = 1.0

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showOnboarding = true
                        }
                    } else {
                        dataController.isAuthenticated = true
                    }
                }
            } catch {
                isLoggingIn = false
                onLoginAbandoned?()
                if let gidError = error as? GIDSignInError, gidError.code == .canceled {
                    // User canceled
                } else {
                    errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
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
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image("google_logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)

                Text("Continue with Google")
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.tertiaryText, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }
}

// Custom Apple Sign-In button that matches OPS styling
struct AppleSignInButton: View {
    let onSignIn: () -> Void

    var body: some View {
        Button(action: onSignIn) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: "apple.logo")
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
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
                    .stroke(OPSStyle.Colors.tertiaryText, lineWidth: OPSStyle.Layout.Border.standard)
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
            OPSStyle.Colors.darkBackground
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(height: 2)
                    .opacity(0.8)

                VStack(spacing: OPSStyle.Layout.spacing4) {
                    ZStack {
                        Circle()
                            .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: OPSStyle.Layout.Border.thick)
                            .frame(width: 56, height: 56)
                            .scaleEffect(showCheckmark ? 1 : 0.8)

                        Image(systemName: "checkmark")
                            .font(.system(size: OPSStyle.Layout.IconSize.lg, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .scaleEffect(showCheckmark ? 1 : 0)
                            .rotationEffect(.degrees(showCheckmark ? 0 : -30))
                    }
                    .animation(OPSStyle.Animation.standard, value: showCheckmark)

                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Text("STATUS:")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text("ACCESS GRANTED")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        .opacity(showCheckmark ? 1 : 0)
                        .animation(OPSStyle.Animation.fast.delay(0.2), value: showCheckmark)

                        Text("AUTHENTICATION SUCCESSFUL")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .opacity(showCheckmark ? 1 : 0)
                            .animation(OPSStyle.Animation.fast.delay(0.3), value: showCheckmark)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Text("WELCOME BACK")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .opacity(showCheckmark ? 1 : 0)
                    .animation(OPSStyle.Animation.fast.delay(0.4), value: showCheckmark)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing5)
                .padding(.vertical, 28)

                Rectangle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(height: 2)
                    .opacity(0.8)
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorderSubtle, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .padding(.horizontal, 60)
            .scaleEffect(showCheckmark ? 1 : 0.95)
            .opacity(showCheckmark ? 1 : 0)
            .animation(OPSStyle.Animation.standard, value: showCheckmark)
        }
        .onAppear {
            withAnimation(OPSStyle.Animation.faster) {
                showCheckmark = true
            }
        }
    }
}

#Preview("LandingView Preview") {
    LandingView()
        .environmentObject(DataController())
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}
