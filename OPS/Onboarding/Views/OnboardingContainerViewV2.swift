//
//  OnboardingContainerViewV2.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import SwiftUI
import SwiftData

/// Main container view for the onboarding flow (consolidated 7-step version)
struct OnboardingView: View {
    // Use StateObject to create the view model
    @StateObject private var viewModel: OnboardingViewModel
    @EnvironmentObject private var dataController: DataController
    
    // Optional completion handler
    var onComplete: (() -> Void)?
    
    init(initialStep: OnboardingStepV2 = .welcome, onComplete: (() -> Void)? = nil) {
        // Initialize the view model with the specified step
        let vm = OnboardingViewModel()
        vm.currentStepV2 = initialStep
        
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
            
            // Consolidated 7-step flow
            VStack(spacing: 0) {
                // Current step view
                Group {
                    switch viewModel.currentStepV2 {
                    case .welcome:
                        WelcomeView(viewModel: viewModel)
                    case .accountSetup:
                        // Use the new consolidated account setup view
                        AccountSetupView(viewModel: viewModel)
                    case .organizationJoin:
                        // Organization join view
                        OrganizationJoinView(viewModel: viewModel, isInConsolidatedFlow: true)
                    case .userDetails:
                        // Use the new consolidated user details view
                        UserDetailsView(viewModel: viewModel)
                    case .companyCode:
                        CompanyCodeView(viewModel: viewModel)
                    case .permissions:
                        // Use the new consolidated permissions view
                        ConsolidatedPermissionsView(viewModel: viewModel)
                    case .fieldSetup:
                        // The field setup is genuinely new functionality
                        FieldSetupView(viewModel: viewModel)
                            .environmentObject(dataController)
                    case .completion:
                        CompleteOnboarding()
                    }
                }
                .id("step_\(viewModel.currentStepV2.rawValue)")
                .transition(.opacity)
            }
        }
        .onAppear {
            // Configure ViewModel with DataController
            configureViewModel()
        }
        .animation(.easeInOut, value: viewModel.currentStepV2.rawValue)
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
            
            // Create or update user in database
            Task {
                // Create a user object with the collected onboarding data
                let userIdValue = UserDefaults.standard.string(forKey: "user_id") ?? viewModel.userId ?? ""
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
                            
                            // Force update the DataController authentication state
                            dataController.isAuthenticated = true
                        } catch {
                            print("Error saving user to database: \(error.localizedDescription)")
                        }
                    }
                } else {
                    // If we don't have user ID, just set auth flag
                    await MainActor.run {
                        dataController.isAuthenticated = true
                    }
                }
            }
            
            // Ensure we have all user data stored
            if UserDefaults.standard.string(forKey: "user_email") == nil {
                UserDefaults.standard.set(viewModel.email, forKey: "user_email")
            }
            
            // Store onboarding step progress (for resuming if needed)
            UserDefaults.standard.set(viewModel.currentStepV2.rawValue, forKey: "last_onboarding_step_v2")
            
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

#Preview("Completion Screen") {
    let previewHelper = OnboardingPreviewHelpers.PreviewStyles()
    
    return OnboardingView(initialStep: .completion)
        .environmentObject(previewHelper)
        .environment(\.colorScheme, .dark)
}