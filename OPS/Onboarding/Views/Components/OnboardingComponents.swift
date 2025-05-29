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
            .font(OPSStyle.Typography.bodyBold)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                !isDisabled && !configuration.isPressed ? 
                HStack {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(OPSStyle.Typography.bodyEmphasis)
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
            .font(OPSStyle.Typography.bodyBold)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .overlay(
                HStack(spacing: 4) {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(OPSStyle.Typography.captionBold) 
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
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(Color("StatusError"))
                
                Text(message)
                    .font(OPSStyle.Typography.caption)
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

// MARK: - Standard Navigation Header

struct StandardNavigationHeader: View {
    var showBack: Bool = true
    var showSignOut: Bool = true
    var onBack: () -> Void
    var onSignOut: () -> Void
    
    var body: some View {
        HStack {
            if showBack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(OPSStyle.Typography.caption)
                        Text("Back")
                            .font(OPSStyle.Typography.bodyBold)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            
            Spacer()
            
            if showSignOut {
                Button(action: onSignOut) {
                    Text("Sign Out")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .padding(.horizontal, 24)
    }
}

// MARK: - Header

struct OnboardingHeaderView: View {
    var title: String
    var subtitle: String
    var isLightTheme: Bool = false // Default to dark theme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(OPSStyle.Typography.title)
                .foregroundColor(isLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText)
                .padding(.bottom, subtitle.isEmpty ? 0 : 4)
            
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(isLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
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
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(.white.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Standard Continue Button

struct StandardContinueButton: View {
    var isDisabled: Bool = false
    var isLoading: Bool = false
    var onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text("CONTINUE")
                    .font(OPSStyle.Typography.bodyBold)
                    .opacity(isLoading ? 0 : 1)
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                }
            }
            .foregroundColor(isDisabled ? Color.gray : OPSStyle.Colors.primaryAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isDisabled ? Color.gray : OPSStyle.Colors.primaryAccent, lineWidth: 1)
            )
        }
        .disabled(isDisabled || isLoading)
    }
}

// MARK: - Underline Text Field

struct UnderlineTextField: View {
    var placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .never
    var disableAutocorrection: Bool = true
    @ObservedObject var viewModel: OnboardingViewModel
    var onChange: ((String) -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 12) {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .font(OPSStyle.Typography.subtitle)
                    .disableAutocorrection(disableAutocorrection)
                    .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: text) { _, newValue in
                        onChange?(newValue)
                    }
            } else {
                TextField(placeholder, text: $text)
                    .font(OPSStyle.Typography.subtitle)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .disableAutocorrection(disableAutocorrection)
                    .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: text) { _, newValue in
                        onChange?(newValue)
                    }
            }
            
            Rectangle()
                .fill(!text.isEmpty ? 
                    (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryAccent : OPSStyle.Colors.primaryAccent) : 
                    (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText.opacity(0.3) : OPSStyle.Colors.secondaryText.opacity(0.3)))
                .frame(height: 1)
                .animation(.easeInOut(duration: 0.2), value: text.isEmpty)
        }
    }
}

// MARK: - Navigation Buttons

struct OnboardingNavigationButtons: View {
    var primaryText: String = "Continue"
    var secondaryText: String = "Back"
    var isPrimaryDisabled: Bool = false
    var isLoading: Bool = false
    var showSecondary: Bool = true
    var isLightTheme: Bool = false // Default to dark theme
    var onPrimaryTapped: () -> Void
    var onSecondaryTapped: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            // Primary continue button
            Button(action: onPrimaryTapped) {
                ZStack {
                    HStack {
                        Text(primaryText)
                            .font(OPSStyle.Typography.bodyBold)
                            .opacity(isLoading ? 0 : 1)
                        
                        Spacer()
                        
                        if !isLoading && !isPrimaryDisabled {
                            Image(systemName: "arrow.right")
                                .font(OPSStyle.Typography.captionBold)
                                .padding(.trailing, 20)
                        }
                    }
                    .foregroundColor(isLightTheme ? .white : .black)
                    
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: isLightTheme ? .white : .black))
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 52)
                .frame(maxWidth: .infinity)
                .background(isPrimaryDisabled || isLoading ? 
                           (isLightTheme ? OPSStyle.Colors.primaryAccent.opacity(0.7) : Color.white.opacity(0.7)) : 
                           (isLightTheme ? OPSStyle.Colors.primaryAccent : Color.white))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .disabled(isPrimaryDisabled || isLoading)
            
            // Secondary back/skip button (if provided)
            if showSecondary, let secondaryAction = onSecondaryTapped {
                Button(action: secondaryAction) {
                    HStack(spacing: 4) {
                        if secondaryText.lowercased() == "back" {
                            Image(systemName: "chevron.left")
                                .font(OPSStyle.Typography.captionBold)
                        }
                        
                        Text(secondaryText)
                            .font(OPSStyle.Typography.bodyBold)
                        
                        if secondaryText.lowercased() != "back" {
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(isLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                        }
                    }
                    .foregroundColor(isLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText)
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
