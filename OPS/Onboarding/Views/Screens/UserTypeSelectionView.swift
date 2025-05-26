//
//  UserTypeSelectionView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-23.
//

import SwiftUI

struct UserTypeSelectionView: View {
    @EnvironmentObject var viewModel: OnboardingViewModel
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Image("LogoWhite")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 60)
                    
                    Text("OPS")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                }
                .padding(.top, 60)
                
                Spacer()
                
                // Content
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("How are you using OPS?")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("Choose the option that best describes you")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    
                    // User type options
                    VStack(spacing: 16) {
                        UserTypeOption(
                            type: .company,
                            title: "Business Owner",
                            description: "I own or manage a construction business and want to organize projects and teams",
                            isSelected: viewModel.selectedUserType == .company,
                            action: {
                                viewModel.selectedUserType = .company
                            }
                        )
                        
                        UserTypeOption(
                            type: .employee,
                            title: "Employee",
                            description: "I work for a construction company and want to access assigned projects",
                            isSelected: viewModel.selectedUserType == .employee,
                            action: {
                                viewModel.selectedUserType = .employee
                            }
                        )
                    }
                }
                
                Spacer()
                
                // Continue button
                Button(action: {
                    if viewModel.selectedUserType != nil {
                        viewModel.moveToNextStepV2()
                    }
                }) {
                    Text("Continue")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(viewModel.selectedUserType != nil ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackground)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .disabled(viewModel.selectedUserType == nil)
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct UserTypeOption: View {
    let type: UserType
    let title: String
    let description: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent)
                            .frame(width: 12, height: 12)
                    }
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(description)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(nil)
                }
                
                Spacer()
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? OPSStyle.Colors.cardBackground : OPSStyle.Colors.cardBackground.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? OPSStyle.Colors.primaryAccent : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    UserTypeSelectionView()
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.dark)
}