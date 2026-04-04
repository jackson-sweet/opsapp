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
        canvasWidth: CGFloat = 600,
        canvasHeight: CGFloat = 400,
        padding: CGFloat = 40
    ) -> DeckDrawingData {
        guard !arVertices.isEmpty else { return DeckDrawingData() }

        // Project 3D to 2D (XZ plane, ignore Y)
        // Convert meters to inches for dimensions
        let metersToInches = 39.3701

        // Calculate bounding box in meters
        let xs = arVertices.map { $0.x }
        let zs = arVertices.map { $0.z }
        let minX = xs.min()!, maxX = xs.max()!
        let minZ = zs.min()!, maxZ = zs.max()!
        let widthMeters = maxX - minX
        let heightMeters = maxZ - minZ

        guard widthMeters > 0 || heightMeters > 0 else { return DeckDrawingData() }

        let widthInches = max(widthMeters, 0.01) * metersToInches
        let heightInches = max(heightMeters, 0.01) * metersToInches

        // Calculate scale to fit in canvas
        let availW = Double(canvasWidth - 2 * padding)
        let availH = Double(canvasHeight - 2 * padding)
        let scaleFactor = min(availW / widthInches, availH / heightInches)

        let offsetX = (Double(canvasWidth) - widthInches * scaleFactor) / 2
        let offsetY = (Double(canvasHeight) - heightInches * scaleFactor) / 2

        // Build deck vertices
        var deckVertices: [DeckVertex] = []
        var vertexIdMap: [String: String] = [:] // AR vertex ID → deck vertex ID

        for arV in arVertices {
            let xInches = (arV.x - minX) * metersToInches
            let zInches = (arV.z - minZ) * metersToInches
            let canvasPos = CGPoint(
                x: xInches * scaleFactor + offsetX,
                y: zInches * scaleFactor + offsetY
            )
            let vertex = DeckVertex(position: canvasPos)
            vertexIdMap[arV.id] = vertex.id
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
