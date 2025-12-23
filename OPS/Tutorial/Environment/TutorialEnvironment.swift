//
//  TutorialEnvironment.swift
//  OPS
//
//  Environment keys for the interactive tutorial system.
//  Allows child views to detect when they're in tutorial mode and adjust behavior.
//

import SwiftUI

// MARK: - Tutorial Mode Environment Key

/// Environment key to indicate whether views are in tutorial mode
struct TutorialModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// When true, views should filter to demo data and may have restricted interactions
    var tutorialMode: Bool {
        get { self[TutorialModeKey.self] }
        set { self[TutorialModeKey.self] = newValue }
    }
}

// MARK: - Tutorial Phase Environment Key

/// Environment key to provide the current tutorial phase to child views
struct TutorialPhaseKey: EnvironmentKey {
    static let defaultValue: TutorialPhase? = nil
}

extension EnvironmentValues {
    /// The current phase of the tutorial, nil when not in tutorial
    var tutorialPhase: TutorialPhase? {
        get { self[TutorialPhaseKey.self] }
        set { self[TutorialPhaseKey.self] = newValue }
    }
}

// MARK: - Tutorial State Manager Environment Key

/// Environment key to provide access to the tutorial state manager
struct TutorialStateManagerKey: EnvironmentKey {
    static let defaultValue: TutorialStateManager? = nil
}

extension EnvironmentValues {
    /// The tutorial state manager, nil when not in tutorial
    var tutorialStateManager: TutorialStateManager? {
        get { self[TutorialStateManagerKey.self] }
        set { self[TutorialStateManagerKey.self] = newValue }
    }
}

// MARK: - View Extensions for Tutorial Mode

extension View {
    /// Injects tutorial mode into the environment
    func tutorialMode(_ enabled: Bool) -> some View {
        environment(\.tutorialMode, enabled)
    }

    /// Injects the current tutorial phase into the environment
    func tutorialPhase(_ phase: TutorialPhase?) -> some View {
        environment(\.tutorialPhase, phase)
    }

    /// Injects the tutorial state manager into the environment
    func tutorialStateManager(_ manager: TutorialStateManager?) -> some View {
        environment(\.tutorialStateManager, manager)
    }

    /// Highlights this view when the current tutorial phase matches
    /// - Parameter phases: The tutorial phase(s) during which this view should be highlighted
    /// - Parameter cornerRadius: Corner radius for the highlight border
    func tutorialHighlight(for phases: TutorialPhase..., cornerRadius: CGFloat = 12) -> some View {
        modifier(TutorialHighlightModifier(phases: phases, cornerRadius: cornerRadius))
    }
}

// MARK: - Tutorial Highlight Style

/// Centralized highlight style configuration for tutorial elements
/// Change these values in one place to update all tutorial highlights
struct TutorialHighlightStyle {
    /// The color of the highlight border
    static let color: Color = OPSStyle.Colors.primaryAccent

    /// The line width of the highlight border
    static let lineWidth: CGFloat = 2

    /// The opacity range for pulsing animation (min, max)
    static let pulseOpacity: (min: Double, max: Double) = (0.3, 1.0)

    /// The duration of one pulse cycle in seconds
    static let pulseDuration: TimeInterval = 1.2

    /// Padding around the highlighted element
    static let padding: CGFloat = 2
}

// MARK: - Tutorial Highlight Modifier (for overlay-style highlights on buttons)

/// View modifier that adds an animated highlight border during specific tutorial phases
struct TutorialHighlightModifier: ViewModifier {
    let phases: [TutorialPhase]
    let cornerRadius: CGFloat

    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var currentPhase

    private var isHighlighted: Bool {
        guard tutorialMode, let current = currentPhase else { return false }
        return phases.contains(current)
    }

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isHighlighted {
                        PulsingBorderOverlay(cornerRadius: cornerRadius)
                    }
                }
            )
    }
}

/// Helper view for pulsing border overlay
private struct PulsingBorderOverlay: View {
    let cornerRadius: CGFloat
    @State private var animatePulse = false
    @State private var isVisible = false  // For fade-in animation

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius + TutorialHighlightStyle.padding)
            .stroke(
                TutorialHighlightStyle.color,
                lineWidth: TutorialHighlightStyle.lineWidth
            )
            .opacity(isVisible ? (animatePulse ? TutorialHighlightStyle.pulseOpacity.max : TutorialHighlightStyle.pulseOpacity.min) : 0)
            .scaleEffect(isVisible ? 1.0 : 0.95)
            .animation(.easeInOut(duration: TutorialHighlightStyle.pulseDuration).repeatForever(autoreverses: true), value: animatePulse)
            .padding(-TutorialHighlightStyle.padding)
            .onAppear {
                // Fade in the highlight
                withAnimation(.easeOut(duration: 0.3)) {
                    isVisible = true
                }
                // Start pulsing after fade-in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    animatePulse = true
                }
            }
    }
}

