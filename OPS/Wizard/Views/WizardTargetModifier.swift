//
//  WizardTargetModifier.swift
//  OPS
//
//  View modifiers that mark UI elements as wizard step targets.
//  When the current wizard step matches, the element gets a pulsing
//  orange glow whose shape and intensity are driven by the element type.
//
//  All styling tokens live in OPSStyle.Wizard — edit there to change
//  every wizard glow centrally.
//
//  Usage:
//    Button("Save") { ... }
//        .wizardTarget("save_project")
//
//    fabButton
//        .wizardTarget("open_fab", style: .circle)
//
//    TextField("Name", text: $name)
//        .wizardTarget("enter_name", style: .input)
//
//    settingsRow(...)
//        .wizardTarget("open_profile", style: .row)
//

import SwiftUI

// MARK: - Wizard Target Style

/// The shape / intensity profile for a wizard glow.
/// Each case maps to a token set in `OPSStyle.Wizard`.
enum WizardTargetStyle {
    /// Rounded rectangle — buttons, tappable areas (default)
    case button
    /// Circle — FAB, avatars, round buttons
    case circle
    /// Text field / input — subtle fill, prominent border
    case input
    /// List row / card — full-width highlight
    case row
}

// MARK: - Environment Bridge

/// Reads the wizard state manager from Environment and bridges it
/// to an @ObservedObject so SwiftUI properly observes @Published changes.
struct WizardTargetModifier: ViewModifier {
    let stepIds: [String]
    let style: WizardTargetStyle
    @Environment(\.wizardStateManager) private var stateManager

