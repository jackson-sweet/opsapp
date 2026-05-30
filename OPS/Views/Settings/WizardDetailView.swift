//
//  WizardDetailView.swift
//  OPS
//
//  Detail view for a single wizard.
//  Shows step list, completion status, resume/restart controls,
//  and "show prompts" toggle.
//

import SwiftUI

struct WizardDetailView: View {
    let wizard: any WizardDefinitionProtocol
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wizardStateManager) private var stateManager

    private var wizardState: WizardState? {
        stateManager?.wizardState(for: wizard.wizardId)
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                SettingsHeader(
                    title: wizard.displayName,
                    onBackTapped: { dismiss() }
                )

                ScrollView {
                    VStack(spacing: 24) {
                        descriptionCard
                        actionButton
                        stepListCard
                        promptToggleCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Subviews

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: wizard.iconName)
                    .font(.system(size: OPSStyle.Layout.IconSize.lg))
                    .foregroundColor(OPSStyle.Colors.wizardAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(wizard.displayName)
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    if let state = wizardState {
                        switch state.status {
                        case .completed:
                            Text("Completed")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.successStatus)
                        case .inProgress:
                            Text("In Progress — \(state.currentStepIndex + 1) / \(wizard.totalSteps)")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                        case .notStarted:
                            Text("Not started")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        case .dismissed:
                            Text("Dismissed")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }
                }

                Spacer()
            }

            Text(wizard.displayDescription)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .lineSpacing(4)
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var actionButton: some View {
        Group {
            if let state = wizardState {
                switch state.status {
                case .inProgress:
                    VStack(spacing: 12) {
                        primaryButton(title: "RESUME", icon: "play.fill") {
                            launchWizard(isRestart: false)
                        }
                        secondaryButton(title: "RESTART") {
                            launchWizard(isRestart: true)
                        }
                    }
                case .completed:
                    secondaryButton(title: "RESTART GUIDE") {
                        launchWizard(isRestart: true)
                    }
                case .notStarted, .dismissed:
                    primaryButton(title: "START GUIDE", icon: "arrow.right") {
                        launchWizard(isRestart: false)
                    }
                }
            } else {
                primaryButton(title: "START GUIDE", icon: "arrow.right") {
                    launchWizard(isRestart: false)
                }
            }
        }
    }

    /// Dismiss the entire Settings cover stack, then start the wizard.
    /// The wizard's own navigation (navigateToCurrentStep + requestDeepNavigation)
    /// handles getting the user to the correct screen.
    private func launchWizard(isRestart: Bool) {
        // Dismiss this detail view first
        dismiss()
        // Dismiss the Settings fullScreenCover so the wizard can navigate freely
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: Notification.Name("WizardDismissSettingsCovers"),
                object: nil
            )
        }
        // Start the wizard after covers have dismissed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            stateManager?.startWizardDirectly(wizard, isRestart: isRestart)
        }
    }

    private var stepListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STEPS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 0) {
                ForEach(Array(wizard.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 14) {
                        stepIndicator(index: index)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.instruction)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(stepColor(index: index))

                            if let desc = step.description {
                                Text(desc)
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)

                    if index < wizard.steps.count - 1 {
                        Rectangle()
                            .fill(OPSStyle.Colors.cardBorder)
                            .frame(height: 1)
                            .padding(.leading, 58)
                    }
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    private var promptToggleCard: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show prompts")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("Show banner when you visit this feature area")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { !(wizardState?.doNotShow ?? false) },
                    set: { newValue in
                        if let state = wizardState {
                            state.doNotShow = !newValue
                            state.needsSync = true

                            if newValue {
                                if state.status == .dismissed {
                                    state.status = .notStarted
                                }

                                stateManager?.analytics.recordEvent(
                                    event: "wizard_prompt_re_enabled",
                                    wizardId: wizard.wizardId,
                                    sessionId: state.currentSessionId,
                                    userId: nil
                                )
                            }
                        }
                    }
                ))
                .tint(OPSStyle.Colors.wizardAccent)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stepIndicator(index: Int) -> some View {
        let currentStep = wizardState?.currentStepIndex ?? 0
        let isCompleted = wizardState?.status == .completed || index < currentStep

        if isCompleted {
            Image("ops.success")
                .font(.system(size: 18))
                .foregroundColor(OPSStyle.Colors.successStatus)
                .frame(width: 28, alignment: .center)
        } else {
            Text("\(index + 1)")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(index == currentStep ? OPSStyle.Colors.wizardAccent : OPSStyle.Colors.tertiaryText)
                .frame(width: 28, alignment: .center)
        }
    }

    private func stepColor(index: Int) -> Color {
        let currentStep = wizardState?.currentStepIndex ?? 0
        let isCompleted = wizardState?.status == .completed || index < currentStep

        if isCompleted { return OPSStyle.Colors.secondaryText }
        if index == currentStep { return OPSStyle.Colors.primaryText }
        return OPSStyle.Colors.tertiaryText
    }

    @ViewBuilder
    private func primaryButton(title: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.invertedText)
                Spacer()
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.invertedText)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
            .background(OPSStyle.Colors.primaryText)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    @ViewBuilder
    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
    }
}
