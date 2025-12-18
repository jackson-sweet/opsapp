//
//  OnboardingLoadingOverlay.swift
//  OPS
//
//  Loading overlay for onboarding v3 flow.
//  Shows a modal loading state with customizable message.
//

import SwiftUI

struct OnboardingLoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            // Loading card
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                Text(message)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .zIndex(999)
    }
}

// MARK: - Extended Loading Overlay

/// Loading overlay with optional progress indicator
struct OnboardingLoadingOverlayWithProgress: View {
    let message: String
    let progress: Double? // 0.0 to 1.0, nil for indeterminate

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            // Loading card
            VStack(spacing: 20) {
                if let progress = progress {
                    // Determinate progress
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                        .frame(width: 200)
                } else {
                    // Indeterminate spinner
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }

                Text(message)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                if let progress = progress {
                    Text("\(Int(progress * 100))%")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .zIndex(999)
    }
}

// MARK: - Loading View Modifier

/// View modifier to conditionally show onboarding loading overlay
struct OnboardingLoadingModifier: ViewModifier {
    let isLoading: Bool
    let message: String

    func body(content: Content) -> some View {
        ZStack {
            content

            if isLoading {
                OnboardingLoadingOverlay(message: message)
            }
        }
    }
}

extension View {
    /// Applies an onboarding loading overlay when isLoading is true
    func onboardingLoading(isLoading: Bool, message: String = "Loading...") -> some View {
        modifier(OnboardingLoadingModifier(isLoading: isLoading, message: message))
    }
}

// MARK: - Previews

#Preview("Basic Loading") {
    ZStack {
        OPSStyle.Colors.background
            .ignoresSafeArea()

        VStack {
            Text("Background Content")
                .foregroundColor(.white)
        }

        OnboardingLoadingOverlay(message: "Creating your account...")
    }
}

#Preview("With Progress") {
    ZStack {
        OPSStyle.Colors.background
            .ignoresSafeArea()

        VStack {
            Text("Background Content")
                .foregroundColor(.white)
        }

        OnboardingLoadingOverlayWithProgress(
            message: "Uploading company logo...",
            progress: 0.65
        )
    }
}

#Preview("View Modifier") {
    VStack {
        Text("Content")
            .foregroundColor(.white)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(OPSStyle.Colors.background)
    .onboardingLoading(isLoading: true, message: "Joining company...")
}
