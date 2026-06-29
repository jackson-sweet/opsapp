//
//  ComponentEmitter.swift
//  OPS
//
//  Projects a DeckDrawingData into the catalog adapter's `components`
//  vocabulary — one row per visible component (railing, deck_board,
//  stair_set, gate, post_set) plus additive structural framing rows with
//  metadata keys the adapter consumes.
//
//  Pure projection — no source-of-truth duplication. Recomputed from
//  geometry on every save via DeckDrawingData.toJSON().
//
//  Spec: docs/superpowers/specs/2026-05-07-deck-builder-catalog-integration-design.md
//  Adapter contract: OPS/Services/DesignToEstimateAdapter.swift
//

import Foundation
import CoreGraphics

public enum ComponentEmitter {

    /// Default residential gate width (inches) — used to subtract gate span
    /// from a railing's `linear_feet` and to populate `gate.width`. The
    /// `AssignedItem` model doesn't yet carry a per-gate dimension; a future
    /// session can introduce one without breaking the metadata schema.
    public static let defaultGateWidthInches: Double = 36.0

    /// Returns the `components` array as Codable rows, ready for inclusion
    /// in DeckDrawingData's JSON. Pure function — no I/O, no side effects.
    /// Multi-level designs flatten components across levels with a
    /// `level_id` metadata key for downstream traceability.
    public static func emit(_ data: DeckDrawingData) -> [DesignComponentRow] {
        var rows: [DesignComponentRow] = []

        if data.isMultiLevel {
            for level in data.levels {
                rows.append(contentsOf: emitLevel(level: level, data: data))
            }
            for connection in data.levelConnections {
                if let row = emitConnectionStair(connection: connection, data: data) {
                    rows.append(row)
                }
            }
        } else {
            for edge in data.edges {
                rows.append(contentsOf: emitEdgeComponents(
                    edge: edge,
                    drawingData: data,
                    levelId: nil
                ))
            }
            rows.append(contentsOf: emitDeckBoardComponents(
                surfaces: data.surfaces,
                footprint: data.footprint,
                isClosed: data.isClosed,
                orderedPositions: data.orderedPositions,
                detectedSurfaces: data.detectedSurfaces,
                scaleFactor: data.effectiveScaleFactor,
                levelId: nil
            ))
        }

        if let framing = data.framing {
            rows.append(contentsOf: emitFramingComponents(
                framing,
                scaleFactor: data.effectiveScaleFactor
            ))
        }

        return rows
    }

    // MARK: - Level (multi-level)

    private static func emitLevel(level: DeckLevel, data: DeckDrawingData) -> [DesignComponentRow] {
        var rows: [DesignComponentRow] = []
        for edge in level.edges {
            rows.append(contentsOf: emitEdgeComponents(
                edge: edge,
                drawingData: data,
                levelId: level.id
            ))
        }
        rows.append(contentsOf: emitDeckBoardComponents(
            surfaces: level.surfaces,
            footprint: level.footprint,
            isClosed: level.isClosed,
            orderedPositions: level.orderedPositions,
            detectedSurfaces: level.detectedSurfaces,
            scaleFactor: data.effectiveScaleFactor,
            levelId: level.id
        ))
        return rows
    }

    // MARK: - Edge components

