//
//  ReadyScreen.swift
//  OPS
//
//  Final onboarding screen with billing + welcome guide content.
//  Progress bar is handled by OnboardingContainer.
//  Page dots show progress through welcome guide pages.
//

import SwiftUI
import UIKit

struct ReadyScreen: View {
    @ObservedObject var manager: OnboardingManager
    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    @State private var currentPage = 0

    // Determine pages based on user type
    private var pages: [WelcomeGuidePage] {
        if manager.state.flow == .companyCreator {
            return WelcomeGuidePage.crewLeadPages
        } else {
            return WelcomeGuidePage.employeePages
        }
    }

    // Show billing page first for all users
    private var showBillingFirst: Bool {
        true
    }

    private var totalPages: Int {
        showBillingFirst ? pages.count + 1 : pages.count
    }

    // Check if we're on a welcome guide page (not billing)
    private var isOnWelcomeGuidePage: Bool {
        showBillingFirst ? currentPage > 0 : true
    }

    // Current welcome guide page index (0-based)
    private var welcomePageIndex: Int {
        showBillingFirst ? currentPage - 1 : currentPage
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Page Content
                TabView(selection: $currentPage) {
                    // Billing page (first page for all users)
                    if showBillingFirst {
                        BillingInfoView(
                            isActive: currentPage == 0,
                            userType: manager.state.flow?.userType
                        )
                        .tag(0)
                    }

                    // Welcome guide pages
                    ForEach(0..<pages.count, id: \.self) { index in
                        let tagIndex = showBillingFirst ? index + 1 : index
                        WelcomePageContent(
                            page: pages[index],
                            isActive: currentPage == tagIndex
                        )
                        .tag(tagIndex)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)
                .gesture(DragGesture().onChanged({ _ in })) // Disable swipe

                // Page dots for welcome guide pages (above button)
                if isOnWelcomeGuidePage {
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Circle()
                                .fill(index == welcomePageIndex ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText.opacity(0.3))
                                .frame(width: 8, height: 8)
                                .animation(.easeInOut(duration: 0.2), value: welcomePageIndex)
                        }
                    }
                    .padding(.bottom, 24)
                }

