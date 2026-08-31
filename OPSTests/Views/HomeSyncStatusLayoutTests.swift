//
//  HomeSyncStatusLayoutTests.swift
//  OPSTests
//
//  Regression proof for 417aac7b: the recovery pill must FLOAT over Home,
//  never displace it. Home used to own an in-flow row inside its measured
//  AppHeader (the cf07df64 design), so the moment an attention item existed
//  the header grew and TODAY / ACTIVE / ALL — and the map under them — were
//  pushed down. Normal Home now joins the same app-level band every other root
//  uses: pinned just below the measured header, trailing-aligned, expanding to
//  the full-width variant at accessibility sizes.
//
//  The band deliberately overlays the content beneath it — that is what
//  "floating" means, and it is the behavior every non-Home root already ships.
//  What is asserted here is the regression surface: the header measures the
//  same with and without the pill, the filter strip starts at the same place
//  either way, and the pill lands inside the band rather than inside the
//  header.
//

#if DEBUG
import SwiftUI
import XCTest
@testable import OPS

@MainActor
final class HomeSyncStatusLayoutTests: XCTestCase {

    /// Taller than a phone viewport on purpose: accessibility-title wrapping
    /// must be fully measured, never silently cropped by the proof harness.
    private let captureHeight: CGFloat = 844

