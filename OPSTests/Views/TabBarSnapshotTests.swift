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
//  HARD-WON (2026-07-19, iOS 26.5): UIWindows created by tests — detached OR
//  scene-attached — never execute PROGRAMMATIC SwiftUI scrolls. Both
//  `ScrollViewProxy.scrollTo` and `scrollPosition(id:)` silently no-op there
//  (content lays out, contentOffset never moves), while direct
//  `UIScrollView.setContentOffset` works and sticks. Any test that asserts a
//  programmatic scroll actually happened must host the view in the app host's
//  KEY WINDOW (the real display pipeline) — see `settledLaneState(...)`.
//  Detached windows remain fine for static pixel captures.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/TabBarSnapshotTests \
//          -clonedSourcePackagesDirPath .spm-local -derivedDataPath .dd
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
    private func designedReveal(laneWidth: CGFloat) -> CGFloat {
        let iconW: CGFloat = 28
        let p = CGFloat(adminTabs.count - 1)
        let gap = max((laneWidth - p * iconW) / (p + 1), 8)
        return (iconW + gap) + 1 + gap // cell + dividerWidth + gap
    }

    /// Legacy fixed-width reveal used by the pixel captures below.
    private var revealOffset: CGFloat { designedReveal(laneWidth: deviceWidth) }

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

    // MARK: - Key-window scroll harness

    private final class TabSelectionModel: ObservableObject {
        @Published var selected: Int
        init(_ selected: Int) { self.selected = selected }
    }

    /// Binding-driven wrapper so the late-selection test can flip the tab the
    /// way a user tap does (a raw `Binding(get:set:)` closure would never
    /// invalidate the view).
    private struct LaneHarness: View {
        @ObservedObject var model: TabSelectionModel
        let tabs: [TabItem]
        var body: some View {
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.background
                CustomTabBar(selectedTab: $model.selected, tabs: tabs)
            }
        }
    }

    private func appKeyWindow() throws -> UIWindow {
        try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
                ?? UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.windows.first }
                    .first,
            "The OPS test host app must expose a window for scroll assertions"
        )
    }

    /// Hosts the real `CustomTabBar` in the app host's key window (the only
    /// environment where programmatic SwiftUI scrolls execute — see header),
    /// optionally flips the selection after the initial state settles, then
    /// polls until the lane reaches its fully-revealed offset or a generous
    /// deadline proves it never will. No fixed-duration sleeps: the reveal
    /// animates on the 200ms panel curve, so we wait on the condition itself.
    /// Restores the app host's UI before returning.
    private func settledLaneState(initialTab: Int, thenSelect flipTo: Int? = nil) throws -> (offset: CGFloat, contentWidth: CGFloat, laneWidth: CGFloat) {
        let window = try appKeyWindow()
        let original = window.rootViewController
        defer {
            window.rootViewController = original
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }

        let model = TabSelectionModel(initialTab)
        let host = UIHostingController(rootView: AnyView(
            LaneHarness(model: model, tabs: adminTabs)
                .environment(\.colorScheme, .dark)
        ))
        host.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.layoutIfNeeded()

        if let flipTo {
            // Let the initial (unrevealed) state settle first, like a user tap.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            model.selected = flipTo
        }

        let scrollView = try XCTUnwrap(findScrollView(host.view))
        let deadline = Date(timeIntervalSinceNow: 5)
        while Date() < deadline {
            let contentWidth = scrollView.contentSize.width
            let target = max(contentWidth - window.bounds.width, 0)
            if contentWidth > window.bounds.width,
               abs(scrollView.contentOffset.x - target) <= 0.5 {
                break
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        return (scrollView.contentOffset.x, scrollView.contentSize.width, window.bounds.width)
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

    func testSettingsSelectionRevealsTrailingTabOnInitialRender() throws {
        let lane = try settledLaneState(initialTab: adminTabs.count - 1)
        let fullyRevealed = lane.contentWidth - lane.laneWidth

        XCTAssertEqual(
            lane.offset,
            fullyRevealed,
            accuracy: 1,
            "An initially selected Settings tab must be scrolled fully into view"
        )
        XCTAssertEqual(
            fullyRevealed,
            designedReveal(laneWidth: lane.laneWidth),
            accuracy: 1,
            "The revealed amount must equal the designed peek group (cell + divider + gap)"
        )
    }

    func testSelectingSettingsAfterRenderRevealsTrailingTab() throws {
        let lane = try settledLaneState(initialTab: 0, thenSelect: adminTabs.count - 1)
        let fullyRevealed = lane.contentWidth - lane.laneWidth

        XCTAssertEqual(
            lane.offset,
            fullyRevealed,
            accuracy: 1,
            "Selecting Settings must slide the lane until it is fully in view"
        )
        XCTAssertEqual(
            fullyRevealed,
            designedReveal(laneWidth: lane.laneWidth),
            accuracy: 1,
            "The revealed amount must equal the designed peek group (cell + divider + gap)"
        )
    }

    /// Mock of the notifications-menu header row — confirms the Settings entry
    /// uses the same nav-settings glyph as the tab bar (not the SF Symbol gear)
    /// and sits balanced beside the back chevron.
    func testRenderNotifHeader() {
        hostSnapshot("notif_header", height: 96) {
            ZStack(alignment: .top) {
                OPSStyle.Colors.background
                HStack {
                    Image(systemName: OPSStyle.Icons.chevronLeft)
                        .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                    Spacer()
                    Text("NOTIFICATIONS")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Spacer()
                    Image("nav-settings")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: OPSStyle.Layout.IconSize.md, height: OPSStyle.Layout.IconSize.md)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing2_5)
            }
        }
    }
}
#endif
