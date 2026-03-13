//
//  OnboardingABTestCoordinator.swift
//  OPS
//
//  Root coordinator for the onboarding flow.
//  After splash, user selects JOIN A CREW or RUN A CREW.
//  Company creators go through A/B/C variant flow (no tutorial).
//  Employees go through streamlined join flow (no A/B test).
//
//  Company creator flow per variant:
//    A: splash -> typeSelection -> signup -> companyName -> crewCode -> complete
//    B: splash -> typeSelection -> signup -> companyName -> crewCode -> complete
//    C: splash -> typeSelection -> walkthrough -> signup -> companyName -> crewCode -> complete
//
//  Employee flow:
//    splash -> typeSelection -> employeeSignup -> employeeCodeEntry -> employeeConfirmation -> employeeProfile -> complete
//

import SwiftUI

// MARK: - Flow Step Enum

enum ABTestFlowStep {
    case splash
    case typeSelection       // JOIN A CREW / RUN A CREW
    case walkthrough         // Variant C only: animated walkthrough
    case signup              // Company creator: auth screen
    case companyName         // Company creator: CompanyNameView
    case crewCode            // Company creator: CrewCodeShareView
    // Employee flow steps
    case employeeSignup      // Employee: auth screen
    case employeeCodeEntry   // Employee: enter crew code
    case employeeConfirmation // Employee: "Welcome to [Company]"
    case employeeProfile     // Employee: name, phone, avatar, emergency contact
    case complete
}

// MARK: - Coordinator View

struct OnboardingABTestCoordinator: View {
    @ObservedObject var variantManager: OnboardingVariantManager
    @ObservedObject var onboardingManager: OnboardingManager

    let onComplete: () -> Void
    let onShowLogin: () -> Void

    @State private var flowStep: ABTestFlowStep = .splash
    @State private var crewCode: String = ""
    @State private var hasTrackedVariant = false

