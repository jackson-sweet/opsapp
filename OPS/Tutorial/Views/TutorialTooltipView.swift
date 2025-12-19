//
//  TutorialTooltipView.swift
//  OPS
//
//  Tooltip view that displays instruction text with typewriter animation.
//  Uses the existing TypewriterText component for consistent animation style.
//

import SwiftUI

/// Tooltip view for displaying tutorial instructions at the bottom of the screen
struct TutorialTooltipView: View {
    /// The instruction text to display
    let text: String

    /// Whether to animate the text with typewriter effect
    let animated: Bool

    /// Typing speed in characters per second
    let typingSpeed: Double

    /// Callback when typing animation completes
    let onComplete: (() -> Void)?

    /// Tracks if we need to reset the animation on text change
    @State private var textId: UUID = UUID()

    /// Creates a tutorial tooltip
    /// - Parameters:
    ///   - text: The instruction text to display
    ///   - animated: Whether to use typewriter animation (default: true)
    ///   - typingSpeed: Characters per second (default: 40)
    ///   - onComplete: Callback when typing finishes
    init(
        text: String,
        animated: Bool = true,
        typingSpeed: Double = 40,
        onComplete: (() -> Void)? = nil
    ) {
        self.text = text
        self.animated = animated
        self.typingSpeed = typingSpeed
        self.onComplete = onComplete
    }

    var body: some View {
        VStack {
            if !text.isEmpty {
                tooltipContent
            }
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
        .onChange(of: text) { _, _ in
            // Reset animation when text changes
            textId = UUID()
        }
    }

    @ViewBuilder
    private var tooltipContent: some View {
        if animated {
            TypewriterText(
                text,
                font: OPSStyle.Typography.bodyBold,
                color: OPSStyle.Colors.primaryText,
                typingSpeed: typingSpeed,
                onComplete: onComplete
            )
            .id(textId) // Force re-render on text change
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
        } else {
            Text(text)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Positioned Tooltip

/// Tooltip positioned at the bottom of the screen with proper spacing
struct PositionedTooltip: View {
    let text: String
    let animated: Bool
    let onComplete: (() -> Void)?

    /// Bottom padding from screen edge
    let bottomPadding: CGFloat

    init(
        text: String,
        animated: Bool = true,
        bottomPadding: CGFloat = 50,
        onComplete: (() -> Void)? = nil
    ) {
        self.text = text
        self.animated = animated
        self.bottomPadding = bottomPadding
        self.onComplete = onComplete
    }

    var body: some View {
        VStack {
            Spacer()

            TutorialTooltipView(
                text: text,
                animated: animated,
                onComplete: onComplete
            )
            .padding(.bottom, bottomPadding)
        }
    }
}

// MARK: - Tooltip with Background

/// Tooltip with a semi-transparent background card
struct TutorialTooltipCard: View {
    let text: String
    let animated: Bool
    let onComplete: (() -> Void)?

    init(
        text: String,
        animated: Bool = true,
        onComplete: (() -> Void)? = nil
    ) {
        self.text = text
        self.animated = animated
        self.onComplete = onComplete
    }

    var body: some View {
        VStack {
            if !text.isEmpty {
                TutorialTooltipView(
                    text: text,
                    animated: animated,
                    onComplete: onComplete
                )
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.largeCornerRadius)
                        .fill(OPSStyle.Colors.cardBackgroundDark.opacity(0.95))
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.largeCornerRadius)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TutorialTooltipView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack {
                Spacer()

                // Standard tooltip
                TutorialTooltipView(
                    text: "TAP THE + TO CREATE YOUR FIRST PROJECT"
                )

                Spacer()

                // Tooltip with card background
                TutorialTooltipCard(
                    text: "DRAG YOUR PROJECT TO ACCEPTED"
                )
                .padding(.bottom, 50)
            }
        }
    }
}
#endif
