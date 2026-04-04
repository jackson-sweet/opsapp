// OPS/OPS/DeckBuilder/Engine/EstimateGeneratorService.swift

import Foundation

struct EstimateGeneratorService {

    /// A generated line item ready for estimate creation
    struct GeneratedLineItem {
        let name: String
        let description: String?
        let type: LineItemType
        let quantity: Double
        let unit: String           // "linear ft", "sq ft", "each", "set"
        let unitPrice: Double
        let productId: String?
        let category: String       // "Surface", "Railing", "Stairs", "Substructure", "Other"
        let sortOrder: Int
        let isOptional: Bool
    }

    /// Generate all line items from a deck drawing
    /// - Parameter drawingData: The complete deck drawing with all assignments
    /// - Returns: Ordered array of line items ready for estimate creation
    static func generateLineItems(from drawingData: DeckDrawingData) -> [GeneratedLineItem] {
        var items: [GeneratedLineItem] = []
        var sortOrder = 0

        // 1. Surface items (from footprint)
        for item in drawingData.footprint.assignedItems {
            let areaSqFt = calculateAreaSqFt(drawingData: drawingData)
            items.append(GeneratedLineItem(
                name: item.name,
                description: nil,
                type: .material,
                quantity: round(areaSqFt * 100) / 100,
                unit: "sq ft",
                unitPrice: item.unitPrice ?? 0,
                productId: item.productId,
                category: "Surface",
                sortOrder: sortOrder,
                isOptional: false
            ))
            sortOrder += 1
        }

        // 2. Substructure (footings from vertices)
        let footingCounts = countFootingTypes(drawingData: drawingData)
        for (footingType, count) in footingCounts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            items.append(GeneratedLineItem(
                name: footingType.displayName,
                description: nil,
                type: .material,
                quantity: Double(count),
                unit: "each",
                unitPrice: 0,
                productId: nil,
                category: "Substructure",
                sortOrder: sortOrder,
                isOptional: false
            ))
            sortOrder += 1
        }

        // 3. Railing (from edge railing configs)
        for edge in drawingData.edges {
            guard let railing = edge.railingConfig,
                  let dimension = edge.dimension else { continue }

            let linearFt = round(dimension / 12.0 * 100) / 100

            // Subtract stair width from railing length if stairs are on this edge
            var railingLinearFt = linearFt
            if let stairConfig = edge.stairConfig {
                railingLinearFt = max(0, linearFt - round(stairConfig.width / 12.0 * 100) / 100)
            }

            // Railing material line item
            items.append(GeneratedLineItem(
                name: "\(railing.railingType.displayName) Railing",
                description: edgeDescription(edge, drawingData: drawingData),
                type: .material,
                quantity: railingLinearFt,
                unit: "linear ft",
                unitPrice: 0,
                productId: nil,
                category: "Railing",
                sortOrder: sortOrder,
                isOptional: false
            ))
            sortOrder += 1

            // Posts line item
            let postCount = DimensionEngine.postCount(
                edgeLengthInches: dimension,
                maxSpacing: railing.maxPostSpacing
            )
            items.append(GeneratedLineItem(
                name: "\(railing.railingType.displayName) Railing Posts",
                description: "\(railing.railingType.displayName) posts at \(DimensionEngine.formatImperial(railing.maxPostSpacing)) max spacing",
                type: .material,
                quantity: Double(postCount),
                unit: "each",
                unitPrice: 0,
                productId: nil,
                category: "Railing",
                sortOrder: sortOrder,
                isOptional: false
            ))
            sortOrder += 1

            // Railing assigned items
            for item in railing.assignedItems {
                items.append(GeneratedLineItem(
                    name: item.name,
                    description: nil,
                    type: .material,
                    quantity: item.unitType == .linearFoot ? railingLinearFt : 1,
                    unit: item.unitType == .linearFoot ? "linear ft" : "each",
                    unitPrice: item.unitPrice ?? 0,
                    productId: item.productId,
                    category: "Railing",
                    sortOrder: sortOrder,
                    isOptional: false
                ))
                sortOrder += 1
            }
        }

