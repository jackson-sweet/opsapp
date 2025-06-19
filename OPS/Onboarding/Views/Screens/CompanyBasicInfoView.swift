//
//  CompanyBasicInfoView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-23.
//

import SwiftUI

struct CompanyBasicInfoView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @State private var currentPhase: CompanyInfoPhase = .companyName
    
    enum CompanyInfoPhase: Int, CaseIterable {
        case companyName = 0
    }
    
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return onboardingViewModel.currentStep.stepNumber(for: onboardingViewModel.selectedUserType) ?? 3
    }
    
    private var totalSteps: Int {
        guard let userType = onboardingViewModel.selectedUserType else { return 12 }
        return OnboardingStep.totalSteps(for: userType)
    }
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Navigation header with step indicator
                HStack {
                    Button(action: {
                        onboardingViewModel.moveToPreviousStep()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(OPSStyle.Typography.caption)
                            Text("Back")
                                .font(OPSStyle.Typography.body)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    
                    Spacer()
                    Spacer()
                    
                    Button(action: {
                        onboardingViewModel.logoutAndReturnToLogin()
                    }) {
                        Text("Sign Out")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding(.horizontal, 24)
                
                // Step indicator bars
                HStack(spacing: 4) {
                    ForEach(0..<totalSteps) { step in
                        Rectangle()
                            .fill(step < currentStepNumber ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText.opacity(0.4))
                            .frame(height: 4)
                    }
                }
                .padding(.bottom, 16)
                .padding(.horizontal, 24)
                
                // Main content area - top-justified
                VStack(spacing: 0) {
                    // Phase content
                    Group {
                        switch currentPhase {
                        case .companyName:
                            CompanyNamePhaseView(
                                companyName: $onboardingViewModel.companyName,
                                viewModel: onboardingViewModel,
                                onContinue: {
                                    onboardingViewModel.moveToNextStep()
                                }
                            )
                        }
                    }
                    .transition(.opacity)
                    .padding(.horizontal, 24)
                    .padding(.top, 40) // Add consistent top padding
                    
                    Spacer()
                }
            }
        }
        .dismissKeyboardOnTap()
    }
}

// MARK: - Phase Views

struct CompanyNamePhaseView: View {
    @Binding var companyName: String
    @ObservedObject var viewModel: OnboardingViewModel
    let onContinue: () -> Void
    
    private var isFormValid: Bool {
        !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("LET'S START WITH YOUR")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(.white)
                
                Text("COMPANY NAME.")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(.white)
                    .padding(.bottom, 12)
                
                Text("This information will be visible to your team members and helps identify your company.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Company Name Field
            UnderlineTextField(
                placeholder: "Company name",
                text: $companyName,
                autocapitalization: .words,
                viewModel: viewModel
            )
        }
        
        Spacer()
        
        // Continue button
        VStack {
            StandardContinueButton(
                isDisabled: !isFormValid,
                onTap: onContinue
            )
        }
    }
}


#Preview {
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    CompanyBasicInfoView()
        .environmentObject(OnboardingViewModel())
        .environmentObject(dataController)
        .preferredColorScheme(.dark)
}