//
//  OnboardingContainer.swift
//  OPS
//
//  Main container view for the new v3 onboarding flow.
//  Handles routing between screens based on OnboardingManager state.
//

import SwiftUI

struct OnboardingContainer: View {
    @ObservedObject var manager: OnboardingManager
    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var locationManager: LocationManager
    var onComplete: (() -> Void)?

    init(manager: OnboardingManager, onComplete: (() -> Void)? = nil) {
        self.manager = manager
        self.onComplete = onComplete
    }

    // Computed transition based on navigation direction
    // Exit: always slides left (forward) or right (backward)
    // Entry: fades in after a brief pause
    private var screenTransition: AnyTransition {
        let isForward = manager.navigationDirection == .forward
        return .asymmetric(
            insertion: .opacity.animation(.easeIn(duration: 0.25).delay(0.15)),
            removal: .move(edge: isForward ? .leading : .trailing)
                .combined(with: .opacity)
                .animation(.easeOut(duration: 0.2))
        )
    }

    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar (shown after credentials)
                if let progressBar = OnboardingProgressBar.forState(manager.state) {
                    progressBar
                        .padding(.top, 8)
                        .transition(.opacity)
                }

                // Screen content based on current state
                screenContent
                    .id(manager.state.currentScreen) // Force view recreation for transition
                    .transition(screenTransition)
            }

            // Loading overlay (uses component from Components/)
            if manager.isLoading {
                OnboardingLoadingOverlay(message: loadingMessage)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: manager.state.currentScreen)
        .alert("Error", isPresented: $manager.showError) {
            Button("OK") {
                manager.clearError()
            }
        } message: {
            Text(manager.errorMessage ?? "An error occurred")
        }
        .onAppear {
            print("[ONBOARDING_CONTAINER] Container appeared, screen: \(manager.state.currentScreen)")
            if let onComplete = onComplete {
                manager.onComplete = onComplete
            }
        }
    }

    // MARK: - Screen Content

    @ViewBuilder
    private var screenContent: some View {
        switch manager.state.currentScreen {
        case .welcome:
            WelcomeScreen(manager: manager)

        case .login:
            LoginScreen(manager: manager)

        case .signup:
            SignupScreen(manager: manager)

        case .userTypeSelection:
            UserTypeSelectionScreen(manager: manager)

        case .credentials:
            CredentialsScreen(manager: manager)

        case .profile:
            ProfileScreen(manager: manager)

        case .companySetup:
            CompanySetupScreen(manager: manager)

        case .companyDetails:
            CompanyDetailsScreen(manager: manager)

        case .companyCode:
            CompanyCodeScreen(manager: manager)

        case .codeEntry:
            CodeEntryScreen(manager: manager)

        case .profileCompany:
            // Legacy - redirect to new flow
            ProfileScreen(manager: manager)

        case .profileJoin:
            // Legacy - redirect to new flow
            CodeEntryScreen(manager: manager)

        case .ready:
            ReadyScreen(manager: manager)

        case .tutorial:
            TutorialLauncherView(
                flowType: TutorialLauncherView.detectFlowType(for: dataController.currentUser),
                onComplete: {
                    manager.goForward() // Will call completeOnboarding()
                }
            )
            .environmentObject(dataController)
            .environmentObject(appState)
            .environmentObject(locationManager)

        case .preSignupTutorial:
            let flowType: TutorialFlowType = manager.state.flow == .employee ? .employee : .companyCreator
            TutorialLauncherView(
                flowType: flowType,
                isPreSignup: true,
                onComplete: {
                    manager.goForward() // Will go to postTutorialCTA
                }
            )
            .environmentObject(dataController)
            .environmentObject(appState)
            .environmentObject(locationManager)

        case .postTutorialCTA:
            PostTutorialCTAScreen(manager: manager)
        }
    }

    // MARK: - Loading Message

    private var loadingMessage: String {
        switch manager.state.currentScreen {
        case .login:
            return "Signing in..."
        case .credentials:
            return "Creating your account..."
        case .companySetup:
            return "Creating your company..."
        case .profileCompany:
            if manager.state.profileCompanyPhase == .processing {
                return manager.state.hasExistingCompany ? "Updating your company..." : "Creating your company..."
            }
            return "Loading..."
        case .profileJoin:
            if manager.state.profileJoinPhase == .joining {
                return "Joining company..."
            }
            return "Loading..."
        case .companyDetails:
            return "Creating your company..."
        case .codeEntry:
            return "Joining crew..."
        case .welcome, .signup, .userTypeSelection, .profile, .companyCode, .ready, .tutorial, .preSignupTutorial, .postTutorialCTA:
            return "Loading..."
        }
    }
}

// MARK: - Preview

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)
    let appState = AppState()

    OnboardingContainer(manager: manager)
        .environmentObject(dataController)
        .environmentObject(appState)
        .environmentObject(SubscriptionManager.shared)
}
