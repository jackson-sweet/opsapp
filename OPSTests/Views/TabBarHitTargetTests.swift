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

    /// Hosts the real `CustomTabBar` at device width in a window pinned to the
    /// screen origin, so the accessibility frames (screen coordinates) can be
    /// read directly.
    private func hostTabBar() -> UIHostingController<AnyView> {
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
        host.view.frame = CGRect(origin: .zero, size: size)

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        return host
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
        let host = hostTabBar()
        var frames: [String: CGRect] = [:]
        tabNodeFrames(in: host.view, into: &frames)

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
        let host = hostTabBar()
        let scrollView = try XCTUnwrap(
            firstScrollView(in: host.view),
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
        let host = hostTabBar()
        var frames: [String: CGRect] = [:]
        tabNodeFrames(in: host.view, into: &frames)

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
