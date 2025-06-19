//
//  FieldSetupView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI
import SwiftData

struct FieldSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @EnvironmentObject private var dataController: DataController
    
    @State private var selectedStorageIndex: Int = 3 // Default to 500MB
    @State private var isLoading = false
    
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 6
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 7 }
        return OnboardingStep.totalSteps(for: userType)
    }
    
    var body: some View {
        ZStack {
            // Background color - conditional theming
            (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.background : OPSStyle.Colors.background)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Navigation header with step indicator
                HStack {
                    Button(action: {
                        viewModel.moveToPreviousStep()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(OPSStyle.Typography.caption)
                            Text("Back")
                                .font(OPSStyle.Typography.body)
                        }
                        .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryAccent : OPSStyle.Colors.primaryAccent)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.logoutAndReturnToLogin()
                    }) {
                        Text("Sign Out")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding(.horizontal, 24)
                
                // Step indicator bars
                HStack(spacing: 4) {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Rectangle()
                            .fill(step < currentStepNumber ? 
                                (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryAccent : OPSStyle.Colors.primaryAccent) : 
                                (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText.opacity(0.4) : OPSStyle.Colors.secondaryText.opacity(0.4)))
                            .frame(height: 4)
                    }
                }
                .padding(.bottom, 16)
                .padding(.horizontal, 24)
                
                // Main content area wrapped in ScrollView
                ScrollView {
                    VStack(spacing: 0) {
                        // Header
                        OnboardingHeaderView(
                            title: "FIELD SETUP",
                            subtitle: "Customize how OPS should work when you're on job sites with limited connectivity.",
                            isLightTheme: viewModel.shouldUseLightTheme
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 30)
                        
                        // Field settings
                        VStack(spacing: 24) {
                            // Offline data settings with storage slider
                            SettingsSection(
                                title: "Offline Storage",
                                description: "Choose how much data to store for offline use when connectivity is limited"
                            ) {
                                StorageOptionSlider(selectedStorageIndex: $selectedStorageIndex)
                                    .environmentObject(viewModel)
                            }
                            .environmentObject(viewModel)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40) // Add bottom padding to prevent cutoff
                    }
                    .padding(.top, 40) // Add consistent top padding
                }
                
                Spacer(minLength: 0)
                
                // Continue button
                StandardContinueButton(
                    isLoading: isLoading,
                    onTap: {
                        applySettings()
                    }
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
    }
    
    // Apply settings and move to next step
    private func applySettings() {
        isLoading = true
        
        // Save offline storage settings based on slider selection
        let storageValues = [0, 100, 250, 500, 1000, 5000, -1] // -1 for unlimited
        let storageMB = storageValues[selectedStorageIndex]
        
        UserDefaults.standard.set(storageMB, forKey: "offlineStorageLimitMB")
        
        // Set cache behavior based on storage selection
        if selectedStorageIndex == 0 {
            // No storage
            UserDefaults.standard.set(false, forKey: "cacheImages")
            UserDefaults.standard.set(false, forKey: "cacheProjectData")
        } else if selectedStorageIndex == 6 {
            // Unlimited
            UserDefaults.standard.set(true, forKey: "cacheImages")
            UserDefaults.standard.set(true, forKey: "cacheProjectData")
            UserDefaults.standard.set(-1, forKey: "offlineStorageLimitMB")
        } else {
            // Limited storage
            UserDefaults.standard.set(true, forKey: "cacheImages")
            UserDefaults.standard.set(true, forKey: "cacheProjectData")
        }
        
        // Simulate a brief loading period
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isLoading = false
            viewModel.moveToNextStep()
        }
    }
}

// MARK: - Helper Components

struct SettingsSection<Content: View>: View {
    var title: String
    var description: String
    @ViewBuilder var content: Content
    @EnvironmentObject var viewModel: OnboardingViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(OPSStyle.Typography.cardSubtitle)
                .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : .white)
            
            Text(description)
                .font(OPSStyle.Typography.cardBody)
                .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : Color.gray)
                .padding(.bottom, 4)
            
            content
        }
        .padding()
        .background(viewModel.shouldUseLightTheme ? Color.white : OPSStyle.Colors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(viewModel.shouldUseLightTheme ? OPSStyle.Colors.cardBackground : Color.clear, lineWidth: 1)
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

// MARK: - Preview
#Preview("Field Setup View") {
    let viewModel = OnboardingViewModel()
    let dataController = DataController()
    
    return FieldSetupView(viewModel: viewModel)
        .environmentObject(dataController)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}
