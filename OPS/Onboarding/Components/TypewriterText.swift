//
//  TypewriterText.swift
//  OPS
//
//  Animated typing text effect with cursor for onboarding screens.
//

import SwiftUI

struct TypewriterText: View {
    let text: String
    let font: Font
    let color: Color
    let typingSpeed: Double // characters per second
    let onComplete: (() -> Void)?

    @State private var displayedText: String = ""
    @State private var showCursor: Bool = true
    @State private var isComplete: Bool = false

    init(
        _ text: String,
        font: Font = OPSStyle.Typography.title,
        color: Color = OPSStyle.Colors.primaryText,
        typingSpeed: Double = 30,
        onComplete: (() -> Void)? = nil
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.typingSpeed = typingSpeed
        self.onComplete = onComplete
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(displayedText)
                .font(font)
                .foregroundColor(color)

            // Blinking cursor
            if !isComplete {
                Rectangle()
                    .fill(color)
                    .frame(width: 2, height: cursorHeight)
                    .opacity(showCursor ? 1 : 0)
            }
        }
        .onAppear {
            startTyping()
            startCursorBlink()
        }
    }

    private var cursorHeight: CGFloat {
        // Approximate cursor height based on font
        switch font {
        case OPSStyle.Typography.title:
            return 28
        case OPSStyle.Typography.subtitle:
            return 22
        case OPSStyle.Typography.body:
            return 16
        default:
            return 20
        }
    }

    private func startTyping() {
        let characters = Array(text)
        let interval = 1.0 / typingSpeed

        for (index, character) in characters.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(index)) {
                displayedText.append(character)

                // Check if complete
                if displayedText.count == text.count {
                    // Small delay before hiding cursor
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isComplete = true
                        }
                        onComplete?()
                    }
                }
            }
        }
    }

    private func startCursorBlink() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if isComplete {
                timer.invalidate()
            } else {
                showCursor.toggle()
            }
        }
    }
}

// MARK: - Animated Header Component

struct AnimatedOnboardingHeader: View {
    let title: String
    let subtitle: String?
    let titleFont: Font
    let subtitleFont: Font
    let onHeaderComplete: (() -> Void)?

    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var titleComplete = false

    init(
        title: String,
        subtitle: String? = nil,
        titleFont: Font = OPSStyle.Typography.title,
        subtitleFont: Font = OPSStyle.Typography.body,
        onHeaderComplete: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleFont = titleFont
        self.subtitleFont = subtitleFont
        self.onHeaderComplete = onHeaderComplete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showTitle {
                TypewriterText(
                    title,
                    font: titleFont,
                    color: OPSStyle.Colors.primaryText,
                    typingSpeed: 35
                ) {
                    titleComplete = true
                    // Pause then show subtitle
                    if subtitle != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showSubtitle = true
                        }
                    } else {
                        onHeaderComplete?()
                    }
                }
            }

            if showSubtitle, let sub = subtitle {
                TypewriterText(
                    sub,
                    font: subtitleFont,
                    color: OPSStyle.Colors.secondaryText,
                    typingSpeed: 40
                ) {
                    onHeaderComplete?()
                }
            }
        }
        .onAppear {
            // Small delay before starting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showTitle = true
            }
        }
    }
}

// MARK: - Page Content Animation Wrapper

struct AnimatedPageContent<Content: View>: View {
    let delay: Double
    @ViewBuilder let content: () -> Content

    @State private var isVisible = false

    var body: some View {
        content()
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        isVisible = true
                    }
                }
            }
    }
}

// MARK: - Footer Animation Wrapper

struct AnimatedFooter<Content: View>: View {
    let delay: Double
    @ViewBuilder let content: () -> Content

    @State private var isVisible = false

    var body: some View {
        content()
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 30)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        isVisible = true
                    }
                }
            }
    }
}

// MARK: - Preview

struct TypewriterText_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 40) {
            AnimatedOnboardingHeader(
                title: "YOUR INFO",
                subtitle: "Your crew will see this."
            ) {
                print("Header complete")
            }

            AnimatedPageContent(delay: 1.5) {
                VStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                        .frame(height: 56)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                        .frame(height: 56)
                }
            }

            Spacer()

            AnimatedFooter(delay: 2.0) {
                Button("CONTINUE") {}
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(8)
            }
        }
        .padding(40)
        .background(OPSStyle.Colors.background)
    }
}
