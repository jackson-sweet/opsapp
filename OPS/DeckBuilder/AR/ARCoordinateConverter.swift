// OPS/OPS/DeckBuilder/AR/ARCoordinateConverter.swift

import Foundation
import SwiftUI

struct ARCoordinateConverter {

    /// An AR vertex position in world space (meters, XZ plane = ground)
    struct ARVertex {
        let id: String
        let x: Double  // meters, world X
        let z: Double  // meters, world Z (forward/backward)
        let y: Double  // meters, world Y (height — ignored for 2D projection)
    }

    /// An AR edge with distance measurement
    struct AREdge {
        let id: String
        let startVertexId: String
        let endVertexId: String
        let distanceMeters: Double
        let accuracyPercent: Double
        var edgeType: EdgeType = .deckEdge
        var railingConfig: RailingConfig?
        var assignedItems: [AssignedItem] = []
    }

    /// Convert AR vertices and edges to DeckDrawingData for the 2D canvas
    /// - Parameters:
    ///   - arVertices: Vertices with world-space positions (meters)
    ///   - arEdges: Edges with measured distances
    ///   - isClosed: Whether the polygon is closed
    ///   - canvasWidth: Target canvas width in points
    ///   - canvasHeight: Target canvas height in points
    ///   - padding: Padding around the shape
    /// - Returns: A valid DeckDrawingData for the canvas
    static func convert(
        arVertices: [ARVertex],
        arEdges: [AREdge],
        isClosed: Bool,
        canvasWidth: CGFloat = 4800,
        canvasHeight: CGFloat = 4800,
        padding: CGFloat = 40
    ) -> DeckDrawingData {
        guard !arVertices.isEmpty else { return DeckDrawingData() }

        let metersToInches = 39.3701

        // Step 1: Find the best rotation to align the longest edge with the X axis
        let rotationAngle = bestAlignmentAngle(vertices: arVertices, edges: arEdges)

        // Step 2: Rotate all vertices around their centroid
        let cx = arVertices.map { $0.x }.reduce(0, +) / Double(arVertices.count)
        let cz = arVertices.map { $0.z }.reduce(0, +) / Double(arVertices.count)
        let cosR = cos(rotationAngle), sinR = sin(rotationAngle)

        struct RotatedPoint { let x: Double; let z: Double; let arId: String }
        let rotated: [RotatedPoint] = arVertices.map { v in
            let dx = v.x - cx, dz = v.z - cz
            return RotatedPoint(
                x: dx * cosR - dz * sinR,
                z: dx * sinR + dz * cosR,
                arId: v.id
            )
        }

        // Step 3: Bounding box of rotated points
        let xs = rotated.map { $0.x }, zs = rotated.map { $0.z }
        let minX = xs.min()!, maxX = xs.max()!
        let minZ = zs.min()!, maxZ = zs.max()!
        let widthMeters = maxX - minX
        let heightMeters = maxZ - minZ

        guard widthMeters > 0 || heightMeters > 0 else { return DeckDrawingData() }

        let widthInches = max(widthMeters, 0.01) * metersToInches
        let heightInches = max(heightMeters, 0.01) * metersToInches

        // Scale to fit ~60% of canvas (centered)
        let availW = Double(canvasWidth) * 0.6
        let availH = Double(canvasHeight) * 0.6
        let scaleFactor = min(availW / widthInches, availH / heightInches)

        // Center of mass at center of canvas
        let canvasCenterX = Double(canvasWidth) / 2
        let canvasCenterY = Double(canvasHeight) / 2
        let shapeCenterXInches = ((minX + maxX) / 2 - minX) * metersToInches
        let shapeCenterZInches = ((minZ + maxZ) / 2 - minZ) * metersToInches
        let offsetX = canvasCenterX - shapeCenterXInches * scaleFactor
        let offsetY = canvasCenterY - shapeCenterZInches * scaleFactor

        // Build deck vertices — snap origin vertex to nearest grid point
        var deckVertices: [DeckVertex] = []
        var vertexIdMap: [String: String] = [:]

        for rp in rotated {
            let xInches = (rp.x - minX) * metersToInches
            let zInches = (rp.z - minZ) * metersToInches
            let canvasPos = CGPoint(
                x: xInches * scaleFactor + offsetX,
                y: zInches * scaleFactor + offsetY
            )
            let vertex = DeckVertex(position: canvasPos)
            vertexIdMap[rp.arId] = vertex.id
            deckVertices.append(vertex)
        }

        // Build deck edges
        var deckEdges: [DeckEdge] = []
        for arE in arEdges {
            guard let startId = vertexIdMap[arE.startVertexId],
                  let endId = vertexIdMap[arE.endVertexId] else { continue }

            var edge = DeckEdge(startVertexId: startId, endVertexId: endId)
            edge.dimension = arE.distanceMeters * metersToInches
            edge.dimensionSource = .ar
            edge.accuracyPercent = arE.accuracyPercent
            edge.edgeType = arE.edgeType
            edge.railingConfig = arE.railingConfig
            edge.assignedItems = arE.assignedItems
            deckEdges.append(edge)
        }

        var data = DeckDrawingData()
        data.vertices = deckVertices
        data.edges = deckEdges
        data.scaleFactor = scaleFactor
        data.footprint = DeckFootprint(isClosed: isClosed)
        return data
    }

    // MARK: - Auto-Rotation Alignment

    /// Find the rotation angle that best aligns the drawing's edges with the canvas axes.
    /// Returns the angle (radians) to rotate around the centroid so the longest edge
    /// is closest to horizontal (X axis).
    private static func bestAlignmentAngle(vertices: [ARVertex], edges: [AREdge]) -> Double {
        guard !edges.isEmpty else { return 0 }

        // Find the longest edge
        var longestLength = 0.0
        var longestAngle = 0.0

        for edge in edges {
            guard let start = vertices.first(where: { $0.id == edge.startVertexId }),
                  let end = vertices.first(where: { $0.id == edge.endVertexId }) else { continue }
            let dx = end.x - start.x
            let dz = end.z - start.z
            let length = sqrt(dx * dx + dz * dz)
            if length > longestLength {
                longestLength = length
                longestAngle = atan2(dz, dx)
            }
        }

        // Snap to nearest 90° alignment — we want edges parallel to X or Y axis
        let snapped = (longestAngle / (.pi / 2)).rounded() * (.pi / 2)
        return -(longestAngle - snapped)
    }

    /// Convert two AR height points to elevation in inches
    /// - Parameters:
    ///   - deckPointY: Y coordinate of the deck surface point (meters, world Y)
    ///   - groundPointY: Y coordinate of the ground point (meters, world Y)
    /// - Returns: Height difference in inches (positive = deck is above ground)
    static func calculateElevation(deckPointY: Double, groundPointY: Double) -> Double {
        let heightMeters = abs(deckPointY - groundPointY)
        return heightMeters * 39.3701
    }

    /// Estimate accuracy for a height measurement (short-range, typically <3m)
    static func heightAccuracy(heightMeters: Double) -> Double {
        AccuracyModel.estimateAccuracy(distanceMeters: heightMeters)
    }
}
