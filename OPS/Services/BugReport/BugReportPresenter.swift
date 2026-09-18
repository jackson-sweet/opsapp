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

    /// The report sheet. Kept across POINT AT IT so the same controller —
    /// scroll position, focus, everything — comes back after the pick.
    private var sheet: UIViewController?

    /// What the operator has put into the report. Owned here, not by the
    /// sheet, because POINT AT IT dismisses the sheet to show the live app.
    private var draft: BugReportDraft?

    /// The running POINT AT IT session and its layer, while picking.
    private var pickSession: BugReportPickSession?
    private var pickHost: UIViewController?

    /// Single source of truth for "is the bug report on screen". The shake
    /// handler guards on this instead of a SwiftUI binding, so a failed/blocked
    /// presentation can never leave a stuck flag that kills future shakes.
    private(set) var isPresenting = false

    /// How long after the finger lifts the sheet comes back — long enough to
    /// see the outline land, short enough to feel like one motion.
    static let sheetReturnDelay: TimeInterval = 0.25

    // MARK: - Present

    func present(
        screenshot: UIImage?,
        appState: AppState,
        dataController: DataController
    ) {
        if isPresenting {
            // Self-heal (bug 70087050): a dismissal whose completion never
            // fired (animated dismissal racing a backgrounding), or a
            // presentation that landed on a scene that then died, strands
            // isPresenting = true with no sheet actually on screen — which
            // used to kill shake-to-report for the rest of the app session.
            // Rather than trusting the latch, verify the sheet is genuinely
            // up; if it isn't, tear the corpse down and present fresh.
            let alive = Self.isPresentationAlive(
                hasWindow: window != nil,
                windowHidden: window?.isHidden ?? true,
                sceneAlive: window?.windowScene != nil
                    && window?.windowScene?.activationState != .unattached,
                sheetUp: window?.rootViewController?.presentedViewController != nil,
                pickLayerUp: pickHost != nil
            )
            if alive { return }
            DebugLogger.shared.log(
                "Bug report: recovered a stuck presenter latch (window: \(window != nil ? "present" : "nil"))",
                level: .warning, category: "BugReport"
            )
            teardown()
        }

        // Only present into a scene the user can actually see. Foreground-
        // inactive is allowed (transient during app-switcher / transitions);
        // presenting into a background scene produced an invisible sheet that
        // latched isPresenting forever.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                ?? scenes.first(where: { $0.activationState == .foregroundInactive }) else {
            DebugLogger.shared.log("Bug report: no foreground scene available", level: .error, category: "BugReport")
            return
        }

        isPresenting = true

        let draft = BugReportDraft(triggerScreenshot: screenshot)
        let content = BugReportSheet(
            draft: draft,
            onClose: { [weak self] in self?.dismiss() },
            onPointAtIt: { [weak self] in self?.beginPointing() }
        )
        .environmentObject(appState)
        .environmentObject(dataController)

        let hosting = UIHostingController(rootView: content)

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
        self.sheet = hosting
        self.draft = draft

        configureAsSheet(hosting)
        rootVC.present(hosting, animated: true)
    }

    /// Page sheet, large detent, swipe-down reported back here. Re-applied on
    /// every presentation: UIKit builds a fresh presentation controller each
    /// time a controller is presented, so the sheet returning from POINT AT IT
    /// needs its configuration again.
    private func configureAsSheet(_ controller: UIViewController) {
        controller.modalPresentationStyle = .pageSheet
        controller.presentationController?.delegate = self
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.large()]
        }
    }

    // MARK: - POINT AT IT

    /// The sheet steps aside and the live app comes up under the pick layer.
    ///
    /// Pick mode switches on first, so every house component on screen has
    /// mounted its probe by the time a finger lands; the capture Vision reads
    /// is taken now, from the app window — the sheet lives in this overlay
    /// window, so it is never in that picture.
    func beginPointing() {
        guard isPresenting, pickSession == nil,
              let window, let sheet,
              let appWindow = BugReportCaptureService.shared.appWindow() else { return }

        let overlay = window
        let session = BugReportPickSession(
            appWindow: appWindow,
            screenName: BugReportCaptureService.shared.currentScreenName,
            toAppWindow: { [weak overlay, weak appWindow] point in
                guard let overlay, let appWindow else { return point }
                return appWindow.convert(point, from: overlay)
            },
            toLayer: { [weak overlay, weak appWindow] rect in
                guard let overlay, let appWindow else { return rect }
                return overlay.convert(rect, from: appWindow)
            }
        )
        pickSession = session
        BugReportPickMode.shared.activate()
        session.arm()

        window.endEditing(true)
        sheet.dismiss(animated: true) { [weak self] in
            self?.installPickLayer(for: session)
        }
        // UIKit drops a dismissal completion when the animation is
        // interrupted (the app backgrounding mid-slide). The layer must still
        // arrive, or the operator is left with no sheet and no way back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.installPickLayer(for: session)
        }
    }

    private func installPickLayer(for session: BugReportPickSession) {
        guard pickSession === session, pickHost == nil,
              let root = window?.rootViewController else { return }

        let layer = BugReportPickLayer(
            session: session,
            onCancel: { [weak self] in self?.returnToSheet(from: session) },
            onLift: { [weak self] point in self?.finishPointing(session, at: point) }
        )
        let host = UIHostingController(rootView: layer)
        host.view.backgroundColor = .clear
        root.addChild(host)
        host.view.frame = root.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.view.addSubview(host.view)
        host.didMove(toParent: root)
        pickHost = host
    }

    /// The finger lifted. The pick is measured and captured now; the sheet
    /// comes back `sheetReturnDelay` later with it.
    private func finishPointing(_ session: BugReportPickSession, at point: CGPoint) {
        guard pickSession === session else { return }
        let lifted = Date()
        Task { @MainActor [weak self] in
            let spot = await session.commit(at: point)
            let elapsed = Date().timeIntervalSince(lifted)
            if elapsed < Self.sheetReturnDelay {
                try? await Task.sleep(
                    nanoseconds: UInt64((Self.sheetReturnDelay - elapsed) * 1_000_000_000)
                )
            }
            guard let self, self.pickSession === session else { return }
            if let spot {
                self.draft?.mark(spot.element, screenshot: spot.screenshot)
            }
            self.returnToSheet(from: session)
        }
    }

    /// Ends the pick session and brings the sheet back. The pick layer stays
    /// under the rising sheet — outline and all — and leaves once the sheet
    /// is up, so the mark reads as landing on the report.
    private func returnToSheet(from session: BugReportPickSession) {
        guard pickSession === session else { return }
        session.cancel()
        pickSession = nil
        BugReportPickMode.shared.deactivate()

        let layer = pickHost
        pickHost = nil
        let removeLayer = {
            guard let layer, layer.parent != nil else { return }
            layer.willMove(toParent: nil)
            layer.view.removeFromSuperview()
            layer.removeFromParent()
        }

        guard let root = window?.rootViewController, let sheet else {
            removeLayer()
            teardown()
            return
        }
        configureAsSheet(sheet)
        root.present(sheet, animated: true) { removeLayer() }
        // Same dropped-completion hazard as the dismissal: never leave a dead
        // layer taking touches behind the sheet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { removeLayer() }
    }

    // MARK: - Dismiss

    /// Dismisses the bug report (Cancel button / submit success) and tears the
    /// overlay window down once the dismissal animation completes.
    func dismiss() {
        guard isPresenting, let window else {
            teardown()
            return
        }
        if let presented = window.rootViewController?.presentedViewController {
            presented.dismiss(animated: true) { [weak self] in
                self?.teardown()
            }
            // Failsafe: UIKit drops the dismissal completion when the
            // animation is interrupted (e.g. the app backgrounds mid-swipe),
            // which stranded the latch. If this exact window is still ours
            // after the animation window has long passed, tear it down anyway.
            let dismissedWindow = window
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.window === dismissedWindow else { return }
                DebugLogger.shared.log(
                    "Bug report: dismissal completion never fired — failsafe teardown",
                    level: .warning, category: "BugReport"
                )
                self.teardown()
            }
        } else {
            // Mid-pick (logout lands here too): no sheet to animate away.
            teardown()
        }
    }

    private func teardown() {
        pickSession?.cancel()
        pickSession = nil
        pickHost = nil
        BugReportPickMode.shared.deactivate()
        window?.isHidden = true
        window = nil
        sheet = nil
        draft = nil
        isPresenting = false
    }

    // MARK: - Latch health

    /// Whether a presentation the latch claims is up is REALLY on screen.
    /// Pure decision logic, unit-tested in BugReportPresenterLatchTests —
    /// `present()` recovers (tears down + re-presents) whenever this is false.
    ///
    /// During POINT AT IT the sheet is deliberately down and the pick layer is
    /// up instead; that is a live report holding a draft, never a corpse.
    nonisolated static func isPresentationAlive(
        hasWindow: Bool,
        windowHidden: Bool,
        sceneAlive: Bool,
        sheetUp: Bool,
        pickLayerUp: Bool = false
    ) -> Bool {
        hasWindow && !windowHidden && sceneAlive && (sheetUp || pickLayerUp)
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

// MARK: - Round-trip test seam

#if DEBUG
/// Lets `BugReportPointAtItRoundTripTests` drive the REAL sequence — sheet
/// steps aside, the pick layer comes up over the live app, the finger lifts,
/// the sheet comes back carrying the mark — without synthesising touches.
/// Debug builds only; nothing here ships.
extension BugReportPresenter {
    var testingSheetIsUp: Bool { window?.rootViewController?.presentedViewController != nil }
    var testingPickLayerIsUp: Bool { pickHost != nil }
    var testingDraft: BugReportDraft? { draft }

    /// What Vision read off the pick-time capture, once that read has
    /// finished; nil while it is still running (or with no pick session). A
    /// lift before the read finishes gets at most `textWaitLimit` of grace —
    /// the instant-tap case, named by role — so a test proving the naming
    /// waits for this, as an operator's aim does.
    var testingRecognizedText: [BugReportTextLine]? {
        guard let pickSession, pickSession.linesReady else { return nil }
        return pickSession.lines
    }

    /// The finger lifting at `point` (pick-layer points, which are app-window
    /// points: both windows fill the same scene).
    func testingLift(at point: CGPoint) {
        guard let session = pickSession else { return }
        finishPointing(session, at: point)
    }

    /// CANCEL on the pick layer.
    func testingCancelPick() {
        guard let session = pickSession else { return }
        returnToSheet(from: session)
    }
}
#endif