// MARK: - Tutorial Input Highlight Helper

/// Helper to determine if a field should be highlighted during tutorial
/// Returns border color and whether it's highlighted for input fields
struct TutorialInputHighlight {
    let isHighlighted: Bool
    let animatePulse: Bool

    /// The border color to use (primary accent when highlighted, otherwise default)
    var borderColor: Color {
        isHighlighted ? TutorialHighlightStyle.color : OPSStyle.Colors.inputFieldBorder
    }

    /// The border opacity (pulsing when highlighted)
    var borderOpacity: Double {
        guard isHighlighted else { return 1.0 }
        return animatePulse ? TutorialHighlightStyle.pulseOpacity.max : TutorialHighlightStyle.pulseOpacity.min
    }

    /// The label color to use (primary accent when highlighted, otherwise secondary)
    var labelColor: Color {
        isHighlighted ? TutorialHighlightStyle.color : OPSStyle.Colors.secondaryText
    }

    /// The label opacity (pulsing when highlighted)
    var labelOpacity: Double {
        guard isHighlighted else { return 1.0 }
        return animatePulse ? TutorialHighlightStyle.pulseOpacity.max : TutorialHighlightStyle.pulseOpacity.min
    }
}

// MARK: - Tutorial Highlight with Circle Shape

extension View {
    /// Highlights this view with a circular border when the current tutorial phase matches
    /// Useful for circular buttons like FAB
    func tutorialHighlightCircle(for phases: TutorialPhase...) -> some View {
        modifier(TutorialHighlightCircleModifier(phases: phases))
    }
}

/// View modifier that adds an animated circular highlight border
struct TutorialHighlightCircleModifier: ViewModifier {
    let phases: [TutorialPhase]

    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var currentPhase

    private var isHighlighted: Bool {
        guard tutorialMode, let current = currentPhase else { return false }
        return phases.contains(current)
    }

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isHighlighted {
                        PulsingCircleBorderOverlay()
                    }
                }
            )
    }
}

/// Helper view for pulsing circle border overlay
private struct PulsingCircleBorderOverlay: View {
    @State private var animatePulse = false

    var body: some View {
        Circle()
            .stroke(
                TutorialHighlightStyle.color,
                lineWidth: TutorialHighlightStyle.lineWidth
            )
            .opacity(animatePulse ? TutorialHighlightStyle.pulseOpacity.max : TutorialHighlightStyle.pulseOpacity.min)
            .animation(.easeInOut(duration: TutorialHighlightStyle.pulseDuration).repeatForever(autoreverses: true), value: animatePulse)
            .padding(-TutorialHighlightStyle.padding)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    animatePulse = true
                }
            }
    }
}

// MARK: - Tutorial Pulse Modifier (for opacity-only pulse on input fields)

/// View modifier that adds pulsing opacity animation without affecting layout
/// Use this for input field labels and borders to avoid layout animation issues
///
/// Uses .id() modifier to force complete view recreation when highlight state changes,
/// which ensures animations properly stop when no longer highlighted.
struct TutorialPulseModifier: ViewModifier {
    let isHighlighted: Bool

    func body(content: Content) -> some View {
        // Use Group + .id() to force complete view recreation on highlight change
        // This ensures the pulsing animation stops cleanly when isHighlighted becomes false
        Group {
            if isHighlighted {
                PulsingOpacityWrapper(content: content)
            } else {
                content
            }
        }
        .id(isHighlighted) // Force view recreation when state changes
    }
}

/// Wrapper that applies pulsing animation to its content
/// Isolated to ensure animation state is properly tied to view lifecycle
private struct PulsingOpacityWrapper<Content: View>: View {
    let content: Content
    @State private var opacity: Double = TutorialHighlightStyle.pulseOpacity.min

    var body: some View {
        content
            .opacity(opacity)
            .onAppear {
                // Start pulsing animation
                withAnimation(.easeInOut(duration: TutorialHighlightStyle.pulseDuration).repeatForever(autoreverses: true)) {
                    opacity = TutorialHighlightStyle.pulseOpacity.max
                }
            }
    }
}
