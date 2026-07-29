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

    private let iconSize = OPSStyle.Layout.tabBarIconSize   // 28
    private let dividerWidth: CGFloat = 1
    /// Sentinel scroll id for the lane's trailing edge — used to fully reveal
    /// the Settings peek when the Settings tab is selected.
    private static let trailingEdgeID = -1
    /// Sentinel scroll id for the lane's leading edge. It rides on the PADDED
    /// primary group, so its frame starts at content-x 0 and the resting
    /// scroll lands the lane fully left. Scrolling to the first tab CELL
    /// instead parks the lane at `gap/2` — the group's leading padding
    /// scrolled away and the trailing divider peeking on screen (bug
    /// df49d9ef).
    private static let leadingEdgeID = -2

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
            // Tab bar background — a black scrim. Pure app-background black
            // varying only in opacity: fully transparent at the top edge, ramped
            // to solid by the time it reaches the icons, then held black to the
            // base. No fill, no tint, no border — the bar melts into whatever is
            // behind it at the top and grounds into the canvas at the bottom.
            LinearGradient(
                gradient: Gradient(stops: [
                    Gradient.Stop(color: OPSStyle.Colors.background.opacity(0), location: 0.0),
                    Gradient.Stop(color: OPSStyle.Colors.background, location: 0.3),
                    Gradient.Stop(color: OPSStyle.Colors.background, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)

            // Tab lane — horizontally scrollable, evenly spaced, with the last
            // tab (Settings) parked just off the right edge as the single peek.
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

    // MARK: - Lane

    /// Even gap so the screen-edge padding equals the inter-icon spacing
    /// (space-evenly across the visible primary tabs).
    private func evenGap(laneWidth: CGFloat, primaryCount: Int) -> CGFloat {
        let p = CGFloat(max(primaryCount, 1))
        return max((laneWidth - p * iconSize) / (p + 1), 8)
    }

    /// The scrollable tab lane. The primary tabs are evenly spaced to fill the
    /// width exactly (edge padding == inter-icon gap); the last tab (Settings)
    /// sits in a trailing group that begins right at the screen edge, so both
    /// the divider and Settings are genuinely off-screen at rest and simply
    /// slide in when swiped. A custom two-state snap settles the lane to exactly
    /// hidden or revealed. Tap cells stay generous (icon + a full gap) for field
    /// use even though the icons read as evenly spaced.
    @ViewBuilder
    private func tabLane(laneWidth: CGFloat) -> some View {
        let n = max(tabs.count, 1)
        let lastIndex = n - 1
        let primaryCount = max(n - 1, 1)
        let gap = evenGap(laneWidth: laneWidth, primaryCount: primaryCount)
        let cell = iconSize + gap
        let revealDistance = n > 1 ? cell + dividerWidth + gap : 0

        // Underline sits under the selected icon, in lane content coords. The
        // primary tabs start after the group's leading gap/2; Settings lives in
        // the trailing group (divider + a full gap) that begins at laneWidth.
        let indicatorOffset: CGFloat = selectedTab == lastIndex && n > 1
            ? laneWidth + dividerWidth + gap
            : gap + CGFloat(selectedTab) * cell

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        // Primary tabs — evenly spaced, filling the lane width.
                        HStack(spacing: 0) {
                            ForEach(Array(tabs.enumerated().prefix(primaryCount)), id: \.element.id) { index, tab in
                                tabButton(tab: tab, index: index)
                                    .frame(width: cell)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, gap / 2)
                        .id(Self.leadingEdgeID)

                        // Trailing reveal group — begins at the right edge, so the
                        // minimal divider + Settings are hidden until swiped in.
                        if n > 1 {
                            RoundedRectangle(cornerRadius: dividerWidth / 2)
                                .fill(OPSStyle.Colors.tertiaryText)
                                .frame(width: dividerWidth, height: iconSize * 0.85)
                                .frame(height: 50)

                            // Gap between divider and Settings, matching the
                            // inter-icon spacing so the divider sits in the rhythm
                            // (a full gap on each side, not gap/2).
                            Color.clear.frame(width: gap / 2)

                            tabButton(tab: tabs[lastIndex], index: lastIndex)
                                .frame(width: cell)
                                .id(lastIndex)

                            // Trailing margin (+ full-reveal scroll anchor) so
                            // Settings keeps its edge padding once revealed.
                            Color.clear.frame(width: gap / 2)
                                .id(Self.trailingEdgeID)
                        }
                    }

                    // Active-tab underline — rides inside the lane so it scrolls
                    // with the tabs and always sits under the selected icon.
                    Rectangle()
                        .fill(indicatorColor)
                        .frame(width: iconSize, height: 2)
                        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                        .offset(x: indicatorOffset)
                        .animation(reduceMotion ? nil : OPSStyle.Animation.panel, value: selectedTab)
                }
                .padding(.top, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing3)
            }
            .scrollDisabled(revealDistance <= 0)
            .scrollTargetBehavior(PeekSnapBehavior(revealDistance: revealDistance))
            // Belt and braces for the resting position: a lane that is re-laid
            // out (rotation, tab-set change) comes back parked fully left
            // rather than holding a mid-lane offset.
            .defaultScrollAnchor(.leading)
            .onChange(of: selectedTab, initial: true) { _, newValue in
                revealOrHide(proxy: proxy, selected: newValue, lastIndex: lastIndex)
            }
        }
    }

    private func tabButton(tab: TabItem, index: Int) -> some View {
        TabBarItem(
            tab: tab,
            isSelected: selectedTab == index,
            action: {
                withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) {
                    selectedTab = index
                }
            }
        )
    }

    /// Aligns the lane to the selected tab: the last tab (Settings) reveals the
    /// peek; any primary tab returns the lane to its default position.
    private func revealOrHide(proxy: ScrollViewProxy, selected: Int, lastIndex: Int) {
        guard lastIndex > 0 else { return }
        withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) {
            if selected == lastIndex {
                // Fully reveal Settings (scroll to the lane's trailing edge) so
                // landing on the Settings tab shows it, never scrolls it back off.
                proxy.scrollTo(Self.trailingEdgeID, anchor: .trailing)
            } else {
                // The lane's leading EDGE, not the first tab cell — the cell
                // sits `gap/2` into the content, so targeting it rests the
                // lane with its edge padding scrolled off and the trailing
                // divider showing.
                proxy.scrollTo(Self.leadingEdgeID, anchor: .leading)
            }
        }
    }
}

/// Two-state snap: the lane rests either fully hidden (0) or fully revealed
/// (revealDistance), never in between — respecting the even edge padding that
/// `.viewAligned` would otherwise scroll away.
private struct PeekSnapBehavior: ScrollTargetBehavior {
    let revealDistance: CGFloat
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        // iOS 26 routes PROGRAMMATIC scrolls (ScrollViewProxy.scrollTo) through
        // custom target behaviors too, passing the target view's own small rect
        // rather than a viewport-sized destination. Rewriting that rect's
        // origin re-targets the scroll to a rect that is already on-screen,
        // silently killing reveal-on-select. Gesture-end targets arrive
        // viewport-sized; only those are the snap's business.
        guard abs(target.rect.width - context.containerSize.width) < 0.5 else { return }
        guard revealDistance > 0 else {
            target.rect.origin.x = 0
            return
        }
        target.rect.origin.x = target.rect.minX >= revealDistance / 2 ? revealDistance : 0
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
