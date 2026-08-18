//
//  ScreenshotBugReportOfferTests.swift
//  OPSTests
//
//  Screenshot-to-report is the one bug-report trigger the operator never asked
//  for, so the thing under test is mostly restraint: when it stays silent, that
//  it never captures a window it isn't going to use, that a burst of unrelated
//  screenshots yields one offer, and that the shot the operator sees offered is
//  the shot the report ends up carrying.
//
//  Clock is injected — no wall-clock sleeps.
//

import XCTest
@testable import OPS

@MainActor
final class ScreenshotBugReportOfferTests: XCTestCase {
    private final class ScreenshotToken {}

    private let start = Date(timeIntervalSince1970: 10_000)
    private var now = Date(timeIntervalSince1970: 10_000)

    override func setUp() {
        super.setUp()
        now = start
    }

    // MARK: - Helpers

    private func makeOffer(debounceInterval: TimeInterval = 30) -> ScreenshotBugReportOffer {
        ScreenshotBugReportOffer(
            debounceInterval: debounceInterval,
            now: { [unowned self] in now }
        )
    }

    private func readyState(
        isAuthenticated: Bool = true,
        isTutorialActive: Bool = false,
        isPresenterActive: Bool = false
    ) -> BugReportTriggerCoordinator.GuardState {
        BugReportTriggerCoordinator.GuardState(
            isAuthenticated: isAuthenticated,
            isTutorialActive: isTutorialActive,
            isPresenterActive: isPresenterActive
        )
    }

    @discardableResult
    private func offer(
        _ subject: ScreenshotBugReportOffer,
        isEnabled: Bool = true,
        state: BugReportTriggerCoordinator.GuardState? = nil,
        captureScreenshot: () -> ScreenshotToken? = { ScreenshotToken() },
        presentOffer: (ScreenshotToken) -> Void = { _ in }
    ) -> ScreenshotBugReportOffer.Outcome {
        subject.offer(
            isEnabled: isEnabled,
            state: state ?? readyState(),
            captureScreenshot: captureScreenshot,
            presentOffer: presentOffer
        )
    }

    /// Asserts the offer was refused without rendering a window or showing
    /// anything. Every rejection path has to be this cheap and this invisible.
    private func assertSuppressedSilently(
        _ subject: ScreenshotBugReportOffer,
        isEnabled: Bool = true,
        state: BugReportTriggerCoordinator.GuardState? = nil,
        expecting rejection: ScreenshotBugReportOffer.Rejection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var didCapture = false
        var didOffer = false

        let outcome = offer(
            subject,
            isEnabled: isEnabled,
            state: state,
            captureScreenshot: {
                didCapture = true
                return ScreenshotToken()
            },
            presentOffer: { _ in didOffer = true }
        )

        XCTAssertEqual(outcome, .rejected(rejection), file: file, line: line)
        XCTAssertFalse(didCapture, "Rejected offers must not render a window", file: file, line: line)
        XCTAssertFalse(didOffer, "Rejected offers must show nothing", file: file, line: line)
    }

    // MARK: - The switch

    func testDisabledPreferenceRejectsBeforeCaptureOrOffer() {
        assertSuppressedSilently(makeOffer(), isEnabled: false, expecting: .disabled)
    }

    func testDisabledPreferenceIsCheckedAheadOfEveryOtherGuard() {
        // An operator who turned this off should cost the app nothing — not a
        // guard read, not a clock read, and certainly not a window render.
        assertSuppressedSilently(
            makeOffer(),
            isEnabled: false,
            state: readyState(isAuthenticated: false, isTutorialActive: true, isPresenterActive: true),
            expecting: .disabled
        )
    }

