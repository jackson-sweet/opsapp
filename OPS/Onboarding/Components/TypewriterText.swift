//
//  TypewriterText.swift
//  OPS
//
//  Animated typing text effect with cursor for onboarding screens.
//  Uses space reservation to prevent layout shifts.
//

import SwiftUI

// MARK: - Typewriter Text (Space Reserved)

struct TypewriterText: View {
    let text: String
    let font: Font
    let color: Color
    let typingSpeed: Double // characters per second
    let startDelay: Double
    let onComplete: (() -> Void)?

    @State private var displayedText: String = ""
    @State private var showCursor: Bool = true
    @State private var isComplete: Bool = false
    @State private var hasStarted: Bool = false

    init(
        _ text: String,
        font: Font = OPSStyle.Typography.title,
        color: Color = OPSStyle.Colors.primaryText,
        typingSpeed: Double = 30,
        startDelay: Double = 0,
        onComplete: (() -> Void)? = nil
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.typingSpeed = typingSpeed
        self.startDelay = startDelay
        self.onComplete = onComplete
    }

    var body: some View {
        // ZStack to reserve space - invisible full text underneath
        ZStack(alignment: .leading) {
            // Invisible placeholder to reserve space
            Text(text)
                .font(font)
                .foregroundColor(.clear)

            // Visible typed text with cursor
            HStack(spacing: 0) {
                Text(displayedText)
                    .font(font)
                    .foregroundColor(color)

                // Blinking cursor
                if hasStarted && !isComplete {
                    Rectangle()
                        .fill(color)
                        .frame(width: 2, height: cursorHeight)
                        .opacity(showCursor ? 1 : 0)
                }
            }
        }
        .onAppear {
            if startDelay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
                    startTyping()
                }
            } else {
                startTyping()
            }
            startCursorBlink()
        }
    }

    private var cursorHeight: CGFloat {
        switch font {
        case OPSStyle.Typography.title:
            return 28
        case OPSStyle.Typography.subtitle:
            return 22
        case OPSStyle.Typography.body:
            return 16
        case OPSStyle.Typography.bodyBold:
            return 16
        case OPSStyle.Typography.caption:
            return 12
        case OPSStyle.Typography.captionBold:
            return 12
        default:
            return 18
        }
    }

    private func startTyping() {
        hasStarted = true
        let characters = Array(text)
        let interval = 1.0 / typingSpeed

        for (index, character) in characters.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(index)) {
                displayedText.append(character)

                if displayedText.count == text.count {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
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

// MARK: - Onboarding Animation Phase Coordinator

class OnboardingAnimationCoordinator: ObservableObject {
    @Published var phase: AnimationPhase = .initial

    enum AnimationPhase: Int, Comparable {
        case initial = 0
        case headerTyping = 1
        case subtitleTyping = 2
        case contentFadeIn = 3
        case labelsTyping = 4
        case buttonContainerFadeIn = 5
        case buttonTextTyping = 6
        case buttonIconFadeIn = 7
        case complete = 8

        static func < (lhs: AnimationPhase, rhs: AnimationPhase) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.phase = .headerTyping
        }
    }

    func advanceTo(_ phase: AnimationPhase) {
        DispatchQueue.main.async {
            if phase > self.phase {
                self.phase = phase
            }
        }
    }
}

// MARK: - Animated Onboarding Header (Space Reserved)

struct AnimatedOnboardingHeader: View {
    let title: String
    let subtitle: String?
    let titleFont: Font
    let subtitleFont: Font
    let onHeaderComplete: (() -> Void)?

    @StateObject private var coordinator = OnboardingAnimationCoordinator()

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
            // Title - always reserves space
            ZStack(alignment: .leading) {
                // Space reservation
                Text(title)
                    .font(titleFont)
                    .foregroundColor(.clear)

                // Typed title
                if coordinator.phase >= .headerTyping {
                    TypewriterText(
                        title,
                        font: titleFont,
                        color: OPSStyle.Colors.primaryText,
                        typingSpeed: 28
                    ) {
                        // Title complete - advance to subtitle
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            coordinator.advanceTo(.subtitleTyping)
                        }
                    }
                }
            }

            // Subtitle - always reserves space if present
            if let sub = subtitle {
                ZStack(alignment: .leading) {
                    // Space reservation
                    Text(sub)
                        .font(subtitleFont)
                        .foregroundColor(.clear)

                    // Typed subtitle
                    if coordinator.phase >= .subtitleTyping {
                        TypewriterText(
                            sub,
                            font: subtitleFont,
                            color: OPSStyle.Colors.secondaryText,
                            typingSpeed: 30
                        ) {
                            onHeaderComplete?()
                        }
                    }
                }
            }
        }
        .onAppear {
            coordinator.start()
        }
    }
}

