//
//  WizardManagementView.swift
//  OPS
//
//  Settings view showing all available wizards with their
//  completion status. Users can start, resume, or restart wizards
//  and manage "don't show" preferences.
//

import SwiftUI

struct WizardManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wizardStateManager) private var optionalStateManager
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore

    private var availableWizards: [any WizardDefinitionProtocol] {
        guard let role = dataController.currentUser?.role else { return [] }
        return WizardRegistry.wizards(for: role) { perm in
            permissionStore.can(perm)
        }
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Setup Guides",
                    onBackTapped: { dismiss() }
                )

                ScrollView {
                    VStack(spacing: 24) {
                        ForEach(Array(availableWizards.enumerated()), id: \.element.wizardId) { _, wizard in
                            wizardRow(wizard: wizard)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private func wizardRow(wizard: any WizardDefinitionProtocol) -> some View {
        let state = optionalStateManager?.wizardState(for: wizard.wizardId)

        NavigationLink {
            WizardDetailView(wizard: wizard)
                .environmentObject(dataController)
                .environmentObject(permissionStore)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: wizard.iconName)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(wizard.displayName)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    statusText(for: state)
                }

                Spacer()

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
        }
        .buttonStyle(PlainButtonStyle())
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    @ViewBuilder
    private func statusText(for state: WizardState?) -> some View {
        if let state {
            switch state.status {
            case .completed:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.successStatus)
                    Text("Completed")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.successStatus)
                }
            case .inProgress:
                Text("\(state.currentStepIndex + 1) / \(WizardRegistry.wizard(for: state.wizardId)?.totalSteps ?? 0) steps")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            case .notStarted:
                if state.doNotShow {
                    Text("Dismissed")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                } else {
                    Text("Not started")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            case .dismissed:
                Text("Dismissed")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        } else {
            Text("Not started")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }
}
