//
//  HomeSyncStatusLayoutTests.swift
//  OPSTests
//
//  Regression proof for cf07df64: the recovery pill must be owned by Home's
//  measured header instead of floating over TODAY / ACTIVE / ALL.
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
    /// stack: one measured title/context/status header, then the real map chips.
    private struct Harness: View {
        let count: Int
        var width: CGFloat = 390
        var isParked = false
        var typeSize: DynamicTypeSize = .large
        var sink: Measurements?

        @State private var filterMode: MapFilterMode = .today

        var body: some View {
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

                    AppHeaderSyncStatusRow {
                        SyncAttentionPill(
                            count: count,
                            isParked: isParked,
                            isElevated: false,
                            adaptsForAccessibility: true
                        )
                            .frame(
                                minWidth: OPSStyle.Layout.touchTargetMin,
                                minHeight: OPSStyle.Layout.touchTargetMin
                            )
                            .anchorPreference(key: PillBoundsKey.self, value: .bounds) { $0 }
                    }
                }
                .anchorPreference(key: HeaderBoundsKey.self, value: .bounds) { $0 }

                MapFilterChips(filterMode: $filterMode)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing1)
                    .anchorPreference(key: FilterBoundsKey.self, value: .bounds) { $0 }

                Spacer(minLength: 0)
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
        sink: Measurements? = nil
    ) -> some View {
        Harness(
            count: count,
            width: width,
            isParked: isParked,
            typeSize: typeSize,
            sink: sink
        )
    }

    private func measure(
        count: Int,
        width: CGFloat,
        typeSize: DynamicTypeSize = .large
    ) throws -> Measurements {
        let sink = Measurements()
        _ = try FixedSizeSnapshot.render(
            harness(count: count, width: width, typeSize: typeSize, sink: sink),
            size: CGSize(width: width, height: captureHeight)
        )
        return sink
    }

    func testStatusRowReservesSpaceBeforeMapFilters() throws {
        let cases: [(width: CGFloat, count: Int, typeSize: DynamicTypeSize)] = [
            (390, 1, .large),
            (320, 99, .accessibility3),
            (320, 128, .accessibility5),
        ]

        for testCase in cases {
            let measured = try measure(
                count: testCase.count,
                width: testCase.width,
                typeSize: testCase.typeSize
            )
            let label = "Home @ \(Int(testCase.width))pt count \(testCase.count)"
            let pill = try XCTUnwrap(measured.pill, "\(label): pill was never measured")
            let header = try XCTUnwrap(measured.header, "\(label): header was never measured")
            let filters = try XCTUnwrap(measured.filters, "\(label): filters were never measured")

            XCTAssertGreaterThanOrEqual(
                pill.minX,
                OPSStyle.Layout.spacing3_5 - 0.5,
                "\(label): pill escapes Home's leading header inset"
            )
            XCTAssertLessThanOrEqual(
                pill.maxX,
                testCase.width - OPSStyle.Layout.spacing3_5 + 0.5,
                "\(label): pill escapes Home's trailing header inset"
            )
            XCTAssertLessThanOrEqual(
                pill.maxY,
                filters.minY,
                "\(label): recovery pill covers TODAY / ACTIVE / ALL"
            )
            XCTAssertLessThanOrEqual(
                header.maxY,
                filters.minY,
                "\(label): map filters started inside the measured header"
            )
            XCTAssertFalse(pill.intersects(filters), "\(label): pill steals filter taps")
            XCTAssertLessThanOrEqual(
                filters.maxY,
                captureHeight,
                "\(label): map filters are cropped out of the proof viewport"
            )
        }
    }

    func testMainTabDoesNotRenderASecondIndicatorOverHome() {
        XCTAssertFalse(
            SyncStatusPlacementPolicy.showsMainTabOverlay(
                selectedTab: 0
            ),
            "Home never accepts the free overlay: both Home modes own an in-flow status host"
        )
        XCTAssertTrue(
            SyncStatusPlacementPolicy.showsMainTabOverlay(
                selectedTab: 1
            ),
            "Non-Home roots must retain the app-level indicator"
        )
    }

    func testHomeKeepsAnInFlowIndicatorWhenProjectModeRemovesTheHeader() {
        XCTAssertFalse(
            HomeSyncStatusPlacementPolicy.showsProjectModeFallback(
                isInProjectMode: false,
                isSyncStatusPresentationVisible: false
            ),
            "Normal Home owns the indicator in its measured header"
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

    func testHomePillExpandsInsteadOfOverflowingAtAccessibilitySizes() {
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
            "The untouched non-Home floating presentation keeps its existing contract"
        )
    }

    func testSnapshots() throws {
        try snapshot(
            "sync-pill-home-header-count-1",
            harness(count: 1),
            width: 390
        )
        try snapshot(
            "sync-pill-home-header-a11y5-count-128",
            harness(count: 128, width: 320, typeSize: .accessibility5),
            width: 320
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
