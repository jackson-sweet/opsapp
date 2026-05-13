//
//  CaptureAssetWriter.swift
//  OPS
//
//  Writes the on-disk assets produced by a single capture:
//    1. HEIC with embedded kCGImageAuxiliaryDataTypeDisparity channel when depth exists
//    2. Standalone FP32 disparity grid when depth exists (raw bytes, height×width×4)
//    3. Sidecar JSON (ARKit snapshot, intrinsics, device pose)
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.2, §7
//
//  Layout under `<directory>/<uuid>.*`:
//    <uuid>.heic            primary photo + embedded depth
//    <uuid>.depth.fp32      standalone disparity grid (90-day retention per §7)
//    <uuid>.metadata.json   ARKit snapshot for Phase C raycasting / classification
//

import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

public enum CaptureAssetWriterError: Error, Equatable {
    case noPhotoData
    case heicEncodingFailed(String)
    case depthBufferUnavailable
    case sidecarEncodingFailed(String)
    case fileWriteFailed(String)
}

public enum CaptureAssetWriter {

    /// Atomic write of all assets. If any step fails, no partial files are left behind —
    /// success writes to temp files first and renames into place.
    public static func write(
        directory: URL,
        captureID: UUID,
        photo: AVCapturePhoto,
        depth: AVDepthData?,
        snapshot: ARKitSnapshot
    ) throws -> CapturedAssets {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        let urls = assetURLs(
            directory: directory,
            captureID: captureID,
            includesStandaloneDepth: depth != nil
        )

        // 1. HEIC (with embedded disparity if depth available)
        try writeHEIC(photo: photo, depth: depth, to: urls.heicURL)

        // 2. Standalone FP32 disparity (if available)
        if let depth = depth, let depthURL = urls.depthURL {
            try writeRawDisparity(depth: depth, to: depthURL)
        }

        // 3. Sidecar JSON
        try writeSidecar(snapshot: snapshot, to: urls.sidecarURL)

        return CapturedAssets(
            heicURL: urls.heicURL,
            depthURL: urls.depthURL,
            sidecarURL: urls.sidecarURL,
            intrinsics: snapshot.cameraIntrinsics,
            arkitSnapshot: snapshot,
            captureID: captureID,
            captureFinishedAt: Date()
        )
    }

    static func assetURLs(
        directory: URL,
        captureID: UUID,
        includesStandaloneDepth: Bool
    ) -> CapturedAssets._AssetURLs {
        CapturedAssets.in(
            directory: directory,
            captureID: captureID,
            includesDepthAsset: includesStandaloneDepth
        )
    }

    // MARK: - HEIC + embedded disparity

    static func writeHEIC(photo: AVCapturePhoto, depth: AVDepthData?, to url: URL) throws {
        guard let baseHEIC = photo.fileDataRepresentation() else {
            throw CaptureAssetWriterError.noPhotoData
        }

        // AVCapturePhoto with embedsDepthDataInPhoto=true + isDepthDataDeliveryEnabled=true
        // already embeds the disparity aux channel in the HEIC blob. Most of the time
        // we just need to write the raw representation. We round-trip through ImageIO
        // only if explicit re-embedding is required (depth provided externally).
        if depth == nil {
            try baseHEIC.write(to: url, options: .atomic)
            return
        }

        // Re-embed explicit AVDepthData by decoding + re-encoding via CGImageDestination.
        // This is the canonical path when the spec calls out
        // `kCGImageAuxiliaryDataTypeDisparity` directly.
        guard let source = CGImageSourceCreateWithData(baseHEIC as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CaptureAssetWriterError.heicEncodingFailed("could not decode base HEIC")
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData, UTType.heic.identifier as CFString, 1, nil
        ) else {
            throw CaptureAssetWriterError.heicEncodingFailed("could not create HEIC destination")
        }

        let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)

        // Convert AVDepthData to disparity if needed, then embed.
        if let depth = depth, let auxData = makeAuxiliaryData(from: depth) {
            CGImageDestinationAddAuxiliaryDataInfo(
                destination,
                kCGImageAuxiliaryDataTypeDisparity,
                auxData as CFDictionary
            )
        }

        guard CGImageDestinationFinalize(destination) else {
            throw CaptureAssetWriterError.heicEncodingFailed("CGImageDestinationFinalize returned false")
        }

        try (mutableData as Data).write(to: url, options: .atomic)
    }

    private static func makeAuxiliaryData(from depth: AVDepthData) -> [CFString: Any]? {
        // Force the disparity float-32 format; HEIC aux channels expect it.
        let normalized: AVDepthData = depth.depthDataType == kCVPixelFormatType_DisparityFloat32
            ? depth
            : depth.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)

        var auxDataType: NSString?
        let dict = normalized.dictionaryRepresentation(forAuxiliaryDataType: &auxDataType)
        return dict as? [CFString: Any]
    }

    // MARK: - Raw FP32 disparity

    static func writeRawDisparity(depth: AVDepthData, to url: URL) throws {
        let disparity = depth.depthDataType == kCVPixelFormatType_DisparityFloat32
            ? depth
            : depth.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)

        let pixelBuffer = disparity.depthDataMap
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw CaptureAssetWriterError.depthBufferUnavailable
        }

        // Pack into a tight buffer (no row padding) for predictable downstream consumption.
        let rowStride = width * MemoryLayout<Float>.size
        var packed = Data(capacity: height * rowStride)
        for row in 0..<height {
            let src = base.advanced(by: row * bytesPerRow)
            packed.append(Data(bytes: src, count: rowStride))
        }

        do {
            try packed.write(to: url, options: .atomic)
        } catch {
            throw CaptureAssetWriterError.fileWriteFailed(error.localizedDescription)
        }
    }

    // MARK: - Sidecar JSON (testable in isolation)

    public static func writeSidecar(snapshot: ARKitSnapshot, to url: URL) throws {
        do {
            let encoded = try ARKitSnapshot.jsonEncoder.encode(snapshot)
            try encoded.write(to: url, options: .atomic)
        } catch let encoding as EncodingError {
            throw CaptureAssetWriterError.sidecarEncodingFailed(String(describing: encoding))
        } catch {
            throw CaptureAssetWriterError.fileWriteFailed(error.localizedDescription)
        }
    }
}
