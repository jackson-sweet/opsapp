//
//  SyncPillHeaderLayoutTests.swift
//  OPSTests
//
//  Regression proof for the sync attention pill colliding with the tab header.
//
//  Reported symptom: on a header carrying the circular search button, the
//  "2 NEED A LOOK" pill was overlapped by that button — the translucent 44pt
//  disc sat on the pill, visually clipping "LOOK" and stealing taps in that
//  region.
//
//  Cause: `MainTabView` floats the status band from the top safe area, the same
//  rectangle `AppHeader` puts its trailing action cluster in. The pill's trailing
//  edge sits `spacing3` (16pt) from the screen edge and the search button's sits
//  `spacing3_5` (20pt) from it, so any pill wider than 4pt runs straight through
//  the disc.
//
//  Fix: the header publishes its measured height (`AppHeaderHeightKey`) and the
//  band is offset by it, so the two cannot occupy the same rectangle at any type
//  size. These tests assert exactly that — real `AppHeader`, real
//  `SyncAttentionPill`, real offset — and emit PNGs for visual review.
//
//  Extract: xcrun xcresulttool export attachments --path <dd>/Logs/Test/*.xcresult --output-path <dir>
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class SyncPillHeaderLayoutTests: XCTestCase {

    private let captureSize = CGSize(width: 390, height: 260)

    /// Accessibility label `UniversalSearchButton` ships.
    private let searchLabel = "Search"

    // MARK: - Harness

    /// Mirrors `MainTabView`'s composition exactly: the tab's header at the top
    /// of the sliding container, and the app-level status band floating above it
    /// — offset by the header's own published height.
    private struct Harness: View {
        let headerType: AppHeader.HeaderType
        let count: Int
        let isParked: Bool
        var typeSize: DynamicTypeSize = .large

        @State private var headerBandHeight: CGFloat = AppHeaderHeightKey.defaultValue

        var body: some View {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    AppHeader(headerType: headerType)
                    Spacer(minLength: 0)
                }
                .onPreferenceChange(AppHeaderHeightKey.self) { headerBandHeight = $0 }

                VStack(spacing: OPSStyle.Layout.spacing2) {
                    HStack {
                        Spacer(minLength: 0)
                        SyncAttentionPill(count: count, isParked: isParked)
                            .padding(.trailing, OPSStyle.Layout.spacing3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, headerBandHeight)
                .zIndex(1)
            }
            .frame(width: 390, alignment: .top)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, .dark)
            .dynamicTypeSize(typeSize)
        }
    }

    private func harness(
        _ headerType: AppHeader.HeaderType,
        count: Int,
        isParked: Bool = false,
        typeSize: DynamicTypeSize = .large
    ) -> some View {
        Harness(headerType: headerType, count: count, isParked: isParked, typeSize: typeSize)
            .environmentObject(DataController())
            .environmentObject(SubscriptionManager.shared)
            .environmentObject(AppState())
    }

    // MARK: - The bug: pill and search button must never share a rectangle

    /// Every non-Home header type carries the circular search button in its
    /// trailing cluster. None of them may overlap the pill.
    func testPillClearsSearchButtonOnEveryHeader() throws {
        let headers: [(AppHeader.HeaderType, String)] = [
            (.jobBoard, "jobBoard"),
            (.schedule, "schedule"),
            (.leads, "leads"),
            (.books, "books"),
            (.inventory, "inventory"),
            (.settings, "settings"),
        ]

        for (headerType, name) in headers {
            let frames = try renderAndMeasure(harness(headerType, count: 2))

            let pill = try XCTUnwrap(
                frames[SyncAttentionPill.accessibilityID],
                "\(name): attention pill was not found in the accessibility tree"
            )
            let search = try XCTUnwrap(
                frames[searchLabel],
                "\(name): search button was not found in the accessibility tree"
            )

            XCTAssertFalse(
                pill.intersects(search),
                """
                \(name): the attention pill overlaps the search button.
                pill=\(pill) search=\(search)
                """
            )
            XCTAssertGreaterThanOrEqual(
                pill.minY, search.maxY,
                "\(name): the pill must sit below the header's action cluster"
            )
        }
    }

    /// Home has no search button — its trailing slot is the 44pt avatar with a
    /// notification badge. The pill has to clear that too.
    func testPillClearsHomeAvatarCluster() throws {
        let frames = try renderAndMeasure(harness(.home, count: 2))
        let pill = try XCTUnwrap(frames[SyncAttentionPill.accessibilityID])

        // Everything the header drew lives above the band; nothing may reach
        // down into the pill.
        let intruders = frames
            .filter { $0.key != SyncAttentionPill.accessibilityID }
            .filter { $0.value.intersects(pill) }

        XCTAssertTrue(
            intruders.isEmpty,
            "home: header elements overlap the pill — \(intruders.keys.sorted())"
        )
    }

    /// The reported clip was the word "LOOK" disappearing. The pill must render
    /// its label whole at a wide count and at an accessibility type size — it
    /// grows, it never truncates.
    func testPillLabelIsNeverTruncated() throws {
        let cases: [(count: Int, typeSize: DynamicTypeSize, name: String)] = [
            (2, .large, "reported"),
            (99, .large, "wide-count"),
            (99, .accessibility3, "wide-count-a11y3"),
            (128, .accessibility5, "widest"),
        ]

        for testCase in cases {
            let frames = try renderAndMeasure(
                harness(.jobBoard, count: testCase.count, typeSize: testCase.typeSize)
            )
            let pill = try XCTUnwrap(
                frames[SyncAttentionPill.accessibilityID],
                "\(testCase.name): pill not found"
            )
            let search = try XCTUnwrap(frames[searchLabel], "\(testCase.name): search not found")

            // A truncated label would collapse the pill's width. Measure against
            // the label the pill is actually asked to draw.
            let label = SyncStatusCopy.PendingWork.pillBadge(count: testCase.count)
            XCTAssertGreaterThan(
                pill.width, CGFloat(label.count) * 4,
                "\(testCase.name): pill is too narrow to be showing \"\(label)\" in full"
            )
            XCTAssertGreaterThan(pill.height, 0, "\(testCase.name): pill has no height")
            XCTAssertFalse(
                pill.intersects(search),
                "\(testCase.name): pill overlaps search button — pill=\(pill) search=\(search)"
            )
            // It must also stay on screen.
            XCTAssertGreaterThanOrEqual(pill.minX, 0, "\(testCase.name): pill runs off the leading edge")
            XCTAssertLessThanOrEqual(pill.maxX, captureSize.width + 1, "\(testCase.name): pill runs off the trailing edge")
        }
    }

    // MARK: - Visual proof

    func testSnapshotPillAndSearchButtonCoexist() throws {
        try snapshot("sync-pill-header-reported-count-2", harness(.jobBoard, count: 2))
        try snapshot("sync-pill-header-schedule-4-buttons", harness(.schedule, count: 2))
        try snapshot("sync-pill-header-home-avatar", harness(.home, count: 2))
    }

    func testSnapshotPillAtLargeCountAndType() throws {
        try snapshot("sync-pill-header-count-99", harness(.jobBoard, count: 99))
        try snapshot("sync-pill-header-parked-rose", harness(.jobBoard, count: 7, isParked: true))
        try snapshot(
            "sync-pill-header-a11y3-count-99",
            harness(.jobBoard, count: 99, typeSize: .accessibility3)
        )
    }

    // MARK: - Render + measure

    /// Hosts the view at a fixed size and returns the on-screen frames of every
    /// labelled/identified accessibility element, in view coordinates.
    private func renderAndMeasure<V: View>(_ view: V) throws -> [String: CGRect] {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController
        defer {
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }

        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .black
        host.safeAreaRegions = []
        host.view.frame = CGRect(origin: .zero, size: captureSize)

        let container = UIViewController()
        container.overrideUserInterfaceStyle = .dark
        container.view.backgroundColor = .black
        container.addChild(host)
        container.view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            host.view.widthAnchor.constraint(equalToConstant: captureSize.width),
            host.view.heightAnchor.constraint(equalToConstant: captureSize.height),
        ])
        host.didMove(toParent: container)

        window.rootViewController = container
        window.layoutIfNeeded()

        // Settle: the preference round-trip (header height → band offset) needs a
        // second layout pass before frames are final.
        var stable = 0
        var last: [String: CGRect] = [:]
        let deadline = Date(timeIntervalSinceNow: 3)
        var collected: [String: CGRect] = [:]
        while stable < 3, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            host.view.layoutIfNeeded()
            collected = Self.elementFrames(in: host.view)
            if collected == last, !collected.isEmpty {
                stable += 1
            } else {
                stable = 0
                last = collected
            }
        }
        return collected
    }

    /// Walks the accessibility tree (SwiftUI publishes `UIAccessibilityElement`s
    /// rather than one UIView per control, so `subviews` alone is not enough) and
    /// returns each element's frame converted into `root`'s coordinate space.
    private static func elementFrames(in root: UIView) -> [String: CGRect] {
        var out: [String: CGRect] = [:]

        func record(_ object: NSObject) {
            // `accessibilityIdentifier` comes from UIAccessibilityIdentification,
            // which bare NSObject does not conform to — cast rather than assume.
            let identified = (object as? UIAccessibilityIdentification)?.accessibilityIdentifier
            let key: String?
            if let identifier = identified, !identifier.isEmpty {
                key = identifier
            } else if let label = object.accessibilityLabel, !label.isEmpty {
                key = label
            } else {
                key = nil
            }
            guard let key else { return }

            let screenFrame: CGRect
            if let view = object as? UIView {
                screenFrame = view.superview?.convert(view.frame, to: nil) ?? view.frame
            } else {
                screenFrame = object.accessibilityFrame
            }
            guard !screenFrame.isEmpty, !screenFrame.isNull else { return }
            let local = root.convert(screenFrame, from: nil)
            // Keep the largest hit for a key — SwiftUI can publish nested
            // elements sharing a label.
            if let existing = out[key], existing.width * existing.height >= local.width * local.height {
                return
            }
            out[key] = local
        }

        func walk(_ object: NSObject, depth: Int) {
            guard depth < 40 else { return }
            record(object)
            if let elements = object.accessibilityElements as? [NSObject], !elements.isEmpty {
                for element in elements { walk(element, depth: depth + 1) }
            }
            if let view = object as? UIView {
                for subview in view.subviews { walk(subview, depth: depth + 1) }
            }
        }

        walk(root, depth: 0)
        return out
    }

    private func snapshot<V: View>(_ name: String, _ view: V) throws {
        let image = try FixedSizeSnapshot.render(view, size: captureSize)
        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("SNAPSHOT \(name) (\(Int(image.size.width))x\(Int(image.size.height))pt)")
    }
}
#endif
