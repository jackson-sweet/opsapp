//
//  TabBarSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for the CustomTabBar refresh:
//    1. MONEY/Books tab icon swapped to the pulse-line glyph (`nav-pulse`).
//    2. Bar background changed from a light translucent material to a vertical
//       gradient (elevated surface → app background #000) crowned by a hairline.
//
//  Renders the bar to PNGs via SwiftUI's `ImageRenderer` over both the black
//  canvas (the real in-app context) and a bright field (to prove it no longer
//  reads "too light"). This is a rendering harness, not an assertion test — it
//  never fails on pixels; it writes images for a human/agent to inspect.
//
//  NOTE: `ImageRenderer` cannot capture `UIVisualEffectView` blur, which is the
//  exact reason the new background is an opaque gradient (no blur) — so these
//  PNGs are faithful to what ships.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/TabBarSnapshotTests \
//          -derivedDataPath /tmp/ops-tabbar-dd
//
//  Output: $TMPDIR/ops-tabbar-shots/<name>@3x.png (path is logged) + attached
//  to the .xcresult (extractable via `xcrun xcresulttool export attachments`).
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class TabBarSnapshotTests: XCTestCase {

    /// iPhone 17 logical width (pt).
    private let deviceWidth: CGFloat = 393

    /// The full operator tab set — Books (index 2) carries the new pulse icon.
    private var tabs: [TabItem] {
        [
            TabItem(iconName: "nav-home", accessibilityLabel: "Home"),
            TabItem(iconName: "nav-pipeline", accessibilityLabel: "Leads"),
            TabItem(iconName: "nav-pulse", accessibilityLabel: "Books"),
            TabItem(iconName: "nav-jobs", accessibilityLabel: "Job board"),
            TabItem(iconName: "nav-calendar", accessibilityLabel: "Schedule"),
            TabItem(iconName: "nav-settings", accessibilityLabel: "Settings")
        ]
    }

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-tabbar-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Renders a SwiftUI view to a PNG at @3x in dark mode.
    private func snapshot<V: View>(_ name: String, height: CGFloat, @ViewBuilder _ content: () -> V) {
        let host = content()
            .frame(width: deviceWidth, height: height)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: host)
        renderer.scale = 3
        renderer.isOpaque = true

        guard let image = renderer.uiImage, let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@3x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name)@3x.png"))
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt)")
    }

    func testRenderTabBarSurfaces() {
        // 1. Over the black canvas — the real in-app context. Books selected so
        //    the pulse icon shows in its active (#EDEDED) tint, and the gradient
        //    base dissolves into the app background.
        snapshot("tabbar_over_dark", height: 220) {
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.background
                CustomTabBar(selectedTab: .constant(2), tabs: tabs)
            }
        }

        // 2. Over a bright field — simulates bright content (map / list) behind
        //    the bar. Proves the opaque gradient holds dark and no longer reads
        //    "too light." Books still selected.
        snapshot("tabbar_over_bright", height: 220) {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [Color(white: 0.88), Color(white: 0.52)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                CustomTabBar(selectedTab: .constant(2), tabs: tabs)
            }
        }

        // 3. Books UNSELECTED (Home selected) — proves the pulse glyph in its
        //    inactive (#8A8A8A tertiary) tint over the black canvas.
        snapshot("tabbar_books_inactive", height: 220) {
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.background
                CustomTabBar(selectedTab: .constant(0), tabs: tabs)
            }
        }
    }
}
#endif
