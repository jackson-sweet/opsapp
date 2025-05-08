//
//  OnboardingContainerView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI

/// Main container view for the onboarding flow
struct OnboardingView: View {
    // Use StateObject to create the view model
    @StateObject private var viewModel: OnboardingViewModel
    @EnvironmentObject private var dataController: DataController
    
    // Optional completion handler
    var onComplete: (() -> Void)?
    private let useConsolidatedFlow = AppConfiguration.UX.useConsolidatedOnboardingFlow
    
    init(initialStep: OnboardingStep = .welcome, consolidatedStep: OnboardingStepV2 = .welcome, onComplete: (() -> Void)? = nil) {
        // Initialize the view model with the specified step
        let vm = OnboardingViewModel()
        vm.currentStep = initialStep
        vm.currentStepV2 = consolidatedStep
        
        // Use underscore to initialize the @StateObject
        _viewModel = StateObject(wrappedValue: vm)
        self.onComplete = onComplete
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.black.edgesIgnoringSafeArea(.all)
            
            if useConsolidatedFlow {
                // Consolidated flow (V2)
                consolidatedFlowView
            } else {
                // Original flow
                originalFlowView
            }
        }
        .animation(.easeInOut, value: useConsolidatedFlow ? viewModel.currentStepV2.rawValue : viewModel.currentStep.rawValue)
    }
    
    // Original 11-step flow
    private var originalFlowView: some View {
        VStack(spacing: 0) {
            // Only show progress indicator for appropriate steps
            if viewModel.currentStep != .welcome && viewModel.currentStep != .completion {
                OnboardingProgressIndicator(currentStep: viewModel.currentStep)
                    .padding(.bottom, 4)
            }
            
            // Current step view - use ID to force recreation
            Group {
                switch viewModel.currentStep {
                case .welcome:
                    WelcomeView(viewModel: viewModel)
                case .email:
                    EmailView(viewModel: viewModel)
                case .password:
                    PasswordView(viewModel: viewModel)
                case .accountCreated:
                    AccountCreatedView(viewModel: viewModel)
                case .organizationJoin:
                    OrganizationJoinView(viewModel: viewModel)
                case .userInfo:
                    UserInfoView(viewModel: viewModel)
                case .phoneNumber:
                    PhoneNumberView(viewModel: viewModel)
                case .companyCode:
                    CompanyCodeView(viewModel: viewModel)
                case .welcomeCompany:
                    WelcomeCompanyView(viewModel: viewModel)
                case .permissions:
                    PermissionsView(viewModel: viewModel)
                case .notifications:
                    NotificationsView(viewModel: viewModel)
                case .completion:
                    CompleteOnboarding()
                }
            }
            .id("step_\(viewModel.currentStep.rawValue)") // Force recreation on step change
            .transition(.opacity)
        }
    }
    
    // Consolidated 7-step flow
    private var consolidatedFlowView: some View {
        VStack(spacing: 0) {
            // Current step view
            Group {
                switch viewModel.currentStepV2 {
                case .welcome:
                    WelcomeView(viewModel: viewModel)
                        .onReceive(viewModel.$currentStep) { _ in
                            // Handle legacy step changes
                            if viewModel.currentStep == .email {
                                viewModel.moveToV2(step: .accountSetup)
                            }
                        }
                case .accountSetup:
                    // Use existing EmailView but configured for consolidated flow
                    EmailView(viewModel: viewModel, isInConsolidatedFlow: true)
                case .organizationJoin:
                    // New organization join view in consolidated flow
                    OrganizationJoinView(viewModel: viewModel, isInConsolidatedFlow: true)
                case .userDetails:
                    // Use existing UserInfoView but configured for consolidated flow
                    UserInfoView(viewModel: viewModel, isInConsolidatedFlow: true)
                case .companyCode:
                    CompanyCodeView(viewModel: viewModel)
                        .onReceive(viewModel.$currentStep) { newStep in
                            // Handle legacy step changes
                            if newStep == .userInfo || newStep == .phoneNumber {
                                viewModel.moveToV2(step: .userDetails)
                            } else if newStep == .welcomeCompany || newStep == .permissions {
                                viewModel.moveToV2(step: .permissions)
                            }
                        }
                case .permissions:
                    // Use existing PermissionsView but configured for consolidated flow
                    PermissionsView(viewModel: viewModel, isInConsolidatedFlow: true)
                case .fieldSetup:
                    // The field setup is genuinely new functionality
                    FieldSetupView(viewModel: viewModel)
                        .environmentObject(dataController)
                case .completion:
                    CompleteOnboarding()
                }
            }
            .id("v2_step_\(viewModel.currentStepV2.rawValue)")
            .transition(.opacity)
        }
    }
    
    // Extracted completion logic to avoid code duplication
    @ViewBuilder
    private func CompleteOnboarding() -> some View {
        CompletionView {
            // Save all relevant user data upon completion
            UserDefaults.standard.set(true, forKey: "onboarding_completed")
            
            // Flag indicating user has a company (required to enter app)
            let hasCompany = !viewModel.companyName.isEmpty || 
                UserDefaults.standard.string(forKey: "Company Name") != nil ||
                UserDefaults.standard.string(forKey: "company_id") != nil
            
            UserDefaults.standard.set(hasCompany, forKey: "has_joined_company")
            
            // CRITICAL: Set authentication flag that determines app entry
            UserDefaults.standard.set(true, forKey: "is_authenticated")
            
            // Ensure we have all user data stored
            if UserDefaults.standard.string(forKey: "user_email") == nil {
                UserDefaults.standard.set(viewModel.email, forKey: "user_email")
            }
            
            // Store onboarding step progress (for resuming if needed)
            if useConsolidatedFlow {
                UserDefaults.standard.set(viewModel.currentStepV2.rawValue, forKey: "last_onboarding_step_v2")
            } else {
                UserDefaults.standard.set(viewModel.currentStep.rawValue, forKey: "last_onboarding_step")
            }
            
            // Save basic user preference settings
            UserDefaults.standard.set(viewModel.isLocationPermissionGranted, forKey: "location_permission_granted")
            UserDefaults.standard.set(viewModel.isNotificationsPermissionGranted, forKey: "notifications_permission_granted")
            
            print("OnboardingView: Onboarding completed successfully!")
            print("OnboardingView: User has company: \(hasCompany)")
            print("OnboardingView: Set is_authenticated = true to enable app entry")
            
            // Call the completion handler - the user will be directed to main app
            if let onComplete = onComplete {
                onComplete()
            }
        }
    }
}

// MARK: - Preview
#Preview("Onboarding Flow") {
    let previewHelper = OnboardingPreviewHelpers.PreviewStyles()
    
    return OnboardingView(initialStep: .welcome)
        .environmentObject(previewHelper)
        .environment(\.colorScheme, .dark)
}

#Preview("Welcome Screen") {
    let previewHelper = OnboardingPreviewHelpers.PreviewStyles()
    
    return OnboardingView(initialStep: .welcome)
        .environmentObject(previewHelper)
        .environment(\.colorScheme, .dark)
}

#Preview("Email Screen") {
    let previewHelper = OnboardingPreviewHelpers.PreviewStyles()
    
    return OnboardingView(initialStep: .email)
        .environmentObject(previewHelper)
        .environment(\.colorScheme, .dark)
}

#Preview("Completion Screen") {
    let previewHelper = OnboardingPreviewHelpers.PreviewStyles()
    
    return OnboardingView(initialStep: .completion)
        .environmentObject(previewHelper)
        .environment(\.colorScheme, .dark)
}