        // 4. Stairs (from edge stair configs)
        for edge in drawingData.edges {
            guard let stairConfig = edge.stairConfig else { continue }

            let totalRise = calculateTotalRise(edge: edge, drawingData: drawingData)

            // Use treadCount override if set, otherwise calculate from rise
            let treadCount: Int
            if let override = stairConfig.treadCount, override > 0 {
                treadCount = override
            } else {
                treadCount = StairConfig.calculateTreadCount(
                    totalRise: totalRise,
                    risePerStep: stairConfig.risePerStep
                )
            }

            let stringerLength = StairConfig.stringerLength(
                totalRise: totalRise,
                treadCount: treadCount,
                runPerTread: stairConfig.runPerTread
            )
            let stringerCount = StairConfig.stringerCount(width: stairConfig.width)

            // Treads
            items.append(GeneratedLineItem(
                name: "Stair Treads",
                description: "\(treadCount) treads, \(DimensionEngine.formatImperial(stairConfig.runPerTread)) run each",
                type: .material,
                quantity: Double(treadCount),
                unit: "each",
                unitPrice: 0,
                productId: nil,
                category: "Stairs",
                sortOrder: sortOrder,
                isOptional: false
            ))
            sortOrder += 1

            // Stringers
            items.append(GeneratedLineItem(
                name: "Stair Stringers",
                description: "\(DimensionEngine.formatImperial(stringerLength)) stringer length",
                type: .material,
                quantity: Double(stringerCount),
                unit: "each",
                unitPrice: 0,
                productId: nil,
                category: "Stairs",
                sortOrder: sortOrder,
                isOptional: false
            ))
            sortOrder += 1

            // Stair railing (if configured)
            if let stairRailing = stairConfig.railingConfig {
                let stairRailingLengthFt = (stringerLength / 12.0) * 2 // both sides
                items.append(GeneratedLineItem(
                    name: "Stair \(stairRailing.railingType.displayName) Railing",
                    description: "Both sides of stairs",
                    type: .material,
                    quantity: round(stairRailingLengthFt * 100) / 100,
                    unit: "linear ft",
                    unitPrice: 0,
                    productId: nil,
                    category: "Stairs",
                    sortOrder: sortOrder,
                    isOptional: false
                ))
                sortOrder += 1

                let stairPostCount = StairCalculator.railingPostCount(
                    stringerLength: stringerLength,
                    maxSpacing: stairRailing.maxPostSpacing
                ) * 2 // both sides
                items.append(GeneratedLineItem(
                    name: "Stair Railing Posts",
                    description: nil,
                    type: .material,
                    quantity: Double(stairPostCount),
                    unit: "each",
                    unitPrice: 0,
                    productId: nil,
                    category: "Stairs",
                    sortOrder: sortOrder,
                    isOptional: false
                ))
                sortOrder += 1
            }

            // Stair assigned items
            for item in stairConfig.assignedItems {
                let qty: Double
                let unitStr: String
                switch item.unitType {
                case .each:
                    qty = 1
                    unitStr = "each"
                case .set:
                    qty = 1
                    unitStr = "set"
                default:
                    qty = Double(treadCount)
                    unitStr = "each"
                }
                items.append(GeneratedLineItem(
                    name: item.name,
                    description: "Stairs",
                    type: .material,
                    quantity: qty,
                    unit: unitStr,
                    unitPrice: item.unitPrice ?? 0,
                    productId: item.productId,
                    category: "Stairs",
                    sortOrder: sortOrder,
                    isOptional: false
                ))
                sortOrder += 1
            }
        }

        // 5. Other edge assigned items (not railing or stairs)
        for edge in drawingData.edges {
            guard let dimension = edge.dimension else { continue }
            for item in edge.assignedItems {
                let quantity: Double
                let unit: String
                switch item.unitType {
                case .linearFoot, .linearMeter:
                    quantity = round(dimension / 12.0 * 100) / 100
                    unit = "linear ft"
                case .each:
                    quantity = 1
                    unit = "each"
                case .set:
                    quantity = 1
                    unit = "set"
                default:
                    quantity = 1
                    unit = "each"
                }
                items.append(GeneratedLineItem(
                    name: item.name,
                    description: edgeDescription(edge, drawingData: drawingData),
                    type: .material,
                    quantity: quantity,
                    unit: unit,
                    unitPrice: item.unitPrice ?? 0,
                    productId: item.productId,
                    category: "Other",
                    sortOrder: sortOrder,
                    isOptional: false
                ))
                sortOrder += 1
            }
        }

