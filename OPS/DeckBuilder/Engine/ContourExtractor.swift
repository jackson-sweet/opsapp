// OPS/OPS/DeckBuilder/Engine/ContourExtractor.swift

import Foundation
import Vision
import UIKit

struct ContourExtractor {

    // MARK: - Main Entry Point

    /// Extract deck outline from a cleaned binary image (grid removed).
    /// Returns vertices, segments, closure status, and detected stair patterns.
    static func extract(
        image: CGImage,
        imageSize: CGSize,
        angleSnapIncrement: Double = 15.0
    ) async -> ContourExtractionResult {
        // Step 1: Detect raw contour points from the image
        let rawPoints = await detectContours(image: image, imageSize: imageSize)

        guard rawPoints.count >= 3 else {
            return ContourExtractionResult(
                vertices: [],
                segments: [],
                isClosed: false,
                stairPatterns: []
            )
        }

        // Step 2: Simplify contour into line segments
        let rawSegments = simplifyContour(rawPoints, imageSize: imageSize)

        guard !rawSegments.isEmpty else {
            return ContourExtractionResult(
                vertices: [],
                segments: [],
                isClosed: false,
                stairPatterns: []
            )
        }

        // Step 3: Snap segment angles to nearest increment
        let snappedSegments = snapSegmentAngles(rawSegments, increment: angleSnapIncrement, imageSize: imageSize)

        // Step 4: Build vertices by merging nearby endpoints
        let mergeRadius = max(imageSize.width, imageSize.height) * 0.02 // 2% of largest dimension
        let (vertices, finalSegments) = buildVerticesAndSegments(from: snappedSegments, mergeRadius: mergeRadius)

        // Step 5: Check if polygon is closed
        let closed = checkClosed(vertices: vertices, segments: finalSegments)

        // Step 6: Detect stair patterns
        let stairPatterns = await detectStairPatterns(image: image, imageSize: imageSize, segments: finalSegments)

        return ContourExtractionResult(
            vertices: vertices,
            segments: finalSegments,
            isClosed: closed,
            stairPatterns: stairPatterns
        )
    }

    // MARK: - Step 1: Contour Detection

    /// Detect the largest contour in the image using Apple Vision.
    /// Returns points converted to image coordinates (origin top-left).
    private static func detectContours(image: CGImage, imageSize: CGSize) async -> [CGPoint] {
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 1.5
        request.detectsDarkOnLight = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let result = request.results?.first as? VNContoursObservation else {
            return []
        }

        // Find the largest contour by perimeter across all top-level and child contours
        var bestContour: VNContour?
        var bestPerimeter: Double = 0.0

        let totalCount = result.contourCount
        for i in 0..<totalCount {
            guard let contour = try? result.contour(at: i) else { continue }

            // Check this contour
            let perim = estimatePerimeter(contour.normalizedPoints)
            if perim > bestPerimeter {
                bestPerimeter = perim
                bestContour = contour
            }

            // Check child contours
            let childCount = contour.childContourCount
            for j in 0..<childCount {
                guard let child = try? contour.childContour(at: j) else { continue }
                let childPerim = estimatePerimeter(child.normalizedPoints)
                if childPerim > bestPerimeter {
                    bestPerimeter = childPerim
                    bestContour = child
                }
            }
        }

        guard let largest = bestContour else { return [] }

        // Simplify with polygon approximation
        guard let simplified = try? largest.polygonApproximation(epsilon: 0.01) else {
            return convertVisionPoints(largest.normalizedPoints, imageSize: imageSize)
        }

        return convertVisionPoints(simplified.normalizedPoints, imageSize: imageSize)
    }

