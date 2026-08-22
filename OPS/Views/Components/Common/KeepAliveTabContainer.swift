//
//  KeepAliveTabContainer.swift
//  OPS
//

import SwiftUI

/// Visibility policy for one retained tab root.
///
/// Selection changes only which root is visible and interactive. There is no
/// full-screen transition to wait for, so the destination is present in the
/// same render transaction as the tap while parked roots keep their state.
struct TabSlotPresentation: Equatable {
    let index: Int
    let selected: Int

    var isSelected: Bool { index == selected }
    var opacity: Double { isSelected ? 1 : 0 }
    var zIndex: Double { isSelected ? 1 : 0 }
    var allowsHitTesting: Bool { isSelected }
    var accessibilityHidden: Bool { !isSelected }
}

/// Renders every mounted tab at once and switches visibility immediately.
///
/// The router this replaced destroyed and cold-rebuilt a whole tab on every
/// switch (`Group { tabContent }.id(selectedTab)`): Home reconstructed the
/// entire Mapbox stack, Leads and Books threw away their view models and
/// refetched behind a spinner, scroll positions died. Tab switching is the
/// app's primary navigation, so that teardown was the single biggest source of
/// navigation lag. Here a tab mounts on first visit and is never unmounted.
/// Inactive roots are transparent, non-interactive, and absent from the
/// accessibility tree. The tab bar's small underline may animate independently;
/// the application content itself never slides or crossfades.
struct KeepAliveTabContainer<Content: View>: View {

    /// The tab on screen.
    let selected: Int
    /// Every mounted slot, ascending. The owner decides what is mounted; this
    /// view never adds or drops one.
    let mounted: [Int]
    /// The root for a given tab index.
    let content: (Int) -> Content

    init(
        selected: Int,
        mounted: [Int],
        @ViewBuilder content: @escaping (Int) -> Content
    ) {
        self.selected = selected
        self.mounted = mounted
        self.content = content
    }

    var body: some View {
        ZStack {
            ForEach(mounted, id: \.self) { index in
                slot(index)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One mounted tab. Hidden slots keep their whole subtree — and therefore
    /// their state — but take no touches, stay out of the accessibility tree,
    /// and tell everything inside them that they are not on screen.
    private func slot(_ index: Int) -> some View {
        let presentation = TabSlotPresentation(index: index, selected: selected)
        return content(index)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.isActiveTab, presentation.isSelected)
            .opacity(presentation.opacity)
            .zIndex(presentation.zIndex)
            .allowsHitTesting(presentation.allowsHitTesting)
            .accessibilityHidden(presentation.accessibilityHidden)
    }
}
