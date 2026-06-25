// OPS/OPS/DeckBuilder/Models/SketchScanResult.swift

import Foundation
import SwiftUI

// MARK: - Stage 1: Grid Detection

/// Output of the grid-detection stage. Contains the cleaned (grid-removed) image
/// and optional grid spacing for scale inference later.
public struct GridDetectionResult {
    public let hasGrid: Bool
    public let gridSpacingPixels: Double?
    public let cleanedImage: CGImage
    public let originalImage: CGImage
    public let imageSize: CGSize
}

// MARK: - Stage 2: Contour Extraction — Primitives

/// A single line segment extracted from the sketch contour.
/// Angle and length are auto-computed from the endpoints.
public struct DetectedLineSegment: Identifiable {
    public let id: String
    public let startPoint: CGPoint
    public let endPoint: CGPoint
    public let angleDegrees: Double
    public let lengthPixels: Double

    public init(id: String = UUID().uuidString, startPoint: CGPoint, endPoint: CGPoint) {
        self.id = id
        self.startPoint = startPoint
        self.endPoint = endPoint

        let dx = Double(endPoint.x - startPoint.x)
        let dy = Double(endPoint.y - startPoint.y)

        // atan2(-dy, dx) because CoreGraphics Y increases downward;
        // normalize to 0-360 range.
        let rawAngle = atan2(-dy, dx) * 180.0 / .pi
        self.angleDegrees = rawAngle < 0 ? rawAngle + 360.0 : rawAngle

        self.lengthPixels = sqrt(dx * dx + dy * dy)
    }
}

/// A vertex where two or more detected segments meet.
public struct DetectedVertex: Identifiable {
    public let id: String
    public let position: CGPoint
    public var connectedSegmentIds: [String]

    public init(id: String = UUID().uuidString, position: CGPoint, connectedSegmentIds: [String] = []) {
        self.id = id
        self.position = position
        self.connectedSegmentIds = connectedSegmentIds
    }
}

/// A rectangular region that looks like stairs (parallel internal lines).
public struct StairPattern: Identifiable {
    public let id: String
    public let boundingRect: CGRect
    public let internalLineCount: Int
    public let nearestSegmentId: String?

    public init(
        id: String = UUID().uuidString,
        boundingRect: CGRect,
        internalLineCount: Int,
        nearestSegmentId: String? = nil
    ) {
        self.id = id
        self.boundingRect = boundingRect
        self.internalLineCount = internalLineCount
        self.nearestSegmentId = nearestSegmentId
    }
}

/// Complete output of the contour extraction stage.
public struct ContourExtractionResult {
    public let vertices: [DetectedVertex]
    public let segments: [DetectedLineSegment]
    public let isClosed: Bool
    public let stairPatterns: [StairPattern]
}

// MARK: - Stage 3: Text Recognition

/// Classification of a recognized text string.
public enum TextClassification {
    case dimension(inches: Double)
    case stairCount(count: Int)
    case clientName(name: String)
    case label(text: String)
    case unknown
}

/// A text region recognized from the sketch via Vision OCR.
public struct RecognizedText: Identifiable {
    public let id: String
    public let text: String
    public let boundingBox: CGRect
    public let confidence: Float
    public let classification: TextClassification

    public init(
        id: String = UUID().uuidString,
        text: String,
        boundingBox: CGRect,
        confidence: Float,
        classification: TextClassification = .unknown
    ) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.classification = classification
    }
}

// MARK: - Stage 4: Dimension Association

/// Links a recognized dimension text to the nearest segment.
public struct DimensionAssociation {
    public let textId: String
    public let segmentId: String
    public let dimensionInches: Double
    /// Association confidence (0-1). Higher = text centroid is closer to the segment midpoint.
    public let score: Double
}

// MARK: - Stage 5: Scale Inference

/// How the pixel-to-inch scale was determined.
public enum ScaleSource {
    case graphPaper(squaresPerUnit: Double, unitName: String)
    case annotatedDimension(edgeId: String)
    case averaged
}

/// A disagreement between the annotated dimension and the scale-derived dimension
/// for a single segment.
public struct ScaleConflict {
    public let segmentId: String
    public let annotatedInches: Double
    public let scaleDerivedInches: Double
    public let percentDifference: Double
}

/// Output of the scale-inference stage.
public struct ScaleResult {
    /// Pixels per real-world inch.
    public let scaleFactor: Double
    public let source: ScaleSource
    public let conflicts: [ScaleConflict]
}

// MARK: - Stage 6: Conflict Resolution

/// User-chosen strategy when annotated dimensions disagree with the derived scale.
public enum ConflictResolution {
    case useAnnotations
    case useScale
    case enterManually
}

// MARK: - Stage 7: Final Scan Result

