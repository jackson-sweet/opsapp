//
//  OnboardingProgressBar.swift
//  OPS
//
//  Thin segmented progress bar for onboarding flow.
//  Tactical minimalism - clean, informative, unobtrusive.
//

import SwiftUI

struct OnboardingProgressBar: View {
    let currentStep: Int
    let totalSteps: Int

    private let barHeight: CGFloat = 3
    private let segmentSpacing: CGFloat = 4

    var body: some View {
        HStack(spacing: segmentSpacing) {
            ForEach(0..<totalSteps, id: \.self) { index in
                RoundedRectangle(cornerRadius: barHeight / 2)
                    .fill(index < currentStep ? Color.white : Color.white.opacity(0.15))
                    .frame(height: barHeight)
            }
        }
        .padding(.horizontal, 40)
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }
}

// MARK: - Flow-Aware Progress Calculation

extension OnboardingProgressBar {

    /// Create progress bar based on current onboarding state
    static func forState(_ state: OnboardingState) -> OnboardingProgressBar? {
        guard let flow = state.flow else { return nil }

        let (currentStep, totalSteps) = progressForScreen(
            state.currentScreen,
            flow: flow
        )

        // Don't show for screens before profile
        guard currentStep > 0 else { return nil }

        return OnboardingProgressBar(
            currentStep: currentStep,
            totalSteps: totalSteps
        )
    }

    /// Calculate progress based on screen and flow
    private static func progressForScreen(
        _ screen: OnboardingScreen,
        flow: OnboardingFlow
    ) -> (current: Int, total: Int) {
        // Hide progress bar on ready screen (billing info only, no welcome guide)
        if screen == .ready {
            return (0, 0)
        }

        switch flow {
        case .companyCreator:
            // profile → companySetup → companyDetails → companyCode
            let totalSteps = 4
            let current: Int
            switch screen {
            case .profile: current = 1
            case .companySetup: current = 2
            case .companyDetails: current = 3
            case .companyCode: current = 4
            default: current = 0
            }
            return (current, totalSteps)

        case .employee:
            // profile → codeEntry
            let totalSteps = 2
            let current: Int
            switch screen {
            case .profile: current = 1
            case .codeEntry: current = 2
            case .profileJoin: current = 2 // Legacy fallback
            default: current = 0
            }
            return (current, totalSteps)
        }
    }
}

// MARK: - Preview

#Preview("Company Creator Flow") {
    VStack(spacing: 32) {
        ForEach(1...5, id: \.self) { step in
            VStack(alignment: .leading, spacing: 8) {
                Text("Step \(step) of 5")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.horizontal, 40)

                OnboardingProgressBar(currentStep: step, totalSteps: 5)
            }
        }
    }
    .padding(.vertical, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(OPSStyle.Colors.background)
}

#Preview("Employee Flow") {
    VStack(spacing: 32) {
        ForEach(1...3, id: \.self) { step in
            VStack(alignment: .leading, spacing: 8) {
                Text("Step \(step) of 3")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.horizontal, 40)

                OnboardingProgressBar(currentStep: step, totalSteps: 3)
            }
        }
    }
    .padding(.vertical, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(OPSStyle.Colors.background)
}
