// OPS/OPS/DeckBuilder/Engine/SketchScanPipeline.swift

import Foundation
import Vision
import UIKit

@MainActor
class SketchScanPipeline: ObservableObject {

    enum ScanStage: String {
        case idle = "Ready"
        case capturing = "Capturing..."
        case detectingGrid = "Detecting grid..."
        case extractingContours = "Finding edges..."
        case recognizingText = "Reading text..."
        case associatingDimensions = "Matching dimensions..."
        case inferringScale = "Calculating scale..."
        case validating = "Validating..."
        case complete = "Done"
        case failed = "Failed"
    }

    @Published var stage: ScanStage = .idle
    @Published var progress: Double = 0.0  // 0.0 to 1.0
    @Published var result: SketchScanResult?
    @Published var error: String?

    /// Run the full 7-stage pipeline on a captured image
    func process(image: UIImage) async {
        guard let cgImage = image.cgImage else {
            error = "Invalid image"
            stage = .failed
            return
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        // Stage 1: Capture is already done (image passed in)
        stage = .detectingGrid
        progress = 0.15

        // Stage 2: Background Separation (Grid Detection)
        let gridResult = GridDetector.detect(image: cgImage)
        stage = .extractingContours
        progress = 0.30

        // Stage 3: Edge Detection
        let contourResult = await ContourExtractor.extract(
            image: gridResult.cleanedImage,
            imageSize: imageSize,
            angleSnapIncrement: 15.0
        )

        guard contourResult.vertices.count >= 3 else {
            error = "Could not detect deck outline. Try a clearer sketch or use AI Assist."
            stage = .failed
            return
        }

        stage = .recognizingText
        progress = 0.50

        // Stage 4: OCR
        let ocrResults = await SketchOCR.recognize(image: cgImage)

        stage = .associatingDimensions
        progress = 0.65

        // Stage 5: Association
        let dimensionTexts = ocrResults.filter {
            if case .dimension = $0.classification { return true }
            return false
        }
        let associations = DimensionAssociator.associate(
            texts: dimensionTexts,
            segments: contourResult.segments,
            imageSize: imageSize
        )

        stage = .inferringScale
        progress = 0.80

        // Stage 6: Scale Inference
        let scaleResult: ScaleResult?
        if gridResult.hasGrid, let gridSpacing = gridResult.gridSpacingPixels {
            scaleResult = ScaleInference.inferFromGrid(
                gridSpacingPixels: gridSpacing,
                associations: associations,
                segments: contourResult.segments
            )
        } else if !associations.isEmpty {
            scaleResult = ScaleInference.inferFromAnnotations(
                associations: associations,
                segments: contourResult.segments
            )
        } else {
            scaleResult = nil // No scale info — user enters manually
        }

        stage = .validating
        progress = 0.90

        // Extract client name
        let clientName = ocrResults.first {
            if case .clientName = $0.classification { return true }
            return false
        }.flatMap {
            if case .clientName(let name) = $0.classification { return name }
            return nil
        }

        // Extract stair detections
        var stairDetections: [(segmentId: String, treadCount: Int)] = []

        // From OCR "N treads" text
        for text in ocrResults {
            if case .stairCount(let count) = text.classification {
                // Find nearest segment to this text
                let nearest = DimensionAssociator.findNearestSegment(
                    to: CGPoint(x: text.boundingBox.midX, y: text.boundingBox.midY),
                    segments: contourResult.segments
                )
                if let segId = nearest {
                    stairDetections.append((segmentId: segId, treadCount: count))
                }
            }
        }

        // From visual stair patterns
        for pattern in contourResult.stairPatterns {
            if let segId = pattern.nearestSegmentId,
               !stairDetections.contains(where: { $0.segmentId == segId }) {
                stairDetections.append((segmentId: segId, treadCount: pattern.internalLineCount))
            }
        }

        // Build complete result
        result = SketchScanResult(
            sourceImage: cgImage,
            gridResult: gridResult,
            contourResult: contourResult,
            recognizedTexts: ocrResults,
            dimensionAssociations: associations,
            scaleResult: scaleResult,
            clientNameCandidate: clientName,
            stairDetections: stairDetections
        )

        stage = .complete
        progress = 1.0
    }
}