// MARK: - Phased Onboarding Header (with external coordinator)

struct PhasedOnboardingHeader: View {
    let title: String
    let subtitle: String?
    let titleFont: Font
    let subtitleFont: Font
    @ObservedObject var coordinator: OnboardingAnimationCoordinator

    init(
        title: String,
        subtitle: String? = nil,
        titleFont: Font = OPSStyle.Typography.title,
        subtitleFont: Font = OPSStyle.Typography.body,
        coordinator: OnboardingAnimationCoordinator
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleFont = titleFont
        self.subtitleFont = subtitleFont
        self.coordinator = coordinator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title - always reserves space
            ZStack(alignment: .leading) {
                Text(title)
                    .font(titleFont)
                    .foregroundColor(.clear)

                if coordinator.phase >= .headerTyping {
                    TypewriterText(
                        title,
                        font: titleFont,
                        color: OPSStyle.Colors.primaryText,
                        typingSpeed: 28
                    ) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            coordinator.advanceTo(.subtitleTyping)
                        }
                    }
                }
            }

            // Subtitle - always reserves space if present
            if let sub = subtitle {
                ZStack(alignment: .leading) {
                    Text(sub)
                        .font(subtitleFont)
                        .foregroundColor(.clear)

                    if coordinator.phase >= .subtitleTyping {
                        TypewriterText(
                            sub,
                            font: subtitleFont,
                            color: OPSStyle.Colors.secondaryText,
                            typingSpeed: 30
                        ) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                coordinator.advanceTo(.contentFadeIn)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Phased Label (types in during labelsTyping phase)

struct PhasedLabel: View {
    let text: String
    let font: Font
    let color: Color
    let typingSpeed: Double
    let index: Int // For staggering multiple labels
    let isLast: Bool // Triggers button phase when complete
    @ObservedObject var coordinator: OnboardingAnimationCoordinator

    init(
        _ text: String,
        font: Font = OPSStyle.Typography.captionBold,
        color: Color = OPSStyle.Colors.secondaryText,
        typingSpeed: Double = 40,
        index: Int = 0,
        isLast: Bool = false,
        coordinator: OnboardingAnimationCoordinator
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.typingSpeed = typingSpeed
        self.index = index
        self.isLast = isLast
        self.coordinator = coordinator
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Space reservation
            Text(text)
                .font(font)
                .foregroundColor(.clear)

            // Typed label (staggered by index)
            if coordinator.phase >= .labelsTyping {
                TypewriterText(
                    text,
                    font: font,
                    color: color,
                    typingSpeed: typingSpeed,
                    startDelay: Double(index) * 0.25
                ) {
                    // If this is the last label, trigger button phase
                    if isLast {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            coordinator.advanceTo(.buttonContainerFadeIn)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Phased Content (fades in upward during contentFadeIn)

struct PhasedContent<Content: View>: View {
    @ObservedObject var coordinator: OnboardingAnimationCoordinator
    let content: () -> Content

    @State private var isVisible = false

    var body: some View {
        content()
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .onChange(of: coordinator.phase) { _, newPhase in
                if newPhase >= .contentFadeIn && !isVisible {
                    withAnimation(.easeOut(duration: 0.5)) {
                        isVisible = true
                    }
                    // After content fades in, advance to labels
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        coordinator.advanceTo(.labelsTyping)
                    }
                }
            }
    }
}

// MARK: - Phased Primary Button

struct PhasedPrimaryButton: View {
    let title: String
    let isEnabled: Bool
    let isLoading: Bool
    let loadingText: String?
    let action: () -> Void
    @ObservedObject var coordinator: OnboardingAnimationCoordinator

    @State private var containerVisible = false
    @State private var textVisible = false
    @State private var iconVisible = false

    init(
        _ title: String,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        loadingText: String? = nil,
        coordinator: OnboardingAnimationCoordinator,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.loadingText = loadingText
        self.coordinator = coordinator
        self.action = action
    }

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        } label: {
            ZStack {
                // Container background (always present for layout)
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(isEnabled && !isLoading ? Color.white : Color.white.opacity(0.5))
                    .frame(height: 56)
                    .opacity(containerVisible ? 1 : 0)
                    .offset(y: containerVisible ? 0 : 20)

                // Content
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))

                        if let loadingText = loadingText {
                            Text(loadingText)
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(.black)
                        }
                    }
                    .opacity(containerVisible ? 1 : 0)
                } else {
                    HStack {
                        // Text with space reservation
                        ZStack(alignment: .leading) {
                            Text(title)
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(.clear)

                            if textVisible {
                                TypewriterText(
                                    title,
                                    font: OPSStyle.Typography.bodyBold,
                                    color: .black,
                                    typingSpeed: 25
                                ) {
                                    // Text complete - show icon after delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                        withAnimation(.easeOut(duration: 0.4)) {
                                            iconVisible = true
                                        }
                                        coordinator.advanceTo(.complete)
                                    }
                                }
                            }
                        }

                        Spacer()

                        // Arrow icon
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                            .opacity(iconVisible ? 1 : 0)
                            .offset(x: iconVisible ? 0 : -10)
                    }
                    .padding(.horizontal, 20)
                    .opacity(containerVisible ? 1 : 0)
                }
            }
            .frame(height: 56)
        }
        .disabled(!isEnabled || isLoading || !containerVisible)
        .onChange(of: coordinator.phase) { _, newPhase in
            if newPhase >= .buttonContainerFadeIn && !containerVisible {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    containerVisible = true
                }
                // Start text typing after container appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    coordinator.advanceTo(.buttonTextTyping)
                    textVisible = true
                }
            }
        }
    }
}

