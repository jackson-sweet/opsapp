//
//  LiDARCaptureCoordinatorTests.swift
//  OPSTests
//
//  Tests the host-runnable surface of LiDARCaptureCoordinator: capability
//  injection, state machine transitions, error surfacing. The AR/AVCapture
//  delegate paths are NOT covered here — they require a real LiDAR device
//  and live in a hardware-gated integration test (see `requiresLiDAR`).
//

import XCTest
@testable import OPS

@MainActor
final class LiDARCaptureCoordinatorTests: XCTestCase {

    // MARK: - Initial state

    func test_coordinator_starts_in_idle_state() {
        let coordinator = LiDARCaptureCoordinator(
            capabilityReport: CaptureCapabilityReport(capability: .lidar, supportsAutoDetect: true)
        )
        XCTAssertEqual(coordinator.state, .idle)
    }

    func test_coordinator_exposes_injected_capability() {
        let report = CaptureCapabilityReport(capability: .visual, supportsAutoDetect: false)
        let coordinator = LiDARCaptureCoordinator(capabilityReport: report)
        XCTAssertEqual(coordinator.capability, .visual)
        XCTAssertFalse(coordinator.supportsAutoDetect)
    }

    // MARK: - startLiveAim

    func test_startLiveAim_on_lidar_capability_transitions_to_warmingUp() {
        let coordinator = LiDARCaptureCoordinator(
            capabilityReport: CaptureCapabilityReport(capability: .lidar, supportsAutoDetect: true)
        )
        coordinator.startLiveAim()
        XCTAssertEqual(coordinator.state, .warmingUp)
    }

    func test_startLiveAim_on_visual_capability_transitions_to_warmingUp() {
        // .visual devices still warm up an ARSession (no LiDAR, but SLAM works).
        let coordinator = LiDARCaptureCoordinator(
            capabilityReport: CaptureCapabilityReport(capability: .visual, supportsAutoDetect: false)
        )
        coordinator.startLiveAim()
        XCTAssertEqual(coordinator.state, .warmingUp)
    }

    func test_startLiveAim_on_noDepth_fails_immediately() {
        let coordinator = LiDARCaptureCoordinator(
            capabilityReport: CaptureCapabilityReport(capability: .noDepth, supportsAutoDetect: false)
        )
        coordinator.startLiveAim()

        guard case .failed(let error) = coordinator.state else {
            return XCTFail("expected .failed, got \(coordinator.state)")
        }
        XCTAssertEqual(error, .capabilityInsufficient)
    }

    func test_startLiveAim_is_idempotent_while_warming() {
        let coordinator = LiDARCaptureCoordinator(
            capabilityReport: CaptureCapabilityReport(capability: .lidar, supportsAutoDetect: true)
        )
        coordinator.startLiveAim()
        coordinator.startLiveAim()
        XCTAssertEqual(coordinator.state, .warmingUp)
    }

    // MARK: - Internal state transitions

    func test_state_advances_through_aim_pipeline() {
        let coordinator = LiDARCaptureCoordinator(
            capabilityReport: CaptureCapabilityReport(capability: .lidar, supportsAutoDetect: true)
        )
        coordinator.startLiveAim()
        XCTAssertEqual(coordinator.state, .warmingUp)

        coordinator._test_transition(to: .ready)
        XCTAssertEqual(coordinator.state, .ready)

        coordinator._test_transition(to: .searching)
        XCTAssertEqual(coordinator.state, .searching)

        coordinator._test_transition(to: .wallDetected)
        XCTAssertEqual(coordinator.state, .wallDetected)

        coordinator._test_transition(to: .openingLocked)
        XCTAssertEqual(coordinator.state, .openingLocked)
    }

    // MARK: - Capture failure surfacing

    func test_capture_without_active_session_fails() async {
        let coordinator = LiDARCaptureCoordinator(
            capabilityReport: CaptureCapabilityReport(capability: .lidar, supportsAutoDetect: true)
        )
        // Did NOT call startLiveAim — must fail with .noActiveSession.
        await coordinator.capture()

        guard case .failed(let error) = coordinator.state else {
            return XCTFail("expected .failed, got \(coordinator.state)")
        }
        XCTAssertEqual(error, .noActiveSession)
    }

    func test_capture_on_noDepth_fails_with_capabilityInsufficient() async {
        let coordinator = LiDARCaptureCoordinator(
            capabilityReport: CaptureCapabilityReport(capability: .noDepth, supportsAutoDetect: false)
        )
        await coordinator.capture()

        guard case .failed(let error) = coordinator.state else {
            return XCTFail("expected .failed, got \(coordinator.state)")
        }
        XCTAssertEqual(error, .capabilityInsufficient)
    }

    // MARK: - .captured payload

    func test_captured_state_carries_assets_payload() {
        let coordinator = LiDARCaptureCoordinator(
            capabilityReport: CaptureCapabilityReport(capability: .lidar, supportsAutoDetect: true)
        )
        let captureID = UUID()
        let directory = URL(fileURLWithPath: "/tmp/fixture")
        let urls = CapturedAssets.in(directory: directory, captureID: captureID)
        let assets = CapturedAssets(
            heicURL: urls.heicURL,
            depthURL: urls.depthURL,
            sidecarURL: urls.sidecarURL,
            intrinsics: DimensionsData.Intrinsics(
                fx: 1, fy: 1, cx: 0, cy: 0, imageWidth: 1, imageHeight: 1
            ),
            arkitSnapshot: ARKitSnapshot(
                meshAnchors: [],
                cameraIntrinsics: DimensionsData.Intrinsics(
                    fx: 1, fy: 1, cx: 0, cy: 0, imageWidth: 1, imageHeight: 1
                ),
                devicePose: Array(repeating: 0, count: 16),
                timestamp: Date(timeIntervalSince1970: 0)
            ),
            captureID: captureID,
            captureFinishedAt: Date(timeIntervalSince1970: 1)
        )

        coordinator._test_transition(to: .captured(assets))

        guard case .captured(let payload) = coordinator.state else {
            return XCTFail("expected .captured, got \(coordinator.state)")
        }
        XCTAssertEqual(payload, assets)
    }

    // MARK: - Reset

    func test_reset_returns_to_idle_from_captured_state() {
        let coordinator = LiDARCaptureCoordinator(
            capabilityReport: CaptureCapabilityReport(capability: .lidar, supportsAutoDetect: true)
        )
        let captureID = UUID()
        let urls = CapturedAssets.in(directory: URL(fileURLWithPath: "/tmp"), captureID: captureID)
        coordinator._test_transition(to: .captured(CapturedAssets(
            heicURL: urls.heicURL, depthURL: urls.depthURL, sidecarURL: urls.sidecarURL,
            intrinsics: DimensionsData.Intrinsics(fx: 1, fy: 1, cx: 0, cy: 0, imageWidth: 1, imageHeight: 1),
            arkitSnapshot: ARKitSnapshot(
                meshAnchors: [],
                cameraIntrinsics: DimensionsData.Intrinsics(fx: 1, fy: 1, cx: 0, cy: 0, imageWidth: 1, imageHeight: 1),
                devicePose: Array(repeating: 0, count: 16),
                timestamp: Date()
            ),
            captureID: captureID,
            captureFinishedAt: Date()
        )))

        coordinator.reset()

        XCTAssertEqual(coordinator.state, .idle)
    }
}
