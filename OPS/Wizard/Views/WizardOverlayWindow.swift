//
//  WizardOverlayWindow.swift
//  OPS
//
//  Wizard instruction bar + exit prompt, applied as a SwiftUI modifier
//  on the root content view. No secondary UIWindow — just native SwiftUI.
//

import SwiftUI
import UIKit

// MARK: - Wizard Overlay Modifier

/// Adds the wizard instruction bar (bottom), exit prompt (centered), and
/// completion toast to any view. Apply once at the ContentView level.
struct WizardOverlayModifier: ViewModifier {
    @ObservedObject var stateManager: WizardStateManager

    @State private var showExitPrompt = false
    @State private var currentTab: String = ""
    @State private var exitPromptSuppressedUntil: Date = .distantPast

    private static let fullscreenManagedWizards: Set<String> = ["inventory_setup"]

    private var isFullscreenManaged: Bool {
        guard let wizardId = stateManager.activeWizard?.wizardId else { return false }
        return Self.fullscreenManagedWizards.contains(wizardId)
    }

    func body(content: Content) -> some View {
        content
            // Instruction bar — collapses between steps so tab bar is visible during transitions
            .safeAreaInset(edge: .bottom) {
                if stateManager.isActive && !showExitPrompt && !isFullscreenManaged && !stateManager.isStepTransitioning {
                    WizardInstructionBar(
                        stateManager: stateManager,
                        onPausedBarTapped: {
                            stateManager.navigateToCurrentStep()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                stateManager.requestDeepNavigation()
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(998)
                }
            }
            // Completion toast pinned to bottom — a prominent two-line confirmation
            // so the user actually registers that the guide wrapped up, instead
            // of a thin bar that blinks past in 2 seconds.
            .safeAreaInset(edge: .bottom) {
                if let completedId = stateManager.completedWizardId {
                    let isWelcomeTour = completedId == "welcome_tour"
                    HStack(alignment: .center, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(OPSStyle.Colors.wizardAccent.opacity(0.18))
                                .frame(width: 36, height: 36)
                            Image(systemName: isWelcomeTour ? "hand.thumbsup.fill" : "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(OPSStyle.Colors.wizardAccent)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isWelcomeTour ? "YOU'RE ALL SET." : "GUIDE COMPLETE.")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .tracking(1.2)
                            Text(isWelcomeTour ? "Start running your jobs." : "You know the board — get after it.")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        BlurView(style: .systemUltraThinMaterialDark)
                            .overlay(OPSStyle.Colors.cardBackgroundDark.opacity(0.92))
                            .ignoresSafeArea(edges: .bottom)
                    )
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(OPSStyle.Colors.wizardAccent.opacity(0.45))
                            .frame(height: 2)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Exit prompt overlay — full-screen scrim + centered dialog
            .overlay {
                if showExitPrompt && !isFullscreenManaged {
                    ZStack {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)

                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                TutorialHaptics.lightTap()
                                showExitPrompt = false
                                stateManager.isPaused = false
                                stateManager.navigateToCurrentStep()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    stateManager.requestDeepNavigation()
                                }
                            }

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3_5) {
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                Text("LEAVE GUIDE?")
                                    .font(OPSStyle.Typography.cardTitle)
                                    .foregroundColor(OPSStyle.Colors.primaryText)

                                Text("You navigated away from the setup guide.")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }

                            VStack(spacing: OPSStyle.Layout.spacing2_5) {
                                Button {
                                    TutorialHaptics.lightTap()
                                    showExitPrompt = false
                                    stateManager.isPaused = false
                                    stateManager.navigateToCurrentStep()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        stateManager.requestDeepNavigation()
                                    }
                                } label: {
                                    Text("CONTINUE GUIDE")
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.buttonText)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                                        .background(OPSStyle.Colors.wizardAccent)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                }

                                Button {
                                    TutorialHaptics.lightTap()
                                    showExitPrompt = false
                                    stateManager.isPaused = false
                                    stateManager.exitWizard()
                                } label: {
                                    Text("EXIT GUIDE")
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                                        .background(OPSStyle.Colors.cardBackgroundDark)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(OPSStyle.Layout.spacing4)
                        .background(
                            BlurView(style: .systemUltraThinMaterialDark)
                                .overlay(OPSStyle.Colors.cardBackgroundDark.opacity(0.85))
                        )
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                        .padding(.horizontal, OPSStyle.Layout.spacing4)
                        .contentShape(Rectangle())
                        .onTapGesture { }
                    }
                    .transition(.opacity)
                    .zIndex(999)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: stateManager.isActive)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: stateManager.currentStepIndex)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showExitPrompt)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: stateManager.completedWizardId != nil)
            .animation(.easeInOut(duration: 0.2), value: stateManager.isStepTransitioning)
            .onChange(of: stateManager.isActive) { _, active in
                if !active {
                    showExitPrompt = false
                } else {
                    exitPromptSuppressedUntil = Date().addingTimeInterval(2.0)
                }
            }
            .onChange(of: stateManager.currentStepIndex) { _, _ in
                exitPromptSuppressedUntil = Date().addingTimeInterval(2.0)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardCurrentTabChanged"))) { notification in
                guard let tabName = notification.userInfo?["tabName"] as? String else { return }

                // Dismiss any pending banner when the user leaves the triggering tab.
                // Animate the slide-out, then clear the wizard reference after the
                // transition so the view isn't yanked mid-animation. Timing here
                // must match the curve/duration on WizardBannerModifier — any
                // mismatch re-introduces the jerky slide this fix is addressing.
                if stateManager.showBanner {
                    withAnimation(OPSStyle.Animation.page) {
                        stateManager.showBanner = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                        stateManager.pendingBannerWizard = nil
                    }
                }

                guard stateManager.isActive else { return }
                currentTab = tabName

                guard let targetScreen = stateManager.currentStep?.targetScreen,
                      let expectedTab = WizardStateManager.tabTarget(for: targetScreen) else { return }

                let isDeepNavOpen = stateManager.deepNavProjectId != nil
                if tabName != expectedTab && !showExitPrompt && Date() > exitPromptSuppressedUntil && !isDeepNavOpen && !isFullscreenManaged {
                    stateManager.isPaused = true
                    showExitPrompt = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardScreenDismissed"))) { notification in
                guard stateManager.isActive,
                      let dismissedScreen = notification.userInfo?["screen"] as? String else { return }

                if let targetScreen = stateManager.currentStep?.targetScreen,
                   targetScreen == dismissedScreen && !showExitPrompt && Date() > exitPromptSuppressedUntil && !isFullscreenManaged {
                    stateManager.isPaused = true
                    showExitPrompt = true
                }
            }
    }
}

extension View {
    func wizardOverlay(stateManager: WizardStateManager) -> some View {
        modifier(WizardOverlayModifier(stateManager: stateManager))
    }

    /// Applies the wizard overlay (instruction bar + exit prompt) only when
    /// a state manager is available. Use inside fullScreenCovers.
    @ViewBuilder
    func wizardOverlayIfAvailable(stateManager: WizardStateManager?) -> some View {
        if let manager = stateManager {
            self.wizardOverlay(stateManager: manager)
        } else {
            self
        }
    }
}

// MARK: - Legacy Overlay Controller (kept for teardown compatibility)

@MainActor
class WizardOverlayController: ObservableObject {
    static let shared = WizardOverlayController()
    private init() {}

    /// No-op — overlay is now a SwiftUI modifier, not a UIWindow.
    func install(stateManager: WizardStateManager) {}

    /// No-op — nothing to tear down.
    func teardown() {}
}
