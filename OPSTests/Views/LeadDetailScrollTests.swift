//
//  LeadDetailScrollTests.swift
//  OPSTests
//
//  Two lead-dossier scroll bugs, asserted against the real `LeadDetailView`
//  hosted in the app host's window:
//
//    * 73f7381b — scrolling the dossier carried the lead's title off the top,
//      so mid-page you could not tell which lead you were reading. Project
//      Details already pins its title (`LazyVStack(pinnedViews:)` + `Section`);
//      leads now does the same.
//    * e13be3bb — the dossier panned sideways. Content wider than the viewport
//      makes a vertical document drift horizontally under a thumb, which reads
//      as breakage on a truck seat.
//
//  Hosted in the APP HOST's window via `AppHostWindow.acquire()` — test-created
//  windows drop programmatic SwiftUI scrolls on iOS 26.5 (see the file header of
//  TabBarSnapshotTests). `setContentOffset` works in either, and it is what
//  these tests drive.
//

#if DEBUG
import XCTest
import SwiftUI
import SwiftData
@testable import OPS

@MainActor
final class LeadDetailScrollTests: XCTestCase {

    private let deviceWidth: CGFloat = 393
    private let deviceHeight: CGFloat = 852

    /// Pinning, asserted the way a human verifies it: the band directly under
    /// the nav bar shows the SAME pixels at rest and halfway down the document.
    ///
    /// A scrolling header changes that band completely; a pinned one does not.
    /// This is deliberately pixel-based — SwiftUI does not vend the header's
    /// accessibility element through the UIView tree, so there is nothing to
    /// look up by identifier, and asserting on rendered output is both closer to
    /// the bug report and impossible to satisfy accidentally. Pixel scanning is
    /// the same technique `LeadTriageCardHeaderLayoutTests` uses.
    func testTitleStaysOnScreenWhenDossierIsScrolled() throws {
        let harness = try hostDossier()
        defer { harness.teardown() }

        let bandAtRest = try XCTUnwrap(pinnedBand(harness))

        harness.scrollView.setContentOffset(
            CGPoint(x: 0, y: harness.scrollView.contentSize.height * 0.5),
            animated: false
        )
        settle(harness.window)

        XCTAssertGreaterThan(
            harness.scrollView.contentOffset.y, 200,
            "the document must actually have scrolled for this assertion to mean anything"
        )

        let bandScrolled = try XCTUnwrap(pinnedBand(harness))
        let similarity = Self.similarity(bandAtRest, bandScrolled)

        XCTAssertGreaterThan(
            similarity, 0.97,
            "the band under the nav bar changed when the dossier scrolled (\(Int(similarity * 100))% identical) — the lead's identity is not pinned, 73f7381b is not fixed"
        )
    }

    /// The pinned band must carry real text, not an empty strip — a header that
    /// renders blank would trivially satisfy the similarity assertion above.
    func testPinnedBandActuallyRendersTheIdentity() throws {
        let harness = try hostDossier()
        defer { harness.teardown() }

        harness.scrollView.setContentOffset(
            CGPoint(x: 0, y: harness.scrollView.contentSize.height * 0.5),
            animated: false
        )
        settle(harness.window)

        let band = try XCTUnwrap(pinnedBand(harness))
        let inkRatio = Self.inkRatio(band)

        XCTAssertGreaterThan(
            inkRatio, 0.01,
            "the pinned band is blank — nothing is being held on screen"
        )
    }

    /// A vertical document must never scroll sideways. e13be3bb.
    func testDossierDoesNotScrollHorizontally() throws {
        let harness = try hostDossier()
        defer { harness.teardown() }

        XCTAssertLessThanOrEqual(
            harness.scrollView.contentSize.width,
            harness.window.bounds.width + 0.5,
            "dossier content is wider than the screen — it will pan sideways"
        )
    }

    /// Accessibility Dynamic Type is the trigger condition on the bug report:
    /// oversized labels are what pushed the content past the viewport.
    func testDossierDoesNotScrollHorizontallyAtAccessibilityTextSize() throws {
        let harness = try hostDossier(sizeCategory: .accessibilityExtraLarge)
        defer { harness.teardown() }

        XCTAssertLessThanOrEqual(
            harness.scrollView.contentSize.width,
            harness.window.bounds.width + 0.5,
            "dossier pans sideways at accessibility XL — e13be3bb is not fixed"
        )
    }

    // MARK: - Harness

    private struct Harness {
        let window: UIWindow
        let scrollView: UIScrollView
        let teardown: () -> Void
    }

