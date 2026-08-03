//
//  SyncPillHeaderLayoutTests.swift
//  OPSTests
//
//  Regression proof for the sync attention pill colliding with the tab header.
//
//  Reported symptom: on a header carrying the circular search button, the
//  "2 NEED A LOOK" pill was overlapped by that button — the translucent 44pt
//  disc sat on the pill, visually clipping "LOOK" and stealing taps there.
//
//  Cause: `MainTabView` floated the status band from the top safe area, the same
//  rectangle `AppHeader` lays its trailing action cluster into. The pill's
//  trailing edge sits `spacing3` (16pt) from the screen edge and the search
//  button's sits `spacing3_5` (20pt) from it, so any pill wider than 4pt runs
//  straight through the disc.
//
//  Fix: the header publishes its measured height (`AppHeaderHeightKey`) and the
//  band is offset by it. The invariant asserted here is therefore stronger than
//  "the pill misses the search button": the pill must clear the ENTIRE header.
//  Every trailing action button is laid out inside the header, so its maxY is by
//  construction <= the header height — clearing the header clears the button at
//  any Dynamic Type size.
//
//  Frames are captured with SwiftUI anchor preferences rather than the UIKit
//  accessibility tree: SwiftUI publishes most controls as synthesized
//  UIAccessibilityElements that a `subviews` / `accessibilityElements` walk does
//  not reliably surface.
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

    /// Every header type that carries the circular search button in its trailing
    /// cluster — the surfaces the bug was reported on.
    ///
    /// `.home` is deliberately absent: its avatar branch reads
    /// `dataController.syncEngine`, an implicitly-unwrapped property that a bare
    /// `DataController()` leaves nil, so rendering it in a unit-test host traps
    /// (AppHeader.swift:206). Home is covered by the same structural invariant —
    /// the band is offset by whatever height the header reports, whichever
    /// header that is.
    private let searchHeaders: [(type: AppHeader.HeaderType, name: String)] = [
        (.jobBoard, "jobBoard"),
        (.schedule, "schedule"),
        (.leads, "leads"),
        (.books, "books"),
        (.inventory, "inventory"),
        (.settings, "settings"),
    ]

    // MARK: - Measurement plumbing

    /// Carries the pill's bounds anchor out of the view tree.
    private struct PillBoundsKey: PreferenceKey {
        static let defaultValue: [String: Anchor<CGRect>] = [:]
        static func reduce(
            value: inout [String: Anchor<CGRect>],
            nextValue: () -> [String: Anchor<CGRect>]
        ) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    /// Sink the harness writes into on each layout pass; read after quiescence.
    private final class Measurements {
        var pill: CGRect?
        var headerHeight: CGFloat?
    }

    // MARK: - Harness

    /// Mirrors `MainTabView`'s composition: the tab's header at the top of the
    /// sliding container, and the app-level status band floating above it —
    /// offset by the header's own published height.
    private struct Harness: View {
        let headerType: AppHeader.HeaderType
        let count: Int
        var isParked: Bool = false
        var typeSize: DynamicTypeSize = .large
        var sink: Measurements?

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
                            .anchorPreference(key: PillBoundsKey.self, value: .bounds) {
                                ["pill": $0]
                            }
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
            .overlayPreferenceValue(PillBoundsKey.self) { anchors in
                GeometryReader { proxy -> Color in
                    if let sink, let anchor = anchors["pill"] {
                        sink.pill = proxy[anchor]
                        sink.headerHeight = headerBandHeight
                    }
                    return Color.clear
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func harness(
        _ headerType: AppHeader.HeaderType,
        count: Int,
        isParked: Bool = false,
        typeSize: DynamicTypeSize = .large,
        sink: Measurements? = nil
    ) -> some View {
        Harness(
            headerType: headerType,
            count: count,
            isParked: isParked,
            typeSize: typeSize,
            sink: sink
        )
        .environmentObject(DataController())
        .environmentObject(SubscriptionManager.shared)
        .environmentObject(AppState())
    }

    /// Renders the harness at a fixed size (settling on layout quiescence) and
    /// returns what it measured.
    private func measure(
        _ headerType: AppHeader.HeaderType,
        count: Int,
        isParked: Bool = false,
        typeSize: DynamicTypeSize = .large
    ) throws -> Measurements {
        let sink = Measurements()
        let view = harness(
            headerType, count: count, isParked: isParked, typeSize: typeSize, sink: sink
        )
        _ = try FixedSizeSnapshot.render(view, size: captureSize)
        return sink
    }

    // MARK: - The bug

    /// The pill must sit entirely below the header on every surface that carries
    /// the search button. This is exactly what was broken.
    func testPillClearsHeaderOnEverySearchHeader() throws {
        for header in searchHeaders {
            let measured = try measure(header.type, count: 2)

            let pill = try XCTUnwrap(measured.pill, "\(header.name): pill was never measured")
            let headerHeight = try XCTUnwrap(
                measured.headerHeight, "\(header.name): header height was never published"
            )

            XCTAssertGreaterThan(
                headerHeight, 0,
                "\(header.name): header reported zero height — the band would collapse onto it"
            )
            XCTAssertFalse(pill.isEmpty, "\(header.name): pill has an empty frame")
            XCTAssertGreaterThanOrEqual(
                pill.minY, headerHeight,
                """
                \(header.name): the pill starts at \(pill.minY) but the header runs to \
                \(headerHeight) — they overlap, which is the reported bug.
                """
            )
        }
    }

    /// The reported clip was the word "LOOK" vanishing. The pill must render its
    /// label whole — growing rather than truncating — at a wide count and at an
    /// accessibility type size, staying on screen and clear of the header.
    func testPillLabelGrowsAndIsNeverTruncated() throws {
        var widths: [Int: CGFloat] = [:]

        let cases: [(count: Int, typeSize: DynamicTypeSize, name: String)] = [
            (2, .large, "reported"),
            (99, .large, "wide-count"),
            (128, .large, "widest"),
            (99, .accessibility3, "wide-count-a11y3"),
            (99, .accessibility5, "wide-count-a11y5"),
        ]

        for testCase in cases {
            let measured = try measure(.jobBoard, count: testCase.count, typeSize: testCase.typeSize)
            let pill = try XCTUnwrap(measured.pill, "\(testCase.name): pill was never measured")
            let headerHeight = try XCTUnwrap(
                measured.headerHeight, "\(testCase.name): header height was never published"
            )

            XCTAssertGreaterThan(pill.width, 0, "\(testCase.name): pill has no width")
            XCTAssertGreaterThan(pill.height, 0, "\(testCase.name): pill has no height")
            XCTAssertGreaterThanOrEqual(
                pill.minY, headerHeight, "\(testCase.name): pill overlaps the header"
            )
            XCTAssertGreaterThanOrEqual(
                pill.minX, 0,
                "\(testCase.name): pill runs off the leading edge — the label is being cut"
            )
            XCTAssertLessThanOrEqual(
                pill.maxX, captureSize.width + 0.5,
                "\(testCase.name): pill runs off the trailing edge"
            )

            if testCase.typeSize == .large { widths[testCase.count] = pill.width }
        }

        // A truncating label would stop widening. It must grow with the count.
        let w2 = try XCTUnwrap(widths[2])
        let w99 = try XCTUnwrap(widths[99])
        let w128 = try XCTUnwrap(widths[128])
        XCTAssertGreaterThan(w99, w2, "pill did not widen from \"2 NEED A LOOK\" to \"99 NEED A LOOK\"")
        XCTAssertGreaterThan(w128, w99, "pill did not widen from 99 to 128 — the label is truncating")
    }

    // MARK: - Visual proof

    func testSnapshotPillAndSearchButtonCoexist() throws {
        try snapshot("sync-pill-header-reported-count-2", harness(.jobBoard, count: 2))
        try snapshot("sync-pill-header-schedule-4-buttons", harness(.schedule, count: 2))
        try snapshot("sync-pill-header-leads-plus-and-search", harness(.leads, count: 2))
    }

    func testSnapshotPillAtLargeCountAndType() throws {
        try snapshot("sync-pill-header-count-128", harness(.jobBoard, count: 128))
        try snapshot("sync-pill-header-parked-rose", harness(.jobBoard, count: 7, isParked: true))
        try snapshot(
            "sync-pill-header-a11y3-count-99",
            harness(.jobBoard, count: 99, typeSize: .accessibility3)
        )
    }

    // MARK: - Snapshot helper

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