// MARK: - Animation Timing Helper

struct OnboardingAnimationTiming {
    static let headerDelay: Double = 0.15
    static let subtitleDelay: Double = 0.25
    static let contentFadeDelay: Double = 0.2
    static let labelStagger: Double = 0.15
    static let buttonContainerDelay: Double = 0.3
    static let buttonTextDelay: Double = 0.3
    static let buttonIconDelay: Double = 0.1
}

// MARK: - Preview

struct TypewriterText_Previews: PreviewProvider {
    static var previews: some View {
        PhasedAnimationPreview()
    }
}

struct PhasedAnimationPreview: View {
    @StateObject private var coordinator = OnboardingAnimationCoordinator()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            PhasedOnboardingHeader(
                title: "YOUR INFO",
                subtitle: "Your crew will see this.",
                coordinator: coordinator
            )
            .padding(.horizontal, 40)
            .padding(.top, 60)

            Spacer().frame(height: 48)

            // Content
            PhasedContent(coordinator: coordinator) {
                VStack(spacing: 20) {
                    // Avatar placeholder
                    Circle()
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                        .frame(width: 120, height: 120)

                    // Form fields
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            PhasedLabel("FIRST NAME", index: 0, coordinator: coordinator)
                            RoundedRectangle(cornerRadius: 8)
                                .fill(OPSStyle.Colors.cardBackgroundDark)
                                .frame(height: 56)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            PhasedLabel("LAST NAME", index: 1, coordinator: coordinator)
                            RoundedRectangle(cornerRadius: 8)
                                .fill(OPSStyle.Colors.cardBackgroundDark)
                                .frame(height: 56)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Button
            PhasedPrimaryButton(
                "CONTINUE",
                coordinator: coordinator
            ) {
                print("Tapped")
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .background(OPSStyle.Colors.background)
        .onAppear {
            coordinator.start()
        }
    }
}
