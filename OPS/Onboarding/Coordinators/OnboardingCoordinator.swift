//
//  OnboardingCoordinator.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import Foundation
import SwiftUI
import Combine

class OnboardingCoordinator: ObservableObject {
    @Published var viewModel = OnboardingViewModel()
    @Published var isOnboardingComplete = false
    
    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        print("OnboardingCoordinator initialized with currentStep: \(viewModel.currentStep.title)")
        
        // Subscribe to completion state
        viewModel.$currentStep
            .sink { [weak self] step in
                print("Step changed to: \(step.title)")
                if step == .completion {
                    // When we reach completion, flag for potential automatic transition
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self?.checkForAutomaticCompletion()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // Check if onboarding has already been completed
    func checkOnboardingStatus() {
        if userDefaults.bool(forKey: "onboarding_completed") {
            isOnboardingComplete = true
        }
    }
    
    // Check if we should automatically complete onboarding after delay
    private func checkForAutomaticCompletion() {
        if viewModel.currentStep == .completion {
            completeOnboarding()
        }
    }
    
    // Complete onboarding and store user information
    func completeOnboarding() {
        print("OnboardingCoordinator: Completing onboarding")
        
        // Save onboarding completion status
        userDefaults.set(true, forKey: "onboarding_completed")
        
        // User ID is now stored by the ViewModel directly in UserDefaults
        // during the sign-up and join-company processes
        
        // Phone number is already stored during the signup process
        // Make sure we have consistent naming of keys
        if !viewModel.phoneNumber.isEmpty {
            userDefaults.set(viewModel.phoneNumber, forKey: "user_phone_number")
        }
        
        // Save email for reference
        if !viewModel.email.isEmpty {
            userDefaults.set(viewModel.email, forKey: "user_email")
        }
        
        // Save first and last name
        if !viewModel.firstName.isEmpty {
            userDefaults.set(viewModel.firstName, forKey: "user_first_name")
        }
        
        if !viewModel.lastName.isEmpty {
            userDefaults.set(viewModel.lastName, forKey: "user_last_name")
        }
        
        // Mark as complete to trigger navigation
        isOnboardingComplete = true
    }
    
    // Reset onboarding (for testing or logout)
    func resetOnboarding() {
        userDefaults.set(false, forKey: "onboarding_completed")
        userDefaults.removeObject(forKey: "user_id")
        userDefaults.removeObject(forKey: "user_phone")
        userDefaults.removeObject(forKey: "user_phone_number") // New key for phone
        userDefaults.removeObject(forKey: "user_email")
        userDefaults.removeObject(forKey: "user_password") // Added for resetting password
        userDefaults.removeObject(forKey: "user_first_name") // Added for first name
        userDefaults.removeObject(forKey: "user_last_name") // Added for last name
        userDefaults.removeObject(forKey: "company_code") // Added for company
        userDefaults.removeObject(forKey: "company_name") // Added for company
        userDefaults.removeObject(forKey: "company_id") // Added for company
        userDefaults.removeObject(forKey: "location_permission_granted") // Added for permissions
        userDefaults.removeObject(forKey: "notifications_permission_granted") // Added for permissions
        
        viewModel = OnboardingViewModel()
        isOnboardingComplete = false
    }
}