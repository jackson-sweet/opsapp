// OPS/OPS/DeckBuilder/Engine/DeckTemplateEngine.swift

import Foundation
import SwiftUI

struct DeckTemplateEngine {

    /// Standard canvas viewport for template generation
    static let canvasWidth: CGFloat = 600
    static let canvasHeight: CGFloat = 400
    static let padding: CGFloat = 40

    /// Generate a complete DeckDrawingData from a template type and user dimensions (in inches)
    static func generate(
        template: DeckTemplateType,
        dimensions: [Double],
        config: DrawingConfig = DrawingConfig()
    ) -> DeckDrawingData? {
        guard dimensions.count >= template.dimensionCount else { return nil }
        guard dimensions.allSatisfy({ $0 > 0 }) else { return nil }

        switch template {
        case .rectangle:
            return generateRectangle(length: dimensions[0], depth: dimensions[1], hasHouseEdge: true, config: config)
        case .frontPorch:
            return generateRectangle(length: dimensions[0], depth: dimensions[1], hasHouseEdge: true, config: config)
        case .freestanding:
            return generateRectangle(length: dimensions[0], depth: dimensions[1], hasHouseEdge: false, config: config)
        case .lShape:
            return generateLShape(a: dimensions[0], b: dimensions[1], c: dimensions[2], d: dimensions[3], config: config)
        case .wraparound:
            return generateWraparound(a: dimensions[0], b: dimensions[1], c: dimensions[2], d: dimensions[3], config: config)
        case .tShape:
            return generateTShape(a: dimensions[0], b: dimensions[1], c: dimensions[2], d: dimensions[3], config: config)
        case .multiLevel:
            return generateMultiLevel(a: dimensions[0], b: dimensions[1], config: config)
        case .poolDeck:
            return generatePoolDeck(length: dimensions[0], depth: dimensions[1], poolDiameter: dimensions[2], config: config)
        }
    }

    // MARK: - Scale Factor

    private static func calculateScale(
        shapeWidthInches: Double,
        shapeHeightInches: Double
    ) -> Double {
        let availableWidth = Double(canvasWidth - 2 * padding)
        let availableHeight = Double(canvasHeight - 2 * padding)
        let scaleX = availableWidth / shapeWidthInches
        let scaleY = availableHeight / shapeHeightInches
        return min(scaleX, scaleY)
    }

    private static func calculateOffset(
        shapeWidthInches: Double,
        shapeHeightInches: Double,
        scaleFactor: Double
    ) -> CGPoint {
        let shapeWidthPts = shapeWidthInches * scaleFactor
        let shapeHeightPts = shapeHeightInches * scaleFactor
        let offsetX = (Double(canvasWidth) - shapeWidthPts) / 2
        let offsetY = (Double(canvasHeight) - shapeHeightPts) / 2
        return CGPoint(x: offsetX, y: offsetY)
    }

