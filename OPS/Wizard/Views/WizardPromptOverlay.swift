//
//  WizardPromptOverlay.swift
//  OPS
//
//  Modal overlay shown when user taps the wizard banner.
//  Presents wizard description with Start Guide / Maybe Later options
//  and a "Don't show me again" checkbox.
//

import SwiftUI

struct WizardPromptOverlay: View {
    let wizard: any WizardDefinitionProtocol
    let onStart: (Bool) -> Void       // doNotShowAgain
    let onDismiss: (Bool) -> Void     // doNotShowAgain

    @State private var doNotShowAgain: Bool = false

    var body: some View {
        ZStack {
            // Scrim
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { /* Prevent tap-through */ }

            // Card
            VStack(alignment: .leading, spacing: 0) {
                // Title
                HStack(spacing: 12) {
                    Image(systemName: wizard.iconName)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.wizardAccent)

                    Text(wizard.displayName)
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.bottom, 16)

                // Description
                Text(wizard.displayDescription)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineSpacing(4)
                    .padding(.bottom, 12)

                // Time estimate
                HStack(spacing: 6) {
                    Image("ops.clock")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Text("About \(wizard.estimatedMinutes) min")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.bottom, 20)

                // Bullet points
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(wizard.bulletPoints.enumerated()), id: \.offset) { index, point in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.wizardAccent)
                                .frame(width: 20, alignment: .center)

                            Text(point)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .padding(.vertical, 10)

                        if index < wizard.bulletPoints.count - 1 {
                            Rectangle()
                                .fill(OPSStyle.Colors.cardBorderSubtle)
                                .frame(height: 1)
                                .padding(.leading, 30)
                        }
                    }
                }
                .padding(.bottom, 24)

                // Start Guide button
                Button {
                    TutorialHaptics.lightTap()
                    onStart(doNotShowAgain)
                } label: {
                    HStack {
                        Text("START GUIDE")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.buttonText)

                        Spacer()

                        Image("ops.arrow-right")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.buttonText)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 56)
                    .background(OPSStyle.Colors.wizardAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .padding(.bottom, 12)

                // Maybe Later button
                Button {
                    TutorialHaptics.lightTap()
                    onDismiss(doNotShowAgain)
                } label: {
                    Text("MAYBE LATER")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .padding(.bottom, 16)

                // Don't show again checkbox
                Button {
                    doNotShowAgain.toggle()
                    TutorialHaptics.lightTap()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: doNotShowAgain ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18))
                            .foregroundColor(doNotShowAgain ? OPSStyle.Colors.wizardAccent : OPSStyle.Colors.tertiaryText)

                        Text("Don't show me this again")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(28)
            .background(
                BlurView(style: .systemUltraThinMaterialDark)
                    .overlay(OPSStyle.Colors.cardBackgroundDark.opacity(0.7))
            )
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - View Modifier

struct WizardPromptOverlayModifier: ViewModifier {
    @ObservedObject var stateManager: WizardStateManager

    func body(content: Content) -> some View {
        ZStack {
            content

            if stateManager.showPromptOverlay, let wizard = stateManager.pendingBannerWizard {
                WizardPromptOverlay(
                    wizard: wizard,
                    onStart: { doNotShow in
                        stateManager.startWizard(doNotShowAgain: doNotShow)
                    },
                    onDismiss: { doNotShow in
                        stateManager.dismissWizard(doNotShowAgain: doNotShow)
                    }
                )
                .transition(.opacity)
                .animation(OPSStyle.Animation.standard, value: stateManager.showPromptOverlay)
                .zIndex(999)
            }
        }
    }
}

extension View {
    func wizardPromptOverlay(stateManager: WizardStateManager) -> some View {
        modifier(WizardPromptOverlayModifier(stateManager: stateManager))
    }
}
