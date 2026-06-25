// OPS/OPS/DeckBuilder/Engine/DimensionAssociator.swift

import Foundation
import SwiftUI

public struct DimensionAssociator {

    // MARK: - Main Entry Point

    /// Associate recognized dimension texts with the nearest detected edge segments.
    ///
    /// For each text classified as `.dimension(inches:)`, scores every segment within
    /// a proximity threshold (15% of image diagonal). The score is `(1/distance) * orientationBonus`,
    /// where the orientation bonus is 1.5 when the text's estimated angle is within 20 degrees
    /// of the segment's angle, and 1.0 otherwise. Each dimension text is assigned to its
    /// highest-scoring segment.
    ///
    /// - Parameters:
    ///   - texts: All recognized text blocks from OCR.
    ///   - segments: All detected line segments from contour extraction.
    ///   - imageSize: The size of the source image in pixels (used for threshold calculation).
    /// - Returns: An array of `DimensionAssociation` linking each dimension text to its best segment.
    public static func associate(
        texts: [RecognizedText],
        segments: [DetectedLineSegment],
        imageSize: CGSize
    ) -> [DimensionAssociation] {
        guard !segments.isEmpty else { return [] }

        let diagonal = sqrt(
            Double(imageSize.width) * Double(imageSize.width) +
            Double(imageSize.height) * Double(imageSize.height)
        )
        let maxDistance = diagonal * 0.15

        var associations: [DimensionAssociation] = []

        for text in texts {
            // Only process dimension-classified texts
            guard case .dimension(let inches) = text.classification else { continue }

            let textCenter = CGPoint(
                x: text.boundingBox.midX,
                y: text.boundingBox.midY
            )
            let textAngle = estimateTextAngle(boundingBox: text.boundingBox)

            var bestSegmentId: String?
            var bestScore: Double = -1.0

            for segment in segments {
                let (_, distance) = PolygonMath.closestPointOnSegment(
                    point: textCenter,
                    segStart: segment.startPoint,
                    segEnd: segment.endPoint
                )

                // Skip segments beyond the proximity threshold
                guard distance < maxDistance else { continue }

                // Avoid division by zero for text sitting exactly on the segment
                let effectiveDistance = max(distance, 0.001)

                let orientationBonus: Double
                let diff = angleDifference(textAngle, segment.angleDegrees)
                if diff <= 20.0 {
                    orientationBonus = 1.5
                } else {
                    orientationBonus = 1.0
                }

                let score = (1.0 / effectiveDistance) * orientationBonus

                if score > bestScore {
                    bestScore = score
                    bestSegmentId = segment.id
                }
            }

            if let segmentId = bestSegmentId {
                associations.append(DimensionAssociation(
                    textId: text.id,
                    segmentId: segmentId,
                    dimensionInches: inches,
                    score: bestScore
                ))
            }
        }

        return associations
    }

    // MARK: - Public Helper

    /// Find the segment closest to a given point.
    ///
    /// Used by `SketchScanPipeline` to associate stair patterns and other features
    /// with the nearest edge segment.
    ///
    /// - Parameters:
    ///   - point: The query point in image coordinates.
    ///   - segments: All detected line segments.
    /// - Returns: The `id` of the closest segment, or `nil` if `segments` is empty.
    public static func findNearestSegment(
        to point: CGPoint,
        segments: [DetectedLineSegment]
    ) -> String? {
        guard !segments.isEmpty else { return nil }

        var bestId: String?
        var bestDistance = Double.greatestFiniteMagnitude

        for segment in segments {
            let (_, distance) = PolygonMath.closestPointOnSegment(
                point: point,
                segStart: segment.startPoint,
                segEnd: segment.endPoint
            )

            if distance < bestDistance {
                bestDistance = distance
                bestId = segment.id
            }
        }

        return bestId
    }

    // MARK: - Private Helpers

    /// Estimate the dominant angle of a text block from its bounding box aspect ratio.
    ///
    /// - If width > height, the text is horizontal (~0 degrees).
    /// - If height > width, the text is vertical (~90 degrees).
    ///
    /// - Parameter boundingBox: The bounding rectangle of the text region.
    /// - Returns: Estimated angle in degrees (0 for horizontal, 90 for vertical).
    private static func estimateTextAngle(boundingBox: CGRect) -> Double {
        if boundingBox.width > boundingBox.height {
            return 0.0
        } else {
            return 90.0
        }
    }

    /// Compute the minimum angular difference between two angles, accounting for wraparound.
    ///
    /// The result is always in the range [0, 180]. For example, the difference between
    /// 350 degrees and 10 degrees is 20 degrees, not 340 degrees.
    ///
    /// - Parameters:
    ///   - a: First angle in degrees.
    ///   - b: Second angle in degrees.
    /// - Returns: The minimum difference in degrees (0-180 range).
    private static func angleDifference(_ a: Double, _ b: Double) -> Double {
        var diff = abs(a - b).truncatingRemainder(dividingBy: 360.0)
        if diff > 180.0 {
            diff = 360.0 - diff
        }
        return diff
    }
}
