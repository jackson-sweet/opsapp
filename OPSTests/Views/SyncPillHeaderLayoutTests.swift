//
//  SyncPillHeaderLayoutTests.swift
//  OPSTests
//
//  The non-Home half of bug 417aac7b's proof, rendered against the REAL
//  `AppHeader` for every root that carries a trailing action cluster.
//
//  History. The pill first floated in an app-level band starting at the top
//  safe area, then in a band offset by the header's measured height — which
//  moved the collision one row down onto whatever control the root parks under
//  its header (on Home, the ALL filter chip). The third close superimposed it
//  on the header but reserved the trailing cluster's own column, and Jackson
//  rejected that on sight (2026-09-08): "It is being influenced by the avatar.
//  It should appear ONTOP of the avatar" — "with a dropshadow".
//
//  The pill now shares the title band's control row with the trailing cluster
//  and is painted OVER it. Both are flush to the band's trailing inset and both
//  end on the same row edge, so the overlap is structural, not incidental.
//
//  What is asserted here is therefore the invariant, not a symptom: the pill's
//  frame MUST intersect the header's trailing controls on every root, must NOT
//  reach past the header into the content below it, and must cost the header no
//  height. The first of those is the one that pins Jackson's direction — the
//  close before this asserted its exact opposite, and passed.
//
//  Frames are captured with SwiftUI anchor preferences rather than the UIKit
//  accessibility tree: SwiftUI publishes most controls as synthesized
//  UIAccessibilityElements that a `subviews` / `accessibilityElements` walk does
//  not reliably surface. `AppHeader` renders the shipped
//  `HeaderSyncStatusOverlay`, which publishes the pill's real bounds.
//
//  Extract: xcrun xcresulttool export attachments --path <dd>/Logs/Test/*.xcresult --output-path <dir>
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

private let pillHarnessSpace = "sync-pill-header-harness"

@MainActor
final class SyncPillHeaderLayoutTests: XCTestCase {

    /// Taller than a phone viewport on purpose: accessibility-size headers wrap
    /// their Cake Mono titles over several lines and the control below the
    /// header still has to be measured, never cropped by the proof harness.
    private let captureHeight: CGFloat = 844

    /// Every header type whose trailing cluster the pill must clear.
    ///
    /// `.home` is absent for a harness reason, not a design one: its avatar
    /// branch reads `dataController.syncEngine`, which only `setModelContext`
    /// creates, so rendering `AppHeader(.home)` in a unit-test host traps.
    /// Home's identical invariant is proven in `HomeSyncStatusLayoutTests`,
    /// which rebuilds the same header band from the primitives `AppHeader`
    /// composes.
    private let searchHeaders: [(type: AppHeader.HeaderType, name: String)] = [
        (.jobBoard, "jobBoard"),
        (.schedule, "schedule"),
        (.leads, "leads"),
        (.books, "books"),
        (.inventory, "inventory"),
        (.settings, "settings"),
        (.pipeline, "pipeline"),
    ]

    // MARK: - Measurement plumbing

    private final class Measurements {
        var pill: CGRect?
        var trailingControl: CGRect?
        var header: CGRect?
        var contentControl: CGRect?
        var publishedHeaderHeight: CGFloat?
    }

    /// Model already carrying attention, so the real `SyncStatusIndicator`
    /// inside the real `AppHeader` is visible on the first layout pass.
    private static func seededModel(count: Int, isParked: Bool) -> SyncStatusIndicatorModel {
        let model = SyncStatusIndicatorModel()
        model.seedAttentionForLayoutProof(
            RecoveryAttentionSummary(attentionCount: count, anyParked: isParked)
        )
        return model
    }

    // MARK: - Harness

    /// The real header, plus the first control a root parks underneath it. The
    /// retired band placement landed on exactly that control; the superimposed
    /// pill must not be able to reach it.
    private struct Harness: View {
        let headerType: AppHeader.HeaderType
        var width: CGFloat = 390
        var typeSize: DynamicTypeSize = .large
        var sink: Measurements?

        @State private var publishedHeaderHeight: CGFloat = AppHeaderHeightKey.defaultValue

