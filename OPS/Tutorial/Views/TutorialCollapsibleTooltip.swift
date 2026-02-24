//
//  TutorialCollapsibleTooltip.swift
//  OPS
//
//  Collapsible tooltip for tutorial that positions at the top of the screen.
//  Can be expanded to show full text or collapsed to a small indicator.
//

import SwiftUI

/// Collapsible tooltip that displays tutorial guidance at the top of the screen
/// Tap to expand/collapse. Expands automatically when text changes.
/// Supports temporary error state that transitions colors to red when triggered.
struct TutorialCollapsibleTooltip: View {
    let text: String
    let description: String?
    let animated: Bool
    var stepIndex: Int = 0      // current step (0-based)
    var totalSteps: Int = 0     // total number of steps

    @State private var isExpanded: Bool = true
    @State private var displayedText: String = ""
    @State private var displayedDescription: String = ""
    @State private var previousText: String = ""
    @State private var isErrorState: Bool = false

    /// The accent color - switches between primary and error based on state
    private var accentColor: Color {
        isErrorState ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryAccent
    }

    /// The icon to display - lightbulb normally, alert when error
    private var iconName: String {
        isErrorState ? "exclamationmark.triangle.fill" : "lightbulb.fill"
    }

    init(text: String, description: String? = nil, animated: Bool = true, stepIndex: Int = 0, totalSteps: Int = 0) {
        self.text = text
        self.description = description
        self.animated = animated
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tooltip content — parent controls vertical positioning
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    // Tutorial icon - changes to alert icon in error state
                    Image(systemName: iconName)
                        .font(.system(size: isExpanded ? 18 : 16))
                        .foregroundColor(accentColor)

                    if isExpanded {
                        // Full text with optional description
                        VStack(alignment: .leading, spacing: 6) {
                            Text(animated ? displayedText : text)
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .multilineTextAlignment(.leading)

                            if let desc = description, !desc.isEmpty {
                                Text(animated ? displayedDescription : desc)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Step counter in top-right area
                        if totalSteps > 0 {
                            Text("STEP \(stepIndex + 1)/\(totalSteps)")
                                .font(.custom("Mohave-Regular", size: 11))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    } else {
                        // Collapsed - show "Tap for hint"
                        Text("Tap for hint")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Spacer()

                        // Expand indicator
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, isExpanded ? 14 : 10)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.largeCornerRadius)
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.largeCornerRadius)
                        .stroke(accentColor.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
                )
                // Dark glow effect - multiple shadows for stronger presence
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.3), value: isErrorState)
        }
        // Listen for tutorial error notifications
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialWrongAction"))) { _ in
            triggerErrorState()
        }
        .onChange(of: text) { oldValue, newValue in
            // Auto-expand when text changes
            if !isExpanded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded = true
                }
            }

            // Animate new text
            if animated {
                animateText(newValue)
                animateDescription(description)
            } else {
                displayedText = newValue
                displayedDescription = description ?? ""
            }
            previousText = oldValue
        }
        .onChange(of: description) { _, newDescription in
            if animated {
                animateDescription(newDescription)
            } else {
                displayedDescription = newDescription ?? ""
            }
        }
        .onAppear {
            if animated {
                animateText(text)
                animateDescription(description)
            } else {
                displayedText = text
                displayedDescription = description ?? ""
            }
            previousText = text
        }
    }

    private func animateText(_ newText: String) {
        displayedText = ""
        let characters = Array(newText)
        for (index, character) in characters.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.02) {
                if displayedText.count == index {
                    displayedText.append(character)
                }
            }
        }
    }

    private func animateDescription(_ newDescription: String?) {
        displayedDescription = ""
        guard let desc = newDescription else { return }
        let characters = Array(desc)
        // Start description animation after main text finishes
        let textDelay = Double(text.count) * 0.02 + 0.1
        for (index, character) in characters.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + textDelay + Double(index) * 0.015) {
                if displayedDescription.count == index {
                    displayedDescription.append(character)
                }
            }
        }
    }

    /// Triggers temporary error state - icon and colors flash red for 2 seconds
    private func triggerErrorState() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isErrorState = true
        }

        // Auto-reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                isErrorState = false
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TutorialCollapsibleTooltip_Previews: PreviewProvider {
    struct PreviewContainer: View {
        @State private var currentText = "Tap the + button to create your first project."

        var body: some View {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack {
                    TutorialCollapsibleTooltip(text: currentText)

                    Spacer()

                    // Test buttons
                    VStack(spacing: 12) {
                        Button("Short text") {
                            currentText = "Tap the + button."
                        }
                        .padding()
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)

                        Button("Long text") {
                            currentText = "Now drag the project card from 'Accepted' to 'In Progress' to update its status."
                        }
                        .padding()
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    }
                    .foregroundColor(.white)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    static var previews: some View {
        PreviewContainer()
    }
}
#endif
