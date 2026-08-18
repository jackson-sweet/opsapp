//
//  ScreenshotBugReportOffer.swift
//  OPS
//
//  Screenshot-to-report: a second trigger into the existing bug-report
//  pipeline, not a parallel system.
//
//  The instinct being served: an operator who screenshots inside OPS is
//  capturing something, and often that something is wrong. Shake-to-report
//  covers the deliberate case. This covers the reflex — the screenshot is
//  already the evidence, so the report should cost one tap from there.
//
//  Why iOS forces this exact shape:
//  `UIApplication.userDidTakeScreenshotNotification` fires AFTER the fact and
//  carries NO image. The only permission-free way to hold the shot is to
//  render the app's own window ourselves at notification time — which is the
//  exact path shake already uses (`BugReportCaptureService.captureScreenshot`,
//  the `.normal`-level app window, keyboard and overlay windows excluded).
//  Pulling the real screenshot back out of the photo library would mean
//  standing up a photo-library permission prompt for a feature nobody asked
//  for; that is not a trade we make. Capture happens at notification time, not
//  at tap time, because the live screen will have moved on by then.
//
//  Why it is quiet:
//  Screenshots are taken for entirely innocent reasons — texting a client a
//  job, saving a reference. So the offer is a toast: a 44pt pill that slides
//  in, sits, and leaves. It blocks nothing, is dismissed by a tap anywhere on
//  it, fires no haptic, and is rate-limited far beyond the shake debounce so a
//  burst of screenshots produces one offer rather than five. Ignoring it
//  records nothing and costs nothing. If the operator never wants to see it,
//  one switch in Settings › SUPPORT retires it for good.
//

import UIKit

extension Notification.Name {
    /// The system's post-screenshot notification, re-exported so the wiring in
    /// `ContentView` reads like the `deviceDidShake` line sitting beside it.
    static let operatorDidTakeScreenshot = UIApplication.userDidTakeScreenshotNotification
}

// MARK: - Preference

/// Whether the screenshot offer is armed.
///
/// Most OPS behavior earns no switch — it should simply be right. This one
/// gets one because it is *ambient*: it acts without being asked, on a gesture
/// the operator makes for reasons that are usually none of the app's business.
/// A person who finds that presumptuous needs a way to end it, permanently, in
/// one tap. On by default; the offer has to be seen once to be judged.
enum ScreenshotBugReportPreference {
    static let defaultsKey = "bugReport.screenshotOfferEnabled"

    /// `UserDefaults.bool(forKey:)` cannot distinguish "off" from "never set",
    /// and never-set has to read as ON — hence the object-then-cast.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? true
    }
}

// MARK: - Offer coordinator

/// One guarded boundary for the screenshot trigger, shaped exactly like
/// `BugReportTriggerCoordinator` so the two cannot drift apart.
///
/// It deliberately does NOT present the bug report. It presents an *offer*;
/// the operator's tap is what enters the shared pipeline, and the pipeline
/// re-runs its own guards at that moment (state can change in the seconds a
/// toast is on screen).
@MainActor
final class ScreenshotBugReportOffer {
    static let shared = ScreenshotBugReportOffer()

    enum Rejection: Equatable {
        case disabled
        case debounced
        case tutorialActive
        case presenterActive
        case unauthenticated
        /// The window could not be rendered. The offer promises "with the shot
        /// attached" — without a shot there is no offer worth making.
        case captureUnavailable
    }

    enum Outcome: Equatable {
        case offered
        case rejected(Rejection)
    }

    /// Quiet window between offers.
    ///
    /// Far longer than shake's 1.5s, and for the opposite reason: shake
    /// debounces a single intentional gesture that fires twice, while this
    /// debounces a burst of *unrelated* screenshots. Someone photographing four
    /// screens to text a client gets one offer, not four. The cost of
    /// under-offering is small — shake and Settings › REPORT A BUG are both
    /// still there — while the cost of over-offering is the app feeling like
    /// it is watching.
    private let debounceInterval: TimeInterval
    private let now: () -> Date
    private var lastOfferedAt: Date?

