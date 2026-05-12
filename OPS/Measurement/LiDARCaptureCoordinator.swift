//
//  LiDARCaptureCoordinator.swift
//  OPS
//
//  Orchestrates the ARKit live-aim phase + AVCaptureSession LiDAR shutter handoff
//  for the dimensioned photo capture pipeline. Phase B deliverable; the view layer
//  in Phase D consumes the @Published state and binds the AR preview / shutter.
//
//  Handoff sequence at shutter (spec §3.2):
//    1. Capture ARKit state snapshot — ARFrame.anchors with classifications,
//       camera.intrinsics, device pose. Non-blocking, ~5 ms.
//    2. Pause ARKit: arSession.pause() — releases the camera.
//    3. Activate pre-warmed AVCaptureSession with builtInLiDARDepthCamera +
//       synchronized photo / depth / calibration outputs.
//    4. capturePhoto() with AVCaptureSynchronizedDataCollection delegate.
//    5. Tear down AVCaptureSession; do NOT resume ARKit.
//
//  Total shutter latency budget (steps 2+3+4): <250 ms.
//  AR session warm-up (covered by pre-warm in startLiveAim): ~800 ms.
//

import Foundation
import AVFoundation
import ARKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Combine
import os.log

@MainActor
public final class LiDARCaptureCoordinator: NSObject, ObservableObject {

    // MARK: - Public types

    public enum CaptureState: Equatable {
        case idle
        case warmingUp
        case ready
        case searching
        case wallDetected
        case openingLocked
        case capturing
        case captured(CapturedAssets)
        case failed(CaptureError)
    }

    public enum CaptureError: Error, Equatable {
        case capabilityInsufficient
        case cameraPermissionDenied
        case arSessionFailed(String)
        case avCaptureFailed(String)
        case persistenceFailed(String)
        case noActiveSession
    }

    // MARK: - Published state

    @Published public private(set) var state: CaptureState = .idle
    public let capabilityReport: CaptureCapabilityReport

    public var capability: CaptureCapability { capabilityReport.capability }
    public var supportsAutoDetect: Bool { capabilityReport.supportsAutoDetect }

    // MARK: - AR + AVCapture infrastructure

    /// Live ARKit session. Exposed read-only so the view layer can bind a
    /// `UIViewRepresentable` AR preview to it (the README documents the view
    /// "binds the SwiftUI preview to its AR session" — this property is that
    /// hook). All mutation goes through `startLiveAim()` / `capture()` /
    /// `reset()`; the view must not call `arSession.run/pause` directly.
    public let arSession = ARSession()
    private let avSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private var dataOutputSynchronizer: AVCaptureDataOutputSynchronizer?
    private let synchronizerQueue = DispatchQueue(
        label: "co.opsapp.lidar.synchronizer",
        qos: .userInteractive
    )
    private var pendingCapture: PendingCapture?
    private let assetDirectory: URL
    private let log = Logger(subsystem: "co.opsapp.ops", category: "lidar-capture")

    /// Snapshot of the latest ARFrame, refreshed on every `session(_:didUpdate:)` callback.
    /// Captured at shutter to seed the sidecar JSON.
    private var latestFrameSnapshot: ARKitSnapshot?

    // MARK: - Init

    public init(
        capabilityReport: CaptureCapabilityReport = CaptureCapability.detect(),
        assetDirectory: URL = CapturedAssets.defaultDirectory()
    ) {
        self.capabilityReport = capabilityReport
        self.assetDirectory = assetDirectory
        super.init()
        arSession.delegate = self
    }

    // MARK: - Public API

    /// Begins the live-aim phase. Configures the ARWorldTrackingConfiguration with
    /// scene-depth + mesh classification + plane detection, then starts the session.
    /// Pre-warms the AVCaptureSession in parallel (config-only, no startRunning()).
    public func startLiveAim() {
        guard capability != .noDepth else {
            transition(to: .failed(.capabilityInsufficient))
            return
        }
        guard state == .idle || state == .failed(.capabilityInsufficient) else {
            return // idempotent — already warming or further along
        }

        transition(to: .warmingUp)

        #if !targetEnvironment(simulator)
        configureAndRunARSession()
        prewarmAVSession()
        #endif
    }

