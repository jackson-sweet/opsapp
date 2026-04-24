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
        let taskTypeId: String?    // task type from the assigned product
        let category: String       // "Surface", "Railing", "Stairs", "Substructure", "Other"
        let sortOrder: Int
        let isOptional: Bool
        var warning: String?       // validation warning (e.g., missing elevation)
    }

    /// Grouped line items by task type for parent-child estimate creation
    struct GeneratedEstimateGroup {
        let taskTypeId: String?
        let taskTypeName: String
        let children: [GeneratedLineItem]
        var parentTotal: Double
    }

    /// Generate all line items from a deck drawing
    /// - Parameter drawingData: The complete deck drawing with all assignments
    /// - Returns: Ordered array of line items ready for estimate creation
    static func generateLineItems(from drawingData: DeckDrawingData) -> [GeneratedLineItem] {
        if drawingData.isMultiLevel {
            return generateMultiLevelLineItems(from: drawingData)
        }
        return generateSingleLevelLineItems(
            footprint: drawingData.footprint,
            edges: drawingData.edges,
            vertices: drawingData.vertices,
            orderedPositions: drawingData.orderedPositions,
            isPolygonClosed: drawingData.isClosed,
            drawingData: drawingData,
            levelPrefix: nil,
            startingSortOrder: 0
        ).items
    }

    /// Multi-level: iterate levels then connections
    private static func generateMultiLevelLineItems(from drawingData: DeckDrawingData) -> [GeneratedLineItem] {
        var allItems: [GeneratedLineItem] = []
        var sortOrder = 0

        // Per-level items
        for level in drawingData.levels {
            let result = generateSingleLevelLineItems(
                footprint: level.footprint,
                edges: level.edges,
                vertices: level.vertices,
                // Walk the edge graph for area — raw vertex insertion order
                // produces a meaningless shoelace value for any non-trivial shape.
                orderedPositions: level.orderedPositions,
                isPolygonClosed: level.isClosed,
                drawingData: drawingData,
                levelPrefix: level.name,
                startingSortOrder: sortOrder
            )
            allItems.append(contentsOf: result.items)
            sortOrder = result.nextSortOrder
        }

        // Connection stair items
        for connection in drawingData.levelConnections {
            guard let diff = drawingData.elevationDifference(
                upperLevelId: connection.upperLevelId,
                lowerLevelId: connection.lowerLevelId
            ), diff > 0 else { continue }

            let config = connection.stairConfig
            let treadCount = config.treadCount ?? StairConfig.calculateTreadCount(totalRise: diff)
            let stringerLength = StairConfig.stringerLength(totalRise: diff, treadCount: treadCount)
            let stringerCount = StairConfig.stringerCount(width: config.width)

            let upperName = drawingData.level(byId: connection.upperLevelId)?.name ?? "Upper"
            let lowerName = drawingData.level(byId: connection.lowerLevelId)?.name ?? "Lower"
            let prefix = "\(upperName) \u{2192} \(lowerName)"

            allItems.append(GeneratedLineItem(
                name: "\(prefix) \u{2014} Stair Treads",
                description: "\(treadCount) treads, \(DimensionEngine.formatImperial(config.runPerTread)) run each",
                type: .material, quantity: Double(treadCount), unit: "each",
                unitPrice: 0, productId: nil, taskTypeId: nil, category: "Connecting Stairs",
                sortOrder: sortOrder, isOptional: false
            ))
            sortOrder += 1

            allItems.append(GeneratedLineItem(
                name: "\(prefix) \u{2014} Stringers",
                description: "\(DimensionEngine.formatImperial(stringerLength)) stringer length",
                type: .material, quantity: Double(stringerCount), unit: "each",
                unitPrice: 0, productId: nil, taskTypeId: nil, category: "Connecting Stairs",
                sortOrder: sortOrder, isOptional: false
            ))
            sortOrder += 1

            if let stairRailing = config.railingConfig {
                let railingLenFt = (stringerLength / 12.0) * 2
                allItems.append(GeneratedLineItem(
                    name: "\(prefix) \u{2014} \(stairRailing.railingType.displayName) Railing",
                    description: "Both sides", type: .material,
                    quantity: round(railingLenFt * 100) / 100, unit: "linear ft",
                    unitPrice: 0, productId: nil, taskTypeId: nil, category: "Connecting Stairs",
                    sortOrder: sortOrder, isOptional: false
                ))
                sortOrder += 1

                let postCount = StairCalculator.railingPostCount(stringerLength: stringerLength, maxSpacing: stairRailing.maxPostSpacing) * 2
                allItems.append(GeneratedLineItem(
                    name: "\(prefix) \u{2014} Stair Railing Posts",
                    description: nil, type: .material,
                    quantity: Double(postCount), unit: "each",
                    unitPrice: 0, productId: nil, taskTypeId: nil, category: "Connecting Stairs",
                    sortOrder: sortOrder, isOptional: false
                ))
                sortOrder += 1
            }
        }

        return allItems
    }

    /// Generate line items for a single level (or the single-level mode).
    /// `orderedPositions` and `isPolygonClosed` are computed by the caller from
    /// the right source (DeckLevel for multi-level, DeckDrawingData for single)
    /// — pass-through avoids the previous bug where the multi-level path used
    /// raw vertex order and produced a meaningless shoelace area.
    private static func generateSingleLevelLineItems(
        footprint: DeckFootprint,
        edges: [DeckEdge],
        vertices: [DeckVertex],
        orderedPositions: [CGPoint],
        isPolygonClosed: Bool,
        drawingData: DeckDrawingData,
        levelPrefix: String?,
        startingSortOrder: Int
    ) -> (items: [GeneratedLineItem], nextSortOrder: Int) {
        var items: [GeneratedLineItem] = []
        var sortOrder = startingSortOrder
        let prefix = levelPrefix.map { "\($0) \u{2014} " } ?? ""

        // 1. Surface items (from footprint)
        for item in footprint.assignedItems {
            let areaSqFt: Double
            if levelPrefix != nil {
                // Multi-level: walk the edge graph for area, gate on closure +
                // self-intersection. Without these guards a half-drawn or bowtied
                // level would still ship into the estimate with a phantom number.
                guard let scale = drawingData.scaleFactor, scale > 0,
                      isPolygonClosed,
                      orderedPositions.count >= 3,
                      !PolygonMath.isSelfIntersecting(vertices: orderedPositions) else { continue }
                areaSqFt = PolygonMath.realWorldArea(vertices: orderedPositions, scaleFactor: scale) / 144.0
            } else {
                // Single-level uses the validated helper that already gates the
                // same way — keeps this branch in lockstep with totalArea / UI.
                areaSqFt = calculateAreaSqFt(drawingData: drawingData)
            }
            items.append(GeneratedLineItem(
                name: "\(prefix)\(item.name)",
                description: nil,
                type: .material,
                quantity: round(areaSqFt * 100) / 100,
                unit: "sq ft",
                unitPrice: item.unitPrice ?? 0,
                productId: item.productId,
                taskTypeId: item.taskTypeId,
                category: "Surface",
                sortOrder: sortOrder,
                isOptional: false
            ))
            sortOrder += 1
        }

        // 2. Substructure (footings from vertices)
        var footingCounts: [FootingType: Int] = [:]
        for vertex in vertices {
            if let footing = vertex.footingType {
                footingCounts[footing, default: 0] += 1
            }
        }
        for (footingType, count) in footingCounts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            items.append(GeneratedLineItem(
                name: "\(prefix)\(footingType.displayName)",
                description: nil,
                type: .material,
                quantity: Double(count),
                unit: "each",
                unitPrice: 0,
                productId: nil,
                taskTypeId: nil,
                category: "Substructure",
                sortOrder: sortOrder,
                isOptional: false
            ))
            sortOrder += 1
        }

        // 3. Railing (from edge railing configs)
        for edge in edges {
            guard let railing = edge.railingConfig,
                  let dimension = edge.dimension else { continue }

            let linearFt = round(dimension / 12.0 * 100) / 100

            var railingLinearFt = linearFt
            if let stairConfig = edge.stairConfig {
                railingLinearFt = max(0, linearFt - round(stairConfig.width / 12.0 * 100) / 100)
            }

            items.append(GeneratedLineItem(
                name: "\(prefix)\(railing.railingType.displayName) Railing",
                description: edgeDescription(edge, drawingData: drawingData),
                type: .material,
                quantity: railingLinearFt,
                unit: "linear ft",
                unitPrice: 0,
                productId: nil,
                taskTypeId: nil,
                category: "Railing",
                sortOrder: sortOrder,
                isOptional: false
            ))
            sortOrder += 1

            let postCount = DimensionEngine.postCount(edgeLengthInches: dimension, maxSpacing: railing.maxPostSpacing)
            items.append(GeneratedLineItem(
                name: "\(prefix)\(railing.railingType.displayName) Railing Posts",
                description: "\(railing.railingType.displayName) posts at \(DimensionEngine.formatImperial(railing.maxPostSpacing)) max spacing",
                type: .material,
                quantity: Double(postCount),
                unit: "each",
                unitPrice: 0,
                productId: nil,
                taskTypeId: nil,
                category: "Railing",
                sortOrder: sortOrder,
                isOptional: false
            ))
            sortOrder += 1

            for item in railing.assignedItems {
                items.append(GeneratedLineItem(
                    name: "\(prefix)\(item.name)",
                    description: nil,
                    type: .material,
                    quantity: item.unitType == .linearFoot ? railingLinearFt : 1,
                    unit: item.unitType == .linearFoot ? "linear ft" : "each",
                    unitPrice: item.unitPrice ?? 0,
                    productId: item.productId,
                    taskTypeId: item.taskTypeId,
                    category: "Railing",
                    sortOrder: sortOrder,
                    isOptional: false
                ))
                sortOrder += 1
            }
        }

        // 4. Stairs (from edge stair configs)
        for edge in edges {
            guard let stairConfig = edge.stairConfig else { continue }

            guard let totalRise = calculateTotalRise(edge: edge, drawingData: drawingData) else {
                // Missing elevation — add a warning line item instead of guessing
                var warning = GeneratedLineItem(
                    name: "\(prefix)Stairs (missing elevation)",
                    description: "Set deck height to calculate stair dimensions",
                    type: .material, quantity: 0, unit: "each",
                    unitPrice: 0, productId: nil, taskTypeId: nil, category: "Stairs",
                    sortOrder: sortOrder, isOptional: false
                )
                warning.warning = "Set deck height — stair calculations require elevation."
                items.append(warning)
                sortOrder += 1
                continue
            }

            let treadCount: Int
            if let override = stairConfig.treadCount, override > 0 {
                treadCount = override
            } else {
                treadCount = StairConfig.calculateTreadCount(totalRise: totalRise, risePerStep: stairConfig.risePerStep)
            }

            let stringerLength = StairConfig.stringerLength(totalRise: totalRise, treadCount: treadCount, runPerTread: stairConfig.runPerTread)
            let stringerCount = StairConfig.stringerCount(width: stairConfig.width)

            items.append(GeneratedLineItem(
                name: "\(prefix)Stair Treads",
                description: "\(treadCount) treads, \(DimensionEngine.formatImperial(stairConfig.runPerTread)) run each",
                type: .material, quantity: Double(treadCount), unit: "each",
                unitPrice: 0, productId: nil, taskTypeId: nil, category: "Stairs",
                sortOrder: sortOrder, isOptional: false
            ))
            sortOrder += 1

            items.append(GeneratedLineItem(
                name: "\(prefix)Stair Stringers",
                description: "\(DimensionEngine.formatImperial(stringerLength)) stringer length",
                type: .material, quantity: Double(stringerCount), unit: "each",
                unitPrice: 0, productId: nil, taskTypeId: nil, category: "Stairs",
                sortOrder: sortOrder, isOptional: false
            ))
            sortOrder += 1

            if let stairRailing = stairConfig.railingConfig {
                let stairRailingLengthFt = (stringerLength / 12.0) * 2
                items.append(GeneratedLineItem(
                    name: "\(prefix)Stair \(stairRailing.railingType.displayName) Railing",
                    description: "Both sides of stairs",
                    type: .material, quantity: round(stairRailingLengthFt * 100) / 100, unit: "linear ft",
                    unitPrice: 0, productId: nil, taskTypeId: nil, category: "Stairs",
                    sortOrder: sortOrder, isOptional: false
                ))
                sortOrder += 1

                let stairPostCount = StairCalculator.railingPostCount(stringerLength: stringerLength, maxSpacing: stairRailing.maxPostSpacing) * 2
                items.append(GeneratedLineItem(
                    name: "\(prefix)Stair Railing Posts",
                    description: nil, type: .material, quantity: Double(stairPostCount), unit: "each",
                    unitPrice: 0, productId: nil, taskTypeId: nil, category: "Stairs",
                    sortOrder: sortOrder, isOptional: false
                ))
                sortOrder += 1
            }

            for item in stairConfig.assignedItems {
                let qty: Double
                let unitStr: String
                switch item.unitType {
                case .each: qty = 1; unitStr = "each"
                case .set:  qty = 1; unitStr = "set"
                default:    qty = Double(treadCount); unitStr = "each"
                }
                items.append(GeneratedLineItem(
                    name: "\(prefix)\(item.name)",
                    description: "Stairs", type: .material, quantity: qty, unit: unitStr,
                    unitPrice: item.unitPrice ?? 0, productId: item.productId,
                    taskTypeId: item.taskTypeId,
                    category: "Stairs",
                    sortOrder: sortOrder, isOptional: false
                ))
                sortOrder += 1
            }
        }

        // 5. Other edge assigned items
        for edge in edges {
            guard let dimension = edge.dimension else { continue }
            for item in edge.assignedItems {
                let quantity: Double
                let unit: String
                switch item.unitType {
                case .linearFoot, .linearMeter:
                    quantity = round(dimension / 12.0 * 100) / 100; unit = "linear ft"
                case .each:  quantity = 1; unit = "each"
                case .set:   quantity = 1; unit = "set"
                default:     quantity = 1; unit = "each"
                }
                items.append(GeneratedLineItem(
                    name: "\(prefix)\(item.name)",
                    description: edgeDescription(edge, drawingData: drawingData),
                    type: .material, quantity: quantity, unit: unit,
                    unitPrice: item.unitPrice ?? 0, productId: item.productId,
                    taskTypeId: item.taskTypeId,
                    category: "Other",
                    sortOrder: sortOrder, isOptional: false
                ))
                sortOrder += 1
            }
        }

        return (items, sortOrder)
    }

    /// Group flat line items by taskTypeId into parent-child bundles
    static func groupByTaskType(
        _ items: [GeneratedLineItem],
        taskTypes: [TaskType]
    ) -> [GeneratedEstimateGroup] {
        let grouped = Dictionary(grouping: items, by: { $0.taskTypeId ?? "__misc__" })
        var groups: [GeneratedEstimateGroup] = []

        for (key, children) in grouped.sorted(by: { $0.key < $1.key }) {
            let taskTypeId: String? = key == "__misc__" ? nil : key
            let taskTypeName: String
            if let id = taskTypeId,
               let tt = taskTypes.first(where: { $0.id == id && $0.deletedAt == nil }) {
                taskTypeName = tt.display
            } else {
                taskTypeName = "Misc"
            }
            let total = children.reduce(0.0) { $0 + ($1.quantity * $1.unitPrice) }
            groups.append(GeneratedEstimateGroup(
                taskTypeId: taskTypeId,
                taskTypeName: taskTypeName,
                children: children,
                parentTotal: round(total * 100) / 100
            ))
        }

        return groups
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
        if drawingData.isMultiLevel {
            for level in drawingData.levels {
                if !level.footprint.assignedItems.isEmpty { return true }
                if level.edges.contains(where: { $0.railingConfig != nil }) { return true }
                if level.edges.contains(where: { $0.stairConfig != nil }) { return true }
                if level.edges.contains(where: { !$0.assignedItems.isEmpty }) { return true }
                if level.vertices.contains(where: { $0.footingType != nil }) { return true }
            }
            if !drawingData.levelConnections.isEmpty { return true }
            return false
        }
        if !drawingData.footprint.assignedItems.isEmpty { return true }
        if drawingData.edges.contains(where: { $0.railingConfig != nil }) { return true }
        if drawingData.edges.contains(where: { $0.stairConfig != nil }) { return true }
        if drawingData.edges.contains(where: { !$0.assignedItems.isEmpty }) { return true }
        if drawingData.vertices.contains(where: { $0.footingType != nil }) { return true }
        return false
    }

    /// Generate AR accuracy internal note if applicable
    static func arAccuracyNote(from drawingData: DeckDrawingData) -> String? {
        let arEdges = drawingData.allEdges.filter { $0.accuracyPercent != nil }
        guard !arEdges.isEmpty else { return nil }
        let maxAccuracy = arEdges.compactMap { $0.accuracyPercent }.max() ?? 3.0
        return "Note: Some measurements in this estimate were captured via AR and have an accuracy of \u{00B1}\(Int(maxAccuracy))%. Verify dimensions before ordering materials."
    }

    // MARK: - Geometry Helpers

    static func calculateAreaSqFt(drawingData: DeckDrawingData) -> Double {
        guard let scale = drawingData.scaleFactor, scale > 0 else { return 0 }
        if drawingData.isMultiLevel {
            return drawingData.levels.reduce(0) { total, level in
                let positions = level.orderedPositions
                // Skip unclosed and self-intersecting levels — both produce
                // shoelace values that are mathematically meaningless for area.
                guard level.isClosed,
                      positions.count >= 3,
                      !PolygonMath.isSelfIntersecting(vertices: positions) else { return total }
                return total + PolygonMath.realWorldArea(vertices: positions, scaleFactor: scale) / 144.0
            }
        }
        guard drawingData.isClosed else { return 0 }
        let positions = drawingData.orderedPositions
        guard !PolygonMath.isSelfIntersecting(vertices: positions) else { return 0 }
        return PolygonMath.realWorldArea(vertices: positions, scaleFactor: scale) / 144.0
    }

    static func calculatePerimeterFt(drawingData: DeckDrawingData) -> Double {
        let edges = drawingData.isMultiLevel ? drawingData.allEdges : drawingData.edges
        var totalInches = 0.0
        for edge in edges {
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

    /// Calculate total rise for stairs on an edge (in inches). Returns nil if elevation is not set.
    static func calculateTotalRise(edge: DeckEdge, drawingData: DeckDrawingData) -> Double? {
        // Get elevation from connected vertices (elevation is in feet)
        if let startVertex = drawingData.vertex(byId: edge.startVertexId),
           let endVertex = drawingData.vertex(byId: edge.endVertexId) {
            guard let overallElev = drawingData.overallElevation else { return nil }
            let startElev = startVertex.elevation ?? overallElev
            let endElev = endVertex.elevation ?? overallElev
            return max(startElev, endElev) * 12.0 // feet to inches
        }
        guard let overallElev = drawingData.overallElevation else { return nil }
        return overallElev * 12.0
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
