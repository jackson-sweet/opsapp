//
//  UserDetailsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import SwiftUI

struct UserDetailsView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @FocusState private var isFieldFocused: Bool
    @State private var currentFieldIndex: Int = 0 // 0: first name, 1: last name
    
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
            backgroundColor.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Minimal header with back button
                HStack {
                    Button(action: {
                        if currentFieldIndex > 0 {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentFieldIndex -= 1
                            }
                        } else {
                            viewModel.moveToPreviousStepV2()
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(OPSStyle.Typography.body)
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
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                VStack(spacing: 0) {
                    // Main content area - top-justified
                    VStack(spacing: 40) {
                        // Header with larger text - changes based on current field
                        VStack(alignment: .leading, spacing: 16) {
                        if currentFieldIndex == 0 {
                            Text("What's your")
                                .font(OPSStyle.Typography.largeTitle)
                                .foregroundColor(primaryTextColor)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text("first name?")
                                .font(OPSStyle.Typography.largeTitle)
                                .foregroundColor(primaryTextColor)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text("This helps your team identify you.")
                                .font(OPSStyle.Typography.cardTitle)
                                .foregroundColor(secondaryTextColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("What's your")
                                .font(OPSStyle.Typography.largeTitle)
                                .foregroundColor(primaryTextColor)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text("last name?")
                                .font(OPSStyle.Typography.largeTitle)
                                .foregroundColor(primaryTextColor)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text("Almost done with your profile.")
                                .font(OPSStyle.Typography.cardTitle)
                                .foregroundColor(secondaryTextColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 24)
                        
                    // Single name field with larger font
                    VStack(spacing: 32) {
                        if currentFieldIndex == 0 {
                            // First Name Field
                            UnderlineTextField(
                                placeholder: "First name",
                                text: $viewModel.firstName,
                                autocapitalization: .words,
                                viewModel: viewModel,
                                onChange: { _ in
                                    viewModel.errorMessage = ""
                                }
                            )
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                        } else {
                            // Last Name Field
                            UnderlineTextField(
                                placeholder: "Last name",
                                text: $viewModel.lastName,
                                autocapitalization: .words,
                                viewModel: viewModel,
                                onChange: { _ in
                                    viewModel.errorMessage = ""
                                }
                            )
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                        }
                    }
                    .padding(.horizontal, 24)
                        
                    // Error message
                        if !viewModel.errorMessage.isEmpty {
                            Text(viewModel.errorMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.top, 40) // Add consistent top padding
                    
                    Spacer()
                    
                    // Continue button - minimal style
                    VStack(spacing: 24) {
                        Button(action: {
                            if currentFieldIndex == 0 {
                                if !viewModel.firstName.isEmpty {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        currentFieldIndex = 1
                                    }
                                } else {
                                    viewModel.errorMessage = "Please enter your first name"
                                }
                            } else {
                                if !viewModel.lastName.isEmpty {
                                    // Store user details
                                    UserDefaults.standard.set(viewModel.firstName, forKey: "user_first_name")
                                    UserDefaults.standard.set(viewModel.lastName, forKey: "user_last_name")
                                    
                                    // Move to next step
                                    viewModel.moveToNextStepV2()
                                } else {
                                    viewModel.errorMessage = "Please enter your last name"
                                }
                            }
                        }) {
                            Text("CONTINUE")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(viewModel.shouldUseLightTheme ? .white : .black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .fill(
                                            (currentFieldIndex == 0 ? !viewModel.firstName.isEmpty : !viewModel.lastName.isEmpty) ? 
                                            (viewModel.shouldUseLightTheme ? OPSStyle.Colors.primaryAccent : Color.white) : 
                                            (viewModel.shouldUseLightTheme ? OPSStyle.Colors.primaryAccent.opacity(0.3) : Color.white.opacity(0.3))
                                        )
                                )
                        }
                        .disabled(currentFieldIndex == 0 ? viewModel.firstName.isEmpty : viewModel.lastName.isEmpty)
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 40)
                }
                .onAppear {
                    isFieldFocused = true
                }
                .onChange(of: currentFieldIndex) { _, _ in
                    isFieldFocused = true
                }
            }
        }
    }
}

#Preview {
    let viewModel = OnboardingViewModel()
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    viewModel.firstName = "John"
    viewModel.lastName = "Doe"
    viewModel.phoneNumber = "5551234567"
    viewModel.isPhoneValid = true
    
    return UserDetailsView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environmentObject(dataController)
        .environment(\.colorScheme, .dark)
}