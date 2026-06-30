//
//  CustomTabBar.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-21.
//

import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    let tabs: [TabItem]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Tutorial mode support
    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var tutorialPhase
    @Environment(\.wizardStateManager) private var wizardStateManager

    /// Whether tab bar should be disabled during tutorial drag step
    private var isDisabledForTutorial: Bool {
        tutorialMode && tutorialPhase == .dragToAccepted
    }

    /// Indicator color — monochrome `--text-2` per design system (§9 nav, §14:
    /// no accent on nav active state). Switches to wizard accent only while a
    /// tutorial step is highlighting the selected tab.
    private var indicatorColor: Color {
        guard let manager = wizardStateManager,
              manager.isActive,
              let currentStep = manager.currentStep,
              selectedTab < tabs.count,
              let stepId = tabs[selectedTab].wizardStepId,
              currentStep.id == stepId else {
            return OPSStyle.Colors.secondaryText
        }
        return OPSStyle.Colors.wizardAccent
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Tab bar background — a vertical gradient from the elevated surface
            // at the top edge fading into the app background (#000) at the base,
            // so the bar reads as solid, high-contrast ground (legible in
            // sunlight) that settles into the canvas instead of floating as a
            // light translucent slab. Crowned with a hairline per the design
            // system's "glass + hairlines" language.
            LinearGradient(
                colors: [
                    OPSStyle.Colors.cardBackground,
                    OPSStyle.Colors.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(OPSStyle.Colors.separator)
                    .frame(height: 1)
            }

            // Tab lane — horizontally scrollable, with the last tab (Settings)
            // parked just off the right edge as the single "peek" tab.
            GeometryReader { geo in
                tabLane(laneWidth: geo.size.width)
            }
            .frame(height: 100)

            // Black overlay during tutorial drag step
            if isDisabledForTutorial {
                OPSStyle.Colors.overlayHeavy
                    .frame(height: 100)
                    .allowsHitTesting(true) // Blocks taps
            }
        }
        .allowsHitTesting(!isDisabledForTutorial)
    }

    /// The scrollable tab lane. Every tab but the last is sized to exactly fill
    /// the width, so the LAST tab (Settings) overflows by precisely one tab —
    /// making it the sole off-screen "peek" tab. Because the overflow is exactly
    /// one tab, `.viewAligned` resolves to a clean two-state snap: Settings hidden
    /// (lane rests at the leading edge) or revealed (lane rests one tab over).
    /// Settings is also reachable from the notifications-menu gear, which selects
    /// it and reveals the peek here via `snapLane`.
    @ViewBuilder
    private func tabLane(laneWidth: CGFloat) -> some View {
        let n = max(tabs.count, 1)
        let tabWidth = n > 1 ? laneWidth / CGFloat(n - 1) : laneWidth
        let canPeek = n > 1

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                            TabBarItem(
                                tab: tab,
                                isSelected: selectedTab == index,
                                action: {
                                    withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) {
                                        selectedTab = index
                                    }
                                }
                            )
                            .frame(width: tabWidth)
                            .id(index)
                        }
                    }
                    .scrollTargetLayout()

                    // Active-tab underline — rides inside the lane so it scrolls
                    // with the tabs and always sits under the selected icon.
                    Rectangle()
                        .fill(indicatorColor)
                        .frame(width: OPSStyle.Layout.tabBarIconSize, height: 2)
                        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                        .offset(x: CGFloat(selectedTab) * tabWidth + (tabWidth - OPSStyle.Layout.tabBarIconSize) / 2)
                        .animation(reduceMotion ? nil : OPSStyle.Animation.panel, value: selectedTab)
                }
                .padding(.top, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing3)
            }
            .scrollDisabled(!canPeek)
            .scrollTargetBehavior(.viewAligned)
            .onChange(of: selectedTab) { _, newValue in
                snapLane(proxy: proxy, selected: newValue, count: n)
            }
            .onChange(of: tabs.count) { _, newCount in
                // Permissions changed the tab set — re-align to the selected tab.
                snapLane(proxy: proxy, selected: selectedTab, count: max(newCount, 1))
            }
        }
    }

    /// Aligns the lane to the selected tab: the last tab (Settings) reveals the
    /// peek; any primary tab returns the lane to its default (Settings-hidden)
    /// position. Honors Reduce Motion.
    private func snapLane(proxy: ScrollViewProxy, selected: Int, count: Int) {
        guard count > 1 else { return }
        withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) {
            if selected == count - 1 {
                proxy.scrollTo(count - 1, anchor: .trailing)
            } else {
                proxy.scrollTo(0, anchor: .leading)
            }
        }
    }
}

struct TabBarItem: View {
    let tab: TabItem
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.wizardStateManager) private var wizardStateManager

    /// Whether this tab's wizard step is currently active
    private var isWizardHighlighted: Bool {
        guard let manager = wizardStateManager,
              manager.isActive,
              let currentStep = manager.currentStep,
              let stepId = tab.wizardStepId else { return false }
        return currentStep.id == stepId
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: OPSStyle.Layout.spacing1) {
                Image(tab.iconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: OPSStyle.Layout.tabBarIconSize, height: OPSStyle.Layout.tabBarIconSize)
                    .foregroundColor(isWizardHighlighted ? OPSStyle.Colors.wizardAccent : (isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText))
                    .accessibilityLabel(Text(tab.accessibilityLabel ?? ""))

                if let title = tab.title {
                    Text(title)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                        .opacity(isSelected ? 1.0 : 0.8)
                }
            }
        }
        .frame(height: 50)
        .contentShape(Rectangle()) // Make entire area tappable for field use
    }
}

struct TabItem: Identifiable {
    let id = UUID()
    let iconName: String
    let title: String?
    /// VoiceOver label — required because Carbon glyphs ship as image assets
    /// (no auto-label like SF Symbols). Never icon-only without this.
    let accessibilityLabel: String?
    let wizardStepId: String?

    init(iconName: String, title: String? = nil, accessibilityLabel: String? = nil, wizardStepId: String? = nil) {
        self.iconName = iconName
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.wizardStepId = wizardStepId
    }
}

// Preview
struct CustomTabBar_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack {
                Spacer()

                CustomTabBar(
                    selectedTab: .constant(0),
                    tabs: [
                        TabItem(iconName: "nav-home", title: "Home"),
                        TabItem(iconName: "nav-calendar", title: "Schedule"),
                        TabItem(iconName: "nav-settings", title: "Settings")
                    ]
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}