    // Employee flow state
    @State private var lookupCompanyName: String = ""
    @State private var lookupCompanyLogoURL: String?

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            switch flowStep {
            case .splash:
                ABTestSplashView(
                    variant: variantManager.variant,
                    onGetStarted: {
                        OnboardingSupabaseAnalytics.shared.trackStepComplete("splash")
                        AnalyticsManager.shared.trackOnboardingStarted(
                            variant: variantManager.variant.rawValue,
                            entryPoint: "get_started"
                        )
                        withAnimation { flowStep = .typeSelection }
                    },
                    onShowLogin: onShowLogin
                )
                .transition(.opacity)

            case .typeSelection:
                UserTypeSelectionContent(
                    config: UserTypeSelectionConfig(
                        title: "GET STARTED",
                        subtitle: "Choose How You'll Use OPS",
                        showBackButton: true,
                        backAction: {
                            withAnimation { flowStep = .splash }
                        },
                        onSelectCompanyCreator: {
                            OnboardingSupabaseAnalytics.shared.startSession(
                                variant: variantManager.variant.rawValue,
                                flowType: "company_creator"
                            )
                            OnboardingSupabaseAnalytics.shared.trackStepComplete("type_selection", metadata: ["choice": "company_creator"])
                            onboardingManager.state.flow = .companyCreator
                            handleCompanyCreatorSelected()
                        },
                        onSelectEmployee: {
                            OnboardingSupabaseAnalytics.shared.startSession(
                                variant: nil,
                                flowType: "employee"
                            )
                            OnboardingSupabaseAnalytics.shared.trackStepComplete("type_selection", metadata: ["choice": "employee"])
                            withAnimation { flowStep = .employeeSignup }
                        }
                    )
                )
                .transition(.opacity)

            // MARK: - Company Creator Flow (A/B/C variants, no tutorial)

            case .walkthrough:
                AnimatedWalkthroughView(onComplete: {
                    OnboardingSupabaseAnalytics.shared.trackStepComplete("walkthrough")
                    withAnimation { flowStep = .signup }
                })
                .transition(.opacity)

            case .signup:
                MinimalSignupView(
                    onboardingManager: onboardingManager,
                    variant: variantManager.variant,
                    onAuthenticated: {
                        OnboardingSupabaseAnalytics.shared.trackStepComplete("signup", metadata: ["flow": "company_creator"])
                        withAnimation { flowStep = .companyName }
                    },
                    onExistingUserComplete: {
                        withAnimation { flowStep = .complete }
                    },
                    onShowLogin: onShowLogin
                )
                .transition(.opacity)

            case .companyName:
                CompanyNameView(
                    onboardingManager: onboardingManager,
                    variant: variantManager.variant,
                    onComplete: { code in
                        crewCode = code
                        OnboardingSupabaseAnalytics.shared.trackStepComplete("company_name")
                        withAnimation { flowStep = .crewCode }
                    }
                )
                .transition(.opacity)

            case .crewCode:
                CrewCodeShareView(
                    crewCode: crewCode,
                    companyName: onboardingManager.state.companyData.name,
                    companyId: onboardingManager.state.companyData.companyId ?? "",
                    variant: variantManager.variant,
                    onContinue: {
                        OnboardingSupabaseAnalytics.shared.trackStepComplete("crew_code")
                        withAnimation { flowStep = .complete }
                    }
                )
                .transition(.opacity)

            // MARK: - Employee Flow (no A/B test)

            case .employeeSignup:
                MinimalSignupView(
                    onboardingManager: onboardingManager,
                    variant: variantManager.variant,
                    onAuthenticated: {
                        onboardingManager.state.flow = .employee
                        OnboardingSupabaseAnalytics.shared.trackStepComplete("signup", metadata: ["flow": "employee"])
                        withAnimation { flowStep = .employeeCodeEntry }
                    },
                    onExistingUserComplete: {
                        withAnimation { flowStep = .complete }
                    },
                    onShowLogin: onShowLogin
                )
                .transition(.opacity)

            case .employeeCodeEntry:
                EmployeeCodeEntryView(
                    onboardingManager: onboardingManager,
                    onCompanyFound: { companyName, companyLogoURL in
                        self.lookupCompanyName = companyName
                        self.lookupCompanyLogoURL = companyLogoURL
                        OnboardingSupabaseAnalytics.shared.trackStepComplete("code_entry")
                        withAnimation { flowStep = .employeeConfirmation }
                    },
                    onBack: {
                        withAnimation { flowStep = .employeeSignup }
                    }
                )
                .transition(.opacity)

            case .employeeConfirmation:
                EmployeeCompanyConfirmationView(
                    companyName: lookupCompanyName,
                    companyLogoURL: lookupCompanyLogoURL,
                    onConfirm: {
                        OnboardingSupabaseAnalytics.shared.trackStepComplete("confirmation")
                        withAnimation { flowStep = .employeeProfile }
                    },
                    onCancel: {
                        withAnimation { flowStep = .employeeCodeEntry }
                    }
                )
                .transition(.opacity)

            case .employeeProfile:
                EmployeeProfileView(
                    onboardingManager: onboardingManager,
                    onComplete: {
                        OnboardingSupabaseAnalytics.shared.trackStepComplete("profile")
                        joinCrewAndComplete()
                    },
                    onSkip: {
                        OnboardingSupabaseAnalytics.shared.trackStepSkip("profile")
                        joinCrewAndComplete()
                    }
                )
                .transition(.opacity)

            case .complete:
                Color.clear
                    .onAppear { onComplete() }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: flowStep)
        .onAppear {
            guard !hasTrackedVariant else { return }
            hasTrackedVariant = true
            AnalyticsManager.shared.trackVariantAssigned(variant: variantManager.variant.rawValue)
        }
    }

    // MARK: - Company Creator CTA (handles A/B/C variant routing)

    private func handleCompanyCreatorSelected() {
        withAnimation {
            switch variantManager.variant {
            case .A, .B:
                flowStep = .signup
            case .C:
                flowStep = .walkthrough
            }
        }
    }

    // MARK: - Employee Join + Complete

    private func joinCrewAndComplete() {
        guard let code = onboardingManager.state.companyData.companyCode else {
            print("[ONBOARDING] No crew code stored, cannot join")
            return
        }

        Task { @MainActor in
            do {
                try await onboardingManager.joinCompany(code: code)
                OnboardingSupabaseAnalytics.shared.trackStepComplete("onboarding_complete")
                withAnimation { flowStep = .complete }
            } catch {
                print("[ONBOARDING] Join failed: \(error)")
                withAnimation { flowStep = .employeeCodeEntry }
            }
        }
    }
}