    private static func toCanvas(
        xInches: Double,
        yInches: Double,
        scaleFactor: Double,
        offset: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: xInches * scaleFactor + offset.x,
            y: yInches * scaleFactor + offset.y
        )
    }

    // MARK: - Helper: Build closed polygon

    private static func buildPolygon(
        vertexPositions: [(x: Double, y: Double)],
        edgeDimensions: [Double],
        houseEdgeIndices: Set<Int>,
        shapeWidth: Double,
        shapeHeight: Double,
        config: DrawingConfig
    ) -> DeckDrawingData {
        let scaleFactor = calculateScale(shapeWidthInches: shapeWidth, shapeHeightInches: shapeHeight)
        let offset = calculateOffset(shapeWidthInches: shapeWidth, shapeHeightInches: shapeHeight, scaleFactor: scaleFactor)

        // Create vertices
        var vertices: [DeckVertex] = []
        for pos in vertexPositions {
            let canvasPos = toCanvas(xInches: pos.x, yInches: pos.y, scaleFactor: scaleFactor, offset: offset)
            vertices.append(DeckVertex(position: canvasPos))
        }

        // Create edges (closed polygon: last edge connects back to first vertex)
        var edges: [DeckEdge] = []
        let n = vertices.count
        for i in 0..<n {
            let j = (i + 1) % n
            var edge = DeckEdge(startVertexId: vertices[i].id, endVertexId: vertices[j].id)
            edge.dimension = edgeDimensions[i]
            edge.dimensionSource = .manual
            if houseEdgeIndices.contains(i) {
                edge.edgeType = .houseEdge
            }
            edges.append(edge)
        }

        var data = DeckDrawingData()
        data.vertices = vertices
        data.edges = edges
        data.config = config
        data.scaleFactor = scaleFactor
        data.footprint = DeckFootprint(isClosed: true)
        return data
    }

    // MARK: - Rectangle

    private static func generateRectangle(
        length: Double,
        depth: Double,
        hasHouseEdge: Bool,
        config: DrawingConfig
    ) -> DeckDrawingData {
        //  V0 ---A--- V1
        //  |          |
        //  B          B
        //  |          |
        //  V3 ---A--- V2

        let positions: [(x: Double, y: Double)] = [
            (0, 0),
            (length, 0),
            (length, depth),
            (0, depth),
        ]

        let dimensions = [length, depth, length, depth]
        let houseEdges: Set<Int> = hasHouseEdge ? [0] : []

        return buildPolygon(
            vertexPositions: positions,
            edgeDimensions: dimensions,
            houseEdgeIndices: houseEdges,
            shapeWidth: length,
            shapeHeight: depth,
            config: config
        )
    }

    // MARK: - L-Shape

    private static func generateLShape(
        a: Double,
        b: Double,
        c: Double,
        d: Double,
        config: DrawingConfig
    ) -> DeckDrawingData {
        guard c < a, d < b else {
            return generateRectangle(length: a, depth: b, hasHouseEdge: true, config: config)
        }

        //  V0 ---------- V1
        //  |               |
        //  |          V3 --V2
        //  |          |
        //  V5 -------V4

        let positions: [(x: Double, y: Double)] = [
            (0, 0),
            (a, 0),
            (a, d),
            (a - c, d),
            (a - c, b),
            (0, b),
        ]

        let dimensions = [
            a,          // V0→V1 (top, house edge)
            d,          // V1→V2 (right upper)
            c,          // V2→V3 (step horizontal)
            b - d,      // V3→V4 (step vertical)
            a - c,      // V4→V5 (bottom)
            b,          // V5→V0 (left)
        ]

        return buildPolygon(
            vertexPositions: positions,
            edgeDimensions: dimensions,
            houseEdgeIndices: [0],
            shapeWidth: a,
            shapeHeight: b,
            config: config
        )
    }

    // MARK: - Wraparound

    private static func generateWraparound(
        a: Double,
        b: Double,
        c: Double,
        d: Double,
        config: DrawingConfig
    ) -> DeckDrawingData {
        guard c < a, d < b else {
            return generateRectangle(length: a, depth: b, hasHouseEdge: true, config: config)
        }

        //  V0 ---------- V1
        //  |               |
        //  V5 --V4         |
        //        |         |
        //        V3 ------V2

        let positions: [(x: Double, y: Double)] = [
            (0, 0),
            (a, 0),
            (a, b),
            (c, b),
            (c, d),
            (0, d),
        ]

        let dimensions = [
            a,          // V0→V1 (top, house edge)
            b,          // V1→V2 (right)
            a - c,      // V2→V3 (bottom right)
            b - d,      // V3→V4 (inner vertical, house edge)
            c,          // V4→V5 (inner horizontal)
            d,          // V5→V0 (left)
        ]

        return buildPolygon(
            vertexPositions: positions,
            edgeDimensions: dimensions,
            houseEdgeIndices: [0, 3],
            shapeWidth: a,
            shapeHeight: b,
            config: config
        )
    }

    // MARK: - T-Shape

    private static func generateTShape(
        a: Double,
        b: Double,
        c: Double,
        d: Double,
        config: DrawingConfig
    ) -> DeckDrawingData {
        guard c < a, d < b else {
            return generateRectangle(length: a, depth: b, hasHouseEdge: true, config: config)
        }

        let stemLeft = (a - c) / 2
        let stemRight = stemLeft + c
        let stemDepth = b - d

        //  V0 -------------------- V1
        //  |                         |
        //  V7 --V6             V3 --V2
        //        |             |
        //        V5 ----------V4

        let positions: [(x: Double, y: Double)] = [
            (0, 0),
            (a, 0),
            (a, d),
            (stemRight, d),
            (stemRight, b),
            (stemLeft, b),
            (stemLeft, d),
            (0, d),
        ]

        let dimensions = [
            a,              // V0→V1 (top, house edge)
            d,              // V1→V2 (right of top bar)
            a - stemRight,  // V2→V3 (right overhang = (a-c)/2)
            stemDepth,      // V3→V4 (right side of stem)
            c,              // V4→V5 (bottom of stem)
            stemDepth,      // V5→V6 (left side of stem)
            stemLeft,       // V6→V7 (left overhang = (a-c)/2)
            d,              // V7→V0 (left of top bar)
        ]

        return buildPolygon(
            vertexPositions: positions,
            edgeDimensions: dimensions,
            houseEdgeIndices: [0],
            shapeWidth: a,
            shapeHeight: b,
            config: config
        )
    }

    // MARK: - Multi-Level

    private static func generateMultiLevel(
        a: Double,
        b: Double,
        config: DrawingConfig
    ) -> DeckDrawingData {
        // Multi-level true geometry is Phase 8 scope.
        // For template purposes, generate the upper rectangle.
        return generateRectangle(length: a, depth: b, hasHouseEdge: true, config: config)
    }

    // MARK: - Pool Deck

    private static func generatePoolDeck(
        length: Double,
        depth: Double,
        poolDiameter: Double,
        config: DrawingConfig
    ) -> DeckDrawingData {
        // Rectangle with pool cutout as informational overlay (not geometric)
        var data = generateRectangle(length: length, depth: depth, hasHouseEdge: false, config: config)
        data.poolDiameter = poolDiameter
        return data
    }

    // MARK: - Copy from Existing Design

    /// Create an independent copy of existing drawing data with all-new vertex/edge IDs.
    /// The original design is completely untouched.
    static func copyDrawingData(_ original: DeckDrawingData) -> DeckDrawingData {
        let json = original.toJSON()
        guard var copy = DeckDrawingData.fromJSON(json) else { return original }

        var idMap: [String: String] = [:]

        // Remap vertices with new IDs
        for i in 0..<copy.vertices.count {
            let oldId = copy.vertices[i].id
            let newId = UUID().uuidString
            idMap[oldId] = newId
            copy.vertices[i] = DeckVertex(
                id: newId,
                position: copy.vertices[i].position,
                elevation: copy.vertices[i].elevation
            )
            copy.vertices[i].elevationSource = original.vertices[i].elevationSource
            copy.vertices[i].footingType = original.vertices[i].footingType
            copy.vertices[i].postType = original.vertices[i].postType
        }

        // Remap edges with new IDs and remapped vertex references
        for i in 0..<copy.edges.count {
            let oldEdge = copy.edges[i]
            let newId = UUID().uuidString
            var newEdge = DeckEdge(
                id: newId,
                startVertexId: idMap[oldEdge.startVertexId] ?? oldEdge.startVertexId,
                endVertexId: idMap[oldEdge.endVertexId] ?? oldEdge.endVertexId
            )
            newEdge.edgeType = oldEdge.edgeType
            newEdge.dimension = oldEdge.dimension
            newEdge.dimensionSource = oldEdge.dimensionSource
            newEdge.railingConfig = oldEdge.railingConfig
            newEdge.stairConfig = oldEdge.stairConfig
            newEdge.assignedItems = oldEdge.assignedItems
            copy.edges[i] = newEdge
        }

        return copy
    }
}
