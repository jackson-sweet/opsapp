//
//  MeasurementNotificationTests.swift
//  OPSTests
//
//  Client-side contract for the 3 LiDAR notification types.
//
//  These tests used to assert the spec §6 body strings verbatim. Those strings
//  are no longer rendered on the client: the 2026-07-15 notification-creation
//  hardening moved rail-row creation behind narrow SECURITY DEFINER RPCs, and
//  the copy was relocated verbatim into
//    ops-software-bible/migrations/20260818023254_ios_notification_surface_rpcs.sql
//    ops-software-bible/migrations/20260818023657_measurement_notification_dedupe_keys.sql
//  where it is verified against the live database instead.
//
//  What is still the client's job, and therefore still tested here:
//    1. `type` strings — the rail matches rows on them.
//    2. The mapping from a derived `CapturedBodySummary` onto the
//       `notify_measurement_captured` argument set, including which half of the
//       payload stays nil. The server rejects (22023) a `p_kind` whose required
//       fields are missing, so a mapping bug is a dropped notification.
//    3. The wire values the server validates against —
//       `p_kind in ('opening','wall_section')` and
//       `p_opening_type in ('window','door')`.
//    4. The dispatcher protocol shape the capture pipeline calls through.
//
//  `LiveDimensionedNotificationDispatcher` calls `NotificationRepository.shared`
//  directly — there is no injectable seam — so it is not unit-testable without
//  network. No network tests are added here; the dispatch contract is covered
//  through the protocol and through `RecordingNotifier` in
//  `OPSTests/Network/DimensionedPhotoSyncManagerTests.swift`.
//
//  Spec: ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §6
//

import XCTest
@testable import OPS

final class MeasurementNotificationTests: XCTestCase {

    // MARK: - rpcArguments — opening

    func testRPCArgumentsForWindowOpening() {
        let args = MeasurementNotificationCopy.rpcArguments(
            for: .opening(widthInches: 36, heightInches: 60, type: .window, sillInches: 28)
        )

        XCTAssertEqual(args.kind, "opening")
        XCTAssertEqual(args.widthInches, 36)
        XCTAssertEqual(args.heightInches, 60)
        XCTAssertEqual(args.openingType, "window")
        XCTAssertEqual(args.sillInches, 28)
        // Wall fields must stay nil — the server ignores them for this kind and
        // sending values would mask a mis-mapped summary.
        XCTAssertNil(args.wallWidthFeet)
        XCTAssertNil(args.wallWidthInches)
        XCTAssertNil(args.wallHeightFeet)
    }

    func testRPCArgumentsForDoorOpeningWithZeroSill() {
        // A door sits on the floor: sill 0. The server requires the sill to be
        // present (`p_sill_inches is null` → 22023), so zero must be sent as
        // zero, never elided into nil.
        let args = MeasurementNotificationCopy.rpcArguments(
            for: .opening(widthInches: 32, heightInches: 80, type: .door, sillInches: 0)
        )

        XCTAssertEqual(args.kind, "opening")
        XCTAssertEqual(args.widthInches, 32)
        XCTAssertEqual(args.heightInches, 80)
        XCTAssertEqual(args.openingType, "door")
        XCTAssertEqual(args.sillInches, 0)
        XCTAssertNil(args.wallWidthFeet)
        XCTAssertNil(args.wallWidthInches)
        XCTAssertNil(args.wallHeightFeet)
    }

    // MARK: - rpcArguments — wall section

    func testRPCArgumentsForWallSectionWithZeroInches() {
        // Whole feet. The server drops the trailing `0″` itself when
        // `p_wall_width_inches = 0`, so the client still sends the zero.
        let args = MeasurementNotificationCopy.rpcArguments(
            for: .wallSection(widthFeet: 14, widthInches: 0, heightFeet: 8)
        )

        XCTAssertEqual(args.kind, "wall_section")
        XCTAssertEqual(args.wallWidthFeet, 14)
        XCTAssertEqual(args.wallWidthInches, 0)
        XCTAssertEqual(args.wallHeightFeet, 8)
        // Opening fields must stay nil for this kind.
        XCTAssertNil(args.widthInches)
        XCTAssertNil(args.heightInches)
        XCTAssertNil(args.openingType)
        XCTAssertNil(args.sillInches)
    }

    func testRPCArgumentsForWallSectionWithNonZeroInches() {
        let args = MeasurementNotificationCopy.rpcArguments(
            for: .wallSection(widthFeet: 14, widthInches: 6, heightFeet: 8)
        )

        XCTAssertEqual(args.kind, "wall_section")
        XCTAssertEqual(args.wallWidthFeet, 14)
        XCTAssertEqual(args.wallWidthInches, 6)
        XCTAssertEqual(args.wallHeightFeet, 8)
        XCTAssertNil(args.widthInches)
        XCTAssertNil(args.heightInches)
        XCTAssertNil(args.openingType)
        XCTAssertNil(args.sillInches)
    }