// MARK: - Splash View (self-contained with proper timer lifecycle)

private struct ABTestSplashView: View {
    let variant: OnboardingVariant
    let onGetStarted: () -> Void
    let onShowLogin: () -> Void

    // Hero slideshow state — scoped to this view only
    @State private var currentSlide: Int = 0
    @State private var slideTimer: Timer?
    private let heroImages = ["hero_1", "hero_2", "hero_3", "hero_4", "hero_5", "hero_6"]

    // Entrance animation state
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0

    private var buttonLabel: String { "GET STARTED" }

    var body: some View {
        ZStack {
            // Background slideshow layer
            backgroundLayer

            // Dark gradient overlay
            LinearGradient(
                colors: [
                    OPSStyle.Colors.modalOverlay,
                    OPSStyle.Colors.overlayMedium,
                    OPSStyle.Colors.overlayHeavy,
                    OPSStyle.Colors.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Content
            VStack(spacing: 0) {
                // Top logo — matches WelcomeScreen layout
                HStack(alignment: .bottom) {
                    Image("LogoWhite")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .padding(.bottom, 8)

                    Text("OPS")
                        .font(OPSStyle.Typography.largeTitle.weight(.bold))
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()
                }
                .padding(.horizontal, 40)
                .padding(.top, 60)
                .opacity(logoOpacity)

                Spacer()

                // Brand message
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("BUILT BY TRADES.")
                            .font(OPSStyle.Typography.largeTitle.weight(.bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("FOR TRADES.")
                            .font(OPSStyle.Typography.largeTitle.weight(.bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }

                    Text("Job management your crew will actually use.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40)
                .opacity(textOpacity)

                Spacer()

                // Bottom area: CTA + login link
                VStack(spacing: 16) {
                    // Primary CTA
                    Button(action: onGetStarted) {
                        HStack {
                            Text(buttonLabel)
                                .font(OPSStyle.Typography.bodyBold)

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        }
                        .foregroundColor(OPSStyle.Colors.invertedText)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(OPSStyle.Colors.primaryText)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }

                    // Sign in link
                    Button(action: onShowLogin) {
                        HStack {
                            Text("SIGN IN")
                                .font(OPSStyle.Typography.bodyBold)

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                    }
                }
                .opacity(buttonOpacity)
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            startSlideshow()
            startEntranceAnimations()
        }
        .onDisappear {
            stopSlideshow()
        }
    }

    // MARK: - Background Layer

    @ViewBuilder
    private var backgroundLayer: some View {
        GeometryReader { geometry in
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ForEach(0..<heroImages.count, id: \.self) { index in
                    Image(heroImages[index])
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(currentSlide == index ? 1 : 0)
                        .animation(.easeInOut(duration: 1.0), value: currentSlide)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Slideshow Control

    private func startSlideshow() {
        slideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            withAnimation {
                currentSlide = (currentSlide + 1) % max(heroImages.count, 1)
            }
        }
    }

    private func stopSlideshow() {
        slideTimer?.invalidate()
        slideTimer = nil
    }

    // MARK: - Entrance Animations

    private func startEntranceAnimations() {
        logoOpacity = 0
        textOpacity = 0
        buttonOpacity = 0

        withAnimation(Animation.spring(response: 0.8, dampingFraction: 0.6).delay(0.3)) {
            logoOpacity = 1.0
        }

        withAnimation(Animation.easeIn(duration: 0.7).delay(0.7)) {
            textOpacity = 1.0
        }

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
        Text("OnboardingABTestCoordinator Preview")
            .preferredColorScheme(.dark)
    }
}
#endif
