//
//  OnboardingContainerView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI
import SwiftData

/// Main container view for the onboarding flow
struct OnboardingView: View {
    // Use StateObject to create the view model
    @StateObject private var viewModel: OnboardingViewModel
    @EnvironmentObject private var dataController: DataController
    
    // Optional completion handler
    var onComplete: (() -> Void)?
    // Always use the consolidated flow
    private let useConsolidatedFlow = true
    
    init(initialStep: OnboardingStep = .welcome, onComplete: (() -> Void)? = nil) {
        // Initialize the view model with the specified step
        let vm = OnboardingViewModel()
        vm.currentStep = initialStep
        
        // Use underscore to initialize the @StateObject
        _viewModel = StateObject(wrappedValue: vm)
        self.onComplete = onComplete
    }
    
    // When the view appears, set the DataController reference
    // This allows SwiftData access throughout the onboarding flow
    func configureViewModel() {
        if viewModel.dataController == nil {
            viewModel.dataController = dataController
        }
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Consolidated flow
            consolidatedFlowView
        }
        .onAppear {
            // Configure ViewModel with DataController
            configureViewModel()
        }
        .animation(.easeInOut, value: viewModel.currentStep.rawValue)
    }
    
    
    // Main onboarding flow view
    private var consolidatedFlowView: some View {
        VStack(spacing: 0) {
            // Current step view
            Group {
                switch viewModel.currentStep {
                case .welcome:
                    WelcomeView(viewModel: viewModel)
                case .userTypeSelection:
                    UserTypeSelectionView()
                        .environmentObject(viewModel)
                case .accountSetup:
                    // Use existing EmailView but configured for consolidated flow
                    EmailView(viewModel: viewModel, isInConsolidatedFlow: true)
                case .organizationJoin:
                    // New organization join view in consolidated flow
                    OrganizationJoinView(viewModel: viewModel, isInConsolidatedFlow: true)
                case .userDetails:
                    // Use existing UserInfoView but configured for consolidated flow
                    UserInfoView(viewModel: viewModel, isInConsolidatedFlow: false)
                case .companyCode:
                    // Show different view based on user type
                    if viewModel.selectedUserType == .employee {
                        CompanyCodeInputView(viewModel: viewModel)
                    } else {
                        CompanyCodeDisplayView(viewModel: viewModel)
                    }
                case .companyBasicInfo:
                    CompanyBasicInfoView(isInConsolidatedFlow: true)
                        .environmentObject(viewModel)
                case .companyAddress:
                    CompanyAddressView(isInConsolidatedFlow: true)
                        .environmentObject(viewModel)
                case .companyContact:
                    CompanyContactView()
                        .environmentObject(viewModel)
                case .companyDetails:
                    CompanyDetailsView()
                        .environmentObject(viewModel)
                case .teamInvites:
                    TeamInvitesView()
                        .environmentObject(viewModel)
                case .welcomeGuide:
                    WelcomeGuideView()
                        .environmentObject(viewModel)
                case .permissions:
                    // Use existing PermissionsView but configured for consolidated flow
                    PermissionsView(viewModel: viewModel, isInConsolidatedFlow: true)
                case .fieldSetup:
                    // The field setup is genuinely new functionality
                    FieldSetupView(viewModel: viewModel)
                        .environmentObject(dataController)
                case .completion:
                    CompleteOnboarding()
                        .environmentObject(viewModel)
                }
            }
            .id("step_\(viewModel.currentStep.rawValue)")
            .transition(.opacity)
        }
    }
    
    // Extracted completion logic to avoid code duplication
    @ViewBuilder
    private func CompleteOnboarding() -> some View {
        CompletionView {
            // This onComplete callback is actually not used anymore
            // The CompletionView calls onboardingViewModel.nextStep() directly
            // which transitions to WelcomeGuideView
            print("CompleteOnboarding: onComplete callback called (this shouldn't happen)")
        }
        .environmentObject(viewModel)
        .onAppear {
            // Save user data when completion view appears
            // The actual completion happens after welcome guide
            
            // Flag indicating user has a company (required to enter app)
            let hasCompany = !viewModel.companyName.isEmpty || 
                UserDefaults.standard.string(forKey: "Company Name") != nil ||
                UserDefaults.standard.string(forKey: "company_id") != nil
            
            UserDefaults.standard.set(hasCompany, forKey: "has_joined_company")
            
            // Create or update user in database (but don't set authentication yet)
            Task {
                // Create a user object with the collected onboarding data
                let userIdValue = UserDefaults.standard.string(forKey: "user_id") ?? viewModel.userId
                let companyId = UserDefaults.standard.string(forKey: "company_id")
                
                if !userIdValue.isEmpty, let modelContext = dataController.modelContext {
                    // Check if user already exists
                    let descriptor = FetchDescriptor<User>(
                        predicate: #Predicate<User> { $0.id == userIdValue }
                    )
                    let existingUsers = try? modelContext.fetch(descriptor)
                    
                    var user: User
                    
                    if let existingUser = existingUsers?.first {
                        // Update existing user
                        user = existingUser
                        user.firstName = viewModel.firstName
                        user.lastName = viewModel.lastName
                        user.email = viewModel.email
                        user.phone = viewModel.phoneNumber
                        user.companyId = companyId
                        print("Updating existing user: \(user.fullName)")
                    } else {
                        // Create new user
                        user = User(
                            id: userIdValue,
                            firstName: viewModel.firstName,
                            lastName: viewModel.lastName,
                            role: .fieldCrew, companyId: companyId ?? ""  // Default role
                        )
                        user.email = viewModel.email
                        user.phone = viewModel.phoneNumber
                        
                        // Insert new user
                        modelContext.insert(user)
                        print("Creating new user: \(user.fullName)")
                    }
                    
                    // Save changes
                    await MainActor.run {
                        do {
                            try modelContext.save()
                            print("User data saved to database: \(user.fullName)")
                            
                            // Set current user in DataController
                            dataController.currentUser = user
                            
                            // Don't set authentication yet - wait for welcome guide
                        } catch {
                            print("Error saving user to database: \(error.localizedDescription)")
                        }
                    }
                }
            }
            
            // Ensure we have all user data stored
            if UserDefaults.standard.string(forKey: "user_email") == nil {
                UserDefaults.standard.set(viewModel.email, forKey: "user_email")
            }
            
            // Store onboarding step progress (for resuming if needed)
            UserDefaults.standard.set(viewModel.currentStep.rawValue, forKey: "last_onboarding_step_v2")
            
            // Save basic user preference settings
            UserDefaults.standard.set(viewModel.isLocationPermissionGranted, forKey: "location_permission_granted")
            UserDefaults.standard.set(viewModel.isNotificationsPermissionGranted, forKey: "notifications_permission_granted")
            
            print("OnboardingView: Completion step reached, user data saved")
            print("OnboardingView: User has company: \(hasCompany)")
            
            // Don't call onComplete yet - wait for welcome guide to finish
        }
    }
}

// MARK: - Preview
#Preview("Onboarding Flow") {
    let previewHelper = OnboardingPreviewHelpers.PreviewStyles()
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    OnboardingView(initialStep: .welcome)
        .environmentObject(previewHelper)
        .environmentObject(dataController)
        .environment(\.colorScheme, .dark)
}

#Preview("Welcome Screen") {
    let previewHelper = OnboardingPreviewHelpers.PreviewStyles()
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    OnboardingView(initialStep: .welcome)
        .environmentObject(previewHelper)
        .environmentObject(dataController)
        .environment(\.colorScheme, .dark)
}

#Preview("Account Setup Screen") {
    let previewHelper = OnboardingPreviewHelpers.PreviewStyles()
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    OnboardingView(initialStep: .accountSetup)
        .environmentObject(previewHelper)
        .environmentObject(dataController)
        .environment(\.colorScheme, .dark)
}

#Preview("Completion Screen") {
    let previewHelper = OnboardingPreviewHelpers.PreviewStyles()
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    OnboardingView(initialStep: .completion)
        .environmentObject(previewHelper)
        .environmentObject(dataController)
        .environment(\.colorScheme, .dark)
}