    /// Emits all components attached to a single edge: railing, post_set
    /// (for post-supported railings), stair_set, and gate (one per
    /// `isGate`-flagged item).
    /// `linear_feet` on the railing is the edge length minus any stair
    /// span and minus all gate widths, mirroring the legacy estimate's
    /// stair-subtraction rule and extending it for gates.
    private static func emitEdgeComponents(
        edge: DeckEdge,
        drawingData: DeckDrawingData,
        levelId: String?
    ) -> [DesignComponentRow] {
        var rows: [DesignComponentRow] = []
        guard let edgeInches = edge.dimension, edgeInches > 0 else { return rows }

        let gateItems = edge.assignedItems.filter { $0.isGate }
        let totalGateInches = Double(gateItems.count) * defaultGateWidthInches
        let stairInches = edge.stairConfig?.width ?? 0

        // Railing component. House edges are wall/cladding boundaries, not
        // deck railing targets. Parapet walls intentionally do not emit a
        // post_set because they are continuous low walls, not post-supported
        // rail systems.
        if let railing = edge.railingConfig, edge.edgeType == .deckEdge {
            let netLengthInches = max(0, edgeInches - totalGateInches - stairInches)
            let linearFt = round((netLengthInches / 12.0) * 100) / 100

            // Per-edge corners_count is 0: corners live at vertices shared
            // between edges, not within an edge's interior. The catalog
            // model treats corner hardware as a Product option that the user
            // can enter on the line item form for designs where it matters.
            var meta: [String: AnyCodable] = [
                "linear_feet": AnyCodable(linearFt),
                "corners_count": AnyCodable(0),
                "color": AnyCodable(railing.color),
                "mount_type": AnyCodable(railing.mountType),
                "mount_surface": AnyCodable(railing.mountSurface),
                "frame_style": AnyCodable(railing.frameStyle.rawValue),
                "mount_placement": AnyCodable(railing.mountPlacement.rawValue),
                "edge_id": AnyCodable(edge.id),
            ]
            if railing.railingType == .parapetWall {
                meta["wall_material"] = AnyCodable(railing.wallMaterial.rawValue)
            }
            if let levelId = levelId { meta["level_id"] = AnyCodable(levelId) }
            rows.append(DesignComponentRow(componentType: "railing", metadata: meta))

            if railing.railingType != .parapetWall {
                let postCount = DimensionEngine.postCount(
                    edgeLengthInches: edgeInches,
                    maxSpacing: railing.maxPostSpacing
                )
                var postMeta: [String: AnyCodable] = [
                    "count": AnyCodable(postCount),
                    "height": AnyCodable(railing.postHeight),
                    "color": AnyCodable(railing.color),
                    "mount_type": AnyCodable(railing.mountType),
                    "mount_placement": AnyCodable(railing.mountPlacement.rawValue),
                    "edge_id": AnyCodable(edge.id),
                ]
                if let levelId = levelId { postMeta["level_id"] = AnyCodable(levelId) }
                rows.append(DesignComponentRow(componentType: "post_set", metadata: postMeta))
            }
        }

        // Stair set (per-edge stairs — distinct from level connection stairs)
        if let stair = edge.stairConfig {
            let totalRise = EstimateGeneratorService.calculateTotalRise(
                edge: edge,
                drawingData: drawingData
            )
            let resolvedTreadCount: Int
            if let override = stair.treadCount, override > 0 {
                resolvedTreadCount = override
            } else if let rise = totalRise, rise > 0 {
                resolvedTreadCount = StairConfig.calculateTreadCount(
                    totalRise: rise,
                    risePerStep: stair.risePerStep
                )
            } else {
                resolvedTreadCount = 0
            }

            var meta: [String: AnyCodable] = [
                "tread_count": AnyCodable(resolvedTreadCount),
                "width": AnyCodable(stair.width),
                "color": AnyCodable(stair.color),
                "mount_type": AnyCodable(stair.mountType),
                "stringer_style": AnyCodable(stair.stringerStyle.rawValue),
                "stringer_material": AnyCodable(stair.stringerMaterial.rawValue),
                "tread_material": AnyCodable(stair.treadMaterial.rawValue),
                "edge_id": AnyCodable(edge.id),
            ]
            if let levelId = levelId { meta["level_id"] = AnyCodable(levelId) }
            rows.append(DesignComponentRow(componentType: "stair_set", metadata: meta))
        }

        // Gates — one component per gate-flagged AssignedItem on this edge.
        // count = 1 per row (each row is one gate); the railing's
        // linear_feet has already been reduced by every gate's width.
        for _ in gateItems {
            let railingColor = edge.railingConfig?.color ?? "Black"
            let railingMountType = edge.railingConfig?.mountType ?? "Topmount"
            let railingMountSurface = edge.railingConfig?.mountSurface ?? "Surface"
            let railingMountPlacement = edge.railingConfig?.mountPlacement ?? .topMounted

            var meta: [String: AnyCodable] = [
                "count": AnyCodable(1),
                "width": AnyCodable(defaultGateWidthInches),
                "color": AnyCodable(railingColor),
                "mount_type": AnyCodable(railingMountType),
                "mount_surface": AnyCodable(railingMountSurface),
                "mount_placement": AnyCodable(railingMountPlacement.rawValue),
                "edge_id": AnyCodable(edge.id),
            ]
            if let levelId = levelId { meta["level_id"] = AnyCodable(levelId) }
            rows.append(DesignComponentRow(componentType: "gate", metadata: meta))
        }

        return rows
    }

