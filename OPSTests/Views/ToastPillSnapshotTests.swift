//
//  ToastPillSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the site-visit report's toast defect: the success
//  toast stretched edge-to-edge instead of hugging its content. Renders
//  ToastHostView (the real banner) on a full-width canvas so the pill's
//  width is visible against the screen edges — a content-hugging, centered
//  pill, not a full-width bar.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/ToastPillSnapshotTests
//  Shots land in NSTemporaryDirectory()/ops-toast-pill-shots.
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class ToastPillSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 393

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-toast-pill-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    override func tearDown() {
        ToastCenter.shared.reset()
        super.tearDown()
    }

    private func snapshot(_ name: String, toast: Toast, settle: TimeInterval = 0.7) {
        ToastCenter.shared.reset()
        let size = CGSize(width: deviceWidth, height: 300)

        // Render the REAL toast layer over a mid-grey field so the pill's
        // edges read against the background — proving it hugs, not stretches.
        let host = UIHostingController(
            rootView: ZStack {
                OPSStyle.Colors.surfaceInput
                ToastHostView()
            }
            .frame(width: deviceWidth, height: 300)
            .environment(\.colorScheme, .dark)
        )
        host.view.backgroundColor = .black

        let window: UIWindow
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()

        // Present after the layer is live so the banner animates in and
        // settles to full opacity before capture.
        ToastCenter.shared.present(toast)
        RunLoop.main.run(until: Date().addingTimeInterval(settle))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@3x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name)@3x.png"))
        window.isHidden = true
        print("📸 SNAPSHOT \(name)")
    }

    /// Short label — the common case (e.g. "// VISIT SAVED"). Must be a
    /// compact centered pill, nowhere near the screen edges.
    func testShortToastHugsContent() {
        snapshot("01_toast_short", toast: Toast(label: "// VISIT SAVED", tone: .success))
    }

    /// The exact toast from the report — the longest label plus a VIEW
    /// action. Still a hugging pill (wider, but not full-bleed) with the
    /// tap-through affordance.
    func testLongToastWithActionHugsContent() {
        snapshot(
            "02_toast_long_action",
            toast: Toast(
                label: "// LEAD WON · PROJECT CREATED",
                tone: .success,
                autoDismissAfter: 6.0,
                action: ToastAction(label: "VIEW", accessibilityLabel: "View project") {}
            )
        )
    }
}
#endif
