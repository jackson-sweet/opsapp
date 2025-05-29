//
//  PhoneNumberView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI

struct PhoneNumberView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var showConfirmation = false
    
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
                // Skip back button at the top
                HStack {
                    Spacer()
                    Button(action: {
                        viewModel.moveToNextStepV2()
                    }) {
                        Text("Skip")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(secondaryTextColor)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                VStack(spacing: 24) {
                    Spacer()
                    
                    // Header - larger text
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Start with your phone\nnumber.")
                            .font(OPSStyle.Typography.largeTitle)
                            .foregroundColor(primaryTextColor)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text("Your number will be used in your company's directory, and won't be shared with anyone outside your organization.")
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(secondaryTextColor)
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                
                    // Phone field with larger font
                    HStack(spacing: 16) {
                        // Country code
                        Text("+1")
                            .font(OPSStyle.Typography.subtitle)
                            .foregroundColor(primaryTextColor)
                        
                        // Phone number with placeholder as hint
                        UnderlineTextField(
                            placeholder: "Phone number",
                            text: $viewModel.phoneNumber,
                            keyboardType: .phonePad,
                            viewModel: viewModel,
                            onChange: { _ in
                                viewModel.formatPhoneNumber()
                                viewModel.errorMessage = ""
                            }
                        )
                    }
                    .padding(.top, 40)
                
                    // Error message
                    if !viewModel.errorMessage.isEmpty {
                        Text(viewModel.errorMessage)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    
                    Spacer()
                    
                    // Continue button with OPS corner radius
                    Button(action: {
                        if viewModel.isPhoneValid {
                            showConfirmation = true
                        }
                    }) {
                        Text("CONTINUE")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .fill(viewModel.isPhoneValid ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryAccent.opacity(0.3))
                            )
                    }
                    .disabled(!viewModel.isPhoneValid || viewModel.isLoading)
                    
                    // Terms and Privacy at bottom
                    HStack(spacing: 16) {
                        Button("Terms") {
                            // Handle terms tap
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(secondaryTextColor)
                        
                        Button("Privacy Policy") {
                            // Handle privacy policy tap
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(secondaryTextColor)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 24)
            }
        }
        .sheet(isPresented: $showConfirmation) {
            PhoneConfirmationView(
                phoneNumber: viewModel.phoneNumber,
                onConfirm: {
                    showConfirmation = false
                    viewModel.moveToNextStepV2()
                },
                onEdit: {
                    showConfirmation = false
                }
            )
        }
        }
    }


// MARK: - Phone Confirmation View
struct PhoneConfirmationView: View {
    let phoneNumber: String
    let onConfirm: () -> Void
    let onEdit: () -> Void
    
    var formattedNumber: String {
        // Format as +1 22 345 6789
        let cleaned = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if cleaned.count >= 10 {
            let areaCode = String(cleaned.prefix(3))
            let middleThree = String(cleaned.dropFirst(3).prefix(3))
            let lastFour = String(cleaned.dropFirst(6).prefix(4))
            return "+1 \(areaCode) \(middleThree) \(lastFour)"
        }
        return "+1 \(phoneNumber)"
    }
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all) // Keep phone confirmation dark for now
            
            VStack(spacing: 40) {
                Spacer()
                
                // Title
                Text("Number Confirmation")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(.white)
                
                // Phone number display
                Text(formattedNumber)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(.white)
                
                // Question
                Text("Is your phone number above correct?")
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
                
                // Buttons
                VStack(spacing: 16) {
                    Button(action: onConfirm) {
                        Text("Yes")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                            )
                    }
                    
                    Button(action: onEdit) {
                        Text("Edit")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Preview
#Preview("Phone Number Screen") {
    let viewModel = OnboardingViewModel()
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    viewModel.email = "user@example.com"
    viewModel.password = "password123"
    viewModel.firstName = "John"
    viewModel.lastName = "Doe"
    viewModel.phoneNumber = "555-123-4567"
    
    return PhoneNumberView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environmentObject(dataController)
        .environment(\.colorScheme, .dark)
}
