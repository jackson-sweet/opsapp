//
//  ToastHostWindow.swift
//  OPS
//
//  Hosts the toast layer in a dedicated UIWindow one tier above the app's
//  normal window — and therefore above every presented `.sheet`,
//  `.fullScreenCover`, and tab header.
//
//  Why a window instead of a `.overlay` on the root view:
//  a SwiftUI `.sheet` is presented through UIKit modal presentation from the
//  view controller that hosts it, in a layer ABOVE the entire root view. A
//  `.overlay(ToastHostView())` on MainTabView therefore sits BELOW any open
//  sheet, so a toast fired from inside a form sheet (e.g. "// CHANGES SAVED" on
//  save) rendered behind the sheet's content. Mirrors the dedicated-window
//  approach already used by BugReportPresenter; the toast window sits one tier
//  below the bug-report modal (`.alert` vs `.alert + 1`).
//

import SwiftUI
import UIKit

/// Window that hosts the toast layer above everything. It only intercepts a
/// touch while a toast is actually on screen — and even then SwiftUI's own
/// hit-testing captures only the pill (the lone element with a `contentShape`);
/// transparent areas return nil and fall straight through to the app window.
final class PassthroughToastWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // `hitTest` is always invoked on the main thread, so reading the
        // @MainActor center here is safe.
        let showingToast = MainActor.assumeIsolated { ToastCenter.shared.current != nil }
        guard showingToast else { return nil }
        return super.hitTest(point, with: event)
    }
}

@MainActor
final class ToastWindowController {
    static let shared = ToastWindowController()

    private var window: PassthroughToastWindow?

    private init() {}

    /// Idempotent. Creates the toast window once, attached to the active scene.
    /// Called from `ToastCenter.present` (so it exists whenever a toast fires,
    /// from any context) and from `.toastHost()`'s `onAppear` (so it exists early).
    func install() {
        // If the previous scene was torn down (scene reconnection), rebuild.
        if let existing = window, existing.windowScene == nil { window = nil }
        guard window == nil else { return }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }

        let host = UIHostingController(rootView: ToastHostView())
        host.view.backgroundColor = .clear

        let window = PassthroughToastWindow(windowScene: scene)
        window.windowLevel = .alert        // above sheets & covers; below the bug-report modal (.alert + 1)
        window.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false            // visible, but never made key — must not steal the keyboard / first responder
        self.window = window
    }
}
