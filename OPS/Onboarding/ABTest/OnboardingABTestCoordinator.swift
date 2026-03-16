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
    case employeeInviteCheck // Employee: checking for pending invites (loading)
    case employeeInvitePicker // Employee: multiple invites found, pick one
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
    @State private var isCheckingInvites: Bool = false

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
                            onboardingManager.state.save()
                            handleCompanyCreatorSelected()
                        },
                        onSelectEmployee: {
                            OnboardingSupabaseAnalytics.shared.startSession(
                                variant: nil,
                                flowType: "employee"
                            )
                            OnboardingSupabaseAnalytics.shared.trackStepComplete("type_selection", metadata: ["choice": "employee"])
                            onboardingManager.state.flow = .employee
                            onboardingManager.state.save()
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
                        let currentFlow = onboardingManager.state.flow ?? .companyCreator
                        OnboardingSupabaseAnalytics.shared.trackStepComplete("signup", metadata: ["flow": currentFlow == .companyCreator ? "company_creator" : "employee"])
                        if currentFlow == .employee {
                            // User switched flow via toggle
                            withAnimation { flowStep = .employeeCodeEntry }
                        } else {
                            withAnimation { flowStep = .companyName }
                        }
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
                        let currentFlow = onboardingManager.state.flow ?? .employee
                        OnboardingSupabaseAnalytics.shared.trackStepComplete("signup", metadata: ["flow": currentFlow == .employee ? "employee" : "company_creator"])
                        if currentFlow == .companyCreator {
                            // User switched flow via toggle
                            withAnimation { flowStep = .companyName }
                        } else {
                            // Employee flow: check for pending invites before code entry
                            withAnimation { flowStep = .employeeInviteCheck }
                        }
                    },
                    onExistingUserComplete: {
                        withAnimation { flowStep = .complete }
                    },
                    onShowLogin: onShowLogin
                )
                .transition(.opacity)

            case .employeeInviteCheck:
                // Loading screen while checking for pending invites
                ZStack {
                    OPSStyle.Colors.background.ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                        Text("CHECKING FOR INVITES...")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .tracking(1.5)
                    }
                }
                .onAppear {
                    Task { @MainActor in
                        await onboardingManager.checkPendingInvites()
                        let count = onboardingManager.pendingInvites.count
                        print("[ONBOARDING_AB] Invite check complete. Found \(count) invites")
                        withAnimation {
                            if count > 1 {
                                flowStep = .employeeInvitePicker
                            } else if count == 1 {
                                onboardingManager.selectedInvite = onboardingManager.pendingInvites.first
                                onboardingManager.confirmationSource = .singleInvite
                                flowStep = .employeeConfirmation
                            } else {
                                flowStep = .employeeCodeEntry
                            }
                        }
                    }
                }
                .transition(.opacity)

            case .employeeInvitePicker:
                InvitePickerScreen(manager: onboardingManager)
                    .onReceive(onboardingManager.$confirmationSource) { source in
                        if source == .pickerSelection && onboardingManager.selectedInvite != nil {
                            withAnimation { flowStep = .employeeConfirmation }
                        }
                    }
                    .onReceive(onboardingManager.$state) { newState in
                        // InvitePickerScreen "Enter a different code" calls goToScreen(.codeEntry)
                        if newState.currentScreen == .codeEntry {
                            withAnimation { flowStep = .employeeCodeEntry }
                        }
                    }
                    .transition(.opacity)

            case .employeeCodeEntry:
                EmployeeCodeEntryView(
                    onboardingManager: onboardingManager,
                    onCompanyFound: { companyName, companyLogoURL in
                        self.lookupCompanyName = companyName
                        self.lookupCompanyLogoURL = companyLogoURL
                        OnboardingSupabaseAnalytics.shared.trackStepComplete("code_entry")
                        // Fetch branded details for the confirmation screen
                        Task { @MainActor in
                            do {
                                let _ = try await onboardingManager.fetchCompanyJoinDetails(code: onboardingManager.state.companyData.companyCode ?? "")
                                onboardingManager.confirmationSource = .manualCodeEntry
                            } catch {
                                // Fall through to legacy confirmation with just name/logo
                            }
                            withAnimation { flowStep = .employeeConfirmation }
                        }
                    },
                    onSignOut: {
                        onboardingManager.signOut()
                    }
                )
                .transition(.opacity)

            case .employeeConfirmation:
                if let invite = onboardingManager.selectedInvite {
                    // Branded confirmation from invite
                    EmployeeCompanyConfirmationView(
                        companyName: invite.companyName,
                        companyLogoURL: invite.companyLogoUrl,
                        onConfirm: {
                            OnboardingSupabaseAnalytics.shared.trackStepComplete("confirmation")
                            // Join via invite-aware method
                            Task { @MainActor in
                                do {
                                    try await onboardingManager.joinCompanyFromOnboarding(
                                        companyId: invite.companyId,
                                        invitationId: invite.invitationId
                                    )
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.success)
                                    withAnimation { flowStep = .employeeProfile }
                                } catch {
                                    print("[ONBOARDING_AB] Join from invite failed: \(error)")
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.error)
                                    withAnimation { flowStep = .employeeCodeEntry }
                                }
                            }
                        },
                        onCancel: {
                            onboardingManager.selectedInvite = nil
                            if onboardingManager.pendingInvites.count > 1 {
                                withAnimation { flowStep = .employeeInvitePicker }
                            } else {
                                withAnimation { flowStep = .employeeCodeEntry }
                            }
                        },
                        industries: invite.industries,
                        teamMembers: invite.teamMembers,
                        teamSize: invite.teamSize,
                        roleName: invite.roleName,
                        invitedByName: invite.invitedByName
                    )
                    .transition(.opacity)
                } else {
                    // From manual code entry
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
                }

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
        // Check if we joined via invite-aware flow (companyId already set by joinCompanyFromOnboarding)
        if onboardingManager.state.hasExistingCompany && onboardingManager.state.companyData.companyId != nil {
            // Already joined via CompanyConfirmationScreen → joinCompanyFromOnboarding
            OnboardingSupabaseAnalytics.shared.trackStepComplete("onboarding_complete")
            withAnimation { flowStep = .complete }
            return
        }

        // Legacy path: join via company code
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
