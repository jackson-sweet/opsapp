//
//  WizardInstructionBar.swift
//  OPS
//
//  Persistent bottom bar shown during active wizards.
//  Displays current instruction, step progress, skip, and exit.
//  Positioned above the tab bar.
//

import SwiftUI

struct WizardInstructionBar: View {
    @ObservedObject var stateManager: WizardStateManager
    var onPausedBarTapped: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(OPSStyle.Colors.wizardAccent.opacity(0.15))

                    Rectangle()
                        .fill(OPSStyle.Colors.wizardAccent)
                        .frame(width: geo.size.width * stateManager.progressFraction)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: stateManager.progressFraction)
                }
            }
            .frame(height: 3)

            // Content — paused and active are separate branches so the paused
            // tap gesture never interferes with the active-state buttons.
            if stateManager.isPaused {
                // Paused: entire bar is one big tappable area
                VStack(spacing: 6) {
                    HStack(alignment: .top) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(OPSStyle.Colors.wizardAccent)
                            Text("TAP TO RETURN TO GUIDE")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.wizardAccent)
                        }

                        Spacer()

                        Text("\(stateManager.currentStepIndex + 1) / \(stateManager.totalSteps)")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    onPausedBarTapped?()
                }
            } else {
                // Active: skip and exit are individual buttons — no parent tap gesture
                VStack(spacing: 6) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stateManager.currentInstruction)
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            if let desc = stateManager.currentDescription {
                                Text(desc)
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()

                        Text("\(stateManager.currentStepIndex + 1) / \(stateManager.totalSteps)")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .monospacedDigit()
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        // Skip button (hidden for welcome tour — NEXT replaces it)
                        if let step = stateManager.currentStep, step.canSkip {
                            Button {
                                TutorialHaptics.lightTap()
                                stateManager.skipCurrentStep()
                            } label: {
                                Text("SKIP")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(OPSStyle.Colors.background.opacity(0.5))
                                    .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                            }
                        }

                        // NEXT button for welcome tour (informational steps)
                        if stateManager.activeWizard?.wizardId == "welcome_tour" {
                            let isLastStep = stateManager.currentStepIndex >= stateManager.totalSteps - 1
                            Button {
                                TutorialHaptics.lightTap()

                                // Collapse bar → switch tab → expand bar with new step
                                stateManager.isStepTransitioning = true

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    stateManager.completeCurrentStep()

                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        if isLastStep {
                                            NotificationCenter.default.post(
                                                name: Notification.Name("WizardNavigateToTarget"),
                                                object: nil,
                                                userInfo: ["tabTarget": "Home"]
                                            )
                                        } else {
                                            stateManager.navigateToCurrentStep()
                                        }

                                        // Slide back up after tab settles
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                            stateManager.isStepTransitioning = false
                                        }
                                    }
                                }
                            } label: {
                                Text(isLastStep ? "GET STARTED" : "NEXT")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.invertedText)
                                    .tracking(1.2)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(OPSStyle.Colors.wizardAccent)
                                    .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                            }
                        }

                        Spacer()

                        // Exit button
                        Button {
                            TutorialHaptics.lightTap()
                            stateManager.exitWizard()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text("EXIT")
                                    .font(OPSStyle.Typography.captionBold)
                            }
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(OPSStyle.Colors.background.opacity(0.5))
                            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .background(
            BlurView(style: .systemUltraThinMaterialDark)
                .overlay(OPSStyle.Colors.cardBackgroundDark.opacity(0.9))
                .ignoresSafeArea(edges: .bottom)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - View Modifier

struct WizardInstructionBarModifier: ViewModifier {
    @ObservedObject var stateManager: WizardStateManager

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if stateManager.isActive {
                    WizardInstructionBar(stateManager: stateManager)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(998)
                }
            }
            .animation(OPSStyle.Animation.spring, value: stateManager.isActive)
    }
}

extension View {
    func wizardInstructionBar(stateManager: WizardStateManager) -> some View {
        modifier(WizardInstructionBarModifier(stateManager: stateManager))
    }
}
