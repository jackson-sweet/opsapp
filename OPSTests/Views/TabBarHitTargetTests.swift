//
//  TabBarHitTargetTests.swift
//  OPSTests
//
//  Guards the tab bar's TAPPABLE region — the thing a gloved thumb actually
//  has to hit, which is not the same as the thing the eye sees.
//
//  THE BUG THIS EXISTS FOR: `TabBarItem` was a `Button` wrapping a 28×28 icon,
//  with `.frame(height:)` + `.contentShape(Rectangle())` applied OUTSIDE the
//  Button and `.frame(width: cell)` outside that again. A SwiftUI Button's
//  interactive region is its LABEL's bounds — outer modifiers position that
//  label inside a larger box without extending what responds to touch. The
//  measured result: a 28pt-wide strip per tab (below the 44pt floor the mobile
//  design system calls non-negotiable) with a 32pt DEAD GAP between adjacent
//  tabs. Every miss read to the user as the tab bar being slow.
//
//  HOW THIS IS MEASURED (2026-08-12, iOS 26.5): UIKit `hitTest` cannot see it —
//  SwiftUI hit-tests internally, so every point in the lane returns the same
//  `PlatformGroupContainer`. What DOES track the interactive region is the
//  accessibility node SwiftUI publishes per Button: against the broken code it
//  reported 28×50 at the icon's own x-range (i.e. it followed `contentShape`,
//  not the outer width frame); against the fix it reports the full cell.
//  That makes the AX node frame a faithful proxy for the hit region — and the
//  only one assertable in-process. Finger-on-glass edge taps are verified on a
//  simulator; this test is the regression fence.
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class TabBarHitTargetTests: XCTestCase {

    /// iPhone 17 logical width (pt).
    private let deviceWidth: CGFloat = 393

    /// Full admin tab set — six primary tabs plus the Settings peek.
    private var adminTabs: [TabItem] {
        [
            TabItem(iconName: "nav-home", accessibilityLabel: "Home"),
            TabItem(iconName: "nav-pipeline", accessibilityLabel: "Leads"),
            TabItem(iconName: "nav-pulse", accessibilityLabel: "Books"),
            TabItem(iconName: "nav-jobs", accessibilityLabel: "Job board"),
            TabItem(iconName: "nav-catalog", accessibilityLabel: "Catalog"),
            TabItem(iconName: "nav-calendar", accessibilityLabel: "Schedule"),
            TabItem(iconName: "nav-settings", accessibilityLabel: "Settings")
        ]
    }

    /// The lane's cell width, mirroring `CustomTabBar.evenGap` — icon plus one
    /// even gap, the span each tab owns on screen.
    private func cellWidth(laneWidth: CGFloat) -> CGFloat {
        let iconSize = OPSStyle.Layout.tabBarIconSize
        let primaryCount = CGFloat(adminTabs.count - 1)
        let gap = max((laneWidth - primaryCount * iconSize) / (primaryCount + 1), 8)
        return iconSize + gap
    }

    private struct Harness {
        let host: UIHostingController<AnyView>
        let restore: () -> Void
    }

    /// SwiftUI publishes accessibility nodes only when the simulator's
    /// per-device accessibility bridging is on (`com.apple.Accessibility` →
    /// `AccessibilityEnabled` + `ApplicationAccessibilityEnabled`). Long-lived
    /// dev simulators have it — Accessibility Inspector or any XCUITest run
    /// leaves it enabled — but a factory-fresh simulator does not, and there
    /// the AX frame (this file's entire measurement seam) exists for NO
    /// SwiftUI button at all. A control probe separates "this environment
    /// cannot measure" from "the tab bar stopped publishing": a bare Button
    /// always publishes a node when bridging is up, so its absence means the
    /// environment — skip loudly with the fix, never fail on the wrong cause.
    private func requireAccessibilityBridging() throws {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController
        defer {
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }

        let probe = UIHostingController(rootView: AnyView(
            Button("ax-probe") {}
                .accessibilityLabel("ax-probe")
                .frame(width: 120, height: 44)
        ))
        window.rootViewController = probe
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))

        var frames: [String: CGRect] = [:]
        tabNodeFrames(in: probe.view, into: &frames)
        if frames["ax-probe"] == nil {
            throw XCTSkip(
                """
                Accessibility bridging is off on this simulator, so SwiftUI \
                publishes no AX nodes and the hit-region fence cannot measure \
                its subject. Enable it once for this device, then reboot it: \
                xcrun simctl spawn <udid> defaults write com.apple.Accessibility \
                AccessibilityEnabled -bool true (and the same for \
                ApplicationAccessibilityEnabled).
                """
            )
        }
    }

    /// Hosts the real `CustomTabBar` in the app host's own window — never a
    /// test-created one, which iOS 26.5 drops out of the render AND
    /// accessibility pipelines (on a fresh simulator a test-created window
    /// publishes no AX nodes at all, and the AX frame is this file's whole
    /// measurement seam; see `AppHostWindow`). The app window sits at the
    /// screen origin and matches `deviceWidth`, so accessibility frames
    /// (screen coordinates) still read directly against the hosted geometry.
    private func hostTabBar() throws -> Harness {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController

        let size = CGSize(width: deviceWidth, height: 200)
        let host = UIHostingController(rootView: AnyView(
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.background
                CustomTabBar(selectedTab: .constant(0), tabs: adminTabs)
            }
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
        ))
        host.overrideUserInterfaceStyle = .dark
        host.safeAreaRegions = []

        window.rootViewController = host
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))

        return Harness(
            host: host,
            restore: {
                window.rootViewController = originalRoot
                window.layoutIfNeeded()
            }
        )
    }

    /// Every tab's published accessibility node, keyed by its VoiceOver label —
    /// SwiftUI reports one per `Button`, framed on that Button's interactive
    /// region.
    private func tabNodeFrames(in view: UIView, into found: inout [String: CGRect]) {
        let count = view.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            for index in 0..<count {
                guard let element = view.accessibilityElement(at: index) as? NSObject,
                      let label = element.accessibilityLabel
                else { continue }
                let frame = element.accessibilityFrame
                found[label] = frame
            }
        }
        for sub in view.subviews { tabNodeFrames(in: sub, into: &found) }
    }

    // MARK: - Tests

    /// Each tab must own its whole cell: the full even-spaced column, not just
    /// the glyph inside it. Both axes must clear the 44pt floor.
    func testEveryTabOwnsItsFullCellAsATouchTarget() throws {
        try requireAccessibilityBridging()
        let harness = try hostTabBar()
        defer { harness.restore() }
        var frames: [String: CGRect] = [:]
        tabNodeFrames(in: harness.host.view, into: &frames)

        let cell = cellWidth(laneWidth: deviceWidth)
        let minimum = OPSStyle.Layout.touchTargetMin

        for tab in adminTabs {
            let label = try XCTUnwrap(tab.accessibilityLabel)
            let frame = try XCTUnwrap(
                frames[label],
                "\(label) must publish a tappable accessibility node"
            )
            XCTAssertEqual(
                frame.width,
                cell,
                accuracy: 0.5,
                "\(label)'s touch target must span the whole tab cell, not just its icon"
            )
            XCTAssertGreaterThanOrEqual(
                frame.width,
                minimum,
                "\(label)'s touch target is narrower than the 44pt field minimum"
            )
            XCTAssertGreaterThanOrEqual(
                frame.height,
                minimum,
                "\(label)'s touch target is shorter than the 44pt field minimum"
            )
        }
    }

    /// The lane must hand touch-down straight to the buttons. `UIScrollView`
    /// otherwise withholds it for ~150ms deciding whether the gesture is a
    /// scroll, so a quick tap never shows its pressed state — no acknowledgment
    /// at the moment of contact, which reads as latency.
    func testLaneDoesNotDelayTouchDown() throws {
        let harness = try hostTabBar()
        defer { harness.restore() }
        let scrollView = try XCTUnwrap(
            firstScrollView(in: harness.host.view),
            "The tab lane must be a scroll view for this guard to mean anything"
        )

        XCTAssertFalse(
            scrollView.delaysContentTouches,
            "A delayed touch-down swallows the pressed state on every quick tab tap"
        )
        XCTAssertTrue(
            scrollView.canCancelContentTouches,
            "A touch that turns into a drag must still cancel the press — swipe-to-reveal depends on it"
        )
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for sub in view.subviews {
            if let found = firstScrollView(in: sub) { return found }
        }
        return nil
    }

    /// The primary tabs must tile edge to edge. The broken layout left a full
    /// 32pt gap of nothing between neighbours — a tap landing there did
    /// absolutely nothing, which is the failure a user reads as lag.
    func testNoDeadGapBetweenAdjacentTabs() throws {
        try requireAccessibilityBridging()
        let harness = try hostTabBar()
        defer { harness.restore() }
        var frames: [String: CGRect] = [:]
        tabNodeFrames(in: harness.host.view, into: &frames)

        let primary = adminTabs.dropLast()
        for (index, tab) in primary.enumerated() where index + 1 < primary.count {
            let label = try XCTUnwrap(tab.accessibilityLabel)
            let nextLabel = try XCTUnwrap(primary[index + 1].accessibilityLabel)
            let frame = try XCTUnwrap(frames[label])
            let next = try XCTUnwrap(frames[nextLabel])

            XCTAssertEqual(
                next.minX - frame.maxX,
                0,
                accuracy: 0.5,
                "A tap between \(label) and \(nextLabel) must hit one of them, never nothing"
            )
        }
    }
}
#endif
