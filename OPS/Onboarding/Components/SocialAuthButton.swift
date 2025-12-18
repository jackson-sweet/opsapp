//
//  SocialAuthButton.swift
//  OPS
//
//  Social authentication buttons for Google and Apple sign-in.
//  Used in the new onboarding v3 Credentials screen.
//

import SwiftUI

// MARK: - Provider Enum

enum SocialAuthProvider {
    case google
    case apple

    var buttonText: String {
        switch self {
        case .google: return "Continue with Google"
        case .apple: return "Continue with Apple"
        }
    }
}

// MARK: - Social Auth Button

struct SocialAuthButton: View {
    let provider: SocialAuthProvider
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                } else {
                    providerIcon
                    Text(provider.buttonText)
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.tertiaryText.opacity(0.5), lineWidth: 1)
            )
        }
        .disabled(isLoading)
    }

    @ViewBuilder
    private var providerIcon: some View {
        switch provider {
        case .google:
            Image("google_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        case .apple:
            Image(systemName: "apple.logo")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }
}

// MARK: - Social Auth Button Stack

/// A vertical stack of social auth buttons with an optional "OR" divider
struct SocialAuthButtonStack: View {
    let isLoading: Bool
    let onGoogleSignIn: () -> Void
    let onAppleSignIn: () -> Void
    let showDivider: Bool

    init(
        isLoading: Bool = false,
        showDivider: Bool = true,
        onGoogleSignIn: @escaping () -> Void,
        onAppleSignIn: @escaping () -> Void
    ) {
        self.isLoading = isLoading
        self.showDivider = showDivider
        self.onGoogleSignIn = onGoogleSignIn
        self.onAppleSignIn = onAppleSignIn
    }

    var body: some View {
        VStack(spacing: 12) {
            // OR divider
            if showDivider {
                orDivider
                    .padding(.vertical, 8)
            }

            // Google button
            SocialAuthButton(
                provider: .google,
                isLoading: isLoading,
                action: onGoogleSignIn
            )

            // Apple button
            SocialAuthButton(
                provider: .apple,
                isLoading: isLoading,
                action: onAppleSignIn
            )
        }
    }

    private var orDivider: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)

            Text("OR")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
        }
    }
}

// MARK: - Previews

#Preview("Individual Buttons") {
    VStack(spacing: 24) {
        SocialAuthButton(
            provider: .google,
            isLoading: false,
            action: { print("Google tapped") }
        )

        SocialAuthButton(
            provider: .apple,
            isLoading: false,
            action: { print("Apple tapped") }
        )

        SocialAuthButton(
            provider: .google,
            isLoading: true,
            action: {}
        )
    }
    .padding(40)
    .background(OPSStyle.Colors.background)
}

#Preview("Button Stack") {
    VStack(spacing: 40) {
        Text("With Divider")
            .foregroundColor(.white)

        SocialAuthButtonStack(
            isLoading: false,
            showDivider: true,
            onGoogleSignIn: { print("Google") },
            onAppleSignIn: { print("Apple") }
        )

        Text("Without Divider")
            .foregroundColor(.white)

        SocialAuthButtonStack(
            isLoading: false,
            showDivider: false,
            onGoogleSignIn: { print("Google") },
            onAppleSignIn: { print("Apple") }
        )
    }
    .padding(40)
    .background(OPSStyle.Colors.background)
}
