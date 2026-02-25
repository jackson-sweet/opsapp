//
//  CompanyCodeView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI
import Combine
import SwiftData
import Foundation

struct CompanyCodeDisplayView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var showCopyFeedback = false
    
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 7
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 12 }
        return OnboardingStep.totalSteps(for: userType)
    }
    
    // Color scheme based on user type
    private var backgroundColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.background : OPSStyle.Colors.background
    }
    
    private var primaryTextColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText
    }
    
    private var secondaryTextColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText
    }
    
    var body: some View {
        ZStack {
            // Background color
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Navigation header with step indicator
                HStack {
                    Button(action: {
                        viewModel.moveToPreviousStep()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(OPSStyle.Typography.button)
                            Text("Back")
                                .font(OPSStyle.Typography.button)
                        }
                        .foregroundColor(secondaryTextColor)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.logoutAndReturnToLogin()
                    }) {
                        Text("Cancel")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(secondaryTextColor)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

                // Step indicator bars
                HStack(spacing: 4) {
                    ForEach(0..<totalSteps) { step in
                        Rectangle()
                            .fill(step < currentStepNumber ? primaryTextColor : secondaryTextColor.opacity(0.3))
                            .frame(height: 2)
                    }
                }
                .padding(.bottom, 16)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                
                // Main content
                ScrollView {
                    VStack(spacing: 32) {
                        // Header
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Your Company Code")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(primaryTextColor)
                            
                            Text("Share this with your crew to join \(viewModel.companyName) on OPS.")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(secondaryTextColor)
                                .lineSpacing(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Company code display
                        VStack(spacing: 24) {
                            // Label row with copy button inline, right aligned
                            HStack {
                                Text("COMPANY CODE")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(secondaryTextColor)

                                Spacer()

                                if !getCompanyCode().isEmpty && getCompanyCode() != "CODE_NOT_FOUND" {
                                    Button(action: {
                                        UIPasteboard.general.string = getCompanyCode()
                                        withAnimation(OPSStyle.Animation.fast) {
                                            showCopyFeedback = true
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            withAnimation(OPSStyle.Animation.fast) {
                                                showCopyFeedback = false
                                            }
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: showCopyFeedback ? "checkmark" : "doc.on.doc")
                                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                            Text(showCopyFeedback ? "COPIED!" : "COPY")
                                                .font(OPSStyle.Typography.smallCaption)
                                        }
                                        .foregroundColor(showCopyFeedback ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent)
                                    }
                                }
                            }

                            // Code display box
                            HStack {
                                Text(getCompanyCode().uppercased())
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(primaryTextColor)
                                    .tracking(2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)

                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                            
                            Spacer()
                            
                            // Info section
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: OPSStyle.Icons.info)
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                        .font(OPSStyle.Typography.body)
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("HOW IT WORKS")
                                            .font(OPSStyle.Typography.cardSubtitle)
                                            .foregroundColor(primaryTextColor)
                                        
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Your crew uses this code to join your company.")
                                        }
                                        .font(OPSStyle.Typography.cardBody)
                                        .foregroundColor(secondaryTextColor)
                                    }
                                }
                                
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "shield")
                                        .foregroundColor(OPSStyle.Colors.successStatus)
                                        .font(OPSStyle.Typography.body)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Keep it secure".uppercased())
                                            .font(OPSStyle.Typography.cardSubtitle)
                                            .fontWeight(.semibold)
                                            .foregroundColor(primaryTextColor)

                                        Text("Only share with crew you trust.")
                                            .font(OPSStyle.Typography.cardBody)
                                            .foregroundColor(secondaryTextColor)
                                    }
                                }
                            }
                            .padding(OPSStyle.Layout.spacing3)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .fill(OPSStyle.Colors.primaryAccent.opacity(0.1))
                            )
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.bottom, 120)
                }
                
                // Bottom button
                VStack(spacing: 16) {
                    StandardContinueButton(
                        isDisabled: false,
                        isLoading: false,
                        onTap: {
                            viewModel.moveToNextStep()
                        }
                    )
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, 34)
                .background(
                    Rectangle()
                        .fill(backgroundColor)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -4)
                )
            }
        }
        .onAppear {
            
            // If we don't have a company code yet, it should have been set when creating the company
            if viewModel.companyCode.isEmpty {
                // Try to load from UserDefaults
                if let savedCode = UserDefaults.standard.string(forKey: "company_code"), !savedCode.isEmpty {
                    viewModel.companyCode = savedCode
                } else if let companyId = UserDefaults.standard.string(forKey: "company_id"), !companyId.isEmpty {
                    // Fallback to company ID if no code exists
                    viewModel.companyCode = companyId
                } else {
                }
            }
        }
    }
    
    private func getCompanyCode() -> String {
        // Debug logging
        
        // First check if we have the company code in viewModel
        if !viewModel.companyCode.isEmpty {
            return viewModel.companyCode
        }
        
        // Check UserDefaults for company_code
        if let savedCode = UserDefaults.standard.string(forKey: "company_code"), !savedCode.isEmpty {
            return savedCode
        }
        
        // Otherwise, use the company ID as fallback
        if let companyId = UserDefaults.standard.string(forKey: "company_id"), !companyId.isEmpty {
            return companyId
        }
        
        // If neither is available, return error message
        return "CODE_NOT_FOUND"
    }
}

// MARK: - Preview
#Preview("Company Code Display") {
    let viewModel = OnboardingViewModel()
    viewModel.companyName = "Demo Construction Inc."
    viewModel.companyCode = "DEMO123"
    
    return CompanyCodeDisplayView(viewModel: viewModel)
        .environment(\.colorScheme, .dark)
}

#Preview("Company Code Loading") {
    let viewModel = OnboardingViewModel()
    viewModel.companyName = "Demo Construction Inc."
    viewModel.companyCode = ""
    
    return CompanyCodeDisplayView(viewModel: viewModel)
        .environment(\.colorScheme, .dark)
}