    /// Runs the 5-step shutter handoff. Pauses ARKit, activates AVCapture, captures
    /// the synchronized photo + depth + calibration triple, writes the three on-disk
    /// assets, and resolves to `.captured(CapturedAssets)` or `.failed(_)`.
    public func capture() async {
        guard capability != .noDepth else {
            transition(to: .failed(.capabilityInsufficient))
            return
        }
        guard state != .idle, state != .failed(.capabilityInsufficient) else {
            transition(to: .failed(.noActiveSession))
            return
        }

        transition(to: .capturing)

        #if targetEnvironment(simulator)
        transition(to: .failed(.avCaptureFailed("AVCapture unavailable in simulator")))
        #else
        await performHandoffAndCapture()
        #endif
    }

    /// Resets the state machine to `.idle` and tears down any running sessions.
    /// Called by the view on dismiss or after the user acks a captured payload.
    public func reset() {
        arSession.pause()
        if avSession.isRunning {
            avSession.stopRunning()
        }
        pendingCapture = nil
        latestFrameSnapshot = nil
        transition(to: .idle)
    }

    // MARK: - State machine

    private func transition(to newState: CaptureState) {
        state = newState
    }

    /// Internal hook for unit tests to drive state transitions deterministically.
    /// Production code never calls this — real transitions go through `transition(to:)`.
    public func _test_transition(to newState: CaptureState) {
        transition(to: newState)
    }

    // MARK: - ARKit live aim

