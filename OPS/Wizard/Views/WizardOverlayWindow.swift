//
//  WizardOverlayWindow.swift
//  OPS
//
//  A UIWindow-level overlay that persists the wizard instruction bar
//  across ALL presentation contexts — sheets, fullScreenCovers, alerts.
//  Uses a passthrough window so touches outside the bar reach the app.
//

import SwiftUI
import UIKit

// MARK: - Passthrough Window

/// A UIWindow that only intercepts touches on its visible content.
/// Touches on transparent areas pass through to the window below.
class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else { return nil }
        // If the hit view is the root hosting controller's view (transparent background),
        // return nil so the touch passes through to the app window below.
        if hitView === rootViewController?.view {
            return nil
        }
        return hitView
    }
}

// MARK: - Wizard Overlay Controller

@MainActor
class WizardOverlayController: ObservableObject {
    static let shared = WizardOverlayController()

    private var overlayWindow: PassthroughWindow?
    private var hostingController: UIHostingController<AnyView>?
    private weak var stateManager: WizardStateManager?

    private init() {}

    /// Install the overlay window. Call once from OPSApp or ContentView after wizard system is configured.
    func install(stateManager: WizardStateManager) {
        guard overlayWindow == nil else { return }
        self.stateManager = stateManager

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        let overlayView = WizardOverlayView(stateManager: stateManager)
        let hosting = UIHostingController(rootView: AnyView(overlayView))
        hosting.view.backgroundColor = .clear

        let window = PassthroughWindow(windowScene: windowScene)
        window.windowLevel = .alert - 1 // Below alerts, above everything else
        window.rootViewController = hosting
        window.isHidden = false
        window.backgroundColor = .clear

        self.overlayWindow = window
        self.hostingController = hosting
    }

    /// Remove the overlay (cleanup).
    func teardown() {
        overlayWindow?.isHidden = true
        overlayWindow = nil
        hostingController = nil
        stateManager = nil
    }
}

// MARK: - Overlay SwiftUI View

/// The SwiftUI view hosted in the overlay window.
/// Shows the instruction bar at the bottom when a wizard is active.
/// Detects when the user navigates away from the wizard context and prompts to exit.
private struct WizardOverlayView: View {
    @ObservedObject var stateManager: WizardStateManager

    @State private var showExitPrompt = false
    @State private var currentTab: String = ""
    @State private var exitPromptSuppressedUntil: Date = .distantPast

    /// Wizards that manage their own fullscreen flow and should not show
    /// the overlay instruction bar or exit-prompt detection.
    private static let fullscreenManagedWizards: Set<String> = ["inventory_setup"]

    private var isFullscreenManaged: Bool {
        guard let wizardId = stateManager.activeWizard?.wizardId else { return false }
        return Self.fullscreenManagedWizards.contains(wizardId)
    }

    var body: some View {
        ZStack {
            // Exit prompt overlay — suppressed for wizards with their own fullscreen flow
            if showExitPrompt && !isFullscreenManaged {
                // Scrim — tapping outside the dialog returns to the wizard.
                // allowsHitTesting(false) on the scrim itself; a background tap
                // handler on the full ZStack layer handles dismiss so it never
                // competes with the dialog buttons.
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // Invisible tap catcher behind the dialog — returns to wizard
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

                // Dialog card
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LEAVE GUIDE?")
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("You navigated away from the setup guide.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }

                    VStack(spacing: 12) {
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
                .padding(24)
                .background(
                    BlurView(style: .systemUltraThinMaterialDark)
                        .overlay(OPSStyle.Colors.cardBackgroundDark.opacity(0.85))
                )
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .padding(.horizontal, 24)
                // Prevent taps on the dialog from falling through to the dismiss handler
                .contentShape(Rectangle())
                .onTapGesture { } // Block taps from falling through to dismiss handler
                .transition(.opacity)
            }

            // Instruction bar at bottom — hidden for wizards that manage their own fullscreen flow
            VStack {
                Spacer()

                if stateManager.isActive && !showExitPrompt && !isFullscreenManaged {
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
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: stateManager.isActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: stateManager.currentStepIndex)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showExitPrompt)
        .onChange(of: stateManager.isActive) { _, active in
            // Clear exit prompt if wizard completes/exits while prompt is showing
            if !active {
                showExitPrompt = false
            } else {
                // Suppress exit prompt for 2s after wizard starts (allows navigation to settle)
                exitPromptSuppressedUntil = Date().addingTimeInterval(2.0)
            }
        }
        .onChange(of: stateManager.currentStepIndex) { _, _ in
            // Suppress exit prompt for 2s after each step advancement.
            // Prevents false exit prompts when a step completion triggers a sheet/cover dismiss
            // that fires WizardScreenDismissed before the user has returned to the target view.
            exitPromptSuppressedUntil = Date().addingTimeInterval(2.0)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardCurrentTabChanged"))) { notification in
            guard stateManager.isActive,
                  let tabName = notification.userInfo?["tabName"] as? String else { return }
            currentTab = tabName

            // Check if the user navigated away from the wizard's target area
            guard let targetScreen = stateManager.currentStep?.targetScreen,
                  let expectedTab = WizardStateManager.tabTarget(for: targetScreen) else { return }

            // Suppress exit prompt when a wizard deep-nav sheet is open above the tab bar —
            // the underlying tab may differ from the expected tab, but the user is still
            // correctly inside the wizard context (e.g., documentation wizard in project details).
            let isDeepNavOpen = stateManager.deepNavProjectId != nil
            if tabName != expectedTab && !showExitPrompt && Date() > exitPromptSuppressedUntil && !isDeepNavOpen && !isFullscreenManaged {
                stateManager.isPaused = true
                showExitPrompt = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardScreenDismissed"))) { notification in
            guard stateManager.isActive,
                  let dismissedScreen = notification.userInfo?["screen"] as? String else { return }

            // If the dismissed screen matches the wizard's current target, prompt to exit
            if let targetScreen = stateManager.currentStep?.targetScreen,
               targetScreen == dismissedScreen && !showExitPrompt && Date() > exitPromptSuppressedUntil && !isFullscreenManaged {
                stateManager.isPaused = true
                showExitPrompt = true
            }
        }
    }
}