    init(
        debounceInterval: TimeInterval = 30,
        now: @escaping () -> Date = Date.init
    ) {
        self.debounceInterval = debounceInterval
        self.now = now
    }

    /// Production entry point, called from `ContentView`'s screenshot observer.
    @discardableResult
    func offer(
        appState: AppState,
        dataController: DataController
    ) -> Outcome {
        let outcome = offer(
            isEnabled: ScreenshotBugReportPreference.isEnabled(),
            state: BugReportTriggerCoordinator.GuardState(
                isAuthenticated: dataController.isAuthenticated,
                isTutorialActive: appState.shouldRestartTutorial,
                isPresenterActive: BugReportPresenter.shared.isPresenting
            ),
            captureScreenshot: { () -> UIImage? in
                BugReportCaptureService.shared.captureScreenshot()
            },
            presentOffer: { (screenshot: UIImage) in
                ToastCenter.shared.present(
                    Self.offerToast {
                        // The tap enters the SAME pipeline shake uses. It
                        // carries the shot taken when the operator pressed the
                        // buttons — the live screen has almost certainly moved
                        // on by now.
                        BugReportTriggerCoordinator.shared.trigger(
                            source: .screenshot,
                            appState: appState,
                            dataController: dataController,
                            capturedScreenshot: screenshot
                        )
                    }
                )
            }
        )

        if outcome == .offered {
            DebugLogger.shared.log(
                "Bug report offered after screenshot",
                level: .info,
                category: "BugReport"
            )
        }

        return outcome
    }

    /// Deterministic core used by production and focused tests.
    ///
    /// Guard order matches `BugReportTriggerCoordinator.trigger` — debounce,
    /// tutorial, presenter, auth — with the preference ahead of all of it (an
    /// operator who turned this off should cost the app nothing, not even a
    /// clock read). A rejected offer never consumes the quiet window, the same
    /// contract the shake path holds.
    ///
    /// One deliberate divergence from the shake path: the quiet window is
    /// consumed AFTER a successful capture, not before it. Shake presents on a
    /// nil capture because the operator explicitly asked for a report; this
    /// offer has nothing to say without a screenshot, so a failed render is a
    /// rejection and must not spend the window.
    @discardableResult
    func offer<Snapshot>(
        isEnabled: Bool,
        state: BugReportTriggerCoordinator.GuardState,
        captureScreenshot: () -> Snapshot?,
        presentOffer: (Snapshot) -> Void
    ) -> Outcome {
        guard isEnabled else {
            return .rejected(.disabled)
        }

        let offerTime = now()
        if let lastOfferedAt,
           offerTime.timeIntervalSince(lastOfferedAt) <= debounceInterval {
            return .rejected(.debounced)
        }

        guard !state.isTutorialActive else {
            return .rejected(.tutorialActive)
        }

        guard !state.isPresenterActive else {
            return .rejected(.presenterActive)
        }

        guard state.isAuthenticated else {
            return .rejected(.unauthenticated)
        }

        guard let screenshot = captureScreenshot() else {
            return .rejected(.captureUnavailable)
        }

        lastOfferedAt = offerTime
        presentOffer(screenshot)

        return .offered
    }

    // MARK: - The offer itself

    /// The quietest surface in the app.
    ///
    /// - Copy states a fact (`// SCREENSHOT CAPTURED`) rather than asking a
    ///   question. "Something wrong?" would presume a problem the operator may
    ///   not have, which is the exact tone this feature must never take.
    /// - `.success` olive: a capture completed. Tan and rose both accuse.
    /// - **No haptic.** The operator just pressed two hardware buttons and iOS
    ///   already flashed the screen and played the shutter. A buzz on top of
    ///   that is the app announcing it was watching.
    /// - 6s, the app's standard dwell for an action-bearing toast — long enough
    ///   to notice, short enough to forget.
    nonisolated static func offerToast(onReport: @escaping () -> Void) -> Toast {
        Toast(
            label: "// SCREENSHOT CAPTURED",
            tone: .success,
            autoDismissAfter: 6.0,
            action: ToastAction(
                label: "REPORT",
                accessibilityLabel: "Report a bug with this screenshot",
                handler: onReport
            ),
            haptics: false
        )
    }
}
