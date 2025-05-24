//
//  CompanyBasicInfoView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-23.
//

import SwiftUI

struct CompanyBasicInfoView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    
    private var isFormValid: Bool {
        !onboardingViewModel.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Navigation header with step indicator
                HStack {
                    Button(action: {
                        onboardingViewModel.previousStep()
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
                    
                    Text("Step 1 of 6")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding(.horizontal, 24)
                
                // Step indicator bars
                HStack(spacing: 4) {
                    ForEach(0..<6) { step in
                        Rectangle()
                            .fill(step < 1 ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText.opacity(0.4))
                            .frame(height: 4)
                    }
                }
                .padding(.bottom, 16)
                .padding(.horizontal, 24)
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Let's start with your")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(.white)
                            
                            Text("company basics.")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(.white)
                                .padding(.bottom, 12)
                            
                            Text("This information will be visible to your team members and helps identify your company.")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .lineSpacing(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(spacing: 24) {
                            // Company Name Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("COMPANY NAME")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                TextField("Enter your company name", text: $onboardingViewModel.companyName)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(.white)
                                    .textContentType(.organizationName)
                                    .disableAutocorrection(true)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(OPSStyle.Colors.cardBackground)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            
                            // Company Logo Placeholder
                            VStack(alignment: .leading, spacing: 8) {
                                Text("COMPANY LOGO")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                VStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 2)
                                        .fill(OPSStyle.Colors.cardBackground)
                                        .frame(height: 120)
                                        .overlay(
                                            VStack(spacing: 8) {
                                                Image(systemName: "photo")
                                                    .font(OPSStyle.Typography.title)
                                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                                
                                                Text("Logo upload coming soon")
                                                    .font(OPSStyle.Typography.caption)
                                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                            }
                                        )
                                    
                                    Text("Your company logo will be added to projects and communications. This feature will be available soon.")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.8))
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                        
                        // Error message
                        if !onboardingViewModel.errorMessage.isEmpty {
                            Text(onboardingViewModel.errorMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                        
                        Spacer()
                        
                        // Continue button
                        Button(action: {
                            if isFormValid {
                                onboardingViewModel.nextStep()
                            } else {
                                onboardingViewModel.errorMessage = "Please enter your company name to continue"
                            }
                        }) {
                            Text("Continue")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(isFormValid ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackground)
                                .cornerRadius(12)
                        }
                        .disabled(!isFormValid)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                }
            }
        }
    }
}

#Preview {
    CompanyBasicInfoView()
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.dark)
}