        var body: some View {
            VStack(spacing: 0) {
                configuredHeader
                    .background(
                        GeometryReader { proxy -> Color in
                            sink?.header = proxy.frame(in: .named(pillHarnessSpace))
                            sink?.publishedHeaderHeight = publishedHeaderHeight
                            return Color.clear
                        }
                    )

                contentControl

                Spacer(minLength: 0)
            }
            .onPreferenceChange(AppHeaderHeightKey.self) { publishedHeaderHeight = $0 }
            .frame(width: width, alignment: .top)
            .background(OPSStyle.Colors.background)
            .coordinateSpace(name: pillHarnessSpace)
            .environment(\.colorScheme, .dark)
            .dynamicTypeSize(typeSize)
            .overlayPreferenceValue(HeaderSyncStatusPillBoundsKey.self) { anchor in
                GeometryReader { proxy -> Color in
                    if let sink, let anchor { sink.pill = proxy[anchor] }
                    return Color.clear
                }
                .allowsHitTesting(false)
            }
            .overlayPreferenceValue(OPSHeaderTrailingSlotBoundsKey.self) { anchor in
                GeometryReader { proxy -> Color in
                    if let sink, let anchor { sink.trailingControl = proxy[anchor] }
                    return Color.clear
                }
                .allowsHitTesting(false)
            }
        }

        /// Stands in for the first control every root parks under its header —
        /// Home's TODAY [TASKS] / ACTIVE / ALL chips, Books' segmented control,
        /// Job Board's lane picker. Only its frame matters.
        private var contentControl: some View {
            Button("FILTER") {}
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing1)
                .background(
                    GeometryReader { proxy -> Color in
                        sink?.contentControl = proxy.frame(in: .named(pillHarnessSpace))
                        return Color.clear
                    }
                )
        }