/// Aggregated output of the entire scan pipeline.
/// Call `toDeckDrawingData(…)` to convert into editable canvas geometry.
public struct SketchScanResult {
    public let sourceImage: CGImage
    public let gridResult: GridDetectionResult
    public let contourResult: ContourExtractionResult
    public let recognizedTexts: [RecognizedText]
    public let dimensionAssociations: [DimensionAssociation]
    public let scaleResult: ScaleResult?
    public let clientNameCandidate: String?
    public let stairDetections: [(segmentId: String, treadCount: Int)]
    public var conflictResolution: ConflictResolution = .useAnnotations

    // MARK: - Conversion to DeckDrawingData

    /// Convert the scan result into editable `DeckDrawingData` for the canvas.
    ///
    /// - Parameters:
    ///   - resolution: The `ConflictResolution` strategy to apply (overrides `self.conflictResolution`).
    ///   - canvasWidth: Available canvas width in points.
    ///   - canvasHeight: Available canvas height in points.
    ///   - padding: Inset from each edge when fitting the sketch to the canvas.
    /// - Returns: A fully populated `DeckDrawingData` ready for editing.
    public func toDeckDrawingData(
        resolution: ConflictResolution? = nil,
        canvasWidth: Double,
        canvasHeight: Double,
        padding: Double = 40.0
    ) -> DeckDrawingData {
        let activeResolution = resolution ?? conflictResolution
        let detectedVertices = contourResult.vertices
        let detectedSegments = contourResult.segments

        guard !detectedVertices.isEmpty else {
            return DeckDrawingData()
        }

        // --- Build dimension lookup: segmentId -> inches ---
        let annotationLookup = buildAnnotationLookup()
        let hasScale = scaleResult != nil

        // --- Compute bounding rect of detected vertices (pixel space) ---
        let pixelBounds = boundingRect(for: detectedVertices)

        // --- Determine real-world dimensions ---
        let (widthInches, heightInches, pixelsPerInch) = computeRealWorldSize(
            pixelBounds: pixelBounds,
            hasScale: hasScale,
            activeResolution: activeResolution,
            annotationLookup: annotationLookup
        )

        // --- Canvas scale factor: points per real-world inch ---
        let drawableWidth = canvasWidth - 2.0 * padding
        let drawableHeight = canvasHeight - 2.0 * padding

        let canvasScale: Double
        if widthInches > 0 && heightInches > 0 {
            canvasScale = min(drawableWidth / widthInches, drawableHeight / heightInches)
        } else {
            // Proportional fit fallback — no real-world scale available
            let pixelW = pixelBounds.width > 0 ? Double(pixelBounds.width) : 1.0
            let pixelH = pixelBounds.height > 0 ? Double(pixelBounds.height) : 1.0
            canvasScale = min(drawableWidth / pixelW, drawableHeight / pixelH)
        }

        // --- Map detected vertices to DeckVertex in canvas coordinates ---
        var vertexIdMap: [String: String] = [:]   // DetectedVertex.id -> DeckVertex.id
        var deckVertices: [DeckVertex] = []

        for dv in detectedVertices {
            let deckId = UUID().uuidString
            vertexIdMap[dv.id] = deckId

            let canvasPoint: CGPoint
            if pixelsPerInch > 0 {
                // Convert pixels -> inches -> canvas points
                let inchX = (Double(dv.position.x) - Double(pixelBounds.origin.x)) / pixelsPerInch
                let inchY = (Double(dv.position.y) - Double(pixelBounds.origin.y)) / pixelsPerInch
                canvasPoint = CGPoint(
                    x: padding + inchX * canvasScale,
                    y: padding + inchY * canvasScale
                )
            } else {
                // Proportional fit (no scale)
                let normX = Double(dv.position.x - pixelBounds.origin.x) / max(Double(pixelBounds.width), 1.0)
                let normY = Double(dv.position.y - pixelBounds.origin.y) / max(Double(pixelBounds.height), 1.0)
                canvasPoint = CGPoint(
                    x: padding + normX * drawableWidth,
                    y: padding + normY * drawableHeight
                )
            }

            deckVertices.append(DeckVertex(id: deckId, position: canvasPoint))
        }

        // --- Map detected segments to DeckEdge ---
        var deckEdges: [DeckEdge] = []
        let stairPatternsBySegment = buildStairLookup()

        for seg in detectedSegments {
            // Find matching vertex IDs via proximity
            guard let startVertexId = findClosestVertexId(point: seg.startPoint, detectedVertices: detectedVertices, vertexIdMap: vertexIdMap),
                  let endVertexId = findClosestVertexId(point: seg.endPoint, detectedVertices: detectedVertices, vertexIdMap: vertexIdMap)
            else { continue }

            var edge = DeckEdge(startVertexId: startVertexId, endVertexId: endVertexId)

            // Assign dimension
            if let annotatedInches = annotationLookup[seg.id] {
                switch activeResolution {
                case .useAnnotations:
                    edge.dimension = annotatedInches
                    edge.dimensionSource = .manual
                case .useScale:
                    if let ppi = scaleResult?.scaleFactor, ppi > 0 {
                        edge.dimension = seg.lengthPixels / ppi
                        edge.dimensionSource = .scale
                    } else {
                        edge.dimension = annotatedInches
                        edge.dimensionSource = .manual
                    }
                case .enterManually:
                    // Leave dimension nil — user will enter manually
                    break
                }
            } else if let ppi = scaleResult?.scaleFactor, ppi > 0 {
                edge.dimension = seg.lengthPixels / ppi
                edge.dimensionSource = .scale
            }

            // Attach stair config if a stair pattern was detected on this segment
            if let stairPattern = stairPatternsBySegment[seg.id] {
                let width = edge.dimension ?? (seg.lengthPixels / (scaleResult?.scaleFactor ?? 1.0))
                edge.stairConfig = StairConfig(
                    width: width,
                    treadCount: stairPattern.internalLineCount
                )
            }

            deckEdges.append(edge)
        }

        // --- Assemble DeckDrawingData ---
        var drawingData = DeckDrawingData()
        drawingData.vertices = deckVertices
        drawingData.edges = deckEdges
        drawingData.footprint = DeckFootprint(isClosed: contourResult.isClosed)
        drawingData.scaleFactor = canvasScale

        return drawingData
    }

