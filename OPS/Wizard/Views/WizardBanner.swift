//
//  WizardBanner.swift
//  OPS
//
//  A persistent, tappable banner that slides down from the top
//  to prompt users to start a wizard guide.
//  Unlike NotificationBanner, this does NOT auto-dismiss.
//

import SwiftUI

struct WizardBanner: View {
    let message: String
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Status bar background
            Color.clear
                .frame(height: 50)
                .background(
                    BlurView(style: .systemUltraThinMaterialDark)
                        .overlay(OPSStyle.Colors.cardBackgroundDark.opacity(0.85))
                )

            // Banner content
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)

                    Text(message)
                        .font(OPSStyle.Typography.cardSubtitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    // Close button
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(width: 28, height: 28)
                            .background(OPSStyle.Colors.background.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    BlurView(style: .systemUltraThinMaterialDark)
                        .overlay(OPSStyle.Colors.cardBackgroundDark.opacity(0.85))
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .transition(.asymmetric(
            insertion: .move(edge: .top),
            removal: .move(edge: .top)
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
                    message: wizard.bannerText,
                    onTap: { stateManager.bannerTapped() },
                    onDismiss: { stateManager.bannerDismissed() }
                )
                .ignoresSafeArea()
                .zIndex(998)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: stateManager.showBanner)
            }
        }
    }
}

extension View {
    func wizardBanner(stateManager: WizardStateManager) -> some View {
        modifier(WizardBannerModifier(stateManager: stateManager))
    }
}