    private struct PillBoundsKey: PreferenceKey {
        static let defaultValue: Anchor<CGRect>? = nil
        static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
            value = nextValue() ?? value
        }
    }

    private struct HeaderBoundsKey: PreferenceKey {
        static let defaultValue: Anchor<CGRect>? = nil
        static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
            value = nextValue() ?? value
        }
    }

    private struct FilterBoundsKey: PreferenceKey {
        static let defaultValue: Anchor<CGRect>? = nil
        static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
            value = nextValue() ?? value
        }
    }

    private struct ExitBoundsKey: PreferenceKey {
        static let defaultValue: Anchor<CGRect>? = nil
        static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
            value = nextValue() ?? value
        }
    }

    private final class Measurements {
        var pill: CGRect?
        var header: CGRect?
        var filters: CGRect?
        var exitAction: CGRect?
        var bandOffset: CGFloat?
    }

    /// Uses the production project-mode action row with the real recovery pill.
    /// The project card itself is intentionally omitted: this isolates the two
    /// adjacent controls whose hit targets must never overlap.
    private struct ProjectModeHarness: View {
        let count: Int
        var width: CGFloat = 390
        var typeSize: DynamicTypeSize = .large
        var sink: Measurements?

        var body: some View {
            ProjectModeSyncStatusActions {
                SyncAttentionPill(
                    count: count,
                    isParked: false,
                    isElevated: false,
                    adaptsForAccessibility: true
                )
                .frame(
                    minWidth: OPSStyle.Layout.touchTargetMin,
                    minHeight: OPSStyle.Layout.touchTargetMin
                )
                .anchorPreference(key: PillBoundsKey.self, value: .bounds) { $0 }
            } exitAction: {
                Text("EXIT PROJECT")
                    .font(OPSStyle.Typography.smallButton)
                    .foregroundColor(OPSStyle.Colors.cardBackground)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(OPSStyle.Colors.primaryText)
                    .clipShape(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    )
                    .anchorPreference(key: ExitBoundsKey.self, value: .bounds) { $0 }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(width: width, alignment: .top)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, .dark)
            .dynamicTypeSize(typeSize)
            .overlayPreferenceValue(PillBoundsKey.self) { anchor in
                GeometryReader { proxy -> Color in
                    if let sink, let anchor {
                        sink.pill = proxy[anchor]
                    }
                    return Color.clear
                }
                .allowsHitTesting(false)
            }
            .overlayPreferenceValue(ExitBoundsKey.self) { anchor in
                GeometryReader { proxy -> Color in
                    if let sink, let anchor {
                        sink.exitAction = proxy[anchor]
                    }
                    return Color.clear
                }
                .allowsHitTesting(false)
            }
        }
    }

    /// Mirrors Home's production boundary without starting its Mapbox and data
    /// stack: one measured title/context header publishing `AppHeaderHeightKey`,
    /// the real map chips below it, and the app-level status band floating on
    /// top — offset by that published height exactly as `MainTabView` composes
    /// it. `AppHeader` itself cannot be rendered for `.home` in a unit host (its
    /// avatar branch dereferences `dataController.syncEngine`, which a bare
    /// `DataController()` leaves nil), so the header band is reproduced from the
    /// same primitives it uses.
    private struct Harness: View {
        let count: Int
        var width: CGFloat = 390
        var isParked = false
        var typeSize: DynamicTypeSize = .large
        /// The zero-attention state: no pill is constructed at all, which is
        /// what the header height must be identical to.
        var showsPill = true
        var sink: Measurements?

        @State private var filterMode: MapFilterMode = .today
        @State private var headerBandHeight: CGFloat = AppHeaderHeightKey.defaultValue

        var body: some View {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        OPSScreenHeader("GOOD AFTERNOON, JACKSON", trailing: {
                            Circle()
                                .fill(OPSStyle.Colors.cardBackgroundDark)
                                .frame(
                                    width: OPSStyle.Layout.IconSize.lg,
                                    height: OPSStyle.Layout.IconSize.lg
                                )
                        })

                        HStack {
                            Text("OPS LTD")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.bottom, OPSStyle.Layout.spacing2)
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: AppHeaderHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
                    .anchorPreference(key: HeaderBoundsKey.self, value: .bounds) { $0 }

                    MapFilterChips(filterMode: $filterMode)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.top, OPSStyle.Layout.spacing1)
                        .anchorPreference(key: FilterBoundsKey.self, value: .bounds) { $0 }

                    Spacer(minLength: 0)
                }
                .onPreferenceChange(AppHeaderHeightKey.self) { headerBandHeight = $0 }

                // The app-level band, composed exactly as MainTabView does.
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    if showsPill {
                        HStack {
                            Spacer(minLength: 0)
                            SyncAttentionPill(
                                count: count,
                                isParked: isParked,
                                isElevated: true,
                                adaptsForAccessibility: true
                            )
                            .frame(
                                minWidth: OPSStyle.Layout.touchTargetMin,
                                minHeight: OPSStyle.Layout.touchTargetMin
                            )
                            .anchorPreference(key: PillBoundsKey.self, value: .bounds) { $0 }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, headerBandHeight)
                .zIndex(1)
            }
            .frame(width: width, alignment: .top)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, .dark)
            .dynamicTypeSize(typeSize)
            .overlayPreferenceValue(PillBoundsKey.self) { anchor in
                GeometryReader { proxy -> Color in
                    if let sink, let anchor {
                        sink.pill = proxy[anchor]
                    }
                    return Color.clear
                }
                .allowsHitTesting(false)
            }
            .overlayPreferenceValue(HeaderBoundsKey.self) { anchor in
                GeometryReader { proxy -> Color in
                    if let sink, let anchor {
                        sink.header = proxy[anchor]
                        sink.bandOffset = headerBandHeight
                    }
                    return Color.clear
                }
                .allowsHitTesting(false)
            }
            .overlayPreferenceValue(FilterBoundsKey.self) { anchor in
                GeometryReader { proxy -> Color in
                    if let sink, let anchor {
                        sink.filters = proxy[anchor]
                    }
                    return Color.clear
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func harness(
        count: Int,
        width: CGFloat = 390,
        isParked: Bool = false,
        typeSize: DynamicTypeSize = .large,
        showsPill: Bool = true,
        sink: Measurements? = nil
    ) -> some View {
        Harness(
            count: count,
            width: width,
            isParked: isParked,
            typeSize: typeSize,
            showsPill: showsPill,
            sink: sink
        )
    }

    private func measure(
        count: Int,
        width: CGFloat,
        typeSize: DynamicTypeSize = .large,
        showsPill: Bool = true
    ) throws -> Measurements {
        let sink = Measurements()
        _ = try FixedSizeSnapshot.render(
            harness(
                count: count,
                width: width,
                typeSize: typeSize,
                showsPill: showsPill,
                sink: sink
            ),
            size: CGSize(width: width, height: captureHeight)
        )
        return sink
    }

    /// The bug itself: an attention item must cost Home zero layout. The header
    /// measures the same with and without the pill, the filter strip begins at
    /// the same y either way, and the pill lands in the floating band below the
    /// header instead of inside it.
    func testHomeHeaderReservesNoRowForTheStatusPill() throws {
        let cases: [(width: CGFloat, count: Int, typeSize: DynamicTypeSize)] = [
            (390, 1, .large),
            (320, 99, .accessibility3),
            (320, 128, .accessibility5),
        ]

        for testCase in cases {
            let label = "Home @ \(Int(testCase.width))pt count \(testCase.count)"

            let withPill = try measure(
                count: testCase.count,
                width: testCase.width,
                typeSize: testCase.typeSize
            )
            let withoutPill = try measure(
                count: testCase.count,
                width: testCase.width,
                typeSize: testCase.typeSize,
                showsPill: false
            )

            let header = try XCTUnwrap(withPill.header, "\(label): header was never measured")
            let quietHeader = try XCTUnwrap(
                withoutPill.header, "\(label): quiet header was never measured"
            )
            let filters = try XCTUnwrap(withPill.filters, "\(label): filters were never measured")
            let quietFilters = try XCTUnwrap(
                withoutPill.filters, "\(label): quiet filters were never measured"
            )
            let pill = try XCTUnwrap(withPill.pill, "\(label): pill was never measured")
            let bandOffset = try XCTUnwrap(
                withPill.bandOffset, "\(label): the header never published its band height"
            )

            XCTAssertEqual(
                header.height, quietHeader.height, accuracy: 0.5,
                "\(label): the header grew a row for the pill — that is bug 417aac7b"
            )
            XCTAssertEqual(
                filters.minY, quietFilters.minY, accuracy: 0.5,
                "\(label): TODAY / ACTIVE / ALL moved when an attention item appeared"
            )
            XCTAssertNil(
                withoutPill.pill,
                "\(label): the zero-attention state must construct no pill at all"
            )

            XCTAssertGreaterThan(
                bandOffset, 0,
                "\(label): header reported zero height — the band would collapse onto it"
            )
            XCTAssertGreaterThanOrEqual(
                pill.minY, header.maxY - 0.5,
                "\(label): the pill is inside the measured header instead of the floating band"
            )
            XCTAssertGreaterThanOrEqual(
                pill.minX,
                OPSStyle.Layout.spacing3 - 0.5,
                "\(label): pill escapes the band's leading inset"
            )
            XCTAssertLessThanOrEqual(
                pill.maxX,
                testCase.width - OPSStyle.Layout.spacing3 + 0.5,
                "\(label): pill escapes the band's trailing inset"
            )
        }
    }

    func testMainTabOverlayHostsThePillOnNormalHome() {
        XCTAssertTrue(
            SyncStatusPlacementPolicy.showsMainTabOverlay(
                selectedTab: 0,
                isInProjectMode: false
            ),
            "Normal Home floats the pill in the app-level band like every other root"
        )
        XCTAssertFalse(
            SyncStatusPlacementPolicy.showsMainTabOverlay(
                selectedTab: 0,
                isInProjectMode: true
            ),
            "Home project mode owns the control in its project stack — no second pill"
        )
        XCTAssertTrue(
            SyncStatusPlacementPolicy.showsMainTabOverlay(
                selectedTab: 2,
                isInProjectMode: false
            ),
            "Non-Home roots must retain the app-level indicator"
        )
        XCTAssertTrue(
            SyncStatusPlacementPolicy.showsMainTabOverlay(
                selectedTab: 2,
                isInProjectMode: true
            ),
            "Project mode only suppresses the band on Home — other roots are unaffected"
        )
    }

    func testHomeKeepsAnInFlowIndicatorWhenProjectModeRemovesTheHeader() {
        XCTAssertFalse(
            HomeSyncStatusPlacementPolicy.showsProjectModeFallback(
                isInProjectMode: false,
                isSyncStatusPresentationVisible: false
            ),
            "Normal Home takes the app-level band, not an in-flow host"
        )
        XCTAssertTrue(
            HomeSyncStatusPlacementPolicy.showsProjectModeFallback(
                isInProjectMode: true,
                isSyncStatusPresentationVisible: false
            ),
            "Project mode must retain an in-flow indicator when AppHeader is absent"
        )
        XCTAssertFalse(
            HomeSyncStatusPlacementPolicy.showsProjectModeFallback(
                isInProjectMode: true,
                isSyncStatusPresentationVisible: true
            ),
            "A visible reconnect presentation remains the single sync-status voice"
        )
    }

    func testOutgoingHomeStatusHostReleasesInteractionAndAccessibilityOwnership() {
        XCTAssertTrue(
            HomeSyncStatusHostOwnership.isInteractive(phase: .willAppear),
            "A reversing host must recover ownership before it is fully settled"
        )
        XCTAssertTrue(
            HomeSyncStatusHostOwnership.isInteractive(phase: .identity),
            "The settled host owns interaction and accessibility"
        )
        XCTAssertFalse(
            HomeSyncStatusHostOwnership.isInteractive(phase: .didDisappear),
            "Only a fully departed transition snapshot is inert"
        )
    }

    func testHomeTransitionVisibilityMatchesTheProductionIndicatorStates() {
        XCTAssertTrue(
            SyncStatusIndicatorVisibility.isVisible(
                attentionCount: 1,
                hasPendingSyncs: false,
                isConnected: true,
                isSyncing: false,
                isSyncStatusPresentationVisible: false
            )
        )
        XCTAssertTrue(
            SyncStatusIndicatorVisibility.isVisible(
                attentionCount: 0,
                hasPendingSyncs: true,
                isConnected: false,
                isSyncing: false,
                isSyncStatusPresentationVisible: false
            )
        )
        XCTAssertTrue(
            SyncStatusIndicatorVisibility.isVisible(
                attentionCount: 0,
                hasPendingSyncs: false,
                isConnected: true,
                isSyncing: true,
                isSyncStatusPresentationVisible: false
            )
        )
        XCTAssertFalse(
            SyncStatusIndicatorVisibility.isVisible(
                attentionCount: 1,
                hasPendingSyncs: true,
                isConnected: false,
                isSyncing: true,
                isSyncStatusPresentationVisible: true
            )
        )
    }

    func testProjectModeStatusAndExitActionsNeverOverlap() throws {
        let cases: [(width: CGFloat, count: Int, typeSize: DynamicTypeSize)] = [
            (390, 1, .large),
            (320, 128, .accessibility5),
        ]

        for testCase in cases {
            let sink = Measurements()
            _ = try FixedSizeSnapshot.render(
                ProjectModeHarness(
                    count: testCase.count,
                    width: testCase.width,
                    typeSize: testCase.typeSize,
                    sink: sink
                ),
                size: CGSize(width: testCase.width, height: 220)
            )

            let label = "Project mode @ \(Int(testCase.width))pt count \(testCase.count)"
            let pill = try XCTUnwrap(sink.pill, "\(label): status was never measured")
            let exitAction = try XCTUnwrap(
                sink.exitAction,
                "\(label): EXIT PROJECT was never measured"
            )

            XCTAssertFalse(pill.intersects(exitAction), "\(label): action hit targets overlap")
            XCTAssertGreaterThanOrEqual(pill.minX, 0, "\(label): status escapes screen")
            XCTAssertLessThanOrEqual(
                max(pill.maxX, exitAction.maxX),
                testCase.width,
                "\(label): project actions escape screen"
            )
        }
    }

    /// The floating band is now the pill's only normal-mode home, so the
    /// expanded variant must engage there too — at accessibility sizes the pill
    /// wraps inside the band's insets instead of painting past the screen edge.
    func testHomePillExpandsInsteadOfOverflowingAtAccessibilitySizes() throws {
        XCTAssertEqual(
            SyncAttentionPillLayoutStyle.resolve(
                adaptsForAccessibility: true,
                dynamicTypeSize: .large
            ),
            .compact
        )
        XCTAssertEqual(
            SyncAttentionPillLayoutStyle.resolve(
                adaptsForAccessibility: true,
                dynamicTypeSize: .accessibility3
            ),
            .expanded,
            "The band-hosted pill adapts from the first accessibility size"
        )
        XCTAssertEqual(
            SyncAttentionPillLayoutStyle.resolve(
                adaptsForAccessibility: true,
                dynamicTypeSize: .accessibility5
            ),
            .expanded
        )
        XCTAssertEqual(
            SyncAttentionPillLayoutStyle.resolve(
                adaptsForAccessibility: false,
                dynamicTypeSize: .accessibility5
            ),
            .compact,
            "Opting out still pins the compact capsule — the flag is the only switch"
        )

        // And the band-hosted pill genuinely fits the width it is offered.
        for typeSize in [DynamicTypeSize.accessibility3, .accessibility5] {
            let measured = try measure(count: 128, width: 320, typeSize: typeSize)
            let pill = try XCTUnwrap(measured.pill, "\(typeSize): pill was never measured")

            XCTAssertGreaterThanOrEqual(
                pill.minX,
                OPSStyle.Layout.spacing3 - 0.5,
                "\(typeSize): expanded pill runs off the leading edge"
            )
            XCTAssertLessThanOrEqual(
                pill.maxX,
                320 - OPSStyle.Layout.spacing3 + 0.5,
                "\(typeSize): expanded pill runs off the trailing edge"
            )
            XCTAssertGreaterThan(pill.height, 0, "\(typeSize): expanded pill has no height")
        }
    }

    func testSnapshots() throws {
        try snapshot(
            "sync-pill-home-band-count-1",
            harness(count: 1),
            width: 390
        )
        try snapshot(
            "sync-pill-home-band-a11y5-count-128",
            harness(count: 128, width: 320, typeSize: .accessibility5),
            width: 320
        )
        try snapshot(
            "sync-pill-home-band-quiet-no-pill",
            harness(count: 0, showsPill: false),
            width: 390
        )
        try snapshot(
            "sync-pill-project-header-a11y5-count-128",
            ProjectModeHarness(count: 128, width: 320, typeSize: .accessibility5),
            width: 320
        )
    }

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
