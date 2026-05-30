//
//  WizardTestingView.swift
//  OPS
//
//  Developer testing controls for the wizard system.
//  Allows resetting states, force-triggering wizards, and viewing event logs.
//

import SwiftUI

struct WizardTestingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var stateManager: WizardStateManager

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                ZStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(OPSStyle.Icons.close)
                                .font(.system(size: 20))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)

                    Text("WIZARD TESTING")
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.vertical, 16)

                ScrollView {
                    VStack(spacing: 24) {
                        masterToggleCard
                        globalActionsCard
                        perWizardControls
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
        }
    }

    private var masterToggleCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wizard System")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text("Master on/off for the entire wizard system")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { stateManager.isEnabled },
                set: { newValue in
                    if newValue != stateManager.isEnabled {
                        stateManager.toggleEnabled()
                    }
                }
            ))
                .tint(OPSStyle.Colors.primaryAccent)
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var globalActionsCard: some View {
        VStack(spacing: 0) {
            Button {
                stateManager.resetAllStates()
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                    Text("Reset All Wizard States")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var perWizardControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PER-WIZARD CONTROLS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ForEach(Array(WizardRegistry.allWizards.enumerated()), id: \.element.wizardId) { _, wizard in
                wizardControlCard(wizard: wizard)
            }
        }
    }

    @ViewBuilder
    private func wizardControlCard(wizard: any WizardDefinitionProtocol) -> some View {
        let state = stateManager.wizardState(for: wizard.wizardId)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(wizard.displayName)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                Text(state?.status.rawValue ?? "no state")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            if let state {
                HStack(spacing: 16) {
                    Text("Step: \(state.currentStepIndex)/\(wizard.totalSteps)")
                    Text("Skipped: \(state.stepsSkipped)")
                    Text("DoNotShow: \(state.doNotShow ? "YES" : "NO")")
                }
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            HStack(spacing: 8) {
                Button("Reset") {
                    stateManager.resetState(for: wizard.wizardId)
                }
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.errorStatus)

                Button("Force Trigger") {
                    stateManager.forceTrigger(wizard: wizard)
                }
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.primaryAccent)

                Spacer()
            }

            if wizard.steps.count > 1 {
                HStack(spacing: 4) {
                    Text("Jump to:")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    ForEach(0..<min(wizard.steps.count, 12), id: \.self) { index in
                        Button("\(index + 1)") {
                            if stateManager.activeWizard?.wizardId != wizard.wizardId {
                                stateManager.startWizardDirectly(wizard)
                            }
                            stateManager.jumpToStep(index)
                        }
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(width: 24, height: 24)
                        .background(OPSStyle.Colors.background.opacity(0.5))
                        .cornerRadius(OPSStyle.Layout.chipRadius)
                    }
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}
