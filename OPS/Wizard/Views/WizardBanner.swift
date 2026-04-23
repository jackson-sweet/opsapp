//
//  WizardBanner.swift
//  OPS
//
//  A notification-style banner that slides down from the top
//  to prompt users to start a wizard guide.
//  Shows the wizard description with three inline action buttons:
//  Launch, Not Now, Never.
//

import SwiftUI

struct WizardBanner: View {
    let wizard: any WizardDefinitionProtocol
    let onLaunch: () -> Void
    let onNotNow: () -> Void
    let onNever: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Status bar fill
            Color.clear
                .frame(height: 50)
                .background(
                    BlurView(style: .systemUltraThinMaterialDark)
                        .overlay(OPSStyle.Colors.cardBackgroundDark.opacity(0.92))
                )

            // Banner content
            VStack(alignment: .leading, spacing: 16) {
                // Icon + title row
                HStack(spacing: 10) {
                    Image(systemName: wizard.iconName)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.wizardAccent)

                    Text(wizard.displayName)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .tracking(1.2)
                }

                // Description + time estimate
                HStack(spacing: 0) {
                    Text(wizard.bannerText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Spacer(minLength: 8)

                    Text("\(wizard.estimatedMinutes) MIN")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .tracking(0.8)
                }
                .lineLimit(2)

                // Action buttons
                HStack(spacing: 10) {
                    // Launch — primary action
                    Button(action: {
                        TutorialHaptics.lightTap()
                        onLaunch()
                    }) {
                        Text("LAUNCH")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.invertedText)
                            .tracking(1.2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(OPSStyle.Colors.wizardAccent)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Not Now — secondary
                    Button(action: {
                        TutorialHaptics.lightTap()
                        onNotNow()
                    }) {
                        Text("NOT NOW")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .tracking(1.2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(OPSStyle.Colors.background.opacity(0.3))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Never — destructive/tertiary
                    Button(action: {
                        TutorialHaptics.lightTap()
                        onNever()
                    }) {
                        Text("NEVER")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .tracking(1.2)
                            .frame(width: 72)
                            .frame(height: 40)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                BlurView(style: .systemUltraThinMaterialDark)
                    .overlay(OPSStyle.Colors.cardBackgroundDark.opacity(0.92))
            )

            // Bottom separator
            Rectangle()
                .fill(OPSStyle.Colors.wizardAccent.opacity(0.4))
                .frame(height: 2)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
    }
}

// MARK: - View Modifier

struct WizardBannerModifier: ViewModifier {
    @ObservedObject var stateManager: WizardStateManager

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if stateManager.showBanner, let wizard = stateManager.pendingBannerWizard {
                WizardBanner(
                    wizard: wizard,
                    onLaunch: { stateManager.bannerLaunchTapped() },
                    onNotNow: { stateManager.bannerNotNowTapped() },
                    onNever: { stateManager.bannerNeverTapped() }
                )
                .ignoresSafeArea()
                .zIndex(998)
            }
        }
    }
}

extension View {
    func wizardBanner(stateManager: WizardStateManager) -> some View {
        modifier(WizardBannerModifier(stateManager: stateManager))
    }

    /// Applies the wizard banner only when a state manager is available.
    /// Use inside fullScreenCovers where the root banner is hidden.
    @ViewBuilder
    func wizardBannerIfAvailable(stateManager: WizardStateManager?) -> some View {
        if let manager = stateManager {
            self.wizardBanner(stateManager: manager)
        } else {
            self
        }
    }
}
