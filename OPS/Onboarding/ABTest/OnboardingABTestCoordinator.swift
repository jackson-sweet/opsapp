//
//  OnboardingABTestCoordinator.swift
//  OPS
//
//  Root coordinator for the A/B/C onboarding test.
//  Reads the assigned variant and orchestrates the correct flow sequence,
//  transitioning between steps with animations.
//
//  Flow per variant:
//    A (try first):    splash -> tryOPS -> signup -> crewCode -> complete
//    B (quick signup): splash -> signup -> crewCode -> tutorial -> complete
//    C (walkthrough):  splash -> walkthrough -> signup -> crewCode -> tutorial -> complete
//

import SwiftUI

// MARK: - Flow Step Enum

enum ABTestFlowStep {
    case splash
    case tryOPS        // Variant A: pre-signup tutorial
    case walkthrough   // Variant C: animated walkthrough screens
    case signup        // All variants: MinimalSignupView
    case crewCode      // All variants: CrewCodeShareView
    case tutorial      // Variants B & C: post-signup tutorial
    case complete
}

// MARK: - Coordinator View

struct OnboardingABTestCoordinator: View {
    @ObservedObject var variantManager: OnboardingVariantManager
    @ObservedObject var onboardingManager: OnboardingManager

    let onComplete: () -> Void
    let onShowLogin: () -> Void  // for "I already have an account"

    @State private var flowStep: ABTestFlowStep = .splash
    @State private var crewCode: String = ""

    // MARK: - Splash Animation State

    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            switch flowStep {
            case .splash:
                splashView

            case .tryOPS:
                TutorialLauncherView(
                    flowType: .companyCreator,
                    isPreSignup: true,
                    onComplete: {
                        withAnimation { flowStep = .signup }
                    }
                )
                .transition(.opacity)

            case .walkthrough:
                AnimatedWalkthroughView(onComplete: {
                    withAnimation { flowStep = .signup }
                })
                .transition(.opacity)

            case .signup:
                MinimalSignupView(
                    onboardingManager: onboardingManager,
                    variant: variantManager.variant,
                    onComplete: { code in
                        crewCode = code
                        withAnimation { flowStep = .crewCode }
                    }
                )
                .transition(.opacity)

            case .crewCode:
                CrewCodeShareView(
                    crewCode: crewCode,
                    variant: variantManager.variant,
                    onContinue: {
                        switch variantManager.variant {
                        case .A:
                            // Variant A already did the tutorial pre-signup
                            withAnimation { flowStep = .complete }
                        case .B, .C:
                            withAnimation { flowStep = .tutorial }
                        }
                    }
                )
                .transition(.opacity)

            case .tutorial:
                TutorialLauncherView(
                    flowType: .companyCreator,
                    isPreSignup: false,
                    onComplete: {
                        withAnimation { flowStep = .complete }
                    }
                )
                .transition(.opacity)

            case .complete:
                Color.clear
                    .onAppear {
                        onComplete()
                    }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: flowStep)
        .onAppear {
            AnalyticsManager.shared.trackVariantAssigned(variant: variantManager.variant.rawValue)
        }
    }

    // MARK: - Splash View

    private var splashView: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack {
                Spacer()

                // Centered logo + branding
                VStack(spacing: 24) {
                    Image("LogoWhite")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .opacity(logoOpacity)

                    VStack(spacing: 4) {
                        Text("OPS")
                            .font(OPSStyle.Typography.largeTitle.weight(.bold))
                            .foregroundColor(.white)

                        Text("Built by trades, for trades.")
                            .font(OPSStyle.Typography.subtitle)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .opacity(textOpacity)
                }

                Spacer()

                // Bottom area: CTA + login link
                VStack(spacing: 16) {
                    // Primary CTA button
                    Button {
                        handleSplashCTA()
                    } label: {
                        HStack {
                            Text(splashButtonLabel)
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(OPSStyle.Colors.invertedText)

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.invertedText)
                        }
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, height: OPSStyle.Layout.touchTargetStandard)
                        .background(Color.white)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }

                    // "I already have an account" link
                    Button {
                        onShowLogin()
                    } label: {
                        Text("I ALREADY HAVE AN ACCOUNT")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                .opacity(buttonOpacity)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            startSplashAnimations()
        }
    }

    // MARK: - Splash Helpers

    private var splashButtonLabel: String {
        switch variantManager.variant {
        case .A:
            return "TRY OPS"
        case .B, .C:
            return "GET STARTED"
        }
    }

    private func handleSplashCTA() {
        // Determine entry point for analytics
        let entryPoint: String
        switch variantManager.variant {
        case .A: entryPoint = "try_ops"
        case .B: entryPoint = "get_started_signup"
        case .C: entryPoint = "get_started_walkthrough"
        }

        AnalyticsManager.shared.trackOnboardingStarted(
            variant: variantManager.variant.rawValue,
            entryPoint: entryPoint
        )

        // Navigate to correct next step
        withAnimation {
            switch variantManager.variant {
            case .A:  flowStep = .tryOPS
            case .B:  flowStep = .signup
            case .C:  flowStep = .walkthrough
            }
        }
    }

    private func startSplashAnimations() {
        // Reset
        logoOpacity = 0
        textOpacity = 0
        buttonOpacity = 0

        // Logo fade-in
        withAnimation(Animation.spring(response: 0.8, dampingFraction: 0.6).delay(0.3)) {
            logoOpacity = 1.0
        }

        // Text fade-in
        withAnimation(Animation.easeIn(duration: 0.7).delay(0.7)) {
            textOpacity = 1.0
        }

        // Button fade-in
        withAnimation(Animation.easeIn(duration: 0.5).delay(1.2)) {
            buttonOpacity = 1.0
        }
    }
}

// MARK: - Equatable Conformance for Animation

extension ABTestFlowStep: Equatable {}

// MARK: - Preview

#if DEBUG
struct OnboardingABTestCoordinator_Previews: PreviewProvider {
    static var previews: some View {
        // Preview requires mock objects; shown for reference only
        Text("OnboardingABTestCoordinator Preview")
            .preferredColorScheme(.dark)
    }
}
#endif
