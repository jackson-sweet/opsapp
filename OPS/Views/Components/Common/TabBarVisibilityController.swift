//
//  TabBarVisibilityController.swift
//  OPS
//
//  Shared visibility control for the global CustomTabBar. The tab bar is a manual
//  ZStack overlay in MainTabView (NOT the system tab bar), so SwiftUI's
//  `.toolbar(.hidden, for: .tabBar)` cannot hide it. Pushed detail screens whose
//  bottom action bar would otherwise sit behind the 100pt bar call
//  `.hidesGlobalTabBar()` to fade it out while they are on screen, so primary
//  CTAs (MARK APPROVED, APPROVE ALL, RECORD PAYMENT) stay reachable.
//

import SwiftUI

/// Tracks which on-screen views want the global tab bar hidden. Toggled only from
/// main-thread SwiftUI lifecycle callbacks (`onAppear`/`onDisappear`).
final class TabBarVisibilityController: ObservableObject {
    /// Stable per-view tokens currently requesting the bar be hidden. A Set keyed
    /// by view instance is idempotent against SwiftUI's double-`onAppear` and is
    /// balanced by the matching `onDisappear` — so it never drifts the way a raw
    /// increment/decrement counter can.
    @Published private(set) var hiders: Set<String> = []

    var isHidden: Bool { !hiders.isEmpty }

    func hide(_ token: String) { hiders.insert(token) }
    func reveal(_ token: String) { hiders.remove(token) }
}

private struct TabBarVisibilityKey: EnvironmentKey {
    // A shared default means `.hidesGlobalTabBar()` is a harmless no-op if a view
    // is ever presented outside MainTabView's injected subtree — never a crash.
    static let defaultValue = TabBarVisibilityController()
}

extension EnvironmentValues {
    var tabBarVisibility: TabBarVisibilityController {
        get { self[TabBarVisibilityKey.self] }
        set { self[TabBarVisibilityKey.self] = newValue }
    }
}

private struct HidesGlobalTabBarModifier: ViewModifier {
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @State private var token = UUID().uuidString

    func body(content: Content) -> some View {
        content
            .onAppear { tabBarVisibility.hide(token) }
            .onDisappear { tabBarVisibility.reveal(token) }
    }
}

extension View {
    /// Hide the global CustomTabBar while this view is on screen. Use on pushed
    /// detail screens whose bottom action bar would otherwise be occluded by the
    /// 100pt tab-bar overlay.
    func hidesGlobalTabBar() -> some View {
        modifier(HidesGlobalTabBarModifier())
    }
}
