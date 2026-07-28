//
//  AppHostWindow.swift
//  OPSTests
//
//  Resolves — and repairs — the app host's own window: the one the OPS app
//  created at launch, in the foreground scene. Never a window a test created.
//
//  WHY (2026-07-28, iOS 26.5): full-suite runs degrade ambient window/scene
//  state in two ways. (1) Hiding a UIWindow neither detaches it from its scene
//  nor deterministically hands key status back, so `scene.windows` accumulates
//  hidden leftover harness windows mid-suite; naive lookups
//  (`first { $0.isKeyWindow }`, `connectedScenes.first`) are one teardown race
//  away from resolving a leftover instead of the app's window. (2) The host
//  can drop out of the foreground-active display pipeline entirely — observed
//  as suite-wide "[Snapshotting] Rendering a window (UIWindow) requires it to
//  be in a foreground scene." warnings, blank window-level snapshots, and
//  later-transaction programmatic SwiftUI scrolls being dropped outright
//  (initial-transaction scrolls and setContentOffset keep working).
//
//  This helper picks the app's real window — first visible normal-level
//  window of the (preferably foreground-active) scene; leftovers are hidden,
//  later in the array, or both — then repairs every quality a test process
//  can restore: scene activation, visibility, key status. Repairs are logged
//  so a still-degraded host explains downstream assertion failures.
//

#if DEBUG
import UIKit
import XCTest

@MainActor
enum AppHostWindow {
    /// The app host's real window, repaired and ready to host test content.
    static func acquire() throws -> UIWindow {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let scene = try XCTUnwrap(
            scenes.first { $0.activationState == .foregroundActive } ?? scenes.first,
            "The OPS test host app must expose a window scene"
        )
        if scene.activationState != .foregroundActive {
            print("AppHostWindow: scene not foreground-active (state \(scene.activationState.rawValue)) — requesting activation")
            UIApplication.shared.activateSceneSession(
                for: UISceneSessionActivationRequest(session: scene.session)
            )
            let deadline = Date(timeIntervalSinceNow: 2)
            while scene.activationState != .foregroundActive, Date() < deadline {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            }
            if scene.activationState != .foregroundActive {
                print("AppHostWindow: scene still not foreground-active after repair — downstream assertions may fail")
            }
        }
        let window = try XCTUnwrap(
            scene.windows.first { !$0.isHidden && $0.windowLevel == .normal }
                ?? scene.windows.first,
            "The OPS test host app must expose a window"
        )
        if window.isHidden {
            print("AppHostWindow: host window was hidden — restoring visibility")
            window.isHidden = false
        }
        if !window.isKeyWindow { window.makeKey() }
        return window
    }
}
#endif
