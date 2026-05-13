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
//    <uuid>.depth.fp32     Standalone FP32 depth grid (LiDAR only), raw bytes
//    <uuid>.metadata.json  Sidecar — ARKit anchors, intrinsics, device pose, capture metadata
//
//  Schema reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.2, §7
//

import Foundation
import simd

public struct CapturedAssets: Equatable {

    /// HEIC photo. LiDAR captures include an embedded Disparity aux channel
    /// (`kCGImageAuxiliaryDataTypeDisparity`); visual captures are standard HEIC.
    /// This is the primary asset — uploaded to `project_photos.url`.
    public let heicURL: URL

    /// Standalone FP32 depth grid for high-precision re-rendering.
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

    public struct MeshFacePayload: Codable, Equatable {
        public let v0: SIMD3<Float>
        public let v1: SIMD3<Float>
        public let v2: SIMD3<Float>
        public let classification: MeshFaceSnapshot.Classification

        public init(
            v0: SIMD3<Float>,
            v1: SIMD3<Float>,
            v2: SIMD3<Float>,
            classification: MeshFaceSnapshot.Classification
        ) {
            self.v0 = v0
            self.v1 = v1
            self.v2 = v2
            self.classification = classification
        }

        var meshFaceSnapshot: MeshFaceSnapshot {
            MeshFaceSnapshot(
                v0: v0,
                v1: v1,
                v2: v2,
                classification: classification
            )
        }

        private enum CodingKeys: String, CodingKey {
            case v0, v1, v2, classification
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.v0 = try Self.decodeVector(forKey: .v0, from: container)
            self.v1 = try Self.decodeVector(forKey: .v1, from: container)
            self.v2 = try Self.decodeVector(forKey: .v2, from: container)
            self.classification = try container.decode(
                MeshFaceSnapshot.Classification.self,
                forKey: .classification
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Self.encodeVector(v0), forKey: .v0)
            try container.encode(Self.encodeVector(v1), forKey: .v1)
            try container.encode(Self.encodeVector(v2), forKey: .v2)
            try container.encode(classification, forKey: .classification)
        }

        private static func decodeVector(
            forKey key: CodingKeys,
            from container: KeyedDecodingContainer<CodingKeys>
        ) throws -> SIMD3<Float> {
            let values = try container.decode([Float].self, forKey: key)
            guard values.count == 3 else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: container,
                    debugDescription: "Mesh face vertex must contain exactly 3 floats"
                )
            }
            return SIMD3<Float>(values[0], values[1], values[2])
        }

        private static func encodeVector(_ vector: SIMD3<Float>) -> [Float] {
            [vector.x, vector.y, vector.z]
        }
    }

    public let meshAnchors: [MeshAnchorPayload]
    public let meshFaces: [MeshFacePayload]
    public let cameraIntrinsics: DimensionsData.Intrinsics

    /// Column-major 4×4 device pose at shutter. Always 16 floats.
    public let devicePose: [Float]

    public let timestamp: Date

    public init(
        meshAnchors: [MeshAnchorPayload],
        meshFaces: [MeshFacePayload] = [],
        cameraIntrinsics: DimensionsData.Intrinsics,
        devicePose: [Float],
        timestamp: Date
    ) {
        self.meshAnchors = meshAnchors
        self.meshFaces = meshFaces
        self.cameraIntrinsics = cameraIntrinsics
        self.devicePose = devicePose
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case meshAnchors
        case meshFaces
        case cameraIntrinsics
        case devicePose
        case timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.meshAnchors = try container.decode([MeshAnchorPayload].self, forKey: .meshAnchors)
        self.meshFaces = try container.decodeIfPresent([MeshFacePayload].self, forKey: .meshFaces) ?? []
        self.cameraIntrinsics = try container.decode(
            DimensionsData.Intrinsics.self,
            forKey: .cameraIntrinsics
        )
        self.devicePose = try container.decode([Float].self, forKey: .devicePose)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(meshAnchors, forKey: .meshAnchors)
        try container.encode(meshFaces, forKey: .meshFaces)
        try container.encode(cameraIntrinsics, forKey: .cameraIntrinsics)
        try container.encode(devicePose, forKey: .devicePose)
        try container.encode(timestamp, forKey: .timestamp)
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

    var cameraToWorldMatrix: simd_float4x4? {
        guard devicePose.count == 16 else { return nil }
        return simd_float4x4(
            SIMD4<Float>(devicePose[0], devicePose[1], devicePose[2], devicePose[3]),
            SIMD4<Float>(devicePose[4], devicePose[5], devicePose[6], devicePose[7]),
            SIMD4<Float>(devicePose[8], devicePose[9], devicePose[10], devicePose[11]),
            SIMD4<Float>(devicePose[12], devicePose[13], devicePose[14], devicePose[15])
        )
    }

    var worldToCameraMatrix: simd_float4x4? {
        guard let cameraToWorld = cameraToWorldMatrix else { return nil }
        let determinant = simd_determinant(cameraToWorld)
        guard determinant.isFinite, abs(determinant) > 1e-6 else { return nil }
        return simd_inverse(cameraToWorld)
    }
}

public extension AnchorSnapshot {
    init?(arkitSnapshot snapshot: ARKitSnapshot) {
        guard let worldToCamera = snapshot.worldToCameraMatrix,
              !snapshot.meshFaces.isEmpty else {
            return nil
        }
        self.init(
            faces: snapshot.meshFaces.map(\.meshFaceSnapshot),
            worldToCamera: worldToCamera
        )
    }
}
