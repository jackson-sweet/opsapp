//
//  SiteVisitDimensionedCaptureStore.swift
//  OPS
//
//  Pre-project persistence for dimensioned photos captured during a site visit.
//

import Foundation
import SwiftData

enum SiteVisitDimensionedCaptureStore {
    enum Error: Swift.Error, Equatable {
        case primaryPhotoMissing
        case primaryPhotoSaveFailed
        case dimensionsEncodingFailed
    }

    struct SavedAssets: Equatable {
        let localPhotoURL: String
        let depthAssetURL: String?
        let sidecarMetadataURL: String
    }

    typealias AssetSaver = (CapturedAssets) throws -> SavedAssets

    @discardableResult
    static func persist(
        captured: CapturedAssets,
        dimensions: DimensionsData,
        siteVisitId: String,
        opportunityId: String?,
        companyId: String,
        createdBy: String?,
        modelContext: ModelContext
    ) throws -> SiteVisitCaptureArtifact {
        try persist(
            captured: captured,
            dimensions: dimensions,
            siteVisitId: siteVisitId,
            opportunityId: opportunityId,
            companyId: companyId,
            createdBy: createdBy,
            modelContext: modelContext,
            assetSaver: savePrimaryPhotoToImageCache
        )
    }

    @discardableResult
    static func persist(
        captured: CapturedAssets,
        dimensions: DimensionsData,
        siteVisitId: String,
        opportunityId: String?,
        companyId: String,
        createdBy: String?,
        modelContext: ModelContext,
        assetSaver: AssetSaver
    ) throws -> SiteVisitCaptureArtifact {
        let savedAssets = try assetSaver(captured)
        var enrichedDimensions = dimensions
        enrichedDimensions.depthAssetUrl = savedAssets.depthAssetURL
        enrichedDimensions.sidecarMetadataUrl = savedAssets.sidecarMetadataURL

        guard let dimensionsData = try? DimensionsData.jsonEncoder.encode(enrichedDimensions),
              let dimensionsJSON = String(data: dimensionsData, encoding: .utf8) else {
            throw Error.dimensionsEncodingFailed
        }

        let artifact = SiteVisitCaptureArtifact(
            siteVisitId: siteVisitId,
            companyId: companyId,
            opportunityId: opportunityId,
            kind: .dimensionedPhoto,
            source: source(for: enrichedDimensions.captureMode),
            title: title(for: enrichedDimensions.captureMode),
            body: summary(for: enrichedDimensions),
            localAssetURL: savedAssets.localPhotoURL,
            dimensionsJSON: dimensionsJSON,
            capturedAt: captured.captureFinishedAt,
            createdBy: createdBy
        )
        modelContext.insert(artifact)
        try modelContext.save()
        return artifact
    }

    private static func savePrimaryPhotoToImageCache(_ captured: CapturedAssets) throws -> SavedAssets {
        guard FileManager.default.fileExists(atPath: captured.heicURL.path) else {
            throw Error.primaryPhotoMissing
        }
        let data = try Data(contentsOf: captured.heicURL)
        let localPhotoURL = "local://project_images/site_visit_dimensioned_\(captured.captureID.uuidString).heic"
        guard ImageFileManager.shared.saveImage(data: data, localID: localPhotoURL) else {
            throw Error.primaryPhotoSaveFailed
        }
        return SavedAssets(
            localPhotoURL: localPhotoURL,
            depthAssetURL: captured.depthURL?.absoluteString,
            sidecarMetadataURL: captured.sidecarURL.absoluteString
        )
    }

    private static func source(for captureMode: DimensionsData.CaptureMode) -> SiteVisitCaptureSource {
        switch captureMode {
        case .lidar:
            return .lidar
        case .visual:
            return .camera
        case .manualScale:
            return .manual
        }
    }

    private static func title(for captureMode: DimensionsData.CaptureMode) -> String {
        switch captureMode {
        case .lidar:
            return "LiDAR measurement"
        case .visual:
            return "Dimensioned measurement"
        case .manualScale:
            return "Scaled measurement"
        }
    }

    private static func summary(for dimensions: DimensionsData) -> String {
        let count = dimensions.measurements.count
        let countLine = "\(count) \(count == 1 ? "MEASUREMENT" : "MEASUREMENTS")"
        let measurementLines = dimensions.measurements.prefix(6).map { measurement in
            let formatted = DimensionFormatter.string(
                for: measurement.valueMeters,
                unit: measurement.primaryDisplayUnit
            )
            return "\(measurement.label.uppercased()) \(formatted)"
        }
        guard !measurementLines.isEmpty else { return countLine }
        return ([countLine] + measurementLines).joined(separator: " :: ")
    }
}