    func testPreferenceDefaultsToOnAndHonorsAnExplicitChoice() throws {
        let suiteName = "ScreenshotBugReportOfferTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Never set: the offer has to be seen once to be judged.
        XCTAssertTrue(ScreenshotBugReportPreference.isEnabled(in: defaults))

        // Explicit off must NOT read as "unset" — this is the whole reason the
        // preference goes through `object(forKey:)` instead of `bool(forKey:)`.
        defaults.set(false, forKey: ScreenshotBugReportPreference.defaultsKey)
        XCTAssertFalse(ScreenshotBugReportPreference.isEnabled(in: defaults))

        defaults.set(true, forKey: ScreenshotBugReportPreference.defaultsKey)
        XCTAssertTrue(ScreenshotBugReportPreference.isEnabled(in: defaults))
    }

    // MARK: - Guards shared with the shake pipeline

    func testTutorialGuardRejectsBeforeCaptureOrOffer() {
        assertSuppressedSilently(
            makeOffer(),
            state: readyState(isTutorialActive: true),
            expecting: .tutorialActive
        )
    }

    func testPresenterLatchRejectsBeforeCaptureOrOffer() {
        // Screenshotting the bug report sheet must not offer another one.
        assertSuppressedSilently(
            makeOffer(),
            state: readyState(isPresenterActive: true),
            expecting: .presenterActive
        )
    }

    func testAuthenticationGuardRejectsBeforeCaptureOrOffer() {
        assertSuppressedSilently(
            makeOffer(),
            state: readyState(isAuthenticated: false),
            expecting: .unauthenticated
        )
    }

    // MARK: - Capture

    func testFailedCaptureSuppressesTheOfferEntirely() {
        let subject = makeOffer()
        var didOffer = false

        let outcome = offer(
            subject,
            captureScreenshot: { nil },
            presentOffer: { _ in didOffer = true }
        )

        // The offer promises a report with the shot attached. Without a shot
        // there is nothing worth interrupting anyone for.
        XCTAssertEqual(outcome, .rejected(.captureUnavailable))
        XCTAssertFalse(didOffer)
    }

    func testCaptureHappensBeforeTheOfferIsPresented() {
        let subject = makeOffer()
        var events: [String] = []

        let outcome = offer(
            subject,
            captureScreenshot: {
                events.append("capture")
                return ScreenshotToken()
            },
            presentOffer: { _ in events.append("offer") }
        )

        XCTAssertEqual(outcome, .offered)
        XCTAssertEqual(events, ["capture", "offer"])
    }

    func testOfferCarriesTheShotTakenAtScreenshotTime() {
        let subject = makeOffer()
        let captured = ScreenshotToken()
        var offered: ScreenshotToken?

        let outcome = offer(
            subject,
            captureScreenshot: { captured },
            presentOffer: { offered = $0 }
        )

        XCTAssertEqual(outcome, .offered)
        XCTAssertTrue(offered === captured)
    }

    // MARK: - The quiet window

    func testBurstOfScreenshotsProducesASingleOffer() {
        let subject = makeOffer()
        var offerCount = 0

        // Four screens photographed to text a client — one offer, not four.
        XCTAssertEqual(offer(subject, presentOffer: { _ in offerCount += 1 }), .offered)

        now.addTimeInterval(3)
        XCTAssertEqual(offer(subject, presentOffer: { _ in offerCount += 1 }), .rejected(.debounced))

        now.addTimeInterval(9)
        XCTAssertEqual(offer(subject, presentOffer: { _ in offerCount += 1 }), .rejected(.debounced))

        now.addTimeInterval(18) // 30s exactly — still inside the window
        XCTAssertEqual(offer(subject, presentOffer: { _ in offerCount += 1 }), .rejected(.debounced))

        XCTAssertEqual(offerCount, 1)
    }

    func testQuietWindowReleasesOnceItHasPassed() {
        let subject = makeOffer()

        XCTAssertEqual(offer(subject), .offered)

        now.addTimeInterval(30)
        XCTAssertEqual(offer(subject), .rejected(.debounced))

        now.addTimeInterval(0.001)
        XCTAssertEqual(offer(subject), .offered)
    }