    // MARK: - Wire values the server validates against

    func testKindConstantsMatchServerContract() {
        // `notify_measurement_captured` raises 22023 for any other p_kind.
        XCTAssertEqual(MeasurementCapturedRPCArguments.openingKind, "opening")
        XCTAssertEqual(MeasurementCapturedRPCArguments.wallSectionKind, "wall_section")
    }

    func testOpeningTypeRawValuesMatchServerContract() {
        // `p_opening_type not in ('window','door')` → 22023.
        XCTAssertEqual(
            MeasurementNotificationCopy.CapturedBodySummary.OpeningType.window.rawValue,
            "window"
        )
        XCTAssertEqual(
            MeasurementNotificationCopy.CapturedBodySummary.OpeningType.door.rawValue,
            "door"
        )
    }

    // MARK: - Type constants — must match `notifications.type` text values verbatim

    func testTypeConstantsMatchSpec() {
        XCTAssertEqual(MeasurementNotificationType.captured, "measurement_captured")
        XCTAssertEqual(MeasurementNotificationType.pendingSync, "measurement_pending_sync")
        XCTAssertEqual(MeasurementNotificationType.syncFailed, "measurement_sync_failed")
    }

    // MARK: - Dispatcher protocol shape

    /// The dispatcher must carry only what the server accepts: a project
    /// anchor, the dimension summary, and the queue depth. Identity and the
    /// project title are derived server-side and are deliberately absent.
    func testDispatcherProtocolCarriesOnlyServerAcceptedArguments() async throws {
        let spy = SpyMeasurementNotifier()
        let dispatcher: any DimensionedNotificationDispatcher = spy

        await dispatcher.dispatchCaptured(
            projectId: "project-123",
            summary: .opening(widthInches: 36, heightInches: 60, type: .window, sillInches: 28)
        )
        await dispatcher.dispatchPendingSync(queueDepth: 3)
        await dispatcher.dispatchSyncFailed(projectId: "project-456")

        let captured = await spy.capturedCalls()
        XCTAssertEqual(captured.count, 1)
        let call = try XCTUnwrap(captured.first)
        XCTAssertEqual(call.projectId, "project-123")
        let expected = MeasurementNotificationCopy.CapturedBodySummary
            .opening(widthInches: 36, heightInches: 60, type: .window, sillInches: 28)
        XCTAssertEqual(call.summary, expected)

        let pending = await spy.pendingDepths()
        XCTAssertEqual(pending, [3])

        let failed = await spy.syncFailedProjectIds()
        XCTAssertEqual(failed, ["project-456"])
    }

    /// Depth zero is the banner's clear signal — it must survive the dispatch
    /// path rather than being filtered out as "nothing to report".
    func testDispatcherForwardsZeroQueueDepth() async {
        let spy = SpyMeasurementNotifier()
        await spy.dispatchPendingSync(queueDepth: 0)

        let pending = await spy.pendingDepths()
        XCTAssertEqual(pending, [0])
    }

    func testNoopDispatcherAcceptsTheReshapedContract() async {
        // Compile-time proof that the shipped no-op conformance matches the
        // protocol; behaviourally it must do nothing and never throw.
        let noop = NoopDimensionedNotificationDispatcher()
        await noop.dispatchCaptured(
            projectId: "project-123",
            summary: .wallSection(widthFeet: 14, widthInches: 6, heightFeet: 8)
        )
        await noop.dispatchPendingSync(queueDepth: 0)
        await noop.dispatchSyncFailed(projectId: "project-123")
    }

    // MARK: - Feature flag slug — must match `feature_flags.slug` verbatim

    func testFeatureFlagSlug() {
        XCTAssertEqual(
            MeasurementFlag.dimensionedCapture,
            "feature.measurement.dimensioned_capture"
        )
    }
}

// MARK: - Spy dispatcher

/// Minimal recorder for the dispatcher protocol. An `actor` so `Sendable` is
/// satisfied without unchecked annotations.
private actor SpyMeasurementNotifier: DimensionedNotificationDispatcher {

    struct CapturedCall: Equatable {
        let projectId: String
        let summary: MeasurementNotificationCopy.CapturedBodySummary
    }

    private var _capturedCalls: [CapturedCall] = []
    private var _pendingDepths: [Int] = []
    private var _syncFailedProjectIds: [String] = []

    func capturedCalls() -> [CapturedCall] { _capturedCalls }
    func pendingDepths() -> [Int] { _pendingDepths }
    func syncFailedProjectIds() -> [String] { _syncFailedProjectIds }

    func dispatchCaptured(
        projectId: String,
        summary: MeasurementNotificationCopy.CapturedBodySummary
    ) async {
        _capturedCalls.append(.init(projectId: projectId, summary: summary))
    }

    func dispatchPendingSync(queueDepth: Int) async {
        _pendingDepths.append(queueDepth)
    }

    func dispatchSyncFailed(projectId: String) async {
        _syncFailedProjectIds.append(projectId)
    }
}
