//
//  BugReportPresenter.swift
//  OPS
//
//  Presents the shake-to-report sheet on a dedicated overlay UIWindow that
//  sits above every other window, sheet, fullScreenCover, alert, and the
//  keyboard.
//
//  Why a separate window instead of a SwiftUI `.sheet`:
//  A SwiftUI `.sheet` presents through UIKit modal presentation from the
//  view controller that hosts the modifier. When any other sheet/cover is
//  already presented in that controller chain, UIKit refuses the new
//  presentation and SwiftUI does NOT queue it — the binding stays `true`
//  and the bug report only appears once every other sheet is closed (the
//  "sheet-on-sheet deadlock" noted in AppState.swift). Shake-to-report has
//  to work from ANY screen over ANYTHING, so it lives in its own window.
//  This is the same approach used by every commercial shake-to-report SDK.
//
//  Note: the wizard instruction bar deliberately uses a SwiftUI modifier
//  (no secondary window) because it is a passive, persistent bar. The bug
//  report is the opposite case — a transient modal that must capture all
//  input and cover everything — which is the textbook use for a dedicated
//  UIWindow.
//

import UIKit
import SwiftUI

@MainActor
final class BugReportPresenter: NSObject {
    static let shared = BugReportPresenter()
    private override init() { super.init() }

    /// Dedicated window hosting the bug report. Held strongly while shown;
    /// released (and key status returned to the app window) on dismiss.
    private var window: UIWindow?

    /// Single source of truth for "is the bug report on screen". The shake
    /// handler guards on this instead of a SwiftUI binding, so a failed/blocked
    /// presentation can never leave a stuck flag that kills future shakes.
    private(set) var isPresenting = false

    // MARK: - Present

    func present(screenshot: UIImage?, appState: AppState, dataController: DataController) {
        guard !isPresenting else { return }

        // Prefer the foreground-active scene; fall back to any window scene so
        // a shake during a scene transition still resolves a target.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            DebugLogger.shared.log("Bug report: no window scene available", level: .error, category: "BugReport")
            return
        }

        isPresenting = true

        let content = BugReportSheet(
            screenshot: screenshot,
            onClose: { [weak self] in self?.dismiss() }
        )
        .environmentObject(appState)
        .environmentObject(dataController)

        let hosting = UIHostingController(rootView: content)
        hosting.modalPresentationStyle = .pageSheet
        hosting.presentationController?.delegate = self
        if let sheet = hosting.sheetPresentationController {
            sheet.detents = [.large()]
        }

        // Transparent passthrough root: the page-sheet dims the live app behind
        // it (visible through the clear window), matching the previous look.
        let rootVC = PassthroughRootController()
        rootVC.view.backgroundColor = .clear

        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        window.backgroundColor = .clear
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = rootVC
        window.makeKeyAndVisible()
        self.window = window

        rootVC.present(hosting, animated: true)
    }

    // MARK: - Dismiss

    /// Dismisses the bug report (Cancel button / submit success) and tears the
    /// overlay window down once the dismissal animation completes.
    func dismiss() {
        guard isPresenting, let window else {
            isPresenting = false
            return
        }
        if let presented = window.rootViewController?.presentedViewController {
            presented.dismiss(animated: true) { [weak self] in
                self?.teardown()
            }
        } else {
            teardown()
        }
    }

    private func teardown() {
        window?.isHidden = true
        window = nil
        isPresenting = false
    }
}

// MARK: - Interactive (swipe-down) dismissal

extension BugReportPresenter: UIAdaptivePresentationControllerDelegate {
    /// Fires when the user swipes the sheet away. The sheet is already gone, so
    /// just release the window — otherwise it would linger invisibly and block
    /// the app behind it.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        teardown()
    }
}

// MARK: - Status-bar host

/// Keeps the status bar light (the app is dark-themed) while the overlay
/// window is key. We intentionally do NOT delegate to the presented page
/// sheet — its default dark text would be invisible over the dimmed backdrop.
private final class PassthroughRootController: UIViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
}
