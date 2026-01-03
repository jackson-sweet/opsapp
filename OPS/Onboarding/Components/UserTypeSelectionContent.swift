//
//  UserTypeSelectionContent.swift
//  OPS
//
//  User type selection with tactical minimalism.
//  Clean, confident, efficient - transforms based on selection.
//

import SwiftUI

// MARK: - Configuration

struct UserTypeSelectionConfig {
    let title: String
    let subtitle: String
    let showBackButton: Bool
    let backAction: (() -> Void)?
    let onSelectCompanyCreator: () -> Void
    let onSelectEmployee: () -> Void
}

// MARK: - Selection State

enum UserTypeChoice: String, CaseIterable {
    case joinCrew = "JOIN A CREW"
    case runCrew = "RUN A CREW"

    var icon: String {
        switch self {
        case .joinCrew: return "person.badge.plus"
        case .runCrew: return "building.2.fill"
        }
    }

    var headline: String {
        switch self {
        case .joinCrew: return "SEE YOUR JOBS. GET TO WORK."
        case .runCrew: return "REGISTER YOUR COMPANY. RUN YOUR JOBS."
        }
    }

    var description: String {
        switch self {
        case .joinCrew:
            return "Your schedule, job details, and directions—all in one place. No more digging through texts for details."
        case .runCrew:
            return "Create jobs, assign your crew, track progress. No training required—open it and you know what to do."
        }
    }

    var features: [String] {
        switch self {
        case .joinCrew:
            return [
                "Stay briefed on all your jobs",
                "One-tap directions to the site",
                "No more missed details",
                "Mark complete when done"
            ]
        case .runCrew:
            return [
                "Create projects in seconds",
                "Assign crew with one tap",
                "See progress from the truck",
                "Works offline, syncs later"
            ]
        }
    }

    var buttonText: String {
        switch self {
        case .joinCrew: return "JOIN MY CREW"
        case .runCrew: return "SET UP MY COMPANY"
        }
    }
}

// MARK: - Main Content View

struct UserTypeSelectionContent: View {
    let config: UserTypeSelectionConfig
    @State private var selectedType: UserTypeChoice?
    @State private var contentId = UUID()
    @State private var isTransitioning = false
    @State private var buttonTextKey = UUID()
    @State private var showButtonArrow = false

    var body: some View {
        VStack(spacing: 0) {
            // Back button (optional)
            if config.showBackButton {
                HStack {
                    Button {
                        config.backAction?()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
            }

            // Header
            VStack(alignment: .leading, spacing: 12) {
                Text(config.title)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(config.subtitle.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .tracking(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, config.showBackButton ? 8 : 60)
            .padding(.bottom, 32)

            // Segmented Picker
            segmentedPicker
                .padding(.horizontal, 40)

            // Content Area
            if let selected = selectedType, !isTransitioning {
                selectedContent(for: selected)
                    .id(contentId)
                    .transition(.opacity)
            } else if !isTransitioning {
                placeholderContent
                    .transition(.opacity)
            } else {
                // Empty spacer during transition
                Spacer()
            }

            Spacer()

            // Continue Button
            if selectedType != nil && !isTransitioning {
                continueButton
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 50)
            }
        }
        .background(OPSStyle.Colors.background)
        .animation(.easeInOut(duration: 0.25), value: selectedType)
    }

    // MARK: - Segmented Picker

    private var segmentedPicker: some View {
        HStack(spacing: 0) {
            ForEach(UserTypeChoice.allCases, id: \.self) { choice in
                Button {
                    selectType(choice)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: choice.icon)
                            .font(.system(size: 13, weight: .medium))

                        Text(choice.rawValue)
                            .font(OPSStyle.Typography.smallCaption)
                    }
                    .foregroundColor(selectedType == choice ? OPSStyle.Colors.background : OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Group {
                            if selectedType == choice {
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius - 2)
                                    .fill(OPSStyle.Colors.primaryText)
                            }
                        }
                    )
                    .animation(.easeInOut(duration: 0.2), value: selectedType)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Selected Content

    private func selectedContent(for choice: UserTypeChoice) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Headline
            Text(choice.headline)
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.top, 40)
                .padding(.horizontal, 40)
                .modifier(SlideInModifier(delay: 0))

            // Description
            Text(choice.description)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .lineSpacing(4)
                .padding(.top, 12)
                .padding(.horizontal, 40)
                .modifier(SlideInModifier(delay: 0.05))

            // Features
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(choice.features.enumerated()), id: \.offset) { index, feature in
                    HStack(spacing: 12) {
                        Text("→")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Text(feature)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .padding(.vertical, 12)
                    .modifier(SlideInModifier(delay: 0.1 + Double(index) * 0.05))

                    if index < choice.features.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Placeholder Content

    private var placeholderContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("[ SELECT YOUR ROLE ]")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Spacer()
        }
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            performSelection()
        } label: {
            ZStack {
                // Button background
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(Color.white)
                    .frame(height: 56)

                // Content
                HStack {
                    // Text with typewriter animation
                    ZStack(alignment: .leading) {
                        // Space reservation
                        Text(selectedType?.buttonText ?? "CONTINUE")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.clear)

                        // Typewriter text
                        TypewriterText(
                            selectedType?.buttonText ?? "CONTINUE",
                            font: OPSStyle.Typography.bodyBold,
                            color: .black,
                            typingSpeed: 30
                        ) {
                            // Show arrow after text completes
                            withAnimation(.easeOut(duration: 0.3)) {
                                showButtonArrow = true
                            }
                        }
                        .id(buttonTextKey)
                    }

                    Spacer()

                    // Arrow icon
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .opacity(showButtonArrow ? 1 : 0)
                        .offset(x: showButtonArrow ? 0 : -10)
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 56)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Actions

    private func selectType(_ type: UserTypeChoice) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Reset button animation state
        showButtonArrow = false
        buttonTextKey = UUID()

        // If already showing content, fade out first then switch
        if selectedType != nil {
            withAnimation(.easeOut(duration: 0.15)) {
                isTransitioning = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                contentId = UUID()
                selectedType = type

                withAnimation(.easeIn(duration: 0.15)) {
                    isTransitioning = false
                }
            }
        } else {
            // First selection - show immediately
            contentId = UUID()
            withAnimation {
                selectedType = type
            }
        }
    }

    private func performSelection() {
        // Success haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        guard let selected = selectedType else { return }

        switch selected {
        case .joinCrew:
            config.onSelectEmployee()
        case .runCrew:
            config.onSelectCompanyCreator()
        }
    }
}

// MARK: - Slide In Animation Modifier

struct SlideInModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3).delay(delay)) {
                    isVisible = true
                }
            }
    }
}

// MARK: - Preview

#Preview("With Back Button") {
    UserTypeSelectionContent(
        config: UserTypeSelectionConfig(
            title: "GET STARTED",
            subtitle: "Choose How You'll Use OPS",
            showBackButton: true,
            backAction: { print("Back") },
            onSelectCompanyCreator: { print("Company") },
            onSelectEmployee: { print("Employee") }
        )
    )
}

#Preview("Without Back Button") {
    UserTypeSelectionContent(
        config: UserTypeSelectionConfig(
            title: "HOW WILL YOU USE OPS?",
            subtitle: "Choose Your Role To Get Started",
            showBackButton: false,
            backAction: nil,
            onSelectCompanyCreator: { print("Company") },
            onSelectEmployee: { print("Employee") }
        )
    )
}
