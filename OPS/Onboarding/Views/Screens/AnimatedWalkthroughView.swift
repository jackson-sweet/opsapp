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
                    }
                }
                .padding(.top, 16)
                .padding(.trailing, 24)

                // Paged content
                TabView(selection: $currentPage) {
                    ForEach(0..<screens.count, id: \.self) { index in
                        WalkthroughPageView(
                            icon: screens[index].icon,
                            headline: screens[index].headline,
                            bodyText: screens[index].body
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

                // Custom page indicator dots
                HStack(spacing: 8) {
                    ForEach(0..<screens.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.white : OPSStyle.Colors.tertiaryText)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 24)

                // GET STARTED button on last screen
                if currentPage == 2 {
                    Button(action: { onComplete() }) {
                        Text("GET STARTED")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.invertedText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(OPSStyle.Colors.primaryText)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                HStack {
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(OPSStyle.Colors.invertedText)
                                        .font(OPSStyle.Typography.caption.weight(.semibold))
                                        .padding(.trailing, 20)
                                }
                            )
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 32)
                    .transition(.opacity)
                }
            }
        }
        .onChange(of: currentPage) { newIndex in
            AnalyticsManager.shared.trackWalkthroughScreenViewed(screenIndex: newIndex)
        }
    }
}

// MARK: - Individual Page View

private struct WalkthroughPageView: View {
    let icon: String
    let headline: String
    let bodyText: String

    @State private var iconScale: CGFloat = 0
    @State private var contentOpacity: Double = 0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated icon
            Image(systemName: icon)
                .font(.system(size: 80))
                .foregroundColor(.white)
                .scaleEffect(iconScale)

            // Headline
            Text(headline)
                .font(OPSStyle.Typography.title)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .opacity(contentOpacity)

            // Body
            Text(bodyText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)
                .opacity(contentOpacity)

            Spacer()
        }
        .onAppear {
            // Reset state for fresh animation each time page appears
            iconScale = 0
            contentOpacity = 0

            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                iconScale = 1
            }
            withAnimation(.easeIn(duration: 0.4).delay(0.3)) {
                contentOpacity = 1
            }
        }
    }
}
