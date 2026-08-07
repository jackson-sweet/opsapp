//
//  BugReportTriggerCoordinatorTests.swift
//  OPSTests
//
//  The supported bug-report entry points (shake and Settings) share one
//  guarded boundary. These tests keep source attribution, debounce, capture
//  ordering, and non-destructive overlay presentation deterministic.
//

import XCTest
@testable import OPS

@MainActor
final class BugReportTriggerCoordinatorTests: XCTestCase {
    private final class ScreenshotToken {}

    private let start = Date(timeIntervalSince1970: 10_000)
    private var now = Date(timeIntervalSince1970: 10_000)

    override func setUp() {
        super.setUp()
        now = start
    }

    private func makeCoordinator() -> BugReportTriggerCoordinator {
        BugReportTriggerCoordinator(now: { [unowned self] in now })
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
    private func trigger(
        _ coordinator: BugReportTriggerCoordinator,
        source: BugReportTriggerCoordinator.Source = .shake,
        state: BugReportTriggerCoordinator.GuardState? = nil,
        captureScreenshot: () -> ScreenshotToken? = { nil },
        presentOverlay: (ScreenshotToken?) -> Void = { _ in }
    ) -> BugReportTriggerCoordinator.Outcome {
        coordinator.trigger(
            source: source,
            state: state ?? readyState(),
            captureScreenshot: captureScreenshot,
            presentOverlay: presentOverlay
        )
    }

    func testAcceptedOutcomePreservesTriggerSourceIdentity() {
        let coordinator = makeCoordinator()

        XCTAssertEqual(trigger(coordinator, source: .shake), .accepted(.shake))

        now.addTimeInterval(1.501)
        XCTAssertEqual(trigger(coordinator, source: .settings), .accepted(.settings))
    }

    func testDebounceIsSharedAcrossShakeAndSettings() {
        let coordinator = makeCoordinator()

        XCTAssertEqual(trigger(coordinator, source: .shake), .accepted(.shake))
        XCTAssertEqual(trigger(coordinator, source: .settings), .rejected(.debounced))

        now.addTimeInterval(1.5)
        XCTAssertEqual(trigger(coordinator, source: .settings), .rejected(.debounced))

        now.addTimeInterval(0.001)
        XCTAssertEqual(trigger(coordinator, source: .settings), .accepted(.settings))
    }

    func testTutorialGuardRejectsBeforeCaptureOrPresentation() {
        let coordinator = makeCoordinator()
        var didCapture = false
        var didPresent = false

        let outcome = trigger(
            coordinator,
            state: readyState(isTutorialActive: true),
            captureScreenshot: {
                didCapture = true
                return nil
            },
            presentOverlay: { _ in didPresent = true }
        )

        XCTAssertEqual(outcome, .rejected(.tutorialActive))
        XCTAssertFalse(didCapture)
        XCTAssertFalse(didPresent)
    }

    func testAuthenticationGuardRejectsBeforeCaptureOrPresentation() {
        let coordinator = makeCoordinator()
        var didCapture = false
        var didPresent = false

        let outcome = trigger(
            coordinator,
            state: readyState(isAuthenticated: false),
            captureScreenshot: {
                didCapture = true
                return nil
            },
            presentOverlay: { _ in didPresent = true }
        )

        XCTAssertEqual(outcome, .rejected(.unauthenticated))
        XCTAssertFalse(didCapture)
        XCTAssertFalse(didPresent)
    }

    func testScreenshotIsCapturedBeforeOverlayPresentation() {
        let coordinator = makeCoordinator()
        var events: [String] = []
        let screenshot = ScreenshotToken()
        var presentedScreenshot: ScreenshotToken?

        let outcome = trigger(
            coordinator,
            source: .settings,
            captureScreenshot: {
                events.append("capture")
                return screenshot
            },
            presentOverlay: { captured in
                events.append("present")
                presentedScreenshot = captured
            }
        )

        XCTAssertEqual(outcome, .accepted(.settings))
        XCTAssertEqual(events, ["capture", "present"])
        XCTAssertTrue(presentedScreenshot === screenshot)
    }

    func testPresenterLatchRejectsDuplicateWithoutRecapturing() {
        let coordinator = makeCoordinator()
        var didCapture = false
        var didPresent = false

        let outcome = trigger(
            coordinator,
            state: readyState(isPresenterActive: true),
            captureScreenshot: {
                didCapture = true
                return nil
            },
            presentOverlay: { _ in didPresent = true }
        )

        XCTAssertEqual(outcome, .rejected(.presenterActive))
        XCTAssertFalse(didCapture)
        XCTAssertFalse(didPresent)
    }

    func testOpenSheetAndKeyboardRemainIntactWhileOverlayPresents() {
        let coordinator = makeCoordinator()
        let isSheetPresented = true
        let isKeyboardVisible = true
        var events: [String] = []

        let outcome = trigger(
            coordinator,
            captureScreenshot: {
                XCTAssertTrue(isSheetPresented)
                XCTAssertTrue(isKeyboardVisible)
                events.append("capture-live-context")
                return nil
            },
            presentOverlay: { _ in
                XCTAssertTrue(isSheetPresented)
                XCTAssertTrue(isKeyboardVisible)
                events.append("present-overlay")
            }
        )

        XCTAssertEqual(outcome, .accepted(.shake))
        XCTAssertEqual(events, ["capture-live-context", "present-overlay"])
        XCTAssertTrue(isSheetPresented)
        XCTAssertTrue(isKeyboardVisible)
    }

    func testRejectedAttemptDoesNotConsumeDebounceWindow() {
        let coordinator = makeCoordinator()

        XCTAssertEqual(
            trigger(coordinator, state: readyState(isAuthenticated: false)),
            .rejected(.unauthenticated)
        )
        XCTAssertEqual(trigger(coordinator, source: .settings), .accepted(.settings))
    }
}
