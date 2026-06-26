// OPS/OPS/DeckBuilder/Engine/DeckTemplateEngine.swift

import Foundation
import SwiftUI

public struct DeckTemplateEngine {

    /// Standard canvas viewport for template generation
    public static let canvasWidth: CGFloat = 600
    public static let canvasHeight: CGFloat = 400
    public static let padding: CGFloat = 40

    /// Generate a complete DeckDrawingData from a template type and user dimensions (in inches).
    ///
    /// Returns nil for any input that fails `template.validationErrors(for:)`.
    /// **Never silently degrades a shape into a different shape** — bug 22577979
    /// reported an L-shape import producing a rectangle because the engine fell
    /// back to a rectangle when c≥a or d≥b. Callers must validate up front so
    /// the user sees an inline message rather than a wrong-shape import.
    public static func generate(
        template: DeckTemplateType,
        dimensions: [Double],
        config: DrawingConfig = DrawingConfig()
    ) -> DeckDrawingData? {
        guard dimensions.count >= template.dimensionCount else { return nil }
        guard dimensions.allSatisfy({ $0 > 0 }) else { return nil }
        guard template.validationErrors(for: dimensions).isEmpty else { return nil }

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
            // Bug 22577979 — input semantics: A=top width, B=stem depth (the
            // stem's own length), C=stem width, D=top depth. Engine internals
            // still expect total height (top depth + stem depth) for `b`, so
            // we sum here. Validation guarantees both inputs are > 0.
            let topWidth   = dimensions[0]
            let stemDepth  = dimensions[1]
            let stemWidth  = dimensions[2]
            let topDepth   = dimensions[3]
            let totalHeight = stemDepth + topDepth
            return generateTShape(a: topWidth, b: totalHeight, c: stemWidth, d: topDepth, config: config)
        case .multiLevel:
            return generateMultiLevel(a: dimensions[0], b: dimensions[1], c: dimensions[2], d: dimensions[3], config: config)
        case .poolDeck:
            return generatePoolDeck(length: dimensions[0], depth: dimensions[1], poolDiameter: dimensions[2], config: config)
        }
    }

    /// Vertex positions in real-world inches for the requested template + inputs.
    ///
    /// Used by the dimension-input diagram so the on-screen shape is the EXACT
    /// shape the engine would emit, eliminating the legacy bug where the
    /// preview drew an L one way and the engine generated it another way.
    /// Returns nil under the same invalid-input conditions as `generate`.
    public static func vertexPositions(
        template: DeckTemplateType,
        dimensions: [Double]
    ) -> [(x: Double, y: Double)]? {
        guard dimensions.count >= template.dimensionCount else { return nil }
        guard dimensions.allSatisfy({ $0 > 0 }) else { return nil }
        guard template.validationErrors(for: dimensions).isEmpty else { return nil }

        switch template {
        case .rectangle, .frontPorch, .freestanding:
            let a = dimensions[0], b = dimensions[1]
            return [(0, 0), (a, 0), (a, b), (0, b)]
        case .lShape:
            let a = dimensions[0], b = dimensions[1], c = dimensions[2], d = dimensions[3]
            return [(0, 0), (a, 0), (a, d), (a - c, d), (a - c, b), (0, b)]
        case .wraparound:
            let a = dimensions[0], b = dimensions[1], c = dimensions[2], d = dimensions[3]
            return [(0, 0), (a, 0), (a, b), (c, b), (c, d), (0, d)]
        case .tShape:
            let a = dimensions[0]
            let stemDepth = dimensions[1]
            let c = dimensions[2]
            let d = dimensions[3]
            let totalH = stemDepth + d
            let stemLeft = (a - c) / 2
            let stemRight = stemLeft + c
            return [
                (0, 0), (a, 0), (a, d), (stemRight, d),
                (stemRight, totalH), (stemLeft, totalH), (stemLeft, d), (0, d),
            ]
        case .multiLevel:
            // Two stacked rectangles with a 24" gap. The diagram returns the
            // outer hull around both so the preview is a single closed polygon
            // the same way the engine arranges levels — both rectangles read
            // as one shape to the user.
            let a = dimensions[0], b = dimensions[1], c = dimensions[2], d = dimensions[3]
            let gap: Double = 24.0
            let totalW = max(a, c)
            let upperX = (totalW - a) / 2
            let lowerX = (totalW - c) / 2
            // Outline traces around both rectangles + the gap so each edge of
            // each level remains identifiable.
            return [
                (upperX, 0), (upperX + a, 0), (upperX + a, b),
                (lowerX + c, b + gap), (lowerX + c, b + gap + d),
                (lowerX, b + gap + d), (lowerX, b + gap),
                (upperX, b),
            ]
        case .poolDeck:
            let a = dimensions[0], b = dimensions[1]
            return [(0, 0), (a, 0), (a, b), (0, b)]
        }
    }

    // MARK: - Scale Factor

    private static func calculateScale(
        shapeWidthInches: Double,
        shapeHeightInches: Double
    ) -> Double {
        guard shapeWidthInches > 0, shapeHeightInches > 0 else {
            print("[DeckBuilder] calculateScale: invalid shape dimensions (w: \(shapeWidthInches), h: \(shapeHeightInches))")
            return 1.0
        }
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
        // Bug 22577979 — the previous silent fallback to a rectangle when
        // c≥a or d≥b is what caused "imported template, got a rectangle"
        // reports. `generate(...)` now validates up front via
        // `DeckTemplateType.validationErrors(for:)`, so by the time we get
        // here the constraints are guaranteed. No fallback necessary.

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
        // Bug 22577979 — see generateLShape; validation now guarantees
        // c < a and d < b before we reach this point.

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
        // Bug 22577979 — input semantics are now: a=top width, b=TOTAL
        // height (caller computes b = topDepth + stemDepth), c=stem width,
        // d=top depth. Validation in `generate(...)` checks c < a; b > d
        // follows automatically because stemDepth > 0.

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
        c: Double,
        d: Double,
        config: DrawingConfig
    ) -> DeckDrawingData {
        // Generate actual 2-level geometry: upper deck (A×B) and lower deck (C×D)
        // Upper level positioned at top of canvas, lower level below with a gap

        let totalHeight = b + d + 24.0 // 24" gap between levels for stairs visual
        let totalWidth = max(a, c)

        let scale = calculateScale(shapeWidthInches: totalWidth, shapeHeightInches: totalHeight)
        let offset = calculateOffset(shapeWidthInches: totalWidth, shapeHeightInches: totalHeight, scaleFactor: scale)

        // Center each level horizontally
        let upperOffsetX = (totalWidth - a) / 2
        let lowerOffsetX = (totalWidth - c) / 2
        let lowerTopY = b + 24.0

        // Build upper level
        var upperLevel = DeckLevel(name: "Upper Deck", displayColor: .blue, sortOrder: 0)
        let uv0 = DeckVertex(position: toCanvas(xInches: upperOffsetX, yInches: 0, scaleFactor: scale, offset: offset))
        let uv1 = DeckVertex(position: toCanvas(xInches: upperOffsetX + a, yInches: 0, scaleFactor: scale, offset: offset))
        let uv2 = DeckVertex(position: toCanvas(xInches: upperOffsetX + a, yInches: b, scaleFactor: scale, offset: offset))
        let uv3 = DeckVertex(position: toCanvas(xInches: upperOffsetX, yInches: b, scaleFactor: scale, offset: offset))
        upperLevel.vertices = [uv0, uv1, uv2, uv3]

        var ue0 = DeckEdge(startVertexId: uv0.id, endVertexId: uv1.id); ue0.dimension = a; ue0.edgeType = .houseEdge
        var ue1 = DeckEdge(startVertexId: uv1.id, endVertexId: uv2.id); ue1.dimension = b
        var ue2 = DeckEdge(startVertexId: uv2.id, endVertexId: uv3.id); ue2.dimension = a
        var ue3 = DeckEdge(startVertexId: uv3.id, endVertexId: uv0.id); ue3.dimension = b
        upperLevel.edges = [ue0, ue1, ue2, ue3]
        upperLevel.footprint = DeckFootprint(isClosed: true)

        // Build lower level
        var lowerLevel = DeckLevel(name: "Lower Deck", displayColor: .green, sortOrder: 1)
        let lv0 = DeckVertex(position: toCanvas(xInches: lowerOffsetX, yInches: lowerTopY, scaleFactor: scale, offset: offset))
        let lv1 = DeckVertex(position: toCanvas(xInches: lowerOffsetX + c, yInches: lowerTopY, scaleFactor: scale, offset: offset))
        let lv2 = DeckVertex(position: toCanvas(xInches: lowerOffsetX + c, yInches: lowerTopY + d, scaleFactor: scale, offset: offset))
        let lv3 = DeckVertex(position: toCanvas(xInches: lowerOffsetX, yInches: lowerTopY + d, scaleFactor: scale, offset: offset))
        lowerLevel.vertices = [lv0, lv1, lv2, lv3]

        var le0 = DeckEdge(startVertexId: lv0.id, endVertexId: lv1.id); le0.dimension = c
        var le1 = DeckEdge(startVertexId: lv1.id, endVertexId: lv2.id); le1.dimension = d
        var le2 = DeckEdge(startVertexId: lv2.id, endVertexId: lv3.id); le2.dimension = c
        var le3 = DeckEdge(startVertexId: lv3.id, endVertexId: lv0.id); le3.dimension = d
        lowerLevel.edges = [le0, le1, le2, le3]
        lowerLevel.footprint = DeckFootprint(isClosed: true)

        // Build connection (stairs from upper bottom edge to lower top edge)
        // Elevations are nil — user sets them after creation
        let connection = LevelConnection(
            upperLevelId: upperLevel.id,
            lowerLevelId: lowerLevel.id,
            upperEdgeId: ue2.id, // bottom edge of upper level
            lowerEdgeId: le0.id, // top edge of lower level
            stairConfig: StairConfig(width: 48) // 4' default, treadCount computed when elevations set
        )

        var data = DeckDrawingData()
        data.levels = [upperLevel, lowerLevel]
        data.levelConnections = [connection]
        data.config = config
        data.scaleFactor = scale
        return data
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
    public static func copyDrawingData(_ original: DeckDrawingData) -> DeckDrawingData {
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