    private func configureAndRunARSession() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        config.isAutoFocusEnabled = true

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }

        if capabilityReport.supportsAutoDetect,
           ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    private func prewarmAVSession() {
        guard let device = AVCaptureDevice.default(
            .builtInLiDARDepthCamera, for: .video, position: .back
        ) else {
            return // .visual path — no LiDAR camera to pre-warm
        }

        avSession.beginConfiguration()
        avSession.sessionPreset = .photo

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if avSession.canAddInput(input) {
                avSession.addInput(input)
            }

            if avSession.canAddOutput(photoOutput) {
                avSession.addOutput(photoOutput)
                photoOutput.isDepthDataDeliveryEnabled = true
                photoOutput.isHighResolutionCaptureEnabled = true
            }

            if avSession.canAddOutput(depthOutput) {
                avSession.addOutput(depthOutput)
                depthOutput.isFilteringEnabled = true
                if let connection = depthOutput.connection(with: .depthData) {
                    connection.isEnabled = true
                }
            }

            // Force FP32 disparity on the depth output, per spec §3.2.
            if let availableFormat = device.activeFormat.supportedDepthDataFormats
                .first(where: {
                    CMFormatDescriptionGetMediaSubType($0.formatDescription)
                        == kCVPixelFormatType_DepthFloat32
                }) {
                try device.lockForConfiguration()
                device.activeDepthDataFormat = availableFormat
                device.unlockForConfiguration()
            }

            let synchronizer = AVCaptureDataOutputSynchronizer(
                dataOutputs: [photoOutput, depthOutput]
            )
            synchronizer.setDelegate(self, queue: synchronizerQueue)
            self.dataOutputSynchronizer = synchronizer
        } catch {
            log.error("AVSession prewarm failed: \(error.localizedDescription)")
            transition(to: .failed(.avCaptureFailed(error.localizedDescription)))
        }

        avSession.commitConfiguration()
        // NOTE: We do not call startRunning() here — shutter will start the session.
    }

    // MARK: - Shutter handoff

    private func performHandoffAndCapture() async {
        // Step 1: ARKit snapshot (~5 ms — must happen while AR is still running)
        guard let snapshot = latestFrameSnapshot else {
            transition(to: .failed(.arSessionFailed("no ARFrame available at shutter")))
            return
        }

        // Step 2: Pause ARKit
        arSession.pause()

        // Step 3: Activate pre-warmed AVCaptureSession
        if !avSession.isRunning {
            avSession.startRunning()
        }

        guard avSession.isRunning else {
            transition(to: .failed(.avCaptureFailed("AVCaptureSession failed to start")))
            return
        }

        // Step 4: Capture
        let captureID = UUID()
        let settings = AVCapturePhotoSettings()
        settings.isDepthDataDeliveryEnabled = true
        settings.isDepthDataFiltered = true
        settings.embedsDepthDataInPhoto = true
        if photoOutput.isHighResolutionCaptureEnabled {
            settings.isHighResolutionPhotoEnabled = true
        }

        let result: Result<CapturedAssets, CaptureError> = await withCheckedContinuation { cont in
            self.pendingCapture = PendingCapture(
                captureID: captureID,
                snapshot: snapshot,
                continuation: cont
            )
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }

        // Step 5: Tear down
        avSession.stopRunning()
        pendingCapture = nil

        switch result {
        case .success(let assets):
            transition(to: .captured(assets))
        case .failure(let error):
            transition(to: .failed(error))
        }
    }

    // MARK: - Pending-capture continuation box

    fileprivate final class PendingCapture {
        let captureID: UUID
        let snapshot: ARKitSnapshot
        let continuation: CheckedContinuation<Result<CapturedAssets, CaptureError>, Never>
        var photoData: AVCapturePhoto?
        var depthData: AVDepthData?

        init(
            captureID: UUID,
            snapshot: ARKitSnapshot,
            continuation: CheckedContinuation<Result<CapturedAssets, CaptureError>, Never>
        ) {
            self.captureID = captureID
            self.snapshot = snapshot
            self.continuation = continuation
        }
    }

    fileprivate func finalizeCapture(
        captureID: UUID,
        snapshot: ARKitSnapshot,
        photo: AVCapturePhoto,
        depth: AVDepthData?,
        continuation: CheckedContinuation<Result<CapturedAssets, CaptureError>, Never>
    ) {
        do {
            let assets = try CaptureAssetWriter.write(
                directory: assetDirectory,
                captureID: captureID,
                photo: photo,
                depth: depth,
                snapshot: snapshot
            )
            continuation.resume(returning: .success(assets))
        } catch {
            log.error("persistence failed: \(error.localizedDescription)")
            continuation.resume(returning: .failure(.persistenceFailed(error.localizedDescription)))
        }
    }
}

// MARK: - ARSessionDelegate

extension LiDARCaptureCoordinator: ARSessionDelegate {

