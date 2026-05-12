//
//  CaptureCapability.swift
//  OPS
//
//  Device capability detection for the LiDAR dimensioned photo capture pipeline.
//
//  Truth table (spec §3.8):
//    lidar + ar + mesh     → .lidar, autoDetect = true   (full pipeline)
//    lidar + ar + !mesh    → .lidar, autoDetect = false  (no auto-classify)
//    !lidar + ar           → .visual                     (manual SLAM measurement)
//    !ar                   → .noDepth                    (manual scale tool only)
//
//  The capability + auto-detect flag are split intentionally: the published
//  capability drives the chip + the tool list, while supportsAutoDetect gates
//  the AUTO tool independently on the small number of devices that have LiDAR
//  but no mesh-with-classification (older iPad Pros).
//

import Foundation
import AVFoundation
import ARKit

public enum CaptureCapability: Equatable {
    case lidar
    case visual
    case noDepth
}

public struct CaptureCapabilityReport: Equatable {
    public let capability: CaptureCapability
    public let supportsAutoDetect: Bool

    public init(capability: CaptureCapability, supportsAutoDetect: Bool) {
        self.capability = capability
        self.supportsAutoDetect = supportsAutoDetect
    }
}

public extension CaptureCapability {

    /// Live detection — queries the real Apple APIs. Use this in production code.
    static func detect() -> CaptureCapabilityReport {
        let lidar = AVCaptureDevice.default(
            .builtInLiDARDepthCamera, for: .video, position: .back
        ) != nil
        let ar = ARWorldTrackingConfiguration.isSupported
        let mesh = ARWorldTrackingConfiguration
            .supportsSceneReconstruction(.meshWithClassification)
        return detect(lidarSupported: lidar, arSupported: ar, meshSupported: mesh)
    }

    /// Pure detection — injectable for unit tests. Has no side effects and
    /// does not touch Apple frameworks; safe to call on any host.
    static func detect(
        lidarSupported: Bool,
        arSupported: Bool,
        meshSupported: Bool
    ) -> CaptureCapabilityReport {
        guard arSupported else {
            return CaptureCapabilityReport(capability: .noDepth, supportsAutoDetect: false)
        }
        if lidarSupported {
            return CaptureCapabilityReport(
                capability: .lidar,
                supportsAutoDetect: meshSupported
            )
        }
        return CaptureCapabilityReport(capability: .visual, supportsAutoDetect: false)
    }
}
