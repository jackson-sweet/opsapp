// OPS/OPS/DeckBuilder/Engine/EstimateGeneratorService.swift

import Foundation

public struct EstimateGeneratorService {

    public enum DeckEstimateLineType: String, Codable, CaseIterable {
        case labor = "LABOR"
        case material = "MATERIAL"
        case other = "OTHER"
    }

    public struct DeckTaskTypeSummary: Equatable {
        public let id: String
        public let display: String
        public let deletedAt: Date?

        public init(id: String, display: String, deletedAt: Date? = nil) {
            self.id = id
            self.display = display
            self.deletedAt = deletedAt
        }
    }

    /// A generated line item ready for estimate creation
    public struct GeneratedLineItem {
        public let name: String
        public let description: String?
        public let type: DeckEstimateLineType
        public let quantity: Double
        public let unit: String           // "linear ft", "sq ft", "each", "set"
        public let unitPrice: Double
        public let productId: String?
        public let taskTypeId: String?    // task type from the assigned product
        public let category: String       // "Surface", "Railing", "Stairs", "Substructure", "Other"
        public let sortOrder: Int
        public let isOptional: Bool
        public var warning: String?       // validation warning (e.g., missing elevation)

        public init(
            name: String,
            description: String?,
            type: DeckEstimateLineType,
            quantity: Double,
            unit: String,
            unitPrice: Double,
            productId: String?,
            taskTypeId: String?,
            category: String,
            sortOrder: Int,
            isOptional: Bool,
            warning: String? = nil
        ) {
            self.name = name
            self.description = description
            self.type = type
            self.quantity = quantity
            self.unit = unit
            self.unitPrice = unitPrice
            self.productId = productId
            self.taskTypeId = taskTypeId
            self.category = category
            self.sortOrder = sortOrder
            self.isOptional = isOptional
            self.warning = warning
        }
    }

    /// Grouped line items by task type for parent-child estimate creation
    public struct GeneratedEstimateGroup {
        public let taskTypeId: String?
        public let taskTypeName: String
        public let children: [GeneratedLineItem]
        public var parentTotal: Double

        public init(
            taskTypeId: String?,
            taskTypeName: String,
            children: [GeneratedLineItem],
            parentTotal: Double
        ) {
            self.taskTypeId = taskTypeId
            self.taskTypeName = taskTypeName
            self.children = children
            self.parentTotal = parentTotal
        }
    }

