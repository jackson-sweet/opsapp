//
//  UserInfoView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-06.
//

import SwiftUI

// Function to format phone number
func formatPhoneNumber(_ phoneNumber: String) -> String {
    // Filter out non-numeric characters
    let digits = phoneNumber.filter { $0.isNumber }
    
    // Format according to pattern (XXX) XXX-XXXX
    var formattedPhone = ""
    
    for (index, digit) in digits.prefix(10).enumerated() {
        if index == 0 {
            formattedPhone.append("(\(digit)")
        } else if index == 2 {
            formattedPhone.append("\(digit)) ")
        } else if index == 5 {
            formattedPhone.append("\(digit)-")
        } else {
            formattedPhone.append(String(digit))
        }
    }
    
    return formattedPhone
}

struct UserInfoView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var isInConsolidatedFlow: Bool = false
    @State private var currentPhase: UserInfoPhase = .firstName
    
    enum UserInfoPhase: Int, CaseIterable {
        case firstName = 0
        case lastName = 1
        case phoneNumber = 2
    }
    
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        if viewModel.selectedUserType == .employee {
            return 3 // Employee flow position - after organization join
        } else {
            return 2 // Company flow position - after account setup
        }
    }
    
    private var totalSteps: Int {
        if viewModel.selectedUserType == .employee {
            return 8 // Employee flow has 8 total steps
        } else {
            return 10 // Company flow has 10 total steps
        }
    }
    
    var body: some View {
        ZStack {
            // Background color - conditional theming
            (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.background : OPSStyle.Colors.background)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Top navigation and progress section
                VStack(spacing: 0) {
                    // Navigation bar with back button and step indicator
                    HStack {
                        Button(action: {
                            if currentPhase == .firstName {
                                if isInConsolidatedFlow {
                                    viewModel.moveToPreviousStepV2()
                                } else {
                                    viewModel.moveToPreviousStep()
                                }
                            } else {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentPhase = UserInfoPhase(rawValue: currentPhase.rawValue - 1) ?? .firstName
                                }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(OPSStyle.Typography.captionBold)
                                Text("Back")
                                    .font(OPSStyle.Typography.bodyBold)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        
                        Spacer()
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
                    
                    // Step indicator bars
                    HStack(spacing: 4) {
                        ForEach(0..<totalSteps) { step in
                            Rectangle()
                                .fill(step < currentStepNumber ? 
                                    (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryAccent : OPSStyle.Colors.primaryAccent) : 
                                    (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText.opacity(0.4) : OPSStyle.Colors.secondaryText.opacity(0.4)))
                                .frame(height: 4)
                        }
                    }
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                
                // Main centered content area
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Phase content
                    Group {
                        switch currentPhase {
                        case .firstName:
                            FirstNamePhaseView(
                                firstName: $viewModel.firstName,
                                isLightTheme: viewModel.shouldUseLightTheme,
                                onContinue: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        currentPhase = .lastName
                                    }
                                }
                            )
                        case .lastName:
                            LastNamePhaseView(
                                lastName: $viewModel.lastName,
                                isLightTheme: viewModel.shouldUseLightTheme,
                                userType: viewModel.selectedUserType,
                                onContinue: {
                                    // Always go to phone number phase for all users
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        currentPhase = .phoneNumber
                                    }
                                }
                            )
                        case .phoneNumber:
                            PhoneNumberPhaseView(
                                phoneNumber: $viewModel.phoneNumber,
                                isLightTheme: viewModel.shouldUseLightTheme,
                                onContinue: {
                                    if isInConsolidatedFlow {
                                        viewModel.moveToNextStepV2()
                                    } else {
                                        viewModel.moveToNextStep()
                                    }
                                }
                            )
                        }
                    }
                    .transition(.opacity)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    
                    Spacer()
                }
            }
        }
        .dismissKeyboardOnTap()
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

// MARK: - Phase Views

struct FirstNamePhaseView: View {
    @Binding var firstName: String
    let isLightTheme: Bool
    let onContinue: () -> Void
    
