//
//  HomeSyncStatusLayoutTests.swift
//  OPSTests
//
//  Regression proof for 417aac7b, which closed wrong three times.
//
//  1. The original defect: the pill sat IN FLOW inside Home's measured
//     AppHeader, so the moment an attention item existed the header grew and
//     TODAY [TASKS] / ACTIVE / ALL — and the map under them — were pushed down.
//  2. The first fix removed the in-flow row and floated the pill in
//     MainTabView's band at `.padding(.top, headerBandHeight)` — starting
//     exactly where the header ends. That put a 44pt pill straight on top of
//     the ALL filter chip. The layout tests passed anyway, because they only
//     asserted that the header reserved no row and that the band hosted the
//     pill. Nothing asserted where the pill LANDED. That blind spot is what
//     this file closes.
//  3. The second fix superimposed the pill on the header but RESERVED the
//     trailing control cluster's column, so it landed as a stagger below-left
//     of the avatar. This file asserted the reservation and passed. Jackson
//     rejected it on sight: "It is being influenced by the avatar. It should
//     appear ONTOP of the avatar" — "with a dropshadow".
//  4. The shipped placement: the pill shares the title band's control row with
//     the avatar and is painted OVER it (`HeaderSyncStatusOverlay`). It
//     reserves no layout, and it is free to cover header TEXT — Jackson: "It
//     should be superimposed over header content. It is intended to be most
//     urgent thing, and then addressed or cancelled" — AND the control.
//
//  Two load-bearing tests, one per half of the contract:
//  `testStatusPillIsPaintedOverTheNotificationsAvatar` pins Jackson's intent so
//  a fourth close cannot quietly reintroduce avoidance, and
//  `testStatusPillNeverReachesTheContentBelowTheHeader` keeps the original
//  defect closed. `testTheRetiredBandPlacementIsWhatThisProofMustReject`
//  renders the retired band composition through the SAME measuring harness and
//  asserts it DOES collide, so the second can never quietly become vacuous.
//
//  Extract: xcrun xcresulttool export attachments --path <dd>/Logs/Test/*.xcresult --output-path <dir>
//

#if DEBUG
import SwiftUI
import XCTest
@testable import OPS

/// Coordinate space every measurement in this file resolves against.
private let harnessSpace = "home-sync-status-harness"

@MainActor
final class HomeSyncStatusLayoutTests: XCTestCase {

    /// Taller than a phone viewport on purpose: accessibility-title wrapping
    /// must be fully measured, never silently cropped by the proof harness.
    private let captureHeight: CGFloat = 844

    /// Where the harness puts the pill. `superimposed` is what ships;
    /// `retiredBand` reproduces the first fix so the proof can show its teeth.
    private enum PillPlacement {
        case superimposed
        case retiredBand
        case none
    }

    private final class Measurements {
        var pill: CGRect?
        var header: CGRect?
        var filters: CGRect?
        var trailingControl: CGRect?
        var exitAction: CGRect?
        var bandOffset: CGFloat?
    }

    // MARK: - Shared pill

    /// The REAL control, not a copy of its visual: `SyncStatusIndicator` renders
    /// the shipped capsule, the shipped glove frame, and the shipped
    /// accessibility expansion. The only concession the unit host needs is a
    /// pre-seeded `SyncStatusIndicatorModel`, injected by `harness(…)`.
    private struct MeasuredPill: View {
        var placement: SyncStatusIndicatorPlacement = .header
        let sink: Measurements?

        var body: some View {
            SyncStatusIndicator(placement: placement)
                .background(
                    GeometryReader { proxy -> Color in
                        sink?.pill = proxy.frame(in: .named(harnessSpace))
                        return Color.clear
                    }
                )
        }
    }

    /// A model already carrying the attention state the case needs, so the very
    /// first layout pass renders the pill (no zero-count frame to settle out of).
    private static func seededModel(count: Int, isParked: Bool) -> SyncStatusIndicatorModel {
        let model = SyncStatusIndicatorModel()
        model.seedAttentionForLayoutProof(
            RecoveryAttentionSummary(attentionCount: count, anyParked: isParked)
        )
        return model
    }

