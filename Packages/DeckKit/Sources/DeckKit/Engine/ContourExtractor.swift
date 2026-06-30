// OPS/OPS/DeckBuilder/Engine/ContourExtractor.swift

import Foundation
import Vision

public struct ContourExtractor {

    // MARK: - Main Entry Point

    /// Extract deck outline from a cleaned binary image (grid removed).
    /// Returns vertices, segments, closure status, and detected stair patterns.
    public static func extract(
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
        request.contrastAdjustment = 2.0
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
        guard let simplified = try? largest.polygonApproximation(epsilon: 0.005) else {
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
    /// Internal (not private) so the segment-merge geometry — including the start/end seam
    /// wraparound merge — is unit-testable via `@testable import OPS`.
    public static func simplifyContour(_ points: [CGPoint], imageSize: CGSize) -> [DetectedLineSegment] {
        guard points.count >= 2 else { return [] }

        let diagonal = sqrt(imageSize.width * imageSize.width + imageSize.height * imageSize.height)
        let minLength = Double(diagonal) * 0.015

        // Create segments between consecutive points (wrapping last→first)
        var rawSegments: [DetectedLineSegment] = []
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            let seg = DetectedLineSegment(startPoint: points[i], endPoint: points[j])
            rawSegments.append(seg)
        }

        // Filter segments shorter than minimum length
        let filtered = rawSegments.filter { $0.lengthPixels >= minLength }

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

        // Check if the first and last segments should also merge (wraparound seam).
        //
        // The contour walk wraps last.end → first.start, so when `last` and `first`
        // are near-collinear they are the two halves of one edge straddling the
        // start/end seam. The merged edge must therefore span the OUTER endpoints:
        //   last.startPoint → first.endPoint
        // (`first` is fully absorbed into `last`, then removed). After removeFirst the
        // new merged[0] is the old merged[1], whose start equals first.endPoint — so
        // the terminal segment still connects back with no gap and no truncation.
        //
        // Require >= 3 segments: removing `first` must still leave a closeable polygon
        // (>= 2 edges → >= 3 before removal). With only 2 segments the pair is a
        // degenerate digon and last.startPoint == first.endPoint, which would collapse
        // the terminal segment to zero length and corrupt vertex building.
        if merged.count >= 3 {
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
    public static func snapSegmentAngles(
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
    public static func buildVerticesAndSegments(
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
    public static func checkClosed(vertices: [DetectedVertex], segments: [DetectedLineSegment]) -> Bool {
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

    /// Count internal parallel lines (stair treads) by scanning pixel columns/rows within the rectangle.
    /// Falls back to a geometric heuristic if pixel data cannot be accessed.
    private static func countInternalLines(in rect: CGRect, image: CGImage) -> Int {
        let imageWidth = image.width
        let imageHeight = image.height

        // Clamp rect to image bounds
        let minX = max(0, Int(rect.origin.x))
        let minY = max(0, Int(rect.origin.y))
        let maxX = min(imageWidth - 1, Int(rect.origin.x + rect.width))
        let maxY = min(imageHeight - 1, Int(rect.origin.y + rect.height))

        let clampedWidth = maxX - minX + 1
        let clampedHeight = maxY - minY + 1
        guard clampedWidth > 0, clampedHeight > 0 else { return 0 }

        // Attempt to access raw pixel data
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            // Fallback: geometric heuristic
            let longerSide = max(rect.width, rect.height)
            guard longerSide > 0 else { return 0 }
            let estimatedSpacing = longerSide * 0.07
            guard estimatedSpacing > 0 else { return 0 }
            let count = Int(longerSide / estimatedSpacing) - 1
            return max(0, min(count, 30))
        }

        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = image.bitsPerPixel / 8
        guard bytesPerPixel > 0 else { return 0 }

        // Determine scan direction:
        // If wider than tall, treads are horizontal lines → project onto the Y axis (scan rows, sum dark pixels per row)
        // If taller than wide, treads are vertical lines → project onto the X axis (scan columns, sum dark pixels per column)
        let scanAlongY = rect.width >= rect.height
        let profileLength = scanAlongY ? clampedHeight : clampedWidth

        guard profileLength > 0 else { return 0 }

        // Build 1D projection profile: for each position along the scan axis,
        // count the number of dark pixels perpendicular to that axis.
        var profile = [Int](repeating: 0, count: profileLength)

        if scanAlongY {
            // Profile along Y: for each row, count dark pixels across all columns
            for row in 0..<clampedHeight {
                let y = minY + row
                var darkCount = 0
                for col in 0..<clampedWidth {
                    let x = minX + col
                    let pixelOffset = y * bytesPerRow + x * bytesPerPixel
                    // Use first channel (red or grayscale) as luminance proxy
                    let value = Int(bytes[pixelOffset])
                    if value < 128 {
                        darkCount += 1
                    }
                }
                profile[row] = darkCount
            }
        } else {
            // Profile along X: for each column, count dark pixels across all rows
            for col in 0..<clampedWidth {
                let x = minX + col
                var darkCount = 0
                for row in 0..<clampedHeight {
                    let y = minY + row
                    let pixelOffset = y * bytesPerRow + x * bytesPerPixel
                    let value = Int(bytes[pixelOffset])
                    if value < 128 {
                        darkCount += 1
                    }
                }
                profile[col] = darkCount
            }
        }

        // Compute mean and standard deviation of the profile
        let sum = profile.reduce(0, +)
        let mean = Double(sum) / Double(profileLength)

        var varianceSum = 0.0
        for value in profile {
            let diff = Double(value) - mean
            varianceSum += diff * diff
        }
        let stddev = sqrt(varianceSum / Double(profileLength))

        let threshold = mean + 0.5 * stddev

        // Find peaks: positions where value > threshold AND is a local maximum
        var peaks: [Int] = []
        for i in 0..<profileLength {
            let value = Double(profile[i])
            guard value > threshold else { continue }

            let leftValue = i > 0 ? Double(profile[i - 1]) : 0.0
            let rightValue = i < profileLength - 1 ? Double(profile[i + 1]) : 0.0

            if value >= leftValue && value >= rightValue {
                peaks.append(i)
            }
        }

        // Merge peaks that are very close together (within 3 pixels)
        var mergedPeaks: [Int] = []
        for peak in peaks {
            if let last = mergedPeaks.last, peak - last <= 3 {
                // Replace with the one that has the higher profile value
                if profile[peak] > profile[last] {
                    mergedPeaks[mergedPeaks.count - 1] = peak
                }
            } else {
                mergedPeaks.append(peak)
            }
        }

        return max(0, min(mergedPeaks.count, 30))
    }
}