    // MARK: - Deck board components

    /// Emits one `deck_board` per `DeckSurface` matched to a detected
    /// closed face (sqft from per-face area), or one per legacy footprint
    /// when the surface store is empty and the polygon is closed.
    /// Surfaces with no detected match (transient mid-edit state) are
    /// skipped — `reconcileSurfaces()` rebinds them on the next save.
    private static func emitDeckBoardComponents(
        surfaces: [DeckSurface],
        footprint: DeckFootprint,
        isClosed: Bool,
        orderedPositions: [CGPoint],
        detectedSurfaces: [DetectedSurface],
        scaleFactor: Double,
        levelId: String?
    ) -> [DesignComponentRow] {
        var rows: [DesignComponentRow] = []

        if !surfaces.isEmpty {
            for surface in surfaces {
                let dSet = surface.vertexIds
                let detected: DetectedSurface? = detectedSurfaces.first(where: {
                    Set($0.vertexIds) == dSet
                }) ?? detectedSurfaces
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
                guard areaSqFt > 0 else { continue }

                var meta: [String: AnyCodable] = [
                    "sqft": AnyCodable(round(areaSqFt * 100) / 100),
                    "color": AnyCodable(surface.color),
                    "material": AnyCodable(surface.boardMaterial),
                    "surface_id": AnyCodable(surface.id),
                ]
                if let levelId = levelId { meta["level_id"] = AnyCodable(levelId) }
                rows.append(DesignComponentRow(componentType: "deck_board", metadata: meta))
            }
            return rows
        }

        // Legacy footprint fallback — only when no per-surface store exists.
        // Emit a single deck_board carrying the whole-polygon area; the
        // `surface_id` traceback uses a stable "footprint" sentinel so the
        // adapter's downstream logs can identify the source.
        guard isClosed,
              orderedPositions.count >= 3,
              !PolygonMath.isSelfIntersecting(vertices: orderedPositions) else {
            return rows
        }
        let areaSqFt = PolygonMath.realWorldArea(vertices: orderedPositions, scaleFactor: scaleFactor) / 144.0
        guard areaSqFt > 0 else { return rows }

        // Default vocabulary when the footprint carries no items — the
        // assignment store on the legacy footprint is `assignedItems`, none
        // of which carry color/material today. The defaults match the
        // surface defaults so the adapter sees a consistent vocabulary.
        var meta: [String: AnyCodable] = [
            "sqft": AnyCodable(round(areaSqFt * 100) / 100),
            "color": AnyCodable("Brown"),
            "material": AnyCodable("composite"),
            "surface_id": AnyCodable("footprint"),
        ]
        if let levelId = levelId { meta["level_id"] = AnyCodable(levelId) }
        rows.append(DesignComponentRow(componentType: "deck_board", metadata: meta))
        return rows
    }

    // MARK: - Connection stair (multi-level)

    /// Emits a `stair_set` for a `LevelConnection` — used in multi-level
    /// designs where the stair belongs to a between-levels traversal rather
    /// than an edge of a single level. `level_id` is set to the upper level
    /// per spec § 7.1 (stairs descend from the upper level to the lower).
    private static func emitConnectionStair(
        connection: LevelConnection,
        data: DeckDrawingData
    ) -> DesignComponentRow? {
        guard let rise = data.elevationDifference(
            upperLevelId: connection.upperLevelId,
            lowerLevelId: connection.lowerLevelId
        ), rise > 0 else { return nil }

        let stair = connection.stairConfig
        let resolvedTreadCount: Int
        if let override = stair.treadCount, override > 0 {
            resolvedTreadCount = override
        } else {
            resolvedTreadCount = StairConfig.calculateTreadCount(
                totalRise: rise,
                risePerStep: stair.risePerStep
            )
        }

        let meta: [String: AnyCodable] = [
            "tread_count": AnyCodable(resolvedTreadCount),
            "width": AnyCodable(stair.width),
            "color": AnyCodable(stair.color),
            "mount_type": AnyCodable(stair.mountType),
            "stringer_style": AnyCodable(stair.stringerStyle.rawValue),
            "stringer_material": AnyCodable(stair.stringerMaterial.rawValue),
            "tread_material": AnyCodable(stair.treadMaterial.rawValue),
            "level_id": AnyCodable(connection.upperLevelId),
            "connection_id": AnyCodable(connection.id),
        ]
        return DesignComponentRow(componentType: "stair_set", metadata: meta)
    }

