//
//  AppSetupScreen.swift
//  OPS
//
//  Full-screen loading screen shown while the app is being set up.
//  Used at end of onboarding (after all steps complete) and during login
//  when syncing user data. Shows the TacticalLoadingBarAnimated with
//  a phased message sequence so the user knows the app is working.
//

import SwiftUI

struct AppSetupScreen: View {
    @ObservedObject var manager: OnboardingManager
    @EnvironmentObject var dataController: DataController

    // Phased status messages that cycle during setup
    @State private var messageIndex: Int = 0
    @State private var messageOpacity: Double = 0
    @State private var logoOpacity: Double = 0
    @State private var loadingOpacity: Double = 0
    @State private var setupTimer: Timer?

    private let messages = [
        "SETTING UP YOUR WORKSPACE",
        "SYNCING YOUR DATA",
        "PREPARING YOUR TOOLS",
        "ALMOST READY"
    ]

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // OPS Logo
                Image("LogoWhite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .opacity(logoOpacity)

                Spacer()
                    .frame(height: 48)

                // Animated loading bar
                TacticalLoadingBarAnimated(
                    barCount: 8,
                    barWidth: 3,
                    barHeight: 8,
                    spacing: 5,
                    emptyColor: OPSStyle.Colors.inputFieldBorder,
                    fillColor: OPSStyle.Colors.primaryAccent
                )
                .opacity(loadingOpacity)

                Spacer()
                    .frame(height: 24)

                // Phased status message
                Text(messages[messageIndex])
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .tracking(2)
                    .opacity(messageOpacity)
                    .animation(.easeInOut(duration: 0.4), value: messageOpacity)
                    .id("setup-message-\(messageIndex)")

                Spacer()
            }
        }
        .onAppear {
            startSetupSequence()
        }
        .onDisappear {
            setupTimer?.invalidate()
            setupTimer = nil
        }
    }

    // MARK: - Setup Sequence

    private func startSetupSequence() {
        // Phase 1: Fade in logo
        withAnimation(.easeIn(duration: 0.6)) {
            logoOpacity = 1.0
        }

        // Phase 2: Fade in loading bar
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeIn(duration: 0.4)) {
                loadingOpacity = 1.0
            }
        }

        // Phase 3: Show first message
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeIn(duration: 0.4)) {
                messageOpacity = 1.0
            }
        }

        // Phase 4: Cycle messages every 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            setupTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                Task { @MainActor in
                    // Fade out current message
                    withAnimation(.easeOut(duration: 0.3)) {
                        messageOpacity = 0
                    }
                    // After fade out, switch and fade in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    messageIndex = (messageIndex + 1) % messages.count
                    withAnimation(.easeIn(duration: 0.3)) {
                        messageOpacity = 1.0
                    }
                }
            }
            if let timer = setupTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }

        // Phase 5: Complete onboarding after a brief delay to ensure sync starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            manager.completeOnboarding()
        }
    }
}

// MARK: - Preview

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)

    return AppSetupScreen(manager: manager)
        .environmentObject(dataController)
}
