//
//  OnboardingComponents.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI

// MARK: - Onboarding Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                isDisabled ? Color.gray.opacity(0.3) : Color.white
            )
            .foregroundColor(.black)
            .font(.system(size: 17, weight: .medium))
            .cornerRadius(26)
            .overlay(
                !isDisabled && !configuration.isPressed ? 
                HStack {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.trailing, 20)
                } : nil
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .foregroundColor(Color.white)
            .font(.system(size: 16, weight: .medium))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .overlay(
                HStack(spacing: 4) {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .medium)) 
                        .foregroundColor(.white.opacity(0.7))
                        .opacity(configuration.isPressed ? 0.5 : 1)
                }
            )
    }
}

// MARK: - Text Field Styles

struct OnboardingTextFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textContentType(.oneTimeCode) // Prevents autofill suggestions
            .padding(.vertical, 12)
            .padding(.horizontal, 2)
            .foregroundColor(.white)
            .overlay(
                VStack {
                    Spacer()
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.gray.opacity(0.5))
                }
            )
    }
}

extension View {
    func onboardingTextFieldStyle() -> some View {
        modifier(OnboardingTextFieldStyle())
    }
}

// MARK: - Progress Indicator

struct OnboardingProgressIndicator: View {
    var currentStep: OnboardingStep
    var totalSteps: Int {
        OnboardingStep.allCases.count - 2 // Exclude welcome and completion
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1..<totalSteps+1, id: \.self) { step in
                RoundedRectangle(cornerRadius: 2)
                    .fill(step <= currentStep.rawValue ? OPSStyle.Colors.primaryAccent : Color.gray.opacity(0.3))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }
}

// MARK: - Error Message View

struct ErrorMessageView: View {
    var message: String
    
    var body: some View {
        if !message.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color("StatusError"))
                
                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(Color("StatusError"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .transition(.opacity)
        }
    }
}

// MARK: - Loading Overlay
// LoadingView moved to UIComponents.swift

// MARK: - Header

struct OnboardingHeaderView: View {
    var title: String
    var subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, subtitle.isEmpty ? 0 : 4)
            
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Color.gray)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }
}

// MARK: - Input Field Label

struct InputFieldLabel: View {
    var label: String
    
    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Navigation Buttons

struct OnboardingNavigationButtons: View {
    var primaryText: String = "Continue"
    var secondaryText: String = "Back"
    var isPrimaryDisabled: Bool = false
    var isLoading: Bool = false
    var showSecondary: Bool = true
    var onPrimaryTapped: () -> Void
    var onSecondaryTapped: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            // Primary continue button
            Button(action: onPrimaryTapped) {
                ZStack {
                    HStack {
                        Text(primaryText)
                            .font(.system(size: 17, weight: .medium))
                            .opacity(isLoading ? 0 : 1)
                        
                        Spacer()
                        
                        if !isLoading && !isPrimaryDisabled {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .semibold))
                                .padding(.trailing, 20)
                        }
                    }
                    .foregroundColor(.black)
                    
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 52)
                .frame(maxWidth: .infinity)
                .background(isPrimaryDisabled || isLoading ? Color.white.opacity(0.7) : Color.white)
                .cornerRadius(26)
            }
            .disabled(isPrimaryDisabled || isLoading)
            
            // Secondary back/skip button (if provided)
            if showSecondary, let secondaryAction = onSecondaryTapped {
                Button(action: secondaryAction) {
                    HStack(spacing: 4) {
                        if secondaryText.lowercased() == "back" {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .medium))
                        }
                        
                        Text(secondaryText)
                            .font(.system(size: 16, weight: .medium))
                        
                        if secondaryText.lowercased() != "back" {
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
                }
                .disabled(isLoading)
            }
        }
    }
}

// MARK: - Previews
#Preview("Button Styles") {
    let previewHelper = OnboardingPreviewHelpers.PreviewStyles()
    
    VStack(spacing: 20) {
        Button("Continue") {}
            .buttonStyle(PrimaryButtonStyle())
        
        Button("Continue") {}
            .buttonStyle(PrimaryButtonStyle(isDisabled: true))
        
        Button("Back") {}
            .buttonStyle(SecondaryButtonStyle())
    }
    .padding()
    .background(Color.black)
    .environmentObject(previewHelper)
    .environment(\.colorScheme, .dark)
}

#Preview("Progress Indicator") {
    let previewHelper = OnboardingPreviewHelpers.PreviewStyles()
    
    VStack(spacing: 20) {
        ForEach(OnboardingStep.allCases, id: \.self) { step in
            if step != .welcome && step != .completion {
                VStack(spacing: 4) {
                    Text(String(describing: step))
                        .foregroundColor(.white)
                        .font(.caption)
                    
                    OnboardingProgressIndicator(currentStep: step)
                }
            }
        }
    }
    .padding()
    .background(Color.black)
    .environmentObject(previewHelper)
    .environment(\.colorScheme, .dark)
}

#Preview("UI Components") {
    let previewHelper = OnboardingPreviewHelpers.PreviewStyles()
    
    VStack(spacing: 30) {
        // Header
        OnboardingHeaderView(
            title: "Create your account",
            subtitle: "Enter your information to get started with OPS."
        )
        
        // Input field with label
        VStack(alignment: .leading, spacing: 8) {
            InputFieldLabel(label: "EMAIL")
            
            TextField("Email address", text: .constant("user@example.com"))
                .onboardingTextFieldStyle()
        }
        
        // Error message
        ErrorMessageView(message: "This email address is already in use.")
        
        // Navigation buttons
        OnboardingNavigationButtons(
            primaryText: "Continue",
            secondaryText: "Back",
            isPrimaryDisabled: false,
            isLoading: false,
            onPrimaryTapped: {},
            onSecondaryTapped: {}
        )
        
        // Loading state
        OnboardingNavigationButtons(
            primaryText: "Continue", 
            secondaryText: "Back",
            isPrimaryDisabled: false,
            isLoading: true,
            onPrimaryTapped: {},
            onSecondaryTapped: {}
        )
    }
    .padding()
    .background(Color.black)
    .environmentObject(previewHelper)
    .environment(\.colorScheme, .dark)
}
