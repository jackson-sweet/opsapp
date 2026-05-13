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
//       mesh faces, camera.intrinsics, device pose. Runs once at shutter.
//    2. Pause ARKit: arSession.pause() — releases the camera.
//    3. Activate pre-warmed AVCaptureSession with builtInLiDARDepthCamera.
//       photoOutput.isDepthDataDeliveryEnabled = true streams depth inline with
//       the still photo. The attached AVCaptureDepthDataOutput is required at
//       session-config time so the LiDAR pipeline reports
//       isDepthDataDeliverySupported = true on the photoOutput; nothing
//       subscribes to its streaming callbacks.
//    4. capturePhoto() — delivery flows through AVCapturePhotoCaptureDelegate,
//       with depth on AVCapturePhoto.depthData.
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

    struct CaptureSessionConfiguration: Equatable {
        let deviceTypes: [AVCaptureDevice.DeviceType]
        let requiresDepthData: Bool
        let attachesDepthOutput: Bool
    }

    struct PhotoSettingsPolicy: Equatable {
        let photoCodec: AVVideoCodecType?
        let enablesDepthDataDelivery: Bool
        let filtersDepthData: Bool
        let embedsDepthDataInPhoto: Bool
        let enablesHighResolutionPhoto: Bool
    }

    private enum CaptureSessionConfigurationError: LocalizedError {
        case inputUnavailable
        case photoOutputUnavailable
        case depthOutputUnavailable

        var errorDescription: String? {
            switch self {
            case .inputUnavailable:
                return "camera input unavailable"
            case .photoOutputUnavailable:
                return "photo output unavailable"
            case .depthOutputUnavailable:
                return "LiDAR depth output unavailable"
            }
        }
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
    private var pendingCapture: PendingCapture?
    private let assetDirectory: URL
    private let log = Logger(subsystem: "co.opsapp.ops", category: "lidar-capture")

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

    // MARK: - AVCapture profile seams

    static func captureSessionConfiguration(
        for capability: CaptureCapability
    ) -> CaptureSessionConfiguration? {
        switch capability {
        case .lidar:
            return CaptureSessionConfiguration(
                deviceTypes: [.builtInLiDARDepthCamera],
                requiresDepthData: true,
                attachesDepthOutput: true
            )
        case .visual:
            return CaptureSessionConfiguration(
                deviceTypes: [
                    .builtInTripleCamera,
                    .builtInDualWideCamera,
                    .builtInDualCamera,
                    .builtInWideAngleCamera
                ],
                requiresDepthData: false,
                attachesDepthOutput: false
            )
        case .noDepth:
            return nil
        }
    }

    static func photoSettingsPolicy(
        for capability: CaptureCapability,
        depthDeliverySupported: Bool,
        heicSupported: Bool = true,
        highResolutionSupported: Bool
    ) -> PhotoSettingsPolicy {
        let enablesDepth = capability == .lidar && depthDeliverySupported
        return PhotoSettingsPolicy(
            photoCodec: heicSupported ? .hevc : nil,
            enablesDepthDataDelivery: enablesDepth,
            filtersDepthData: enablesDepth,
            embedsDepthDataInPhoto: enablesDepth,
            enablesHighResolutionPhoto: highResolutionSupported
        )
    }

    static func depthDeliveryValidationFailure(
        for configuration: CaptureSessionConfiguration,
        depthDeliverySupported: Bool
    ) -> CaptureError? {
        guard configuration.requiresDepthData, !depthDeliverySupported else {
            return nil
        }
        return .avCaptureFailed("LiDAR depth data unavailable")
    }

    static func processedPhotoDepthValidationFailure(
        capability: CaptureCapability,
        hasDepthData: Bool
    ) -> CaptureError? {
        guard capability == .lidar, !hasDepthData else {
            return nil
        }
        return .avCaptureFailed("LiDAR capture returned no depth data")
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
        guard let configuration = Self.captureSessionConfiguration(for: capability) else {
            return
        }
        guard let device = Self.bestAvailableBackCamera(for: configuration) else {
            transition(to: .failed(.avCaptureFailed("back camera unavailable")))
            return
        }

        avSession.beginConfiguration()
        defer { avSession.commitConfiguration() }
        avSession.sessionPreset = .photo

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if avSession.canAddInput(input) {
                avSession.addInput(input)
            } else {
                throw CaptureSessionConfigurationError.inputUnavailable
            }

            if avSession.canAddOutput(photoOutput) {
                avSession.addOutput(photoOutput)
                photoOutput.isHighResolutionCaptureEnabled = true
            } else {
                throw CaptureSessionConfigurationError.photoOutputUnavailable
            }

            if configuration.attachesDepthOutput {
                if avSession.canAddOutput(depthOutput) {
                    avSession.addOutput(depthOutput)
                    depthOutput.isFilteringEnabled = true
                    if let connection = depthOutput.connection(with: .depthData) {
                        connection.isEnabled = true
                    }
                } else {
                    throw CaptureSessionConfigurationError.depthOutputUnavailable
                }
            }

            // Force FP32 depth on the depth output, per spec §3.2.
            if configuration.requiresDepthData,
               let availableFormat = device.activeFormat.supportedDepthDataFormats
                    .first(where: {
                        CMFormatDescriptionGetMediaSubType($0.formatDescription)
                            == kCVPixelFormatType_DepthFloat32
                    }) {
                try device.lockForConfiguration()
                device.activeDepthDataFormat = availableFormat
                device.unlockForConfiguration()
            }

            if let failure = Self.depthDeliveryValidationFailure(
                for: configuration,
                depthDeliverySupported: photoOutput.isDepthDataDeliverySupported
            ) {
                transition(to: .failed(failure))
                return
            }

            photoOutput.isDepthDataDeliveryEnabled = configuration.requiresDepthData
        } catch {
            log.error("AVSession prewarm failed: \(error.localizedDescription)")
            transition(to: .failed(.avCaptureFailed(error.localizedDescription)))
        }
        // NOTE: We do not call startRunning() here — shutter will start the session.
    }

    private static func bestAvailableBackCamera(
        for configuration: CaptureSessionConfiguration
    ) -> AVCaptureDevice? {
        for deviceType in configuration.deviceTypes {
            if let device = AVCaptureDevice.default(deviceType, for: .video, position: .back) {
                return device
            }
        }
        return nil
    }

    // MARK: - Shutter handoff

    private func performHandoffAndCapture() async {
        // Step 1: Build the full ARKit snapshot once, while ARKit is still running.
        guard let frame = arSession.currentFrame else {
            transition(to: .failed(.arSessionFailed("no ARFrame available at shutter")))
            return
        }
        let snapshot = Self.makeSnapshot(from: frame, purpose: .shutterCapture)

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
        let policy = Self.photoSettingsPolicy(
            for: capability,
            depthDeliverySupported: photoOutput.isDepthDataDeliverySupported,
            heicSupported: photoOutput.availablePhotoCodecTypes.contains(.hevc),
            highResolutionSupported: photoOutput.isHighResolutionCaptureEnabled
        )
        let settings: AVCapturePhotoSettings
        if let codec = policy.photoCodec {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.isDepthDataDeliveryEnabled = policy.enablesDepthDataDelivery
        settings.isDepthDataFiltered = policy.filtersDepthData
        settings.embedsDepthDataInPhoto = policy.embedsDepthDataInPhoto
        if policy.enablesHighResolutionPhoto {
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
        Task { @MainActor in
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

    enum ARKitSnapshotPurpose {
        case liveFrameUpdate
        case shutterCapture

        var extractsFullMeshFaces: Bool {
            self == .shutterCapture
        }
    }

    nonisolated static func makeSnapshotPayload(
        meshAnchors: [ARKitSnapshot.MeshAnchorPayload],
        meshFaces: () -> [ARKitSnapshot.MeshFacePayload],
        cameraIntrinsics: DimensionsData.Intrinsics,
        devicePose: [Float],
        timestamp: Date,
        purpose: ARKitSnapshotPurpose
    ) -> ARKitSnapshot {
        ARKitSnapshot(
            meshAnchors: meshAnchors,
            meshFaces: purpose.extractsFullMeshFaces ? meshFaces() : [],
            cameraIntrinsics: cameraIntrinsics,
            devicePose: devicePose,
            timestamp: timestamp
        )
    }

    nonisolated static func makeSnapshot(
        from frame: ARFrame,
        purpose: ARKitSnapshotPurpose
    ) -> ARKitSnapshot {
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

        let meshes = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        let meshPayloads = meshes.map(makePayload(from:))

        return makeSnapshotPayload(
            meshAnchors: meshPayloads,
            meshFaces: { meshes.flatMap(makeFacePayloads(from:)) },
            cameraIntrinsics: intrinsics,
            devicePose: simdMatrixToArray(frame.camera.transform),
            timestamp: Date(timeIntervalSinceReferenceDate: frame.timestamp),
            purpose: purpose
        )
    }

    private nonisolated static func makePayload(from mesh: ARMeshAnchor) -> ARKitSnapshot.MeshAnchorPayload {
        let geometry = mesh.geometry
        let vertexCount = geometry.vertices.count
        let faceCount = geometry.faces.count

        var histogram: [String: Int] = [:]
        let classification = geometry.classification
        if let classification = classification {
            for i in 0..<classification.count {
                let raw = classificationRawValue(source: classification, index: i) ?? 0
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

    private nonisolated static func makeFacePayloads(
        from mesh: ARMeshAnchor
    ) -> [ARKitSnapshot.MeshFacePayload] {
        let geometry = mesh.geometry
        let faces = geometry.faces
        guard faces.primitiveType == .triangle,
              faces.indexCountPerPrimitive == 3 else {
            return []
        }

        var payloads: [ARKitSnapshot.MeshFacePayload] = []
        payloads.reserveCapacity(faces.count)

        for faceIndex in 0..<faces.count {
            guard let i0 = meshIndex(faceIndex: faceIndex, corner: 0, faces: faces),
                  let i1 = meshIndex(faceIndex: faceIndex, corner: 1, faces: faces),
                  let i2 = meshIndex(faceIndex: faceIndex, corner: 2, faces: faces),
                  let v0 = meshVertex(index: i0, vertices: geometry.vertices),
                  let v1 = meshVertex(index: i1, vertices: geometry.vertices),
                  let v2 = meshVertex(index: i2, vertices: geometry.vertices) else {
                continue
            }

            let classification = geometry.classification
                .flatMap { classificationRawValue(source: $0, index: faceIndex) }
                .map(meshFaceClassification(raw:)) ?? .none

            payloads.append(
                ARKitSnapshot.MeshFacePayload(
                    v0: transformToWorld(v0, transform: mesh.transform),
                    v1: transformToWorld(v1, transform: mesh.transform),
                    v2: transformToWorld(v2, transform: mesh.transform),
                    classification: classification
                )
            )
        }

        return payloads
    }

    private nonisolated static func meshIndex(
        faceIndex: Int,
        corner: Int,
        faces: ARGeometryElement
    ) -> Int? {
        let linearIndex = faceIndex * faces.indexCountPerPrimitive + corner
        let byteOffset = linearIndex * faces.bytesPerIndex
        let address = faces.buffer.contents().advanced(by: byteOffset)
        switch faces.bytesPerIndex {
        case MemoryLayout<UInt16>.size:
            return Int(address.assumingMemoryBound(to: UInt16.self).pointee)
        case MemoryLayout<UInt32>.size:
            return Int(address.assumingMemoryBound(to: UInt32.self).pointee)
        default:
            return nil
        }
    }

    private nonisolated static func meshVertex(
        index: Int,
        vertices: ARGeometrySource
    ) -> SIMD3<Float>? {
        guard index >= 0,
              index < vertices.count,
              vertices.componentsPerVector >= 3 else {
            return nil
        }
        let byteOffset = vertices.offset + index * vertices.stride
        let address = vertices.buffer.contents().advanced(by: byteOffset)
        let pointer = address.assumingMemoryBound(to: Float.self)
        return SIMD3<Float>(pointer[0], pointer[1], pointer[2])
    }

    private nonisolated static func classificationRawValue(
        source: ARGeometrySource,
        index: Int
    ) -> Int? {
        guard index >= 0, index < source.count else { return nil }
        let byteOffset = source.offset + index * source.stride
        let address = source.buffer.contents().advanced(by: byteOffset)
        return Int(address.assumingMemoryBound(to: UInt8.self).pointee)
    }

    private nonisolated static func transformToWorld(
        _ local: SIMD3<Float>,
        transform: simd_float4x4
    ) -> SIMD3<Float> {
        let world = transform * SIMD4<Float>(local.x, local.y, local.z, 1)
        return SIMD3<Float>(world.x, world.y, world.z)
    }

    private nonisolated static func meshFaceClassification(
        raw: Int
    ) -> MeshFaceSnapshot.Classification {
        switch raw {
        case 1: return .wall
        case 2: return .floor
        case 3: return .ceiling
        case 4: return .table
        case 5: return .seat
        case 6: return .window
        case 7: return .door
        default: return .none
        }
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

            if let failure = Self.processedPhotoDepthValidationFailure(
                capability: self.capability,
                hasDepthData: photo.depthData != nil
            ) {
                pending.continuation.resume(returning: .failure(failure))
                return
            }

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
