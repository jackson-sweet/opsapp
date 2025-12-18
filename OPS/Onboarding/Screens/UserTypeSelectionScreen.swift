//
//  UserTypeSelectionScreen.swift
//  OPS
//
//  Screen for logged-in users without userType to select their path.
//  Shown when resuming onboarding and userType is not set.
//  Reuses UserTypeSelectionContent shared component.
//

import SwiftUI

struct UserTypeSelectionScreen: View {
    @ObservedObject var manager: OnboardingManager

    var body: some View {
        UserTypeSelectionContent(
            config: UserTypeSelectionConfig(
                title: "HOW WILL YOU USE OPS?",
                subtitle: "Pick one to get started.",
                showBackButton: false,
                backAction: nil,
                onSelectCompanyCreator: {
                    selectUserType(.company)
                },
                onSelectEmployee: {
                    selectUserType(.employee)
                }
            )
        )
    }

    private func selectUserType(_ userType: UserType) {
        Task {
            do {
                try await manager.updateUserType(userType)

                await MainActor.run {
                    // Set the flow based on user type
                    let flow: OnboardingFlow = userType == .company ? .companyCreator : .employee
                    manager.selectFlow(flow)

                    // Navigate to profile screen (common entry point for both flows)
                    manager.goToScreen(.profile)
                }
            } catch {
                await MainActor.run {
                    manager.showError(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)

    UserTypeSelectionScreen(manager: manager)
        .environmentObject(dataController)
}
