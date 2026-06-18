//
//  AnimatedWalkthroughView.swift
//  OPS
//
//  Created by Jackson Sweet on 2026-02-28.
//

import SwiftUI

struct AnimatedWalkthroughView: View {
    let onComplete: () -> Void
    @State private var currentPage = 0
    @State private var buttonVisible = false

    private let screens: [(icon: String, headline: String, body: String)] = [
        (
            icon: "hammer.fill",
            headline: "MANAGE PROJECTS",
            body: "Create projects, assign tasks, and track progress from draft to complete — all in one place."
        ),
        (
            icon: "person.3.fill",
            headline: "COORDINATE YOUR CREW",
            body: "Assign team members, share schedules, and keep everyone on the same page in the field."
        ),
        (
            icon: "calendar",
            headline: "TRACK EVERYTHING",
            body: "See your week at a glance. Every job, every task, every crew member — organized and accessible."
        )
    ]

    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // SKIP button top-right
                HStack {
                    Spacer()
                    Button(action: { onComplete() }) {
                        Text("SKIP")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
                .padding(.top, OPSStyle.Layout.spacing3)
                .padding(.trailing, OPSStyle.Layout.spacing4)

                // Paged content
                TabView(selection: $currentPage) {
                    ForEach(0..<screens.count, id: \.self) { index in
                        WalkthroughPageView(
                            icon: screens[index].icon,
                            headline: screens[index].headline,
                            bodyText: screens[index].body,
                            pageIndex: index
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

                // Custom page indicator — animated bars instead of dots
                HStack(spacing: 6) {
                    ForEach(0..<screens.count, id: \.self) { index in
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                            .fill(index == currentPage ? Color.white : OPSStyle.Colors.tertiaryText.opacity(0.4))
                            .frame(width: index == currentPage ? 24 : 8, height: 4)
                            .animation(OPSStyle.Animation.standard, value: currentPage)
                    }
                }
                .padding(.bottom, OPSStyle.Layout.spacing4)

                // GET STARTED button on last screen
                Button(action: { onComplete() }) {
                    HStack {
                        Text("GET STARTED")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.invertedText)

                        Spacer()

                        Image(systemName: "arrow.right")
                            .foregroundColor(OPSStyle.Colors.invertedText)
                            .font(OPSStyle.Typography.caption.weight(.semibold))
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(OPSStyle.Colors.primaryText)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, OPSStyle.Layout.spacing5)
                .opacity(buttonVisible ? 1 : 0)
                .offset(y: buttonVisible ? 0 : 12)
                .animation(OPSStyle.Animation.standard, value: buttonVisible)
            }
        }
        .onChange(of: currentPage) { _, newIndex in
            AnalyticsManager.shared.trackWalkthroughScreenViewed(screenIndex: newIndex)
            withAnimation {
                buttonVisible = newIndex == screens.count - 1
            }
        }
    }
}

// MARK: - Individual Page View

private struct WalkthroughPageView: View {
    let icon: String
    let headline: String
    let bodyText: String
    let pageIndex: Int

    @State private var iconScale: CGFloat = 0.6
    @State private var iconOpacity: Double = 0
    @State private var headlineOffset: CGFloat = 20
    @State private var headlineOpacity: Double = 0
    @State private var bodyOffset: CGFloat = 20
    @State private var bodyOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon with accent ring
            ZStack {
                // Subtle ring behind icon
                Circle()
                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 140, height: 140)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)

                Image(systemName: icon)
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
            }
            .padding(.bottom, 40)

            // Headline
            Text(headline)
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .tracking(2)
                .multilineTextAlignment(.center)
                .offset(y: headlineOffset)
                .opacity(headlineOpacity)
                .padding(.bottom, OPSStyle.Layout.spacing3)

            // Body
            Text(bodyText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.horizontal, 44)
                .offset(y: bodyOffset)
                .opacity(bodyOpacity)

            Spacer()
        }
        .onAppear {
            animateIn()
            OnboardingSupabaseAnalytics.shared.trackStepView("walkthrough")
        }
    }

    private func animateIn() {
        // Reset
        iconScale = 0.6
        iconOpacity = 0
        headlineOffset = 20
        headlineOpacity = 0
        bodyOffset = 20
        bodyOpacity = 0
        ringScale = 0.5
        ringOpacity = 0

        // Staggered entrance: ring → icon → headline → body
        withAnimation(.easeOut(duration: 0.4)) {
            ringScale = 1.0
            ringOpacity = 1.0
        }

        withAnimation(OPSStyle.Animation.standard.delay(0.1)) {
            iconScale = 1.0
            iconOpacity = 1.0
        }

        withAnimation(OPSStyle.Animation.standard.delay(0.25)) {
            headlineOffset = 0
            headlineOpacity = 1.0
        }

        withAnimation(OPSStyle.Animation.standard.delay(0.35)) {
            bodyOffset = 0
            bodyOpacity = 1.0
        }
    }
}