    /// Uses the production project-mode action row with the real recovery pill.
    /// The project card itself is intentionally omitted: this isolates the two
    /// adjacent controls whose hit targets must never overlap.
    private struct ProjectModeHarness: View {
        var width: CGFloat = 390
        var typeSize: DynamicTypeSize = .large
        var sink: Measurements?

        var body: some View {
            ProjectModeSyncStatusActions {
                MeasuredPill(placement: .projectHeader, sink: sink)
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
                    .background(
                        GeometryReader { proxy -> Color in
                            sink?.exitAction = proxy.frame(in: .named(harnessSpace))
                            return Color.clear
                        }
                    )
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(width: width, alignment: .top)
            .background(OPSStyle.Colors.background)
            .coordinateSpace(name: harnessSpace)
            .environment(\.colorScheme, .dark)
            .dynamicTypeSize(typeSize)
        }
    }

    /// Mirrors Home's production boundary without starting its Mapbox and data
    /// stack: `AppHeader.headerContent`'s exact composition (canonical band with
    /// a 44pt trailing avatar control, then the company context strip), the real
    /// map chips below it, and the shipped `HeaderSyncStatusOverlay` on top.
    ///
    /// `AppHeader` itself cannot be rendered for `.home` in a unit host — its
    /// avatar branch dereferences `dataController.syncEngine`, which only
    /// `setModelContext` creates — so the header band is reproduced from the
    /// same primitives it uses. The PLACEMENT, however, is production's own
    /// view, and the pill is production's own control. Every other header type
    /// is proven against the real `AppHeader` in `SyncPillHeaderLayoutTests`.
    private struct Harness: View {
        var width: CGFloat = 390
        var typeSize: DynamicTypeSize = .large
        var placement: PillPlacement = .superimposed
        var sink: Measurements?

        @State private var filterMode: MapFilterMode = .today
        @State private var headerBandHeight: CGFloat = AppHeaderHeightKey.defaultValue

        var body: some View {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    headerContent
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: AppHeaderHeightKey.self,
                                    value: proxy.size.height
                                )
                            }
                        )
                        .background(
                            GeometryReader { proxy -> Color in
                                sink?.header = proxy.frame(in: .named(harnessSpace))
                                sink?.bandOffset = headerBandHeight
                                return Color.clear
                            }
                        )