    nonisolated public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let snapshot = Self.makeSnapshot(from: frame)
        Task { @MainActor in
            self.latestFrameSnapshot = snapshot
            self.advanceAimStateIfNeeded(using: frame)
        }
    }

    nonisolated public func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.transition(to: .failed(.arSessionFailed(error.localizedDescription)))
        }
    }

    @MainActor
    private func advanceAimStateIfNeeded(using frame: ARFrame) {
        // Coarse state machine — Phase D will refine with classification confidence.
        switch state {
        case .warmingUp:
            if frame.camera.trackingState == .normal {
                transition(to: .ready)
            }
        case .ready:
            transition(to: .searching)
        case .searching:
            let hasVerticalPlane = frame.anchors.contains { anchor in
                guard let plane = anchor as? ARPlaneAnchor else { return false }
                return plane.alignment == .vertical
            }
            if hasVerticalPlane {
                transition(to: .wallDetected)
            }
        case .wallDetected:
            // Phase C `OpeningClassifier` will promote to .openingLocked when
            // a rectangular opening is classified with >0.8 confidence. For Phase B
            // we stay in .wallDetected until shutter.
            break
        default:
            break
        }
    }

    private nonisolated static func makeSnapshot(from frame: ARFrame) -> ARKitSnapshot {
        let intrinsicsMatrix = frame.camera.intrinsics
        let imageRes = frame.camera.imageResolution
        let intrinsics = DimensionsData.Intrinsics(
            fx: Double(intrinsicsMatrix.columns.0.x),
            fy: Double(intrinsicsMatrix.columns.1.y),
            cx: Double(intrinsicsMatrix.columns.2.x),
            cy: Double(intrinsicsMatrix.columns.2.y),
            imageWidth: Int(imageRes.width),
            imageHeight: Int(imageRes.height)
        )

        let meshPayloads: [ARKitSnapshot.MeshAnchorPayload] = frame.anchors.compactMap { anchor in
            guard let mesh = anchor as? ARMeshAnchor else { return nil }
            return makePayload(from: mesh)
        }

        return ARKitSnapshot(
            meshAnchors: meshPayloads,
            cameraIntrinsics: intrinsics,
            devicePose: simdMatrixToArray(frame.camera.transform),
            timestamp: Date(timeIntervalSinceReferenceDate: frame.timestamp)
        )
    }

    private nonisolated static func makePayload(from mesh: ARMeshAnchor) -> ARKitSnapshot.MeshAnchorPayload {
        let geometry = mesh.geometry
        let vertexCount = geometry.vertices.count
        let faceCount = geometry.faces.count

        var histogram: [String: Int] = [:]
        let classification = geometry.classification
        if let classification = classification {
            let buffer = classification.buffer
            let pointer = buffer.contents().assumingMemoryBound(to: UInt8.self)
            for i in 0..<classification.count {
                let raw = Int(pointer[i])
                let key = meshClassificationName(raw: raw)
                histogram[key, default: 0] += 1
            }
        }

        return ARKitSnapshot.MeshAnchorPayload(
            identifier: mesh.identifier,
            transform: simdMatrixToArray(mesh.transform),
            vertexCount: vertexCount,
            faceCount: faceCount,
            classifications: histogram
        )
    }

    private nonisolated static func simdMatrixToArray(_ m: simd_float4x4) -> [Float] {
        return [
            m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w,
            m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w,
            m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w,
            m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w
        ]
    }

    private nonisolated static func meshClassificationName(raw: Int) -> String {
        // ARMeshClassification raw values per Apple docs:
        //   0 none, 1 wall, 2 floor, 3 ceiling, 4 table, 5 seat, 6 window, 7 door
        switch raw {
        case 0: return "none"
        case 1: return "wall"
        case 2: return "floor"
        case 3: return "ceiling"
        case 4: return "table"
        case 5: return "seat"
        case 6: return "window"
        case 7: return "door"
        default: return "unknown_\(raw)"
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension LiDARCaptureCoordinator: AVCapturePhotoCaptureDelegate {

    nonisolated public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            guard let pending = self.pendingCapture else { return }
            if let error = error {
                pending.continuation.resume(
                    returning: .failure(.avCaptureFailed(error.localizedDescription))
                )
                return
            }
            pending.photoData = photo
            pending.depthData = photo.depthData

            self.finalizeCapture(
                captureID: pending.captureID,
                snapshot: pending.snapshot,
                photo: photo,
                depth: photo.depthData,
                continuation: pending.continuation
            )
        }
    }
}

// MARK: - AVCaptureDataOutputSynchronizerDelegate
//
// Wired up for parity with the synchronized-output pipeline described in spec §3.2,
// though Phase B funnels capture through AVCapturePhotoCaptureDelegate above —
// photoOutput already delivers AVDepthData on its own delegate when
// isDepthDataDeliveryEnabled = true. The synchronizer remains configured so Phase C
// can subscribe to streaming depth frames during live aim without rewiring.
extension LiDARCaptureCoordinator: AVCaptureDataOutputSynchronizerDelegate {
    nonisolated public func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        // No-op for Phase B. Phase C will tap into this for live-aim depth previews.
    }
}