    func body(content: Content) -> some View {
        if let manager = stateManager {
            WizardTargetGlow(
                stepIds: stepIds,
                style: style,
                stateManager: manager
            ) {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - Glow View (observes state manager)

/// Inner view that uses @ObservedObject to properly react to wizard state changes.
private struct WizardTargetGlow<Content: View>: View {
    let stepIds: [String]
    let style: WizardTargetStyle
    @ObservedObject var stateManager: WizardStateManager
    @ViewBuilder let content: Content

    @State private var pulsePhase: Bool = false

    private var isActive: Bool {
        guard stateManager.isActive,
              let currentStep = stateManager.currentStep else { return false }
        return stepIds.contains(currentStep.id)
    }

    // MARK: - Token resolution

    private var fillOpacityHigh: Double {
        switch style {
        case .button: return OPSStyle.Wizard.Button.fillOpacityHigh
        case .circle: return OPSStyle.Wizard.Circle.fillOpacityHigh
        case .input:  return OPSStyle.Wizard.Input.fillOpacityHigh
        case .row:    return OPSStyle.Wizard.Row.fillOpacityHigh
        }
    }

    private var fillOpacityLow: Double {
        switch style {
        case .button: return OPSStyle.Wizard.Button.fillOpacityLow
        case .circle: return OPSStyle.Wizard.Circle.fillOpacityLow
        case .input:  return OPSStyle.Wizard.Input.fillOpacityLow
        case .row:    return OPSStyle.Wizard.Row.fillOpacityLow
        }
    }

    private var borderOpacityHigh: Double {
        switch style {
        case .button: return OPSStyle.Wizard.Button.borderOpacityHigh
        case .circle: return OPSStyle.Wizard.Circle.borderOpacityHigh
        case .input:  return OPSStyle.Wizard.Input.borderOpacityHigh
        case .row:    return OPSStyle.Wizard.Row.borderOpacityHigh
        }
    }

    private var borderOpacityLow: Double {
        switch style {
        case .button: return OPSStyle.Wizard.Button.borderOpacityLow
        case .circle: return OPSStyle.Wizard.Circle.borderOpacityLow
        case .input:  return OPSStyle.Wizard.Input.borderOpacityLow
        case .row:    return OPSStyle.Wizard.Row.borderOpacityLow
        }
    }

    private var borderWidth: CGFloat {
        switch style {
        case .button: return OPSStyle.Wizard.Button.borderWidth
        case .circle: return OPSStyle.Wizard.Circle.borderWidth
        case .input:  return OPSStyle.Wizard.Input.borderWidth
        case .row:    return OPSStyle.Wizard.Row.borderWidth
        }
    }

    private var cornerRadius: CGFloat {
        switch style {
        case .button: return OPSStyle.Wizard.Button.cornerRadius
        case .circle: return 0
        case .input:  return OPSStyle.Wizard.Input.cornerRadius
        case .row:    return OPSStyle.Wizard.Row.cornerRadius
        }
    }

    private let color = OPSStyle.Wizard.accentColor
    private let duration = OPSStyle.Wizard.pulseDuration

    // MARK: - Body

    var body: some View {
        content
            .background(
                Group {
                    if isActive {
                        glowFill
                            .animation(
                                .easeInOut(duration: duration).repeatForever(autoreverses: true),
                                value: pulsePhase
                            )
                    }
                }
            )
            .overlay(
                Group {
                    if isActive {
                        glowBorder
                            .animation(
                                .easeInOut(duration: duration).repeatForever(autoreverses: true),
                                value: pulsePhase
                            )
                    }
                }
            )
            .id(isActive ? "wizard_active_\(stepIds.first ?? "")" : "")
            .onChange(of: isActive) { _, active in
                pulsePhase = active
                if active, let stepId = stepIds.first {
                    // Request scroll to this element
                    NotificationCenter.default.post(
                        name: Notification.Name("WizardScrollToTarget"),
                        object: nil,
                        userInfo: ["stepId": stepId]
                    )
                }
            }
            .onAppear {
                if isActive {
                    pulsePhase = true
                    // Post scroll request on appear — handles the case where the view
                    // wasn't in the hierarchy when the step activated (e.g., returning
                    // from a detail view). The onChange(of: isActive) only fires on
                    // transitions, so this covers the "already active" case.
                    if let stepId = stepIds.first {
                        NotificationCenter.default.post(
                            name: Notification.Name("WizardScrollToTarget"),
                            object: nil,
                            userInfo: ["stepId": stepId]
                        )
                    }
                }
            }
    }

    // MARK: - Shape builders

    @ViewBuilder
    private var glowFill: some View {
        let opacity = pulsePhase ? fillOpacityHigh : fillOpacityLow
        switch style {
        case .circle:
            Circle().fill(color.opacity(opacity)).padding(-6)
        case .button, .input, .row:
            RoundedRectangle(cornerRadius: cornerRadius).fill(color.opacity(opacity))
        }
    }

    @ViewBuilder
    private var glowBorder: some View {
        let opacity = pulsePhase ? borderOpacityHigh : borderOpacityLow
        switch style {
        case .circle:
            Circle().stroke(color.opacity(opacity), lineWidth: borderWidth).padding(-6)
        case .button, .input, .row:
            RoundedRectangle(cornerRadius: cornerRadius).stroke(color.opacity(opacity), lineWidth: borderWidth)
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Marks this view as the target for a wizard step.
    /// When the wizard reaches this step, the view gets a pulsing orange glow.
    ///
    /// - Parameters:
    ///   - stepId: The wizard step ID (e.g., "open_profile")
    ///   - style: The glow shape/intensity profile. Defaults to `.button`.
    func wizardTarget(_ stepId: String, style: WizardTargetStyle = .button) -> some View {
        modifier(WizardTargetModifier(stepIds: [stepId], style: style))
    }

    /// Marks this view as the target for multiple wizard steps (e.g., FAB matches two steps).
    ///
    /// - Parameters:
    ///   - style: The glow shape/intensity profile.
    ///   - stepIds: The wizard step IDs this view corresponds to.
    func wizardTarget(style: WizardTargetStyle, _ stepIds: String...) -> some View {
        modifier(WizardTargetModifier(stepIds: stepIds, style: style))
    }
}
