//
//  OnboardingHeader.swift
//  OPS
//
//  Standard header component for onboarding screens.
//  Includes optional back button and sign out button.
//

import SwiftUI

struct OnboardingHeader: View {
    let showBack: Bool
    let onBack: (() -> Void)?
    let onSignOut: () -> Void

    init(
        showBack: Bool = true,
        onBack: (() -> Void)? = nil,
        onSignOut: @escaping () -> Void
    ) {
        self.showBack = showBack
        self.onBack = onBack
        self.onSignOut = onSignOut
    }

    var body: some View {
        HStack {
            if showBack {
                Button {
                    onBack?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(OPSStyle.Typography.body)
                    }
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            Spacer()

            Button {
                onSignOut()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14, weight: .medium))
                    Text("Sign out")
                        .font(OPSStyle.Typography.caption)
                }
                .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        // With back button
        OnboardingHeader(
            showBack: true,
            onBack: { print("Back") },
            onSignOut: { print("Sign out") }
        )

        // Without back button
        OnboardingHeader(
            showBack: false,
            onBack: nil,
            onSignOut: { print("Sign out") }
        )
    }
    .padding(40)
    .background(OPSStyle.Colors.background)
}