    private func hostDossier(
        sizeCategory: ContentSizeCategory = .large
    ) throws -> Harness {
        let container = try ModelContainer(
            for: Schema(versionedSchema: OPSSchemaV22.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let permissions = PermissionStore()
        permissions.permissions = ["leads.edit": "all", "leads.convert": "all"]

        let view = NavigationStack {
            LeadDetailView(opportunity: leadFixture())
                .environmentObject(DataController())
                .environmentObject(permissions)
        }
        .modelContainer(container)
        .environment(\.sizeCategory, sizeCategory)
        .environment(\.colorScheme, .dark)
        .frame(width: deviceWidth, height: deviceHeight)

        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(x: 0, y: 0, width: deviceWidth, height: deviceHeight)

        let window = try AppHostWindow.acquire()
        let previousRoot = window.rootViewController
        window.rootViewController = host
        window.layoutIfNeeded()
        settle(window)

        let scrollView = try XCTUnwrap(
            findScrollView(host.view),
            "LeadDetailView must host a scroll view"
        )
        settleGeometry(scrollView, in: window)

        return Harness(
            window: window,
            scrollView: scrollView,
            teardown: { window.rootViewController = previousRoot }
        )
    }

    private func leadFixture() -> Opportunity {
        let opp = Opportunity.preview(
            id: "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
            title: "Roof tear-off and full re-deck, 28 sq",
            contactName: "Helen Calloway",
            stage: .quoted,
            estimatedValue: 14_200,
            daysInStage: 9
        )
        opp.contactPhone = "(555) 123-4567"
        opp.contactEmail = "helen@example.com"
        opp.address = "1240 Maple Avenue, Victoria, British Columbia"
        opp.source = "referral"
        return opp
    }

    // MARK: - Settling + traversal

    private func settle(_ window: UIWindow, for interval: TimeInterval = 0.35) {
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: interval))
    }

    /// Settle on geometry quiescence, never a fixed sleep — a content size that
    /// is still growing produces a false pass on the width assertions.
    private func settleGeometry(_ scrollView: UIScrollView, in window: UIWindow) {
        var lastSize = CGSize(width: -1, height: -1)
        let deadline = Date(timeIntervalSinceNow: 3)
        while Date() < deadline {
            let size = scrollView.contentSize
            if size.height > 0, size == lastSize { return }
            lastSize = size
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }

    private func findScrollView(_ view: UIView) -> UIScrollView? {
        if let sv = view as? UIScrollView { return sv }
        for sub in view.subviews {
            if let found = findScrollView(sub) { return found }
        }
        return nil
    }

    // MARK: - Pixel band

    /// The strip of the window directly beneath the nav bar — where a pinned
    /// header lives. Captured from the app host's own window, which is the only
    /// window that renders reliably mid-suite.
    private func pinnedBand(_ harness: Harness) -> CGImage? {
        let viewport = harness.scrollView.convert(harness.scrollView.bounds, to: harness.window)
        let band = CGRect(
            x: 0,
            y: viewport.minY,
            width: harness.window.bounds.width,
            height: min(Self.bandHeight, viewport.height)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: harness.window.bounds, format: format).image { _ in
            harness.window.drawHierarchy(in: harness.window.bounds, afterScreenUpdates: true)
        }
        return image.cgImage?.cropping(to: band)
    }

    /// Height of the identity band: id line + two title lines + contact +
    /// address, comfortably inside the header even at the default type size.
    private static let bandHeight: CGFloat = 150

    private static func pixels(_ image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    /// Fraction of channel samples that match within a small tolerance.
    static func similarity(_ lhs: CGImage, _ rhs: CGImage) -> Double {
        guard lhs.width == rhs.width, lhs.height == rhs.height,
              let a = pixels(lhs), let b = pixels(rhs), a.count == b.count else {
            return 0
        }
        var matching = 0
        for index in stride(from: 0, to: a.count, by: 4) {
            let dr = abs(Int(a[index]) - Int(b[index]))
            let dg = abs(Int(a[index + 1]) - Int(b[index + 1]))
            let db = abs(Int(a[index + 2]) - Int(b[index + 2]))
            if dr <= 8, dg <= 8, db <= 8 { matching += 1 }
        }
        return Double(matching) / Double(a.count / 4)
    }

    /// Fraction of pixels bright enough to be text on the near-black canvas.
    static func inkRatio(_ image: CGImage) -> Double {
        guard let buffer = pixels(image) else { return 0 }
        var ink = 0
        for index in stride(from: 0, to: buffer.count, by: 4) {
            let luma = (Int(buffer[index]) * 299 + Int(buffer[index + 1]) * 587 + Int(buffer[index + 2]) * 114) / 1000
            if luma > 90 { ink += 1 }
        }
        return Double(ink) / Double(buffer.count / 4)
    }
}
#endif
