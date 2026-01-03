//
//  ReadyScreen.swift
//  OPS
//
//  Final onboarding screen with billing info before tutorial.
//

import SwiftUI
import UIKit

struct ReadyScreen: View {
    @ObservedObject var manager: OnboardingManager
    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Billing Info Content
                BillingInfoView(
                    isActive: true,
                    userType: manager.state.flow?.userType
                )

                // Navigation Button
                VStack(spacing: 24) {
                    let buttonText = manager.state.flow == .companyCreator ? "START TRIAL" : "CONTINUE"
                    OnboardingPrimaryButton(buttonText) {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        // Go forward to check if tutorial is needed
                        manager.goForward()
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - Preview

struct ReadyScreen_Previews: PreviewProvider {
    static var previews: some View {
        let dataController = DataController()
        let manager = OnboardingManager(dataController: dataController)
        manager.selectFlow(.companyCreator)

        return ReadyScreen(manager: manager)
            .environmentObject(dataController)
            .environmentObject(SubscriptionManager.shared)
    }
}
