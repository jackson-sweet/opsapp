//
//  OnboardingPrimaryButton.swift
//  OPS
//
//  Primary action button for onboarding screens with haptic feedback.
//

import SwiftUI
import UIKit

struct OnboardingPrimaryButton: View {
    let title: String
    let isEnabled: Bool
    let isLoading: Bool
    let loadingText: String?
    let action: () -> Void

    init(
        _ title: String,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        loadingText: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.loadingText = loadingText
        self.action = action
    }

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        } label: {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))

                    if let loadingText = loadingText {
                        Text(loadingText)
                            .font(OPSStyle.Typography.bodyBold)
                    }
                }
            } else {
                HStack {
                    Text(title)
                        .font(OPSStyle.Typography.bodyBold)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(isEnabled && !isLoading ? Color.white : Color.white.opacity(0.5))
        .foregroundColor(.black)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - Preview

struct OnboardingPrimaryButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            OnboardingPrimaryButton("CONTINUE", isEnabled: true) {
                print("Tapped")
            }

            OnboardingPrimaryButton("CONTINUE", isEnabled: false) {
                print("Tapped")
            }

            OnboardingPrimaryButton("JOIN CREW", isLoading: true, loadingText: "Joining...") {
                print("Tapped")
            }
        }
        .padding(40)
        .background(OPSStyle.Colors.background)
    }
}
