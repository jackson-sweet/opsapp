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
                                .font(OPSStyle.Typography.caption)
                            Text("Back")
                                .font(OPSStyle.Typography.body)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.logoutAndReturnToLogin()
                    }) {
                        Text("Sign Out")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(secondaryTextColor)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding(.horizontal, 24)
                
                // Step indicator bars
                HStack(spacing: 4) {
                    ForEach(0..<totalSteps) { step in
                        Rectangle()
                            .fill(step < currentStepNumber ? OPSStyle.Colors.primaryAccent : secondaryTextColor.opacity(0.4))
                            .frame(height: 4)
                    }
                }
                .padding(.bottom, 16)
                .padding(.horizontal, 24)
                
                // Main content
                ScrollView {
                    VStack(spacing: 32) {
                        // Header
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Your Company Code")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(primaryTextColor)
                            
                            Text("Share this code with your employees so they can join \(viewModel.companyName) on OPS.")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(secondaryTextColor)
                                .lineSpacing(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Company code display
                        VStack(spacing: 24) {
                            // Code display box
                            ZStack {
                                VStack(spacing: 16) {
                                    HStack(alignment: .center){
                                        Text("[")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(primaryTextColor)
                                            .tracking(2)
                                        
                                        Text("\(getCompanyCode())")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(primaryTextColor)
                                            .tracking(2)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                        
                                        Text("]")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(primaryTextColor)
                                            .tracking(2)
                                    }
                                    .padding(.vertical, 24)
                                    .padding(.horizontal, 16)
                                    
                                    // Copy button
                                    Button(action: {
                                        UIPasteboard.general.string = getCompanyCode()
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showCopyFeedback = true
                                        }
                                        
                                        // Hide feedback after 2 seconds
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                showCopyFeedback = false
                                            }
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: showCopyFeedback ? "checkmark" : "doc.on.doc")
                                                .font(OPSStyle.Typography.body)
                                            Text(showCopyFeedback ? "Copied!".uppercased() : "Copy Code".uppercased())
                                                .font(OPSStyle.Typography.bodyBold)
                                        }
                                        .foregroundColor(showCopyFeedback ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(showCopyFeedback ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                        )
                                    }
                                    .opacity(getCompanyCode().isEmpty || getCompanyCode() == "CODE_NOT_FOUND" ? 0.5 : 1)
                                    .disabled(getCompanyCode().isEmpty || getCompanyCode() == "CODE_NOT_FOUND")
                                }
                            }
                            
                            Spacer()
                            
                            // Info section
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                        .font(OPSStyle.Typography.body)
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("HOW IT WORKS")
                                            .font(OPSStyle.Typography.cardSubtitle)
                                            .foregroundColor(primaryTextColor)
                                        
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Your employees will use this code to register with your company.")
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
                                        Text("Keep this code secure".uppercased())
                                            .font(OPSStyle.Typography.cardSubtitle)
                                            .fontWeight(.semibold)
                                            .foregroundColor(primaryTextColor)
                                        
                                        Text("Only share with employees you want to have access to your company's projects and data.")
                                            .font(OPSStyle.Typography.cardBody)
                                            .foregroundColor(secondaryTextColor)
                                    }
                                }
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(OPSStyle.Colors.primaryAccent.opacity(0.1))
                            )
                        }
                    }
                    .padding(.horizontal, 24)
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
                .padding(.horizontal, 24)
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
