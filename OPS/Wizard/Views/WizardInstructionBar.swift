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
                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.15))

                    Rectangle()
                        .fill(OPSStyle.Colors.primaryAccent)
                        .frame(width: geo.size.width * stateManager.progressFraction)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: stateManager.progressFraction)
                }
            }
            .frame(height: 3)

            // Content
            VStack(spacing: 6) {
                // Instruction text + step counter
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        if stateManager.isPaused {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                Text("TAP TO RETURN TO GUIDE")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                        } else {
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
                    }

                    Spacer()

                    Text("\(stateManager.currentStepIndex + 1) / \(stateManager.totalSteps)")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .monospacedDigit()
                }

                // Action buttons
                HStack(spacing: 12) {
                    // Skip button
                    if let step = stateManager.currentStep, step.canSkip, !stateManager.isPaused {
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
                        .buttonStyle(PlainButtonStyle())
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
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                BlurView(style: .systemUltraThinMaterialDark)
                    .overlay(OPSStyle.Colors.cardBackgroundDark.opacity(0.9))
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if stateManager.isPaused {
                onPausedBarTapped?()
            }
        }
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
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: stateManager.isActive)
                        .zIndex(998)
                }
            }
    }
}

extension View {
    func wizardInstructionBar(stateManager: WizardStateManager) -> some View {
        modifier(WizardInstructionBarModifier(stateManager: stateManager))
    }
}