    // MARK: - Private Helpers

    /// Build a lookup from segment ID to annotated dimension in inches.
    private func buildAnnotationLookup() -> [String: Double] {
        var lookup: [String: Double] = [:]
        for assoc in dimensionAssociations {
            lookup[assoc.segmentId] = assoc.dimensionInches
        }
        return lookup
    }

    /// Build a lookup from segment ID to the nearest stair pattern.
    /// Combines visual stair patterns from contour detection with OCR-detected stair counts.
    private func buildStairLookup() -> [String: StairPattern] {
        var lookup: [String: StairPattern] = [:]
        // Visual stair patterns from contour detection
        for pattern in contourResult.stairPatterns {
            if let segId = pattern.nearestSegmentId {
                lookup[segId] = pattern
            }
        }
        // OCR-detected stair counts (override visual if both exist)
        for detection in stairDetections {
            if lookup[detection.segmentId] != nil {
                // OCR count is more reliable — update the internal line count
                lookup[detection.segmentId] = StairPattern(
                    boundingRect: lookup[detection.segmentId]!.boundingRect,
                    internalLineCount: detection.treadCount
                )
            } else {
                // OCR-only detection with no visual pattern
                lookup[detection.segmentId] = StairPattern(
                    boundingRect: .zero,
                    internalLineCount: detection.treadCount
                )
            }
        }
        return lookup
    }

    /// Compute the real-world size of the sketch in inches and the pixels-per-inch value.
    /// Returns (widthInches, heightInches, pixelsPerInch). If no scale is available,
    /// widthInches and heightInches are pixel dimensions and pixelsPerInch is 0.
    private func computeRealWorldSize(
        pixelBounds: CGRect,
        hasScale: Bool,
        activeResolution: ConflictResolution,
        annotationLookup: [String: Double]
    ) -> (Double, Double, Double) {
        if hasScale, let ppi = scaleResult?.scaleFactor, ppi > 0 {
            let widthInches = Double(pixelBounds.width) / ppi
            let heightInches = Double(pixelBounds.height) / ppi
            return (widthInches, heightInches, ppi)
        }
        // No scale — return pixel dimensions; pixelsPerInch = 0 signals proportional mode
        return (Double(pixelBounds.width), Double(pixelBounds.height), 0.0)
    }

    /// Bounding rect of all detected vertex positions.
    private func boundingRect(for vertices: [DetectedVertex]) -> CGRect {
        guard let first = vertices.first else { return .zero }
        var minX = Double(first.position.x)
        var minY = Double(first.position.y)
        var maxX = minX
        var maxY = minY

        for v in vertices.dropFirst() {
            let x = Double(v.position.x)
            let y = Double(v.position.y)
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Find the DeckVertex ID whose DetectedVertex is closest to a given point.
    private func findClosestVertexId(
        point: CGPoint,
        detectedVertices: [DetectedVertex],
        vertexIdMap: [String: String]
    ) -> String? {
        let threshold: Double = 20.0
        var bestId: String?
        var bestDist = Double.greatestFiniteMagnitude

        for dv in detectedVertices {
            let dist = closeTo(point, dv.position, threshold: threshold)
            if let d = dist, d < bestDist {
                bestDist = d
                bestId = vertexIdMap[dv.id]
            }
        }

        // If nothing within threshold, fall back to absolute closest
        if bestId == nil {
            for dv in detectedVertices {
                let d = SnapEngine.distance(point, dv.position)
                if d < bestDist {
                    bestDist = d
                    bestId = vertexIdMap[dv.id]
                }
            }
        }

        return bestId
    }

    /// Returns the distance between two points if it is within the threshold, otherwise nil.
    private func closeTo(_ a: CGPoint, _ b: CGPoint, threshold: Double) -> Double? {
        let d = SnapEngine.distance(a, b)
        return d <= threshold ? d : nil
    }
}