    private var primaryTextColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText
    }
    
    private var secondaryTextColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText
    }
    
    private var placeholderColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.secondaryText.opacity(0.6) : OPSStyle.Colors.secondaryText.opacity(0.6)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("WHAT'S YOUR")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(primaryTextColor)
                
                Text("FIRST NAME?")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(primaryTextColor)
                    .padding(.bottom, 12)
                
                Text("This will be used for your profile so your team can recognize you.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(secondaryTextColor)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 30)
            
            // First name input
            TextField("First name", text: $firstName)
                .font(OPSStyle.Typography.body)
                .foregroundColor(primaryTextColor)
                .keyboardType(.namePhonePad)
                .autocapitalization(.words)
                .disableAutocorrection(true)
                .textContentType(.givenName)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isLightTheme ? OPSStyle.Colors.Light.cardBackground : OPSStyle.Colors.cardBackground)
                        )
                )
            
            Spacer()
            
            // Continue button
            StandardContinueButton(
                isDisabled: firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onTap: onContinue
            )
        }
    }
}

struct LastNamePhaseView: View {
    @Binding var lastName: String
    let isLightTheme: Bool
    let userType: UserType?
    let onContinue: () -> Void
    
    private var primaryTextColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText
    }
    
    private var secondaryTextColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("AND YOUR")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(primaryTextColor)
                
                Text("LAST NAME?")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(primaryTextColor)
                    .padding(.bottom, 12)
                
                Text("This completes your profile name for team identification.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(secondaryTextColor)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 30)
            
            // Last name input
            TextField("Last name", text: $lastName)
                .font(OPSStyle.Typography.body)
                .foregroundColor(primaryTextColor)
                .keyboardType(.namePhonePad)
                .autocapitalization(.words)
                .disableAutocorrection(true)
                .textContentType(.familyName)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isLightTheme ? OPSStyle.Colors.Light.cardBackground : OPSStyle.Colors.cardBackground)
                        )
                )
            
            Spacer()
            
            // Continue button
            StandardContinueButton(
                isDisabled: lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onTap: onContinue
            )
        }
    }
}

struct PhoneNumberPhaseView: View {
    @Binding var phoneNumber: String
    let isLightTheme: Bool
    let onContinue: () -> Void
    
    private var primaryTextColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText
    }
    
    private var secondaryTextColor: Color {
        isLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText
    }
    
    private var isPhoneValid: Bool {
        let digits = phoneNumber.filter { $0.isNumber }
        return digits.count >= 10
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR PHONE")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(primaryTextColor)
                
                Text("NUMBER?")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(primaryTextColor)
                    .padding(.bottom, 12)
                
                Text("We'll use this to send you project updates and notifications.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(secondaryTextColor)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 30)
            
            // Phone number input
            TextField("(___) ___-____", text: $phoneNumber)
                .font(OPSStyle.Typography.body)
                .foregroundColor(primaryTextColor)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .onChange(of: phoneNumber) { oldValue, newValue in
                    // Only keep digits and format
                    let digits = newValue.filter { $0.isNumber }
                    if digits.count <= 10 {
                        phoneNumber = formatPhoneNumber(newValue)
                    } else {
                        phoneNumber = oldValue
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isLightTheme ? OPSStyle.Colors.Light.cardBackground : OPSStyle.Colors.cardBackground)
                        )
                )
            
            Spacer()
            
            // Continue button
            StandardContinueButton(
                isDisabled: !isPhoneValid,
                onTap: onContinue
            )
        }
    }
}

// MARK: - Preview
#Preview("User Info Screen") {
    let viewModel = OnboardingViewModel()
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    viewModel.email = "user@example.com"
    viewModel.password = "password123"
    viewModel.firstName = "John"
    viewModel.lastName = "Doe"
    
    return UserInfoView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environmentObject(dataController)
        .environment(\.colorScheme, .dark)
}