                    MapFilterChips(filterMode: $filterMode)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.top, OPSStyle.Layout.spacing1)
                        .background(
                            GeometryReader { proxy -> Color in
                                sink?.filters = proxy.frame(in: .named(harnessSpace))
                                return Color.clear
                            }
                        )

                    Spacer(minLength: 0)
                }
                .onPreferenceChange(AppHeaderHeightKey.self) { headerBandHeight = $0 }

                // The retired band, composed exactly as MainTabView used to.
                if placement == .retiredBand {
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        HStack {
                            Spacer(minLength: 0)
                            MeasuredPill(sink: sink)
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)

                        Spacer(minLength: 0)
                    }
                    .padding(.top, headerBandHeight)
                    .zIndex(1)
                }
            }
            .frame(width: width, alignment: .top)
            .background(OPSStyle.Colors.background)
            .coordinateSpace(name: harnessSpace)
            .environment(\.colorScheme, .dark)
            .dynamicTypeSize(typeSize)
        }

        /// `AppHeader.headerContent` for `.home`, primitive for primitive —
        /// including where the pill is hosted: an `.overlay` on the BAND, so
        /// the proof measures the shipped z-order and the shipped geometry.
        private var headerContent: some View {
            VStack(spacing: 0) {
                OPSScreenHeader("GOOD AFTERNOON, JACKSON", trailing: { avatarStandIn })
                    .overlay { superimposedPill }

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("OPS LTD")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent)
                            .frame(
                                width: OPSStyle.Layout.Indicator.dotSM,
                                height: OPSStyle.Layout.Indicator.dotSM
                            )

                        Text("TRIAL ENDS OCT 3")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, OPSStyle.Layout.spacing2)
            }
        }

        /// The shipped pill placement, hosted exactly as `AppHeader` hosts it.
        @ViewBuilder
        private var superimposedPill: some View {
            if placement == .superimposed {
                HeaderSyncStatusOverlay { MeasuredPill(sink: sink) }
            }
        }

        /// Home's notifications avatar is a 44pt control at top-trailing. Its
        /// FRAME is what the assertions read, but the snapshots have to SHOW
        /// the pill landing on it — so it carries production's own white ring
        /// (`avatarButton`'s `Circle().stroke(primaryText, .thick)`). A bare
        /// `#0D0D0D` disc on the `#000000` canvas is invisible in a PNG, and
        /// the pill's drop shadow would have nothing to read against.
        private var avatarStandIn: some View {
            Circle()
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .overlay(
                    Circle().stroke(
                        OPSStyle.Colors.primaryText,
                        lineWidth: OPSStyle.Layout.Border.thick
                    )
                )
                .frame(
                    width: OPSStyle.Layout.touchTargetMin,
                    height: OPSStyle.Layout.touchTargetMin
                )
                .background(
                    GeometryReader { proxy -> Color in
                        sink?.trailingControl = proxy.frame(in: .named(harnessSpace))
                        return Color.clear
                    }
                )
        }
    }

    // MARK: - Rendering

    private func harness(
        count: Int,
        width: CGFloat = 390,
        isParked: Bool = false,
        typeSize: DynamicTypeSize = .large,
        placement: PillPlacement = .superimposed,
        sink: Measurements? = nil
    ) -> some View {
        Harness(
            width: width,
            typeSize: typeSize,
            placement: placement,
            sink: sink
        )
        .environmentObject(DataController())
        .environmentObject(Self.seededModel(count: count, isParked: isParked))
    }

    private func measure(
        count: Int,
        width: CGFloat,
        typeSize: DynamicTypeSize = .large,
        placement: PillPlacement = .superimposed
    ) throws -> Measurements {
        let sink = Measurements()
        _ = try FixedSizeSnapshot.render(
            harness(
                count: count,
                width: width,
                typeSize: typeSize,
                placement: placement,
                sink: sink
            ),
            size: CGSize(width: width, height: captureHeight)
        )
        return sink
    }

    /// Widths, counts and type sizes the placement must hold at. 320pt is the
    /// narrowest shipping phone; the accessibility rows are where the pill
    /// wraps its label and grows tall — the case where a bottom-anchored
    /// placement would have started reaching for the content below.
    private let coverageCases: [(width: CGFloat, count: Int, typeSize: DynamicTypeSize)] = [
        (390, 1, .large),
        (390, 128, .large),
        (320, 1, .large),
        (320, 99, .xxxLarge),
        (320, 99, .accessibility1),
        (320, 128, .accessibility3),
        (320, 128, .accessibility5),
    ]

    // MARK: - The invariant the previous three closes were missing

    /// THE test, half one. The pill must be painted ON the notifications
    /// avatar — Jackson, 2026-09-08: "It is being influenced by the avatar. It
    /// should appear ONTOP of the avatar."
    ///
    /// This is a POSITIVE assertion on purpose. The close before this one
    /// reserved the avatar's column so the pill would never touch it, and the
    /// suite passed. Pinning the intent means a fourth close that reintroduces
    /// avoidance — an inset, an offset, a shrunken pill — fails here rather
    /// than reaching Jackson again.
    ///
    /// Both parts matter. The column assertion is the exact inverse of the
    /// rejected reservation: the pill's horizontal span must reach the avatar's
    /// trailing edge, because both are flush to the same band inset. The frame
    /// intersection is the whole claim: they occupy the same rectangle.
    func testStatusPillIsPaintedOverTheNotificationsAvatar() throws {
        for testCase in coverageCases {
            let label = "Home @ \(Int(testCase.width))pt count \(testCase.count) \(testCase.typeSize)"
            let measured = try measure(
                count: testCase.count,
                width: testCase.width,
                typeSize: testCase.typeSize
            )

            let pill = try XCTUnwrap(measured.pill, "\(label): pill was never measured")
            let avatar = try XCTUnwrap(
                measured.trailingControl, "\(label): the avatar was never measured"
            )

            XCTAssertFalse(pill.isEmpty, "\(label): pill has an empty frame")
            XCTAssertFalse(avatar.isEmpty, "\(label): avatar has an empty frame")

            XCTAssertGreaterThanOrEqual(
                pill.maxX, avatar.maxX - 0.5,
                """
                \(label): the pill stops short of the avatar's trailing edge \
                (pill \(pill), avatar \(avatar)) — something is reserving the \
                control's column again, which is the placement Jackson rejected.
                """
            )
            XCTAssertLessThanOrEqual(
                pill.minX, avatar.minX + 0.5,
                """
                \(label): the pill is narrower than the avatar's column \
                (pill \(pill), avatar \(avatar)) — it must cover the control, \
                not perch on part of it.
                """
            )
            XCTAssertTrue(
                pill.intersects(avatar),
                """
                \(label): the pill does NOT overlap the notifications avatar \
                (pill \(pill), avatar \(avatar)). It is meant to sit ON the \
                avatar and own its taps until the work is addressed.
                """
            )
        }
    }

    /// THE test, half two — and the original defect's permanent guard. The pill
    /// may cover header TEXT and the header's own control; it may NEVER reach
    /// the content below the header.
    ///
    /// The filter row is measured whole — chips plus the trailing spacer —
    /// which is a superset of TODAY [TASKS] / ACTIVE / ALL, so a pass here
    /// clears every chip.
    ///
    /// This fails on the retired band placement; see
    /// `testTheRetiredBandPlacementIsWhatThisProofMustReject`.
    func testStatusPillNeverReachesTheContentBelowTheHeader() throws {
        for testCase in coverageCases {
            let label = "Home @ \(Int(testCase.width))pt count \(testCase.count) \(testCase.typeSize)"
            let measured = try measure(
                count: testCase.count,
                width: testCase.width,
                typeSize: testCase.typeSize
            )

            let pill = try XCTUnwrap(measured.pill, "\(label): pill was never measured")
            let header = try XCTUnwrap(measured.header, "\(label): header was never measured")
            let filters = try XCTUnwrap(measured.filters, "\(label): filters were never measured")

            XCTAssertFalse(pill.isEmpty, "\(label): pill has an empty frame")

            XCTAssertFalse(
                pill.intersects(filters),
                """
                \(label): the pill covers the TODAY [TASKS] / ACTIVE / ALL row \
                (pill \(pill), filters \(filters)) — that is how 417aac7b closed \
                wrong the second time.
                """
            )
            XCTAssertLessThanOrEqual(
                pill.maxY, header.maxY + 0.5,
                """
                \(label): the pill hangs below the header (pill \(pill), \
                header \(header)) — everything the root parks under its header \
                is now in its path.
                """
            )
        }
    }

    /// Keeps the invariant above honest. The same harness, the same measuring,
    /// the same assertions — but fed the retired band composition, which is what
    /// shipped between the first and second close. It MUST collide. If this ever
    /// stops colliding, the harness has stopped being able to see the defect and
    /// the test above proves nothing.
    func testTheRetiredBandPlacementIsWhatThisProofMustReject() throws {
        let measured = try measure(count: 1, width: 390, placement: .retiredBand)

        let pill = try XCTUnwrap(measured.pill, "band pill was never measured")
        let filters = try XCTUnwrap(measured.filters, "filters were never measured")

        XCTAssertTrue(
            pill.intersects(filters),
            """
            The retired band no longer overlaps the filter row \
            (pill \(pill), filters \(filters)). Either the band composition in \
            this harness drifted from what shipped, or the measurement stopped \
            working — in both cases \
            testStatusPillNeverReachesTheContentBelowTheHeader is now vacuous.
            """
        )
    }

    // MARK: - The original defect: zero reserved layout

    /// An attention item must cost Home zero layout. The header measures the
    /// same with and without the pill, the filter strip begins at the same y
    /// either way, and the pill stays inside the header rather than reaching
    /// past its bottom edge into the content below.
    func testHomeHeaderReservesNoRowForTheStatusPill() throws {
        for testCase in coverageCases {
            let label = "Home @ \(Int(testCase.width))pt count \(testCase.count) \(testCase.typeSize)"

            let withPill = try measure(
                count: testCase.count,
                width: testCase.width,
                typeSize: testCase.typeSize
            )
            let withoutPill = try measure(
                count: testCase.count,
                width: testCase.width,
                typeSize: testCase.typeSize,
                placement: .none
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
                "\(label): header reported zero height — image-sync progress would collapse onto it"
            )
            XCTAssertLessThanOrEqual(
                pill.maxY, header.maxY + 0.5,
                "\(label): the pill hangs below the header and reaches the content under it"
            )
            XCTAssertGreaterThanOrEqual(
                pill.minX,
                OPSStyle.Layout.spacing3_5 - 0.5,
                "\(label): pill escapes the header's leading inset"
            )
            XCTAssertLessThanOrEqual(
                pill.maxX,
                testCase.width - OPSStyle.Layout.spacing3_5 + 0.5,
                "\(label): pill escapes the header's trailing inset"
            )
        }
    }

    // MARK: - Placement policy

    func testEveryRootSuperimposesThePillUnlessAnotherSyncVoiceIsSpeaking() {
        XCTAssertTrue(
            HeaderSyncStatusPlacementPolicy.showsHeaderOverlay(
                isSyncRestoredAlertVisible: false,
                isSuppressedByToast: false
            ),
            "Every root superimposes the pill on its own header"
        )
        XCTAssertFalse(
            HeaderSyncStatusPlacementPolicy.showsHeaderOverlay(
                isSyncRestoredAlertVisible: true,
                isSuppressedByToast: false
            ),
            "The restored banner is the single sync voice while it speaks"
        )
        XCTAssertFalse(
            HeaderSyncStatusPlacementPolicy.showsHeaderOverlay(
                isSyncRestoredAlertVisible: false,
                isSuppressedByToast: true
            ),
            "A toast that has claimed the sync topic stands the pill down"
        )
    }

    func testHomeKeepsAnInFlowIndicatorWhenProjectModeRemovesTheHeader() {
        XCTAssertFalse(
            HomeSyncStatusPlacementPolicy.showsProjectModeFallback(
                isInProjectMode: false,
                isSyncStatusPresentationVisible: false
            ),
            "Normal Home superimposes the pill on its header, not an in-flow host"
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

    /// The arithmetic behind both halves of the invariant, pinned separately
    /// from the rendering so a token edit cannot quietly weaken it.
    ///
    /// The pill's bottom edge sits on the bottom edge of the control row that
    /// `OPSHeaderControlSlot` centres in the band — i.e. at
    /// `bandHeight / 2 + controlRowHeight / 2`. Two things follow, for every
    /// band the canonical header can produce:
    ///
    /// * that edge never falls below the band, so the pill can never reach the
    ///   content under the header (the original defect); and
    /// * the row is exactly a touch target tall, so the pill and the control
    ///   always share it.
    func testTheControlRowPlacementCannotReachBelowTheBand() {
        XCTAssertEqual(
            HeaderSyncStatusGeometry.controlRowHeight,
            OPSStyle.Layout.touchTargetMin,
            """
            The pill shares the trailing control's row. If the row stops being \
            the control's own height, "the pill always covers the control" \
            stops being true by construction.
            """
        )
        XCTAssertLessThanOrEqual(
            HeaderSyncStatusGeometry.controlRowHeight,
            OPSStyle.Layout.screenHeaderBandHeight,
            "The control row must fit the canonical band it is centred in"
        )

        // Every band the canonical header can produce: its 52pt floor, then
        // the taller bands Dynamic Type wraps it into.
        let bandHeights: [CGFloat] = [
            OPSStyle.Layout.screenHeaderBandHeight, 52, 70, 82, 123, 159, 195, 400
        ]
        for bandHeight in bandHeights {
            let pillBottom = bandHeight / 2 + HeaderSyncStatusGeometry.controlRowHeight / 2
            XCTAssertLessThanOrEqual(
                pillBottom, bandHeight,
                """
                A \(bandHeight)pt band puts the pill's bottom edge at \
                \(pillBottom)pt — past the band, and therefore into whatever \
                the root parks below its header. That is bug 417aac7b.
                """
            )
        }
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
                    width: testCase.width,
                    typeSize: testCase.typeSize,
                    sink: sink
                )
                .environmentObject(DataController())
                .environmentObject(
                    Self.seededModel(count: testCase.count, isParked: false)
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

    /// The superimposed pill must expand rather than overflow at accessibility
    /// sizes, wrapping inside the insets the header overlay gives it.
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
            "The superimposed pill adapts from the first accessibility size"
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

        for typeSize in [DynamicTypeSize.accessibility3, .accessibility5] {
            let measured = try measure(count: 128, width: 320, typeSize: typeSize)
            let pill = try XCTUnwrap(measured.pill, "\(typeSize): pill was never measured")

            XCTAssertGreaterThanOrEqual(
                pill.minX,
                OPSStyle.Layout.spacing3_5 - 0.5,
                "\(typeSize): expanded pill runs off the leading edge"
            )
            XCTAssertLessThanOrEqual(
                pill.maxX,
                320 - OPSStyle.Layout.spacing3_5 + 0.5,
                "\(typeSize): expanded pill runs off the trailing edge"
            )
            XCTAssertGreaterThan(pill.height, 0, "\(typeSize): expanded pill has no height")
        }
    }

    // MARK: - Visual proof

    /// What Jackson reviews. The first two are the answer to "it should appear
    /// ONTOP of the avatar, with a dropshadow": the pill on the avatar's own
    /// row, extending leftward over the greeting as the count grows, its
    /// `floatingElevation` shadow reading against the avatar's white ring. The
    /// third is the quiet state — the avatar, uncovered, exactly as before.
    func testSnapshots() throws {
        try snapshot(
            "sync-pill-home-over-avatar-count-1",
            harness(count: 1),
            width: 390
        )
        try snapshot(
            "sync-pill-home-over-avatar-count-128",
            harness(count: 128),
            width: 390
        )
        try snapshot(
            "sync-pill-home-over-avatar-320-count-128",
            harness(count: 128, width: 320),
            width: 320
        )
        try snapshot(
            "sync-pill-home-over-avatar-a11y5-count-128",
            harness(count: 128, width: 320, typeSize: .accessibility5),
            width: 320
        )
        try snapshot(
            "sync-pill-home-quiet-no-pill",
            harness(count: 0, placement: .none),
            width: 390
        )
        // The defect this fix retires, rendered for side-by-side comparison:
        // the band pill lands on the ALL chip.
        try snapshot(
            "sync-pill-home-REJECTED-band-covers-filters",
            harness(count: 1, placement: .retiredBand),
            width: 390
        )
        try snapshot(
            "sync-pill-project-header-a11y5-count-128",
            ProjectModeHarness(width: 320, typeSize: .accessibility5)
                .environmentObject(DataController())
                .environmentObject(Self.seededModel(count: 128, isParked: false)),
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
