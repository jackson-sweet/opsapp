//
//  UserTypeSelectionView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-23.
//

import SwiftUI

struct UserTypeSelectionView: View {
    @EnvironmentObject var viewModel: OnboardingViewModel
    
    // Color scheme based on selected user type
    private var backgroundColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.background : OPSStyle.Colors.background
    }
    
    private var primaryTextColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText
    }
    
    private var secondaryTextColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText
    }
    
    private var cardBackgroundColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.cardBackground : OPSStyle.Colors.cardBackground
    }
    
    var body: some View {
        ZStack {
            // Background - changes based on selection
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Header
                HStack(alignment: .bottom, spacing: 16) {
                    Image("LogoWhite")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 60)
                        .colorMultiply(viewModel.shouldUseLightTheme ? .black : .white) // Adjust logo color
                    
                    Text("OPS")
                        .font(OPSStyle.Typography.largeTitle)
                        .foregroundColor(primaryTextColor)
                    Spacer()
                }
                .padding(.top, 60)
                
                Spacer()
                
                // Content
                VStack(spacing: 24) {

                    // User type options
                    VStack(spacing: 16) {
                        UserTypeOption(
                            type: .company,
                            title: "COMPANY LEAD",
                            description: "Command operations. Coordinate teams. Control the outcomes.",
                            isSelected: viewModel.selectedUserType == .company,
                            isLightTheme: viewModel.shouldUseLightTheme,
                            action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    viewModel.selectedUserType = .company
                                }
                            }
                        )

                        UserTypeOption(
                            type: .employee,
                            title: "TEAM MEMBER",
                            description: "Execute plans. Crush projects. Rise through the ranks.",
                            isSelected: viewModel.selectedUserType == .employee,
                            isLightTheme: viewModel.shouldUseLightTheme,
                            action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    viewModel.selectedUserType = .employee
                                }
                            }
                        )
                    }

                }

                Spacer()
                
                // Continue button
                StandardContinueButton(
                    isDisabled: viewModel.selectedUserType == nil,
                    onTap: {
                        if viewModel.selectedUserType != nil {
                            viewModel.moveToNextStep()
                        }
                    }
                )
                .padding(.bottom, 50)
            }
            .padding(OPSStyle.Layout.spacing3)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.selectedUserType)
    }
}

struct UserTypeOption: View {
    let type: UserType
    let title: String
    let description: String
    let isSelected: Bool
    let isLightTheme: Bool
    let action: () -> Void
    @EnvironmentObject var viewModel: OnboardingViewModel
    
    private var primaryTextColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText
    }
    
    private var secondaryTextColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText
    }
    
    private var cardBackgroundColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.cardBackground : OPSStyle.Colors.cardBackground
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(isSelected ? (isLightTheme ? .white : .black) : primaryTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(description)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(isSelected ? (isLightTheme ? OPSStyle.Colors.Light.tertiaryText : OPSStyle.Colors.tertiaryText) : secondaryTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(nil)
                }
                
                Spacer()
                
                // Selection indicator
                Image(systemName: "rectangle.portrait.and.arrow.forward")
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? (isLightTheme ? .white : .black) : primaryTextColor)
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(isSelected ?
                          (isLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText) :
                          cardBackgroundColor.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(isSelected ? OPSStyle.Colors.secondaryText : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    UserTypeSelectionView()
        .environmentObject(OnboardingViewModel())
        .environmentObject(dataController)
        .preferredColorScheme(.dark)
}
