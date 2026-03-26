//
//  WizardTargetModifier.swift
//  OPS
//
//  A view modifier that marks a UI element as the target for a wizard step.
//  When the current wizard step matches, the element gets a pulsing orange
//  background fill that draws the user's eye to the action they need to take.
//
//  Usage:
//    settingsRow(icon: "person", title: "Profile")
//        .wizardTarget("open_profile")
//

import SwiftUI

// MARK: - Wizard Target Modifier

struct WizardTargetModifier: ViewModifier {
    let stepId: String
    @Environment(\.wizardStateManager) private var stateManager

    private var isActive: Bool {
        guard let manager = stateManager,
              manager.isActive,
              let currentStep = manager.currentStep else { return false }
        return currentStep.id == stepId
    }

    @State private var pulsePhase: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                Group {
                    if isActive {
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(OPSStyle.Colors.wizardAccent.opacity(pulsePhase ? 0.35 : 0.15))
                            .animation(
                                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                                value: pulsePhase
                            )
                    }
                }
            )
            .overlay(
                Group {
                    if isActive {
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.wizardAccent.opacity(pulsePhase ? 0.9 : 0.4), lineWidth: 2)
                            .animation(
                                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                                value: pulsePhase
                            )
                    }
                }
            )
            .onChange(of: isActive) { _, active in
                if active {
                    pulsePhase = true
                } else {
                    pulsePhase = false
                }
            }
            .onAppear {
                if isActive {
                    pulsePhase = true
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// Marks this view as the target for a wizard step.
    /// When the wizard reaches this step, the view gets a pulsing orange highlight.
    ///
    /// - Parameter stepId: The wizard step ID that this view corresponds to (e.g., "open_profile")
    func wizardTarget(_ stepId: String) -> some View {
        modifier(WizardTargetModifier(stepId: stepId))
    }
}