    /// Estimate perimeter from normalized Vision points.
    private static func estimatePerimeter(_ points: [SIMD2<Float>]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            let dx = Double(points[j].x - points[i].x)
            let dy = Double(points[j].y - points[i].y)
            total += sqrt(dx * dx + dy * dy)
        }
        return total
    }

    /// Convert Vision normalized coordinates (bottom-left origin, 0-1) to image coordinates (top-left origin, pixels).
    private static func convertVisionPoints(_ points: [SIMD2<Float>], imageSize: CGSize) -> [CGPoint] {
        points.map { point in
            CGPoint(
                x: CGFloat(point.x) * imageSize.width,
                y: (1.0 - CGFloat(point.y)) * imageSize.height // Flip Y: Vision bottom-left → image top-left
            )
        }
    }

    // MARK: - Step 2: Contour Simplification

    /// Create line segments from contour points, filter short segments, and merge near-collinear ones.
    private static func simplifyContour(_ points: [CGPoint], imageSize: CGSize) -> [DetectedLineSegment] {
        guard points.count >= 2 else { return [] }

        let diagonal = sqrt(imageSize.width * imageSize.width + imageSize.height * imageSize.height)
        let minLength = Double(diagonal) * 0.03 // 3% of image diagonal

        // Create segments between consecutive points (wrapping last→first)
        var rawSegments: [DetectedLineSegment] = []
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            let seg = DetectedLineSegment(startPoint: points[i], endPoint: points[j])
            rawSegments.append(seg)
        }

        // Filter segments shorter than minimum length
        var filtered = rawSegments.filter { $0.lengthPixels >= minLength }

        guard !filtered.isEmpty else { return [] }

        // Merge near-collinear consecutive segments (angle difference < 5°)
        var merged: [DetectedLineSegment] = [filtered[0]]
        for i in 1..<filtered.count {
            let prev = merged[merged.count - 1]
            let curr = filtered[i]

            let angleDiff = abs(prev.angleDegrees - curr.angleDegrees)
            // Handle wraparound (e.g., 359° vs 1°)
            let normalizedDiff = min(angleDiff, 360.0 - angleDiff)

            if normalizedDiff < 5.0 {
                // Merge: extend previous segment's start to current segment's end
                let mergedSeg = DetectedLineSegment(
                    id: prev.id,
                    startPoint: prev.startPoint,
                    endPoint: curr.endPoint
                )
                merged[merged.count - 1] = mergedSeg
            } else {
                merged.append(curr)
            }
        }

        // Check if the first and last segments should also merge (wraparound)
        if merged.count >= 2 {
            let last = merged[merged.count - 1]
            let first = merged[0]
            let angleDiff = abs(last.angleDegrees - first.angleDegrees)
            let normalizedDiff = min(angleDiff, 360.0 - angleDiff)

            if normalizedDiff < 5.0 {
                let mergedSeg = DetectedLineSegment(
                    id: last.id,
                    startPoint: last.startPoint,
                    endPoint: first.endPoint
                )
                merged[merged.count - 1] = mergedSeg
                merged.removeFirst()
            }
        }

        return merged
    }

    // MARK: - Step 3: Angle Snapping

    /// Snap each segment's angle to the nearest increment, keeping the start point fixed
    /// and recomputing the end point at the snapped angle with the same length.
    static func snapSegmentAngles(
        _ segments: [DetectedLineSegment],
        increment: Double,
        imageSize: CGSize
    ) -> [DetectedLineSegment] {
        segments.map { seg in
            let snappedAngle = SnapEngine.snapAngle(seg.angleDegrees, increment: increment)
            let radians = snappedAngle * .pi / 180.0

            // Recompute end point at snapped angle, same length, start fixed.
            // Y-flip: in image coordinates, Y increases downward,
            // so "up" (positive angle) means subtracting from Y.
            let endX = seg.startPoint.x + CGFloat(seg.lengthPixels * cos(radians))
            let endY = seg.startPoint.y - CGFloat(seg.lengthPixels * sin(radians))

            return DetectedLineSegment(
                id: seg.id,
                startPoint: seg.startPoint,
                endPoint: CGPoint(x: endX, y: endY)
            )
        }
    }

    // MARK: - Step 4: Vertex Building

    /// Collect all segment endpoints, cluster nearby points within mergeRadius,
    /// create one vertex per cluster at the average position, and update segments to reference vertices.
    static func buildVerticesAndSegments(
        from segments: [DetectedLineSegment],
        mergeRadius: Double
    ) -> ([DetectedVertex], [DetectedLineSegment]) {
        guard !segments.isEmpty else { return ([], []) }

        // Collect all endpoints with their segment references.
        // Each entry: (point, segmentId, isStart)
        struct EndpointRef {
            let point: CGPoint
            let segmentId: String
            let isStart: Bool
        }

        var refs: [EndpointRef] = []
        for seg in segments {
            refs.append(EndpointRef(point: seg.startPoint, segmentId: seg.id, isStart: true))
            refs.append(EndpointRef(point: seg.endPoint, segmentId: seg.id, isStart: false))
        }

        // Greedy clustering: assign each endpoint to an existing cluster or start a new one.
        struct Cluster {
            var points: [CGPoint]
            var refIndices: [Int] // indices into refs array

            var centroid: CGPoint {
                let sumX = points.reduce(0.0) { $0 + $1.x }
                let sumY = points.reduce(0.0) { $0 + $1.y }
                let count = CGFloat(points.count)
                return CGPoint(x: sumX / count, y: sumY / count)
            }
        }

        var clusters: [Cluster] = []

        for (idx, ref) in refs.enumerated() {
            var merged = false
            for ci in 0..<clusters.count {
                let dist = SnapEngine.distance(ref.point, clusters[ci].centroid)
                if dist <= mergeRadius {
                    clusters[ci].points.append(ref.point)
                    clusters[ci].refIndices.append(idx)
                    merged = true
                    break
                }
            }
            if !merged {
                clusters.append(Cluster(points: [ref.point], refIndices: [idx]))
            }
        }

        // Create a vertex for each cluster.
        // Determine which segments connect to each vertex.
        var vertices: [DetectedVertex] = []
        // Map from ref index → vertex id
        var refToVertexId: [Int: String] = [:]

        for cluster in clusters {
            let vertexId = UUID().uuidString
            var connectedSegmentIds: Set<String> = []
            for refIdx in cluster.refIndices {
                connectedSegmentIds.insert(refs[refIdx].segmentId)
                refToVertexId[refIdx] = vertexId
            }
            vertices.append(DetectedVertex(
                id: vertexId,
                position: cluster.centroid,
                connectedSegmentIds: Array(connectedSegmentIds)
            ))
        }

        // Update segment endpoints to vertex positions.
        var updatedSegments: [DetectedLineSegment] = []
        for (segIdx, seg) in segments.enumerated() {
            let startRefIdx = segIdx * 2
            let endRefIdx = segIdx * 2 + 1

            guard let startVertexId = refToVertexId[startRefIdx],
                  let endVertexId = refToVertexId[endRefIdx],
                  let startVertex = vertices.first(where: { $0.id == startVertexId }),
                  let endVertex = vertices.first(where: { $0.id == endVertexId }) else {
                updatedSegments.append(seg)
                continue
            }

            updatedSegments.append(DetectedLineSegment(
                id: seg.id,
                startPoint: startVertex.position,
                endPoint: endVertex.position
            ))
        }

        return (vertices, updatedSegments)
    }

    // MARK: - Step 5: Closed Polygon Check

    /// True if every vertex has exactly 2 connected segments (simple closed polygon).
    static func checkClosed(vertices: [DetectedVertex], segments: [DetectedLineSegment]) -> Bool {
        guard vertices.count >= 3 && segments.count >= 3 else { return false }
        return vertices.allSatisfy { $0.connectedSegmentIds.count == 2 }
    }

    // MARK: - Step 6: Stair Pattern Detection

    /// Detect rectangular regions that may contain stair treads using VNDetectRectanglesRequest.
    private static func detectStairPatterns(
        image: CGImage,
        imageSize: CGSize,
        segments: [DetectedLineSegment]
    ) async -> [StairPattern] {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.2
        request.maximumAspectRatio = 0.8
        request.minimumSize = 0.05
        request.maximumObservations = 5

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let results = request.results else { return [] }

        var patterns: [StairPattern] = []

        for observation in results {
            // Convert Vision normalized bounding box to image coordinates (flip Y).
            let visionRect = observation.boundingBox
            let imageRect = CGRect(
                x: visionRect.origin.x * imageSize.width,
                y: (1.0 - visionRect.origin.y - visionRect.height) * imageSize.height,
                width: visionRect.width * imageSize.width,
                height: visionRect.height * imageSize.height
            )

            // Estimate internal line count from rectangle dimensions.
            let lineCount = countInternalLines(in: imageRect, image: image)

            // Filter: require at least 3 internal lines for a stair pattern.
            guard lineCount >= 3 else { continue }

            // Find the nearest segment to this rectangle's center.
            let rectCenter = CGPoint(
                x: imageRect.midX,
                y: imageRect.midY
            )
            var nearestSegmentId: String?
            var nearestDistance = Double.infinity

            for seg in segments {
                let (_, dist) = PolygonMath.closestPointOnSegment(
                    point: rectCenter,
                    segStart: seg.startPoint,
                    segEnd: seg.endPoint
                )
                if dist < nearestDistance {
                    nearestDistance = dist
                    nearestSegmentId = seg.id
                }
            }

            patterns.append(StairPattern(
                boundingRect: imageRect,
                internalLineCount: lineCount,
                nearestSegmentId: nearestSegmentId
            ))
        }

        return patterns
    }

    /// Simplified estimate of internal parallel lines within a rectangle.
    /// Uses the rectangle's shorter dimension divided by an assumed tread spacing to approximate line count.
    private static func countInternalLines(in rect: CGRect, image: CGImage) -> Int {
        // Stair treads are evenly-spaced horizontal lines within the rectangle.
        // Typical tread spacing in a sketch is roughly 1/15th of the rectangle's shorter side.
        // Use the shorter dimension as the "run" direction (across treads).
        let shorterSide = min(rect.width, rect.height)
        let longerSide = max(rect.width, rect.height)

        // Each tread line occupies roughly (longerSide / lineCount) spacing.
        // Approximate: assume treads are spaced at ~7% of the longer side (empirical for hand-drawn stairs).
        guard longerSide > 0 else { return 0 }

        let estimatedSpacing = longerSide * 0.07
        guard estimatedSpacing > 0 else { return 0 }

        // Line count = number of internal divisions along the longer axis.
        let count = Int(longerSide / estimatedSpacing) - 1
        // Sanity clamp: stair patterns should have between 2 and 30 lines.
        return max(0, min(count, 30))
    }
}