    func testDebounceIsCheckedWithoutRenderingAWindow() {
        let subject = makeOffer()
        XCTAssertEqual(offer(subject), .offered)

        var didCapture = false
        let outcome = offer(
            subject,
            captureScreenshot: {
                didCapture = true
                return ScreenshotToken()
            }
        )

        XCTAssertEqual(outcome, .rejected(.debounced))
        XCTAssertFalse(didCapture, "A debounced screenshot must not cost a window render")
    }

    func testRejectedOfferDoesNotConsumeTheQuietWindow() {
        let subject = makeOffer()

        // Same contract the shake path holds: only an accepted attempt starts
        // the clock, so a screenshot taken while signed out doesn't swallow the
        // next one.
        XCTAssertEqual(
            offer(subject, state: readyState(isAuthenticated: false)),
            .rejected(.unauthenticated)
        )
        XCTAssertEqual(offer(subject), .offered)
    }

    func testFailedCaptureDoesNotConsumeTheQuietWindow() {
        let subject = makeOffer()

        XCTAssertEqual(offer(subject, captureScreenshot: { nil }), .rejected(.captureUnavailable))
        XCTAssertEqual(offer(subject), .offered)
    }

    // MARK: - The offer surface

    func testOfferToastIsSilentAndCarriesTheReportAction() throws {
        var didRequestReport = false
        let toast = ScreenshotBugReportOffer.offerToast { didRequestReport = true }

        // Unsolicited: iOS already flashed and shuttered. No buzz on top.
        XCTAssertFalse(toast.haptics)

        // States a fact; never asks whether something is wrong.
        XCTAssertEqual(toast.label, "// SCREENSHOT CAPTURED")
        guard case .success = toast.tone else {
            return XCTFail("The offer must use the calmest tone — nothing has gone wrong")
        }

        // Long enough to notice, short enough to forget.
        XCTAssertEqual(toast.autoDismissAfter, 6.0)

        let action = try XCTUnwrap(toast.action)
        XCTAssertEqual(action.label, "REPORT")
        XCTAssertEqual(action.accessibilityLabel, "Report a bug with this screenshot")

        // Nothing is filed until the operator taps. An ignored offer is inert.
        XCTAssertFalse(didRequestReport, "Building the offer must not file anything")
        action.handler()
        XCTAssertTrue(didRequestReport)
    }

    // MARK: - Guard order

    func testGuardPrecedenceMatchesTheShakePipeline() {
        // Tutorial, then presenter, then auth — the order
        // BugReportTriggerCoordinator uses. Asserting the precedence (not just
        // "some rejection happened") is what keeps the two from drifting.
        assertSuppressedSilently(
            makeOffer(),
            state: readyState(isAuthenticated: false, isTutorialActive: true, isPresenterActive: true),
            expecting: .tutorialActive
        )
        assertSuppressedSilently(
            makeOffer(),
            state: readyState(isAuthenticated: false, isPresenterActive: true),
            expecting: .presenterActive
        )

        // ...and the quiet window outranks all three, so a burst can't be
        // turned back into a stream of offers by a change in app state.
        let subject = makeOffer()
        XCTAssertEqual(offer(subject), .offered)
        assertSuppressedSilently(
            subject,
            state: readyState(isAuthenticated: false, isTutorialActive: true),
            expecting: .debounced
        )
    }

    func testEachAcceptedOfferCapturesAFreshShot() {
        let subject = makeOffer()
        let first = ScreenshotToken()
        let second = ScreenshotToken()
        var offered: [ScreenshotToken] = []

        XCTAssertEqual(
            offer(subject, captureScreenshot: { first }, presentOffer: { offered.append($0) }),
            .offered
        )

        now.addTimeInterval(31)
        XCTAssertEqual(
            offer(subject, captureScreenshot: { second }, presentOffer: { offered.append($0) }),
            .offered
        )

        // The second offer must carry the second screen, never a stale hold-over
        // from the first.
        XCTAssertEqual(offered.count, 2)
        XCTAssertTrue(offered.first === first)
        XCTAssertTrue(offered.last === second)
    }
}