        @ViewBuilder
        private var configuredHeader: some View {
            switch headerType {
            case .schedule:
                AppHeader(
                    headerType: .schedule,
                    onFilterTapped: {},
                    onMonthTapped: {},
                    onScopeToggled: {},
                    isScopeAll: true,
                    hasActiveFilters: true,
                    filterCount: 2
                )
            case .jobBoard:
                AppHeader(
                    headerType: .jobBoard,
                    onPaymentReviewTapped: {},
                    paymentReviewBadgeCount: 3,
                    onTaskReviewTapped: {},
                    taskReviewBadgeCount: 2,
                    onUnscheduledReviewTapped: {},
                    unscheduledReviewBadgeCount: 1
                )
            case .inventory:
                AppHeader(headerType: .inventory, onInsightsTapped: {})
            case .leads:
                AppHeader(headerType: .leads, onAddLead: {})
            case .home, .settings, .pipeline, .books:
                AppHeader(headerType: headerType)
            }
        }
    }

    private func harness(
        _ headerType: AppHeader.HeaderType,
        count: Int,
        width: CGFloat = 390,
        isParked: Bool = false,
        typeSize: DynamicTypeSize = .large,
        sink: Measurements? = nil
    ) -> some View {
        Harness(
            headerType: headerType,
            width: width,
            typeSize: typeSize,
            sink: sink
        )
        .environmentObject(DataController())
        .environmentObject(SubscriptionManager.shared)
        .environmentObject(AppState())
        .environmentObject(Self.seededModel(count: count, isParked: isParked))
    }

    private func measure(
        _ headerType: AppHeader.HeaderType,
        count: Int,
        width: CGFloat = 390,
        isParked: Bool = false,
        typeSize: DynamicTypeSize = .large
    ) throws -> Measurements {
        let sink = Measurements()
        _ = try FixedSizeSnapshot.render(
            harness(
                headerType,
                count: count,
                width: width,
                isParked: isParked,
                typeSize: typeSize,
                sink: sink
            ),
            size: CGSize(width: width, height: captureHeight)
        )
        return sink
    }

    // MARK: - The invariant

    /// The pill covers header TEXT and the header's own trailing CONTROL.
    /// Proven against the real `AppHeader` on every root that carries a
    /// trailing cluster, at the narrowest shipping width and at accessibility
    /// sizes, where the pill wraps its label and grows tall.
    ///
    /// This asserts the exact opposite of what it asserted before 2026-09-08,
    /// deliberately. Overlapping the trailing cluster is now the requirement:
    /// while the pill is up it is the most urgent thing on screen, it owns
    /// that region's taps, and it disappears once the work is addressed. A
    /// change that re-teaches the pill to dodge the cluster fails here.
    ///
    /// The trailing-edge check is the sharper of the two. Pill and cluster are
    /// both flush to the band's own inset, so their right edges coincide; an
    /// inset, an offset or a reserved column shows up here first.
    func testPillIsPaintedOverTheTrailingActionsOnEverySearchHeader() throws {
        let sizes: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility3, .accessibility5]

        for width in [CGFloat(320), CGFloat(390)] {
            for header in searchHeaders {
                for typeSize in sizes {
                    let measured = try measure(
                        header.type,
                        count: 128,
                        width: width,
                        typeSize: typeSize
                    )

                    let label = "\(header.name) @ \(Int(width))pt \(typeSize)"
                    let pill = try XCTUnwrap(measured.pill, "\(label): pill was never measured")
                    let control = try XCTUnwrap(
                        measured.trailingControl,
                        "\(label): the trailing action cluster was never measured"
                    )

                    XCTAssertFalse(pill.isEmpty, "\(label): pill has an empty frame")
                    XCTAssertGreaterThanOrEqual(
                        pill.maxX, control.maxX - 0.5,
                        """
                        \(label): the pill stops short of the trailing cluster's \
                        edge (pill \(pill), control \(control)) — something is \
                        reserving the control's column again, which is the \
                        placement Jackson rejected.
                        """
                    )
                    XCTAssertTrue(
                        pill.intersects(control),
                        """
                        \(label): the pill does NOT overlap the header's trailing \
                        actions (pill \(pill), control \(control)). It is meant to \
                        sit ON them and own their taps until the work is addressed.
                        """
                    )
                }
            }
        }
    }

    /// Sitting on the band's control row, the pill cannot reach the first
    /// control the root parks below the header. That is the collision the
    /// retired band placement shipped, and it is the half of the contract that
    /// covering the trailing cluster must never be allowed to cost.
    func testPillStaysInsideTheHeaderAndClearsTheContentBelowIt() throws {
        for header in searchHeaders {
            for typeSize in [DynamicTypeSize.large, .accessibility5] {
                let measured = try measure(header.type, count: 128, typeSize: typeSize)

                let label = "\(header.name) \(typeSize)"
                let pill = try XCTUnwrap(measured.pill, "\(label): pill was never measured")
                let headerFrame = try XCTUnwrap(
                    measured.header, "\(label): header was never measured"
                )
                let contentControl = try XCTUnwrap(
                    measured.contentControl, "\(label): content control was never measured"
                )

                XCTAssertLessThanOrEqual(
                    pill.maxY, headerFrame.maxY + 0.5,
                    "\(label): the pill hangs below the header instead of inside it"
                )
                XCTAssertFalse(
                    pill.intersects(contentControl),
                    """
                    \(label): the pill covers the first control under the header \
                    (pill \(pill), control \(contentControl)).
                    """
                )
            }
        }
    }

    /// The pill costs the header nothing: an attention item must not move a
    /// single point of layout on any root.
    func testHeaderHeightIsIdenticalWithAndWithoutAnAttentionItem() throws {
        for header in searchHeaders {
            let loud = try measure(header.type, count: 128)
            let quiet = try measure(header.type, count: 0)

            let label = header.name
            let loudHeader = try XCTUnwrap(loud.header, "\(label): header was never measured")
            let quietHeader = try XCTUnwrap(quiet.header, "\(label): quiet header was never measured")
            let loudContent = try XCTUnwrap(loud.contentControl, "\(label): content was never measured")
            let quietContent = try XCTUnwrap(
                quiet.contentControl, "\(label): quiet content was never measured"
            )

            // The overlay is always mounted, so the quiet state publishes an
            // EMPTY frame rather than none at all — the pill draws nothing.
            XCTAssertTrue(
                quiet.pill?.isEmpty ?? true,
                "\(label): the zero-attention state must render no pill, measured \(String(describing: quiet.pill))"
            )
            XCTAssertEqual(
                loudHeader.height, quietHeader.height, accuracy: 0.5,
                "\(label): the header grew for the pill — that is bug 417aac7b"
            )
            XCTAssertEqual(
                loudContent.minY, quietContent.minY, accuracy: 0.5,
                "\(label): content below the header moved when an attention item appeared"
            )
        }
    }

    func testHeaderBandUsesNominalTokenAndGrowsForDynamicType() throws {
        let nominal = try measure(.jobBoard, count: 2, width: 320)
        let accessibility = try measure(
            .jobBoard,
            count: 2,
            width: 320,
            typeSize: .accessibility5
        )
        let nominalHeight = try XCTUnwrap(nominal.header?.height)
        let accessibilityHeight = try XCTUnwrap(accessibility.header?.height)

        XCTAssertEqual(
            nominalHeight,
            OPSStyle.Layout.screenHeaderBandHeight,
            accuracy: 0.5
        )
        XCTAssertGreaterThan(
            accessibilityHeight,
            nominalHeight,
            "AppHeader must grow with Dynamic Type rather than clipping the Cake Mono title"
        )
        XCTAssertEqual(
            try XCTUnwrap(nominal.publishedHeaderHeight), nominalHeight, accuracy: 0.5,
            "The published band height must match the header's real height"
        )
    }

    /// The reported clip was the word "LOOK" vanishing. The pill must render its
    /// label whole — growing rather than truncating — at a wide count and at an
    /// accessibility type size, staying on screen and clear of the controls.
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
            let measured = try measure(
                .jobBoard,
                count: testCase.count,
                typeSize: testCase.typeSize
            )
            let pill = try XCTUnwrap(measured.pill, "\(testCase.name): pill was never measured")

            XCTAssertGreaterThan(pill.width, 0, "\(testCase.name): pill has no width")
            XCTAssertGreaterThan(pill.height, 0, "\(testCase.name): pill has no height")
            XCTAssertGreaterThanOrEqual(
                pill.minX, OPSStyle.Layout.spacing3_5 - 0.5,
                "\(testCase.name): pill runs off the leading edge — the label is being cut"
            )
            XCTAssertLessThanOrEqual(
                pill.maxX, 390.5,
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

    /// The pill over the real trailing actions, on the real `AppHeader`. The
    /// `floatingElevation` shadow reads against the buttons underneath — which
    /// is the point of keeping it (Jackson: "with a dropshadow").
    func testSnapshotPillOverTheTrailingActions() throws {
        try snapshot("sync-pill-header-over-actions-count-2", harness(.jobBoard, count: 2), width: 390)
        try snapshot(
            "sync-pill-header-over-actions-schedule-320",
            harness(.schedule, count: 2, width: 320),
            width: 320
        )
        try snapshot(
            "sync-pill-header-over-actions-leads-plus-and-search",
            harness(.leads, count: 2),
            width: 390
        )
        try snapshot(
            "sync-pill-header-books-quiet-no-pill",
            harness(.books, count: 0),
            width: 390
        )
    }

    func testSnapshotPillAtLargeCountAndType() throws {
        try snapshot("sync-pill-header-count-128", harness(.jobBoard, count: 128), width: 390)
        try snapshot(
            "sync-pill-header-parked-rose",
            harness(.jobBoard, count: 7, isParked: true),
            width: 390
        )
        try snapshot(
            "sync-pill-header-a11y3-count-99",
            harness(.jobBoard, count: 99, typeSize: .accessibility3),
            width: 390
        )
        try snapshot(
            "sync-pill-header-a11y5-count-99-320",
            harness(.jobBoard, count: 99, width: 320, typeSize: .accessibility5),
            width: 320
        )
    }

    // MARK: - Snapshot helper

    private func snapshot<V: View>(_ name: String, _ view: V, width: CGFloat) throws {
        let image = try FixedSizeSnapshot.render(
            view,
            size: CGSize(width: width, height: captureHeight)
        )
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