    /// Generate all line items from a deck drawing
    /// - Parameter drawingData: The complete deck drawing with all assignments
    /// - Returns: Ordered array of line items ready for estimate creation
    public static func generateLineItems(from drawingData: DeckDrawingData) -> [GeneratedLineItem] {
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
            persistedSurfaces: drawingData.surfaces,
            detectedSurfaces: drawingData.detectedSurfaces,
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
                persistedSurfaces: level.surfaces,
                detectedSurfaces: level.detectedSurfaces,
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
        persistedSurfaces: [DeckSurface],
        detectedSurfaces: [DetectedSurface],
        levelPrefix: String?,
        startingSortOrder: Int
    ) -> (items: [GeneratedLineItem], nextSortOrder: Int) {
        var items: [GeneratedLineItem] = []
        var sortOrder = startingSortOrder
        let prefix = levelPrefix.map { "\($0) \u{2014} " } ?? ""

        // 1. Surface items — per-surface materials & areas (DECK-NEW-1
        //    follow-up). Iterates the persisted DeckSurface store; each
        //    surface is matched to a detected face by vertex set so the
        //    area used for billing is THIS surface's area, not the whole
        //    polygon's. Falls back to the legacy single-footprint payload
        //    only when the persisted store is empty (e.g. a drawing that
        //    was generated before reconcile was first run).
        let perSurfaceItems = perSurfaceLineItems(
            persistedSurfaces: persistedSurfaces,
            detectedSurfaces: detectedSurfaces,
            scaleFactor: drawingData.effectiveScaleFactor,
            prefix: prefix,
            startingSortOrder: sortOrder
        )
        items.append(contentsOf: perSurfaceItems.items)
        sortOrder = perSurfaceItems.nextSortOrder

        // Legacy footprint fallback — only when no per-surface payload
        // exists. Same area math as before so unmigrated drawings still
        // produce identical estimates.
        if persistedSurfaces.isEmpty {
            for item in footprint.assignedItems {
                let areaSqFt: Double
                if levelPrefix != nil {
                    guard isPolygonClosed,
                          orderedPositions.count >= 3,
                          !PolygonMath.isSelfIntersecting(vertices: orderedPositions) else { continue }
                    areaSqFt = PolygonMath.realWorldArea(vertices: orderedPositions, scaleFactor: drawingData.effectiveScaleFactor) / 144.0
                } else {
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
            guard edge.edgeType == .deckEdge,
                  let railing = edge.railingConfig,
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
    public static func groupByTaskType(
        _ items: [GeneratedLineItem],
        taskTypes: [DeckTaskTypeSummary]
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
    public static func materialSummary(from drawingData: DeckDrawingData) -> String {
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
    public static func hasAssignments(_ drawingData: DeckDrawingData) -> Bool {
        if drawingData.isMultiLevel {
            for level in drawingData.levels {
                if !level.footprint.assignedItems.isEmpty { return true }
                if level.surfaces.contains(where: { !$0.assignedItems.isEmpty }) { return true }
                if level.edges.contains(where: { $0.railingConfig != nil }) { return true }
                if level.edges.contains(where: { $0.stairConfig != nil }) { return true }
                if level.edges.contains(where: { !$0.assignedItems.isEmpty }) { return true }
                if level.vertices.contains(where: { $0.footingType != nil }) { return true }
            }
            if !drawingData.levelConnections.isEmpty { return true }
            return false
        }
        if !drawingData.footprint.assignedItems.isEmpty { return true }
        if drawingData.surfaces.contains(where: { !$0.assignedItems.isEmpty }) { return true }
        if drawingData.edges.contains(where: { $0.railingConfig != nil }) { return true }
        if drawingData.edges.contains(where: { $0.stairConfig != nil }) { return true }
        if drawingData.edges.contains(where: { !$0.assignedItems.isEmpty }) { return true }
        if drawingData.vertices.contains(where: { $0.footingType != nil }) { return true }
        return false
    }

    /// Generate AR accuracy internal note if applicable
    public static func arAccuracyNote(from drawingData: DeckDrawingData) -> String? {
        let arEdges = drawingData.allEdges.filter { $0.accuracyPercent != nil }
        guard !arEdges.isEmpty else { return nil }
        let maxAccuracy = arEdges.compactMap { $0.accuracyPercent }.max() ?? 3.0
        return "Note: Some measurements in this estimate were captured via AR and have an accuracy of \u{00B1}\(Int(maxAccuracy))%. Verify dimensions before ordering materials."
    }

    // MARK: - Per-Surface Helpers (DECK-NEW-1 follow-up)

    /// Generates surface line items per persisted DeckSurface, matched to
    /// detected faces by vertex set. Each item is billed against the
    /// matching face's own real-world area, not the whole polygon. When a
    /// persisted surface has no detected match (e.g. transient state mid-
    /// edit before reconcile runs), it's skipped — `save()` will rebind
    /// it on the next pass.
    private static func perSurfaceLineItems(
        persistedSurfaces: [DeckSurface],
        detectedSurfaces: [DetectedSurface],
        scaleFactor: Double,
        prefix: String,
        startingSortOrder: Int
    ) -> (items: [GeneratedLineItem], nextSortOrder: Int) {
        guard !persistedSurfaces.isEmpty else {
            return (items: [], nextSortOrder: startingSortOrder)
        }

        var items: [GeneratedLineItem] = []
        var sortOrder = startingSortOrder

        for surface in persistedSurfaces {
            guard !surface.assignedItems.isEmpty else { continue }

            let dSet = surface.vertexIds
            let detected: DetectedSurface? = detectedSurfaces.first(where: { Set($0.vertexIds) == dSet })
                ?? detectedSurfaces
                    .filter { Set($0.vertexIds).intersection(dSet).count > 0 }
                    .max(by: { lhs, rhs in
                        let li = Set(lhs.vertexIds).intersection(dSet).count
                        let ri = Set(rhs.vertexIds).intersection(dSet).count
                        return li < ri
                    })
            guard let face = detected,
                  face.positions.count >= 3,
                  !PolygonMath.isSelfIntersecting(vertices: face.positions) else { continue }

            let areaSqFt = PolygonMath.realWorldArea(vertices: face.positions, scaleFactor: scaleFactor) / 144.0
            let surfaceLabel: String? = {
                if let l = surface.label?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty { return l }
                return nil
            }()

            for item in surface.assignedItems {
                let displayName: String
                if let label = surfaceLabel {
                    displayName = "\(prefix)\(label) \u{2014} \(item.name)"
                } else {
                    displayName = "\(prefix)\(item.name)"
                }
                items.append(GeneratedLineItem(
                    name: displayName,
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
        }

        return (items, sortOrder)
    }

    // MARK: - Geometry Helpers

    public static func calculateAreaSqFt(drawingData: DeckDrawingData) -> Double {
        // Sum every detected surface (per level in multi-level mode) instead of
        // shoelacing the outer perimeter. `isClosed`/`orderedPositions` rejects
        // any level whose graph isn't a single Hamiltonian cycle — i.e. every
        // multi-surface drawing since DECK-NEW-1 (an L-shape drawn as two loops
        // sharing an edge) — returning 0. `totalRealWorldArea` is the same
        // surface-aware computation the area badge and per-surface line items
        // already use; it returns square inches, so divide by 144 for sq ft.
        drawingData.totalRealWorldArea(scaleFactor: drawingData.effectiveScaleFactor) / 144.0
    }

    public static func calculatePerimeterFt(drawingData: DeckDrawingData) -> Double {
        // Every edge stores its length as real-world inches, either against
        // the calibrated scale factor or the prescale fallback. So the
        // perimeter is just the sum of edge dimensions; no canvas-points-to-
        // inches conversion is needed.
        let edges = drawingData.isMultiLevel ? drawingData.allEdges : drawingData.edges
        let totalInches = edges.reduce(0.0) { $0 + ($1.dimension ?? 0) }
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
    /// Searches across all levels in multi-level mode — `drawingData.vertex(byId:)`
    /// only checks the top-level array, so without this the multi-level path would
    /// always fall through to the overallElevation branch and use the wrong height.
    public static func calculateTotalRise(edge: DeckEdge, drawingData: DeckDrawingData) -> Double? {
        // Lookup helper that walks the active geometry source (single-level or
        // every level), plus the level whose elevation overrides per-vertex
        // elevation when per-vertex isn't enabled.
        func findVertexAndLevelElev(_ id: String) -> (vertex: DeckVertex, levelElev: Double?)? {
            if drawingData.isMultiLevel {
                for level in drawingData.levels {
                    if let v = level.vertex(byId: id) {
                        return (v, level.elevation)
                    }
                }
                return nil
            }
            if let v = drawingData.vertex(byId: id) {
                return (v, drawingData.overallElevation)
            }
            return nil
        }

        guard let startInfo = findVertexAndLevelElev(edge.startVertexId),
              let endInfo = findVertexAndLevelElev(edge.endVertexId) else {
            // Edge belongs to no known level — fall back to top-level elevation.
            guard let overallElev = drawingData.overallElevation else { return nil }
            return overallElev * 12.0
        }

        let startElev = startInfo.vertex.elevation ?? startInfo.levelElev ?? drawingData.overallElevation
        let endElev = endInfo.vertex.elevation ?? endInfo.levelElev ?? drawingData.overallElevation
        guard let s = startElev, let e = endElev else { return nil }
        // A stair is centered on its edge, so its representative rise is the
        // edge MIDPOINT height — the AVERAGE of the two endpoint elevations,
        // not the higher one. On a LEVEL edge (the common case) s == e, so this
        // is identical to before. On a SLOPED edge (per-vertex elevation, or a
        // multi-level edge bridging heights) `max` over-counted by biasing to
        // the taller endpoint, inflating tread/riser/stringer quantities; the
        // mid-edge average is the physically correct rise the stair sits at.
        return (s + e) / 2.0 * 12.0  // feet to inches
    }

    private static func edgeDescription(_ edge: DeckEdge, drawingData: DeckDrawingData) -> String? {
        guard let dim = edge.dimension else { return nil }
        return DimensionEngine.format(dim, system: drawingData.config.measurementSystem)
    }
}

// MARK: - FootingType Display Name

extension FootingType {
    public var displayName: String {
        switch self {
        case .helicalPile: return "Helical Pile"
        case .sonoTube: return "Sono Tube"
        case .concretePad: return "Concrete Pad"
        }
    }
}
