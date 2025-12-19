//
//  TutorialCompletionView.swift
//  OPS
//
//  Final completion screen showing success message and optional completion time.
//  Uses typewriter animation for the completion message.
//

import SwiftUI

/// Completion screen shown when the tutorial is finished
struct TutorialCompletionView: View {
    /// The tutorial state manager
    @ObservedObject var manager: TutorialStateManager

    /// Callback when user dismisses the completion screen
    let onDismiss: () -> Void

    /// Animation state
    @State private var showMessage: Bool = false
    @State private var showButton: Bool = false

    var body: some View {
        ZStack {
            // Dark background
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Completion message with typewriter animation
                if showMessage {
                    completionMessage
                }

                Spacer()

                // CTA Button
                if showButton {
                    ctaButton
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .transition(.opacity)
        .onAppear {
            startAnimationSequence()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var completionMessage: some View {
        if manager.showTimeInCompletion {
            // Show time if completed quickly (< 3 min)
            TypewriterText(
                "DONE IN \(manager.formattedTime). NOW WE'RE TALKING.",
                font: OPSStyle.Typography.title,
                color: OPSStyle.Colors.primaryText,
                typingSpeed: 25
            ) {
                // Show button after message completes
                withAnimation(.easeOut(duration: 0.3)) {
                    showButton = true
                }
            }
            .multilineTextAlignment(.center)
        } else {
            // Generic completion message for longer times
            TypewriterText(
                "DONE. LET'S GET TO WORK.",
                font: OPSStyle.Typography.title,
                color: OPSStyle.Colors.primaryText,
                typingSpeed: 25
            ) {
                // Show button after message completes
                withAnimation(.easeOut(duration: 0.3)) {
                    showButton = true
                }
            }
            .multilineTextAlignment(.center)
        }
    }

    private var ctaButton: some View {
        Button {
            TutorialHaptics.success()
            onDismiss()
        } label: {
            Text("LET'S GO")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.white)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - Animation

    private func startAnimationSequence() {
        // Start message animation after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation {
                showMessage = true
            }
        }
    }
}

// MARK: - Standalone Completion View

/// Standalone completion view that doesn't require TutorialStateManager
/// Useful for previews and testing
struct StandaloneCompletionView: View {
    let completionTime: TimeInterval?
    let onDismiss: () -> Void

    @State private var showMessage: Bool = false
    @State private var showButton: Bool = false

    /// Formatted completion time string (MM:SS)
    private var formattedTime: String {
        guard let time = completionTime else { return "" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Whether to show completion time (only for < 3 min)
    private var showTimeInCompletion: Bool {
        guard let time = completionTime else { return false }
        return time < 180
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                if showMessage {
                    if showTimeInCompletion {
                        TypewriterText(
                            "DONE IN \(formattedTime). NOW WE'RE TALKING.",
                            font: OPSStyle.Typography.title,
                            color: OPSStyle.Colors.primaryText,
                            typingSpeed: 25
                        ) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showButton = true
                            }
                        }
                        .multilineTextAlignment(.center)
                    } else {
                        TypewriterText(
                            "DONE. LET'S GET TO WORK.",
                            font: OPSStyle.Typography.title,
                            color: OPSStyle.Colors.primaryText,
                            typingSpeed: 25
                        ) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showButton = true
                            }
                        }
                        .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                if showButton {
                    Button {
                        TutorialHaptics.success()
                        onDismiss()
                    } label: {
                        Text("LET'S GO")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    showMessage = true
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TutorialCompletionView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Fast completion (shows time)
            StandaloneCompletionView(completionTime: 45) {
                print("Dismissed")
            }
            .previewDisplayName("Fast Completion (45 sec)")

            // Slow completion (no time shown)
            StandaloneCompletionView(completionTime: 200) {
                print("Dismissed")
            }
            .previewDisplayName("Slow Completion (3+ min)")
        }
    }
}
#endif