                // Navigation Button
                VStack(spacing: 24) {
                    if currentPage == 0 {
                        // Billing page - Start Trial for company creators, Continue for employees
                        let buttonText = manager.state.flow == .companyCreator ? "START TRIAL" : "CONTINUE"
                        OnboardingPrimaryButton(buttonText) {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            withAnimation {
                                currentPage += 1
                            }
                        }
                    } else if currentPage < totalPages - 1 {
                        OnboardingPrimaryButton("NEXT") {
                            withAnimation {
                                currentPage += 1
                            }
                        }
                    } else {
                        OnboardingPrimaryButton("LET'S GO") {
                            // Use goForward() to check if tutorial is needed before completing
                            manager.goForward()
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - Welcome Page Content

private struct WelcomePageContent: View {
    let page: WelcomeGuidePage
    let isActive: Bool

    @State private var currentScreenshot = 0
    @State private var showTitle = false
    @State private var titleComplete = false
    @State private var showDescription = false
    @State private var showContent = false
    @State private var animationKey = UUID() // Force typewriter recreation

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
                .frame(height: 40)

            // Title with square brackets - typed animation
            HStack(spacing: 0) {
                if showTitle {
                    WelcomeTypewriterText(
                        "[\(page.title)]",
                        font: OPSStyle.Typography.subtitle,
                        color: .white,
                        typingSpeed: 35
                    ) {
                        titleComplete = true
                        // Small delay then show description
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showDescription = true
                        }
                    }
                    .id(animationKey) // Force recreation when key changes
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            // If page has screenshots, show carousel
            if !page.screenshots.isEmpty {
                VStack(spacing: 12) {
                    // Screenshot carousel with prev/next preview
                    ZStack {
                        // Previous screenshot (grayed out, smaller, left side)
                        if currentScreenshot > 0 {
                            Image(page.screenshots[currentScreenshot - 1].imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 240)
                                .cornerRadius(8)
                                .opacity(0.3)
                                .offset(x: -140)
                        }

                        // Current screenshot
                        TabView(selection: $currentScreenshot) {
                            ForEach(0..<page.screenshots.count, id: \.self) { index in
                                Image(page.screenshots[index].imageName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 380)
                                    .cornerRadius(12)
                                    .tag(index)
                            }
                        }
                        .frame(height: 400)
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

                        // Next screenshot (grayed out, smaller, right side)
                        if currentScreenshot < page.screenshots.count - 1 {
                            Image(page.screenshots[currentScreenshot + 1].imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 240)
                                .cornerRadius(8)
                                .opacity(0.3)
                                .offset(x: 140)
                        }
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)

                    // Screenshot dots (for multiple screenshots per page)
                    if page.screenshots.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(0..<page.screenshots.count, id: \.self) { index in
                                Circle()
                                    .fill(index == currentScreenshot ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText.opacity(0.3))
                                    .frame(width: 6, height: 6)
                                    .animation(.easeInOut, value: currentScreenshot)
                            }
                        }
                        .padding(.bottom, 4)
                        .opacity(showContent ? 1 : 0)
                    }

                    // Description for current screenshot - typed animation
                    if showDescription {
                        WelcomeTypewriterText(
                            page.screenshots[currentScreenshot].description,
                            font: OPSStyle.Typography.caption,
                            color: OPSStyle.Colors.secondaryText,
                            typingSpeed: 50
                        ) {
                            // Show rest of content after description types
                            withAnimation(.easeOut(duration: 0.4)) {
                                showContent = true
                            }
                        }
                        .id("\(animationKey)-desc")
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 60)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                    } else {
                        // Placeholder to maintain layout
                        Text(" ")
                            .font(OPSStyle.Typography.caption)
                            .frame(minHeight: 60)
                    }
                }
            } else {
                // Layout for pages without screenshots
                VStack(spacing: 30) {
                    Spacer()

                    if showDescription {
                        WelcomeTypewriterText(
                            page.description,
                            font: OPSStyle.Typography.body,
                            color: OPSStyle.Colors.secondaryText,
                            typingSpeed: 45
                        )
                        .id("\(animationKey)-desc")
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                    }

                    Spacer()
                }
            }

            Spacer()
        }
        .onChange(of: isActive) { _, nowActive in
            if nowActive {
                // Page just became visible - start animations
                startAnimations()
            }
        }
        .onAppear {
            // Only start if already active (first page case)
            if isActive {
                startAnimations()
            }
        }
    }

    private func startAnimations() {
        // Reset state
        showTitle = false
        titleComplete = false
        showDescription = false
        showContent = false
        currentScreenshot = 0
        animationKey = UUID() // New key forces typewriter recreation

        // Start title typing after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showTitle = true
        }
    }
}

// MARK: - Welcome Guide Typewriter Text

private struct WelcomeTypewriterText: View {
    let text: String
    let font: Font
    let color: Color
    let typingSpeed: Double
    let onComplete: (() -> Void)?

    @State private var displayedText: String = ""
    @State private var showCursor: Bool = true
    @State private var isComplete: Bool = false

    init(
        _ text: String,
        font: Font = OPSStyle.Typography.body,
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
        switch font {
        case OPSStyle.Typography.title:
            return 28
        case OPSStyle.Typography.subtitle:
            return 22
        case OPSStyle.Typography.body:
            return 16
        case OPSStyle.Typography.caption:
            return 14
        default:
            return 18
        }
    }

    private func startTyping() {
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

// MARK: - Preview

struct ReadyScreen_Previews: PreviewProvider {
    static var previews: some View {
        let dataController = DataController()
        let manager = OnboardingManager(dataController: dataController)
        manager.selectFlow(.companyCreator)

        return ReadyScreen(manager: manager)
            .environmentObject(dataController)
            .environmentObject(SubscriptionManager.shared)
    }
}
