//
//  CapturedAssets.swift
//  OPS
//
//  Descriptor for the on-disk artifacts produced by a single dimensioned
//  capture, plus the ARKit state snapshot taken at the moment of shutter.
//  Used as the @Published .captured(...) payload on the coordinator and as
//  the input to the upload manager in Phase F.
//
//  On-disk layout under `<Documents>/lidar-captures/<uuid>.*`:
//    <uuid>.heic           HEIC photo, with embedded disparity when depth exists
//    <uuid>.depth.fp32     Standalone FP32 disparity grid (LiDAR only), raw bytes
//    <uuid>.metadata.json  Sidecar — ARKit anchors, intrinsics, device pose, capture metadata
//
//  Schema reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.2, §7
//

import Foundation

public struct CapturedAssets: Equatable {

    /// HEIC photo. LiDAR captures include an embedded Disparity aux channel
    /// (`kCGImageAuxiliaryDataTypeDisparity`); visual captures are standard HEIC.
    /// This is the primary asset — uploaded to `project_photos.url`.
    public let heicURL: URL

    /// Standalone FP32 disparity grid for high-precision re-rendering.
    /// Present for LiDAR captures, nil for visual-only captures.
    /// Lifecycled out after 90 days per spec §7.
    public let depthURL: URL?

    /// JSON sidecar with mesh anchors + classification + intrinsics + device pose.
    public let sidecarURL: URL

    /// Camera intrinsics captured at shutter — same values written into the sidecar JSON
    /// and into `DimensionsData.intrinsics` for Phase C re-projection math.
    public let intrinsics: DimensionsData.Intrinsics

    /// In-memory ARKit snapshot. Identical content to what's written to `sidecarURL` on disk;
    /// kept in-process so Phase C `OpeningClassifier` can read anchors without re-parsing JSON.
    public let arkitSnapshot: ARKitSnapshot

    public let captureID: UUID
    public let captureFinishedAt: Date

    public init(
        heicURL: URL,
        depthURL: URL?,
        sidecarURL: URL,
        intrinsics: DimensionsData.Intrinsics,
        arkitSnapshot: ARKitSnapshot,
        captureID: UUID,
        captureFinishedAt: Date
    ) {
        self.heicURL = heicURL
        self.depthURL = depthURL
        self.sidecarURL = sidecarURL
        self.intrinsics = intrinsics
        self.arkitSnapshot = arkitSnapshot
        self.captureID = captureID
        self.captureFinishedAt = captureFinishedAt
    }
}

// MARK: - URL conventions

public extension CapturedAssets {

    /// Default capture directory: `<Documents>/lidar-captures/`.
    /// Created lazily on first write; callers should ensure existence before saving.
    static func defaultDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("lidar-captures", isDirectory: true)
    }

    /// Builds a CapturedAssets descriptor with URLs only — no intrinsics or snapshot.
    /// Useful for tests; the production path uses the full initializer once capture completes.
    static func `in`(
        directory: URL,
        captureID: UUID,
        includesDepthAsset: Bool = true
    ) -> _AssetURLs {
        _AssetURLs(
            heicURL: directory.appendingPathComponent("\(captureID.uuidString).heic"),
            depthURL: includesDepthAsset
                ? directory.appendingPathComponent("\(captureID.uuidString).depth.fp32")
                : nil,
            sidecarURL: directory.appendingPathComponent("\(captureID.uuidString).metadata.json")
        )
    }

    /// Lightweight URL triple — full `CapturedAssets` requires intrinsics + snapshot
    /// which are only available post-shutter.
    struct _AssetURLs: Equatable {
        public let heicURL: URL
        public let depthURL: URL?
        public let sidecarURL: URL
    }
}

// MARK: - ARKitSnapshot

/// JSON-serializable ARKit state captured at the moment of shutter, per spec §3.2 step 1.
/// Read from `ARFrame` while ARKit is still running, then ARKit is paused and AVCapture takes over.
public struct ARKitSnapshot: Codable, Equatable {

    public struct MeshAnchorPayload: Codable, Equatable {
        /// `ARMeshAnchor.identifier`.
        public let identifier: UUID

        /// Column-major 4×4 world transform. Always exactly 16 floats.
        public let transform: [Float]

        public let vertexCount: Int
        public let faceCount: Int

        /// Histogram of vertex classifications: key is `ARMeshClassification` raw name
        /// (e.g. "wall", "floor", "window"), value is the vertex count. Used by
        /// Phase C's `OpeningClassifier` without re-parsing the full mesh.
        public let classifications: [String: Int]

        public init(
            identifier: UUID,
            transform: [Float],
            vertexCount: Int,
            faceCount: Int,
            classifications: [String: Int]
        ) {
            self.identifier = identifier
            self.transform = transform
            self.vertexCount = vertexCount
            self.faceCount = faceCount
            self.classifications = classifications
        }
    }

    public let meshAnchors: [MeshAnchorPayload]
    public let cameraIntrinsics: DimensionsData.Intrinsics

    /// Column-major 4×4 device pose at shutter. Always 16 floats.
    public let devicePose: [Float]

    public let timestamp: Date

    public init(
        meshAnchors: [MeshAnchorPayload],
        cameraIntrinsics: DimensionsData.Intrinsics,
        devicePose: [Float],
        timestamp: Date
    ) {
        self.meshAnchors = meshAnchors
        self.cameraIntrinsics = cameraIntrinsics
        self.devicePose = devicePose
        self.timestamp = timestamp
    }
}

public extension ARKitSnapshot {
    static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