        return items
    }

    /// Generate a material summary text for sharing
    static func materialSummary(from drawingData: DeckDrawingData) -> String {
        let items = generateLineItems(from: drawingData)
        guard !items.isEmpty else { return "No materials assigned" }

        var lines: [String] = ["Deck Estimate Summary", String(repeating: "\u{2500}", count: 30)]

        let grouped = Dictionary(grouping: items, by: { $0.category })
        let categoryOrder = ["Surface", "Substructure", "Railing", "Stairs", "Other"]

        for category in categoryOrder {
            guard let categoryItems = grouped[category], !categoryItems.isEmpty else { continue }
            for item in categoryItems {
                let qty = item.quantity == item.quantity.rounded() ? "\(Int(item.quantity))" : String(format: "%.1f", item.quantity)
                lines.append("\(item.name) \u{2014} \(qty) \(item.unit)")
            }
        }

        lines.append(String(repeating: "\u{2500}", count: 30))

        let areaSqFt = calculateAreaSqFt(drawingData: drawingData)
        if areaSqFt > 0 {
            lines.append("Total Area: \(Int(areaSqFt.rounded())) sq ft")
        }

        let perimeterFt = calculatePerimeterFt(drawingData: drawingData)
        if perimeterFt > 0 {
            lines.append("Total Perimeter: \(Int(perimeterFt.rounded())) lin ft")
        }

        return lines.joined(separator: "\n")
    }

    /// Check if the drawing has any assignments (estimate-able content)
    static func hasAssignments(_ drawingData: DeckDrawingData) -> Bool {
        if !drawingData.footprint.assignedItems.isEmpty { return true }
        if drawingData.edges.contains(where: { $0.railingConfig != nil }) { return true }
        if drawingData.edges.contains(where: { $0.stairConfig != nil }) { return true }
        if drawingData.edges.contains(where: { !$0.assignedItems.isEmpty }) { return true }
        if drawingData.vertices.contains(where: { $0.footingType != nil }) { return true }
        return false
    }

    /// Generate AR accuracy internal note if applicable
    static func arAccuracyNote(from drawingData: DeckDrawingData) -> String? {
        let arEdges = drawingData.edges.filter { $0.accuracyPercent != nil }
        guard !arEdges.isEmpty else { return nil }
        let maxAccuracy = arEdges.compactMap { $0.accuracyPercent }.max() ?? 3.0
        return "Note: Some measurements in this estimate were captured via AR and have an accuracy of \u{00B1}\(Int(maxAccuracy))%. Verify dimensions before ordering materials."
    }

    // MARK: - Geometry Helpers

    static func calculateAreaSqFt(drawingData: DeckDrawingData) -> Double {
        guard drawingData.isClosed, let scale = drawingData.scaleFactor, scale > 0 else { return 0 }
        let areaSqInches = PolygonMath.realWorldArea(
            vertices: drawingData.orderedPositions,
            scaleFactor: scale
        )
        return areaSqInches / 144.0
    }

    static func calculatePerimeterFt(drawingData: DeckDrawingData) -> Double {
        var totalInches = 0.0
        for edge in drawingData.edges {
            totalInches += edge.dimension ?? 0
        }
        return totalInches / 12.0
    }

    // MARK: - Private Helpers

    /// Count vertices by footing type
    private static func countFootingTypes(drawingData: DeckDrawingData) -> [FootingType: Int] {
        var counts: [FootingType: Int] = [:]
        for vertex in drawingData.vertices {
            if let footing = vertex.footingType {
                counts[footing, default: 0] += 1
            }
        }
        return counts
    }

    /// Calculate total rise for stairs on an edge (in inches)
    private static func calculateTotalRise(edge: DeckEdge, drawingData: DeckDrawingData) -> Double {
        // Get elevation from connected vertices (elevation is in feet)
        if let startVertex = drawingData.vertex(byId: edge.startVertexId),
           let endVertex = drawingData.vertex(byId: edge.endVertexId) {
            let defaultElevation = drawingData.overallElevation ?? 2.5 // 2.5 feet default
            let startElev = startVertex.elevation ?? defaultElevation
            let endElev = endVertex.elevation ?? defaultElevation
            return max(startElev, endElev) * 12.0 // feet to inches
        }
        return (drawingData.overallElevation ?? 2.5) * 12.0
    }

    private static func edgeDescription(_ edge: DeckEdge, drawingData: DeckDrawingData) -> String? {
        guard let dim = edge.dimension else { return nil }
        return DimensionEngine.format(dim, system: drawingData.config.measurementSystem)
    }
}

// MARK: - FootingType Display Name

extension FootingType {
    var displayName: String {
        switch self {
        case .helicalPile: return "Helical Pile"
        case .sonoTube: return "Sono Tube"
        case .concretePad: return "Concrete Pad"
        }
    }
}
