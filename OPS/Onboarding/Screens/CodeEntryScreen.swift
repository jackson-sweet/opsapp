//
//  CodeEntryScreen.swift
//  OPS
//
//  Employee screen for entering crew code to join a company.
//  Features expanding bracket animation on focus.
//  Uses phased animation system for entrance effects.
//

import SwiftUI
import SwiftData
import UIKit

struct CodeEntryScreen: View {
    @ObservedObject var manager: OnboardingManager
    @EnvironmentObject var dataController: DataController

    @State private var companyCode: String = ""
    @State private var errorMessage: String?
    @State private var isJoining = false
    @State private var showHelpSheet = false
    @State private var showSwitchConfirmation = false
    @FocusState private var isInputFocused: Bool

    // Animation coordinator
    @StateObject private var animationCoordinator = OnboardingAnimationCoordinator()

    private var isFormValid: Bool {
        !companyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with back and sign out
            OnboardingHeader(
                showBack: true,
                onBack: { manager.goBack() },
                onSignOut: { manager.signOut() }
            )
            .padding(.horizontal, 40)
            .padding(.top, 16)

            // Title area with phased typing animation
            PhasedOnboardingHeader(
                title: "JOIN YOUR CREW",
                subtitle: "Enter the code your boss gave you.",
                coordinator: animationCoordinator
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 32)

            Spacer()

            // Content section - fades in upward
            PhasedContent(coordinator: animationCoordinator) {
                VStack(spacing: 0) {
                    // Code input with expanding brackets
                    ExpandingBracketInput(
                        text: $companyCode,
                        isFocused: _isInputFocused,
                        placeholder: "CODE"
                    )

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .padding(.top, 16)
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Bottom section: Help button + Join button
            VStack(spacing: 16) {
                // Help button - trigger button phase when this appears
                PhasedHelpButton(coordinator: animationCoordinator) {
                    showHelpSheet = true
                }

                // Join button with phased animation
                PhasedPrimaryButton(
                    "JOIN CREW",
                    isEnabled: isFormValid,
                    isLoading: isJoining,
                    loadingText: "Joining...",
                    coordinator: animationCoordinator
                ) {
                    joinCrew()
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .background(OPSStyle.Colors.background)
        .onTapGesture {
            isInputFocused = false
        }
        .onAppear {
            prefillCode()
            animationCoordinator.start()
        }
        .sheet(isPresented: $showHelpSheet) {
            CompanyCodeHelpSheet(
                onCreateCompany: {
                    showHelpSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showSwitchConfirmation = true
                    }
                },
                onDismiss: {
                    showHelpSheet = false
                }
            )
        }
        .alert("Switch to Company Setup?", isPresented: $showSwitchConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Discard & Switch", role: .destructive) {
                switchToCompanyCreator()
            }
        } message: {
            Text("This will discard your current progress and start the company creation flow.")
        }
    }

    // MARK: - Helpers

    private func prefillCode() {
        if let code = manager.state.companyData.companyCode {
            companyCode = code
        }
    }

    private func joinCrew() {
        guard isFormValid else { return }

        let trimmedCode = companyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        isJoining = true

        Task {
            do {
                try await manager.joinCompany(code: trimmedCode)

                await MainActor.run {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    isJoining = false
                    manager.goToScreen(.ready)
                }
            } catch {
                await MainActor.run {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    isJoining = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func switchToCompanyCreator() {
        manager.state.companyData = OnboardingCompanyData()
        manager.goToScreen(.userTypeSelection)
    }
}

// MARK: - Phased Help Button

struct PhasedHelpButton: View {
    @ObservedObject var coordinator: OnboardingAnimationCoordinator
    let action: () -> Void

    @State private var isVisible = false

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 14))
                Text("Where is my code?")
                    .font(OPSStyle.Typography.caption)
            }
            .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 10)
        .onChange(of: coordinator.phase) { _, newPhase in
            if newPhase >= .labelsTyping && !isVisible {
                withAnimation(.easeOut(duration: 0.4)) {
                    isVisible = true
                }
                // Trigger button phase after help button appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    coordinator.advanceTo(.buttonContainerFadeIn)
                }
            }
        }
    }
}

// MARK: - Expanding Bracket Input

struct ExpandingBracketInput: View {
    @Binding var text: String
    @FocusState var isFocused: Bool
    let placeholder: String

    // Animation values
    private let collapsedSpacing: CGFloat = 80 // Minimum width to prevent placeholder text wrapping
    private let expandedSpacing: CGFloat = UIScreen.main.bounds.width - 120 // Full width minus padding

    private var currentSpacing: CGFloat {
        if isFocused {
            return expandedSpacing
        } else if text.isEmpty {
            return collapsedSpacing
        } else {
            // Contract to fit text with small padding
            let textWidth = text.size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 18, weight: .medium)]).width
            return max(collapsedSpacing, textWidth + 24)
        }
    }

    private var underlineColor: Color {
        isFocused ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText.opacity(0.5)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left bracket
                Text("[")
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Spacer()
                    .frame(width: isFocused ? 8 : (text.isEmpty ? 4 : 8))

                // Input field
                ZStack {
                    // Placeholder
                    if text.isEmpty && !isFocused {
                        Text(placeholder)
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .foregroundColor(OPSStyle.Colors.placeholderText)
                    }

                    TextField("", text: $text)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .multilineTextAlignment(.center)
                        .focused($isFocused)
                }
                .frame(width: currentSpacing - 16) // Account for bracket spacing

                Spacer()
                    .frame(width: isFocused ? 8 : (text.isEmpty ? 4 : 8))

                // Right bracket
                Text("]")
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .frame(height: 56)

            // Underline
            Rectangle()
                .fill(underlineColor)
                .frame(width: currentSpacing, height: 2)
                .offset(y: -8)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isFocused)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: text)
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
    }
}

// MARK: - String Extension for Size Calculation

extension String {
    func size(withAttributes attrs: [NSAttributedString.Key: Any]) -> CGSize {
        let size = (self as NSString).size(withAttributes: attrs)
        return size
    }
}

// MARK: - Preview

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)
    manager.selectFlow(.employee)

    return CodeEntryScreen(manager: manager)
        .environmentObject(dataController)
}
