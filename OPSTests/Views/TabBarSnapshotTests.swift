//
//  TabBarSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for the CustomTabBar refresh:
//    1. MONEY/Books tab icon = the pulse-line glyph (`nav-pulse`).
//    2. Bar background = a vertical gradient (elevated surface → app background
//       #000) crowned by a hairline — grounds into the canvas, holds dark over
//       bright content.
//    3. Scroll-peek lane: the non-Settings tabs fill the width; Settings (the
//       last tab) is parked just off the right edge as the single peek tab,
//       revealed by a swipe that snaps between hidden and shown.
//
//  Renders the REAL `CustomTabBar` via `UIHostingController` + `UIWindow` +
//  `drawHierarchy` (NOT `ImageRenderer`, which can't lay out a live `ScrollView`
//  off-screen). The lane's scroll offset is set directly to capture both the
//  rest (Settings hidden) and revealed (Settings shown) states. The snap *feel*
//  itself is a runtime gesture — confirm that on a simulator.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17' \
//          -only-testing:OPSTests/TabBarSnapshotTests \
//          -derivedDataPath /tmp/ops-tabbar-dd
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class TabBarSnapshotTests: XCTestCase {

    /// iPhone 17 logical width (pt).
    private let deviceWidth: CGFloat = 393

    /// Full admin tab set (7 tabs) — Books carries the pulse icon, Settings is
    /// the trailing peek tab. tabWidth == width / (7 - 1).
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

    /// The off-screen overflow that reveals the Settings peek (one tap cell +
    /// divider), matching CustomTabBar's even-spacing geometry.
    private var revealOffset: CGFloat {
        let iconW: CGFloat = 28
        let p = CGFloat(adminTabs.count - 1)
        let gap = max((deviceWidth - p * iconW) / (p + 1), 8)
        return (iconW + gap) + 1 + gap / 2 // cell + dividerWidth + trailing gap/2
    }

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-tabbar-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func findScrollView(_ view: UIView) -> UIScrollView? {
        if let sv = view as? UIScrollView { return sv }
        for sub in view.subviews {
            if let found = findScrollView(sub) { return found }
        }
        return nil
    }

    /// Hosts a real SwiftUI view in a window, lays it out (so a live `ScrollView`
    /// resolves), optionally drives the lane's scroll offset, then captures.
    private func hostSnapshot<V: View>(_ name: String, height: CGFloat, scrollOffsetX: CGFloat = 0, @ViewBuilder _ content: () -> V) {
        let size = CGSize(width: deviceWidth, height: height)
        let host = UIHostingController(rootView:
            content()
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
        )
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))

        if scrollOffsetX != 0, let scrollView = findScrollView(host.view) {
            scrollView.setContentOffset(CGPoint(x: scrollOffsetX, y: 0), animated: false)
            host.view.layoutIfNeeded()
            // Let the scroll-offset preference propagate to the divider fade.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@\(Int(image.scale))x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt)")
    }

    func testRenderTabBarSurfaces() {
        // REST — six primary tabs fill the width, Settings parked off the right.
        hostSnapshot("tabbar_rest", height: 200) {
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.background
                CustomTabBar(selectedTab: .constant(2), tabs: adminTabs)
            }
        }

        // REST over a bright field — proves the gradient holds dark (no wash-out)
        // and that Settings is the only tab off the edge.
        hostSnapshot("tabbar_rest_bright", height: 200) {
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(white: 0.88), Color(white: 0.52)],
                               startPoint: .top, endPoint: .bottom)
                CustomTabBar(selectedTab: .constant(2), tabs: adminTabs)
            }
        }

        // REVEALED — lane scrolled one tab over: Settings fully in view at the
        // right (selected, with its underline), Home scrolled off the left.
        hostSnapshot("tabbar_revealed", height: 200, scrollOffsetX: revealOffset) {
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.background
                CustomTabBar(selectedTab: .constant(6), tabs: adminTabs)
            }
        }
    }
}
#endif
