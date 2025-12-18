//
//  SignupScreen.swift
//  OPS
//
//  Path selection screen: CREATE or JOIN a company.
//  Shown after user taps "GET STARTED" on WelcomeScreen.
//

import SwiftUI

struct SignupScreen: View {
    @ObservedObject var manager: OnboardingManager

    var body: some View {
        UserTypeSelectionContent(
            config: UserTypeSelectionConfig(
                title: "HOW WILL YOU USE OPS?",
                subtitle: "Pick one to get started.",
                showBackButton: true,
                backAction: {
                    manager.goToScreen(.welcome)
                },
                onSelectCompanyCreator: {
                    manager.selectFlow(.companyCreator)
                    manager.goToScreen(.credentials)
                },
                onSelectEmployee: {
                    manager.selectFlow(.employee)
                    manager.goToScreen(.credentials)
                }
            )
        )
    }
}

// MARK: - Preview

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)

    SignupScreen(manager: manager)
        .environmentObject(dataController)
}
