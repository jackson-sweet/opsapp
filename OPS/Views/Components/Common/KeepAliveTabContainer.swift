//
//  KeepAliveTabContainer.swift
//  OPS
//

import SwiftUI

/// Measured width of the keep-alive tab container. Inactive tabs park exactly
/// one container width to the side, so the slide covers the whole screen and
/// never a fraction of it.
struct TabContainerWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Renders every mounted tab at once and slides between them.
///
/// The router this replaced destroyed and cold-rebuilt a whole tab on every
/// switch (`Group { tabContent }.id(selectedTab)`): Home reconstructed the
/// entire Mapbox stack, Leads and Books threw away their view models and
/// refetched behind a spinner, scroll positions died. Tab switching is the
/// app's primary navigation, so that teardown was the single biggest source of
/// navigation lag. Here a tab mounts on first visit and is never unmounted —
/// it just parks a full width to the side its index lives on.
///
/// This type owns GEOMETRY only: where each slot sits, which slots animate, and
/// how wide the parking distance is. Selection policy — what the indices mean,
/// how a tab is chosen, when the mounted set is rebuilt — belongs to the owner
/// (`MainTabView`), which must keep `selected`, `previous` and `mounted`
/// consistent within a single transaction. `previous` is load-bearing, not
/// bookkeeping: it is the only way to know which slot is leaving, and a stale
/// value teleports the outgoing tab off-screen instead of sliding it.
struct KeepAliveTabContainer<Content: View>: View {

    /// The tab on screen.
    let selected: Int
    /// The tab being left. Must land in the same transaction as `selected`.
    let previous: Int
    /// Every mounted slot, ascending. The owner decides what is mounted; this
    /// view never adds or drops one.
    let mounted: [Int]
    /// The root for a given tab index.
    let content: (Int) -> Content

    init(
        selected: Int,
        previous: Int,
        mounted: [Int],
        @ViewBuilder content: @escaping (Int) -> Content
    ) {
        self.selected = selected
        self.previous = previous
        self.mounted = mounted
        self.content = content
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(mounted, id: \.self) { index in
                slot(index)
            }
        }
        // Drives the insertion transition on a tab's first visit. The per-slot
        // `.animation` sits closer to the offsets and governs those.
        .animation(OPSStyle.Animation.standard, value: selected)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TabContainerWidthKey.self,
                    value: proxy.size.width
                )
            }
        )
        .onPreferenceChange(TabContainerWidthKey.self) { containerWidth = $0 }
    }

    /// One mounted tab. Hidden slots keep their whole subtree — and therefore
    /// their state — but take no touches, stay out of the accessibility tree,
    /// and tell everything inside them that they are not on screen.
    private func slot(_ index: Int) -> some View {
        content(index)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.isActiveTab, index == selected)
            .offset(x: slotOffset(for: index))
            .opacity(slotOpacity(for: index))
            .allowsHitTesting(index == selected)
            .accessibilityHidden(index != selected)
            .animation(slotAnimation(for: index), value: selected)
            .transition(slotInsertionTransition)
    }

    // MARK: - Geometry

    /// Off-screen parking distance. The screen-width fallback covers the single
    /// frame before the container reports its own measured width.
    private var slideWidth: CGFloat {
        containerWidth > 0 ? containerWidth : UIScreen.main.bounds.width
    }

    /// Where a mounted tab sits. The selected tab owns the screen; every other
    /// tab parks a full width to the side its index lives on, so the direction
    /// of travel is a straight index comparison — a forward move brings the new
    /// tab in from the trailing edge and pushes the old one off the leading
    /// edge, a back move does the reverse.
    ///
    /// Reduce Motion pins every slot to zero: the switch becomes a crossfade
    /// with no lateral travel, carried entirely by `slotOpacity`.
    private func slotOffset(for index: Int) -> CGFloat {
        guard !reduceMotion else { return 0 }
        if index == selected { return 0 }
        return index < selected ? -slideWidth : slideWidth
    }

    private func slotOpacity(for index: Int) -> Double {
        guard reduceMotion else { return 1 }
        return index == selected ? 1 : 0
    }

    /// Only the arriving and departing tabs animate. Every other mounted tab
    /// merely flips which side it is parked on — animating that would drag
    /// whole screens across the display on any non-adjacent jump.
    private func slotAnimation(for index: Int) -> SwiftUI.Animation? {
        (index == selected || index == previous) ? OPSStyle.Animation.standard : nil
    }

    /// First visit to a tab: the slot does not exist yet, so there is no offset
    /// to animate away from — the insertion transition supplies the identical
    /// slide. Removal is never used; slots are never unmounted.
    private var slotInsertionTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: selected > previous ? .trailing : .leading),
            removal: .identity
        )
    }
}