    // MARK: - Framing components

    private static func emitFramingComponents(
        _ framing: FramingPlan,
        scaleFactor: Double
    ) -> [DesignComponentRow] {
        var rows: [DesignComponentRow] = []
        let safeScaleFactor = scaleFactor > 0 ? scaleFactor : 1

        for set in framing.members {
            for member in set.members {
                guard let componentType = framingComponentType(for: member.role) else { continue }

                let linearFeet = roundToTwo(memberLinearFeet(member, scaleFactor: safeScaleFactor))
                let meta: [String: AnyCodable] = [
                    "linear_feet": AnyCodable(linearFeet),
                    "nominal_size": nullableString(member.nominalSize?.rawValue),
                    "ply_count": AnyCodable(max(1, member.plyCount)),
                    "count": AnyCodable(1),
                    "species": nullableString(member.species?.rawValue ?? framing.loadPreset?.species.rawValue),
                    "grade": nullableString(member.grade?.rawValue ?? framing.loadPreset?.grade.rawValue),
                    "level_id": AnyCodable(set.levelId),
                    "member_id": AnyCodable(member.id),
                ]
                rows.append(DesignComponentRow(componentType: componentType, metadata: meta))
            }
        }

        return rows
    }

    private static func framingComponentType(for role: FramingRole) -> String? {
        switch role {
        case .joist:
            return "joist"
        case .beam:
            return "beam"
        case .post:
            return "post"
        case .rimBand:
            return "rim_joist"
        case .blocking:
            return "blocking"
        case .ledger, .bridging, .cantilever:
            return nil
        }
    }

    private static func memberLinearFeet(_ member: FramingMember, scaleFactor: Double) -> Double {
        let dx = member.end.x - member.start.x
        let dy = member.end.y - member.start.y
        return Double(hypot(dx, dy)) / scaleFactor / 12
    }

    private static func roundToTwo(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private static func nullableString(_ value: String?) -> AnyCodable {
        if let value { return AnyCodable(value) }
        return AnyCodable(NSNull())
    }
}

/// One row in `DeckDrawingData.components` — the projection
/// `DesignToEstimateAdapter` consumes. `componentType` matches the
/// catalog's `DesignComponentType` raw values (`railing`, `deck_board`,
/// `stair_set`, `gate`, `post_set`) plus additive structural rows (`joist`,
/// `beam`, `post`, `rim_joist`, `blocking`). Adding component_type strings
/// is fine; renaming is a contract break.
public struct DesignComponentRow: Codable, Equatable {
    public let componentType: String
    public let metadata: [String: AnyCodable]

    public enum CodingKeys: String, CodingKey {
        case componentType = "component_type"
        case metadata
    }

    public init(componentType: String, metadata: [String: AnyCodable]) {
        self.componentType = componentType
        self.metadata = metadata
    }
}

/// Thin Codable wrapper that round-trips Int / Double / String / Bool
/// through JSONEncoder/JSONDecoder. Kept narrow on purpose: the
/// components projection only needs scalar metadata values.
///
/// Also used by `ProductConfigurationResolver.Resolution.serializedOptions`
/// for line_item snapshot serialization (encode-only path).
public struct AnyCodable: Codable, Equatable {
    public let value: Any

    public init(_ v: Any) { self.value = v }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self.value = NSNull()
        } else if let b = try? c.decode(Bool.self) {
            self.value = b
        } else if let i = try? c.decode(Int.self) {
            self.value = i
        } else if let d = try? c.decode(Double.self) {
            self.value = d
        } else if let s = try? c.decode(String.self) {
            self.value = s
        } else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Unsupported AnyCodable scalar type"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let s as String: try c.encode(s)
        case let b as Bool:   try c.encode(b)
        case let i as Int:    try c.encode(i)
        case let d as Double: try c.encode(d)
        case is NSNull:       try c.encodeNil()
        default:              try c.encodeNil()
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (let l as String, let r as String): return l == r
        case (let l as Bool, let r as Bool):     return l == r
        case (let l as Int, let r as Int):       return l == r
        case (let l as Double, let r as Double): return l == r
        case (is NSNull, is NSNull):             return true
        default: return false
        }
    }
}
