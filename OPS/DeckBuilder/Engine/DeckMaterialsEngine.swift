// OPS/OPS/DeckBuilder/Engine/DeckMaterialsEngine.swift
//
// Pure computation of the deck-tab materials list (spec § 6): the vinyl cut plan
// (via the existing VinylCutListEngine), drip edge / clip / 90° flashing totals +
// stick counts, and glue buckets. Sits beside VinylCutListEngine; consumes the
// read-only inputs from DeckMaterialsInputBuilder and the vinyl set from
// DeckVinylDetection.
//
// Edge classification (first match wins, spec § 6.1), per vinyl surface face:
//   1. segment's vertex pair shared by ≥2 detected faces (interior seam) → none
//   2. matched edge is a house edge                                       → 90 flash
//   3. matched edge carries a parapet-wall railing                        → 90 flash
//   4. otherwise (incl. unmatched, stair-carrying, full span)             → drip + clip
// Interior test runs against ALL detected faces on the level (vinyl or not).
// Stairs are deliberately ignored — a stair-carrying edge gets drip across its
// full span like any other open edge.

import CoreGraphics
import Foundation

/// Seed-/label-independent fingerprint of a materials list, used to detect
/// design drift after ordering. Two lists match when their cut geometry,
/// flashing totals, glue area, and vinyl surface count agree within tolerance —
/// surface renames and offcut re-labeling never flag drift; geometry does.
struct DeckMaterialsDriftKey: Equatable {
    struct CutPair: Equatable {
        let lengthInches: Double
        let rollWidthInches: Double
    }

    /// Sorted (lengthInches, rollWidthInches) of ALL cut pieces (purchased +
    /// reused — offcut seeding re-labels provenance but never changes geometry).
    var cutPairs: [CutPair]
    var dripExactFeet: Double
    var ninetyExactFeet: Double
    var glueAreaSqFt: Double
    var vinylSurfaceCount: Int
    var directionSurfaces: [VinylSurfaceDirectionGeometrySnapshot]?
    var directionRegions: [VinylDirectionRegionSnapshot]?
    var directionTransitions: [VinylDirectionTransitionSnapshot]?

    static func == (lhs: DeckMaterialsDriftKey, rhs: DeckMaterialsDriftKey) -> Bool {
        guard lhs.vinylSurfaceCount == rhs.vinylSurfaceCount,
              lhs.cutPairs.count == rhs.cutPairs.count else { return false }
        for (a, b) in zip(lhs.cutPairs, rhs.cutPairs) {
            if abs(a.lengthInches - b.lengthInches) > 0.05 { return false }
            if abs(a.rollWidthInches - b.rollWidthInches) > 0.05 { return false }
        }
        if let lhsSurfaces = lhs.directionSurfaces,
           let rhsSurfaces = rhs.directionSurfaces {
            guard directionSurfacesEqual(lhsSurfaces, rhsSurfaces) else { return false }
        } else {
            // Additive compatibility for snapshots written before direction
            // geometry retained its enclosing-surface ownership.
            if let lhsRegions = lhs.directionRegions,
               let rhsRegions = rhs.directionRegions {
                guard directionRegionsEqual(lhsRegions, rhsRegions) else { return false }
            }
            if let lhsTransitions = lhs.directionTransitions,
               let rhsTransitions = rhs.directionTransitions {
                guard directionTransitionsEqual(lhsTransitions, rhsTransitions) else { return false }
            }
        }
        // Flashing/glue tolerance per spec § 8 (±0.1' feet, ±0.1 sq ft).
        return abs(lhs.dripExactFeet - rhs.dripExactFeet) <= 0.1
            && abs(lhs.ninetyExactFeet - rhs.ninetyExactFeet) <= 0.1
            && abs(lhs.glueAreaSqFt - rhs.glueAreaSqFt) <= 0.1
    }

    /// Builds a drift key from a stored ordered snapshot. Uses `driftCutGroups`
    /// (ALL cut pieces — purchased + intra-job reused), NOT the purchased-only
    /// `cutGroups`: the live drift key counts every cut piece, so comparing
    /// against purchased-only would drop intra-job reused strips and false-flag
    /// DESIGN CHANGED the instant a reuse deck is ordered. Clip mirrors drip, so
    /// only drip + 90 feet are compared.
    init(snapshot: DeckMaterialsSnapshot) {
        self.cutPairs = snapshot.driftCutGroups
            .flatMap { group in
                Array(repeating: CutPair(lengthInches: group.lengthInches, rollWidthInches: group.rollWidthInches),
                      count: max(0, group.count))
            }
            .sorted(by: DeckMaterialsDriftKey.cutPairOrder)
        self.dripExactFeet = snapshot.dripEdgeFeet
        self.ninetyExactFeet = snapshot.ninetyFeet
        self.glueAreaSqFt = snapshot.glueAreaSqFt
        // Read the count the snapshot STORED at order time — the live side sets
        // it from `vinylInputs.count`, so both agree. Reconstructing it from
        // `cutGroups` here would diverge whenever two surfaces share a label or a
        // degenerate surface dropped out of the plan, false-flagging drift.
        self.vinylSurfaceCount = snapshot.vinylSurfaceCount
        self.directionSurfaces = snapshot.vinylDirectionSurfaces
        self.directionRegions = snapshot.vinylDirectionRegions
        self.directionTransitions = snapshot.vinylDirectionTransitions
    }

    init(
        cutPairs: [CutPair],
        dripExactFeet: Double,
        ninetyExactFeet: Double,
        glueAreaSqFt: Double,
        vinylSurfaceCount: Int,
        directionSurfaces: [VinylSurfaceDirectionGeometrySnapshot]? = nil,
        directionRegions: [VinylDirectionRegionSnapshot]? = nil,
        directionTransitions: [VinylDirectionTransitionSnapshot]? = nil
    ) {
        self.cutPairs = cutPairs
        self.dripExactFeet = dripExactFeet
        self.ninetyExactFeet = ninetyExactFeet
        self.glueAreaSqFt = glueAreaSqFt
        self.vinylSurfaceCount = vinylSurfaceCount
        self.directionSurfaces = directionSurfaces
        self.directionRegions = directionRegions
        self.directionTransitions = directionTransitions
    }

    static func cutPairOrder(_ a: CutPair, _ b: CutPair) -> Bool {
        if abs(a.lengthInches - b.lengthInches) > 0.0001 { return a.lengthInches < b.lengthInches }
        return a.rollWidthInches < b.rollWidthInches
    }

    static func directionGeometry(
        for plan: VinylCutPlan
    ) -> (
        surfaces: [VinylSurfaceDirectionGeometrySnapshot],
        regions: [VinylDirectionRegionSnapshot],
        transitions: [VinylDirectionTransitionSnapshot]
    ) {
        let scaledPlanPoints = plan.surfaces.flatMap { surface in
            guard surface.scaleFactor > 0 else { return [VinylDirectionPointSnapshot]() }
            return surface.positions.map {
                VinylDirectionPointSnapshot(
                    xInches: Double($0.x) / surface.scaleFactor,
                    yInches: Double($0.y) / surface.scaleFactor
                )
            }
        }
        guard let planMinX = scaledPlanPoints.map(\.xInches).min(),
              let planMinY = scaledPlanPoints.map(\.yInches).min() else {
            return ([], [], [])
        }

        var surfaces: [VinylSurfaceDirectionGeometrySnapshot] = []

        for surface in plan.surfaces {
            guard surface.scaleFactor > 0 else { continue }

            func point(_ value: CGPoint) -> VinylDirectionPointSnapshot {
                VinylDirectionPointSnapshot(
                    xInches: (Double(value.x) / surface.scaleFactor) - planMinX,
                    yInches: (Double(value.y) / surface.scaleFactor) - planMinY
                )
            }

            var regions = surface.directionRegions.map { region in
                VinylDirectionRegionSnapshot(
                    runAngleDegrees: normalizedRunAngle(region.runAngleDegrees),
                    points: canonicalPolygon(region.polygon.map(point))
                )
            }
            regions.sort(by: directionRegionOrder)

            var transitions: [VinylDirectionTransitionSnapshot] = []
            for transition in surface.directionTransitions {
                for segment in transition.segments {
                    let rawStart = point(segment.start)
                    let rawEnd = point(segment.end)
                    let ordered = directionPointOrder(rawEnd, rawStart)
                        ? (start: rawEnd, end: rawStart)
                        : (start: rawStart, end: rawEnd)
                    transitions.append(
                        VinylDirectionTransitionSnapshot(
                            start: ordered.start,
                            end: ordered.end
                        )
                    )
                }
            }
            transitions.sort(by: directionTransitionOrder)

            surfaces.append(
                VinylSurfaceDirectionGeometrySnapshot(
                    surfaceId: surface.id,
                    boundary: canonicalPolygon(surface.positions.map(point)),
                    regions: regions,
                    transitions: transitions
                )
            )
        }

        surfaces.sort(by: directionSurfaceOrder)
        return (
            surfaces,
            surfaces.flatMap(\.regions).sorted(by: directionRegionOrder),
            surfaces.flatMap(\.transitions).sorted(by: directionTransitionOrder)
        )
    }

    private static func directionSurfacesEqual(
        _ lhs: [VinylSurfaceDirectionGeometrySnapshot],
        _ rhs: [VinylSurfaceDirectionGeometrySnapshot]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let canUseIds = lhs.allSatisfy { $0.surfaceId != nil }
            && rhs.allSatisfy { $0.surfaceId != nil }
        let orderedLhs = canUseIds ? lhs : lhs.sorted(by: directionSurfaceGeometryOrder)
        let orderedRhs = canUseIds ? rhs : rhs.sorted(by: directionSurfaceGeometryOrder)
        for (a, b) in zip(orderedLhs, orderedRhs) {
            if canUseIds, a.surfaceId != b.surfaceId { return false }
            guard directionPointsEqual(a.boundary, b.boundary),
                  directionRegionsEqual(a.regions, b.regions),
                  directionTransitionsEqual(a.transitions, b.transitions) else {
                return false
            }
        }
        return true
    }

    private static func directionRegionsEqual(
        _ lhs: [VinylDirectionRegionSnapshot],
        _ rhs: [VinylDirectionRegionSnapshot]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (a, b) in zip(lhs, rhs) {
            guard abs(a.runAngleDegrees - b.runAngleDegrees) <= 0.1,
                  a.points.count == b.points.count else { return false }
            for (aPoint, bPoint) in zip(a.points, b.points) {
                if abs(aPoint.xInches - bPoint.xInches) > 0.05 { return false }
                if abs(aPoint.yInches - bPoint.yInches) > 0.05 { return false }
            }
        }
        return true
    }

    private static func directionPointsEqual(
        _ lhs: [VinylDirectionPointSnapshot],
        _ rhs: [VinylDirectionPointSnapshot]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (a, b) in zip(lhs, rhs) {
            if abs(a.xInches - b.xInches) > 0.05 { return false }
            if abs(a.yInches - b.yInches) > 0.05 { return false }
        }
        return true
    }

    private static func directionTransitionsEqual(
        _ lhs: [VinylDirectionTransitionSnapshot],
        _ rhs: [VinylDirectionTransitionSnapshot]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (a, b) in zip(lhs, rhs) {
            if abs(a.start.xInches - b.start.xInches) > 0.05 { return false }
            if abs(a.start.yInches - b.start.yInches) > 0.05 { return false }
            if abs(a.end.xInches - b.end.xInches) > 0.05 { return false }
            if abs(a.end.yInches - b.end.yInches) > 0.05 { return false }
        }
        return true
    }

    private static func directionRegionOrder(
        _ lhs: VinylDirectionRegionSnapshot,
        _ rhs: VinylDirectionRegionSnapshot
    ) -> Bool {
        if abs(lhs.runAngleDegrees - rhs.runAngleDegrees) > 0.0001 {
            return lhs.runAngleDegrees < rhs.runAngleDegrees
        }
        if lhs.points.count != rhs.points.count { return lhs.points.count < rhs.points.count }
        for (a, b) in zip(lhs.points, rhs.points) {
            if abs(a.xInches - b.xInches) > 0.0001 { return a.xInches < b.xInches }
            if abs(a.yInches - b.yInches) > 0.0001 { return a.yInches < b.yInches }
        }
        return false
    }

    private static func directionSurfaceOrder(
        _ lhs: VinylSurfaceDirectionGeometrySnapshot,
        _ rhs: VinylSurfaceDirectionGeometrySnapshot
    ) -> Bool {
        if let lhsId = lhs.surfaceId, let rhsId = rhs.surfaceId, lhsId != rhsId {
            return lhsId < rhsId
        }
        return directionSurfaceGeometryOrder(lhs, rhs)
    }

    private static func directionSurfaceGeometryOrder(
        _ lhs: VinylSurfaceDirectionGeometrySnapshot,
        _ rhs: VinylSurfaceDirectionGeometrySnapshot
    ) -> Bool {
        if directionPointSequenceOrder(lhs.boundary, rhs.boundary) { return true }
        if directionPointSequenceOrder(rhs.boundary, lhs.boundary) { return false }
        if lhs.regions.count != rhs.regions.count { return lhs.regions.count < rhs.regions.count }
        for (a, b) in zip(lhs.regions, rhs.regions) {
            if directionRegionOrder(a, b) { return true }
            if directionRegionOrder(b, a) { return false }
        }
        if lhs.transitions.count != rhs.transitions.count {
            return lhs.transitions.count < rhs.transitions.count
        }
        for (a, b) in zip(lhs.transitions, rhs.transitions) {
            if directionTransitionOrder(a, b) { return true }
            if directionTransitionOrder(b, a) { return false }
        }
        return false
    }

    private static func directionTransitionOrder(
        _ lhs: VinylDirectionTransitionSnapshot,
        _ rhs: VinylDirectionTransitionSnapshot
    ) -> Bool {
        if directionPointOrder(lhs.start, rhs.start) { return true }
        if directionPointOrder(rhs.start, lhs.start) { return false }
        return directionPointOrder(lhs.end, rhs.end)
    }

    private static func directionPointOrder(
        _ lhs: VinylDirectionPointSnapshot,
        _ rhs: VinylDirectionPointSnapshot
    ) -> Bool {
        if abs(lhs.xInches - rhs.xInches) > 0.0001 { return lhs.xInches < rhs.xInches }
        return lhs.yInches < rhs.yInches
    }

    private static func canonicalPolygon(
        _ points: [VinylDirectionPointSnapshot]
    ) -> [VinylDirectionPointSnapshot] {
        guard points.count > 1 else { return points }
        let forward = canonicalRotation(points)
        let reverse = canonicalRotation(Array(points.reversed()))
        return directionPointSequenceOrder(reverse, forward) ? reverse : forward
    }

    private static func canonicalRotation(
        _ points: [VinylDirectionPointSnapshot]
    ) -> [VinylDirectionPointSnapshot] {
        guard let firstIndex = points.indices.min(by: {
            directionPointOrder(points[$0], points[$1])
        }) else { return points }
        return Array(points[firstIndex...]) + Array(points[..<firstIndex])
    }

    private static func directionPointSequenceOrder(
        _ lhs: [VinylDirectionPointSnapshot],
        _ rhs: [VinylDirectionPointSnapshot]
    ) -> Bool {
        if lhs.count != rhs.count { return lhs.count < rhs.count }
        for (a, b) in zip(lhs, rhs) {
            if directionPointOrder(a, b) { return true }
            if directionPointOrder(b, a) { return false }
        }
        return false
    }

    private static func normalizedRunAngle(_ angle: Double) -> Double {
        var normalized = angle.truncatingRemainder(dividingBy: 180)
        if normalized < 0 { normalized += 180 }
        return abs(normalized - 180) < 0.001 ? 0 : normalized
    }
}

/// The computed materials list. `FlashingLine` carries pre-rounding exact feet
/// (for drift + tests) alongside the display-ready whole feet and stick count.
struct DeckMaterialsList: Equatable {
    struct FlashingLine: Equatable {
        var exactFeet: Double        // pre-rounding sum
        var displayFeet: Int         // Int(ceil(exactFeet)); 0 → row shows "—"
        var stickFeet: Double
        var sticks: Int              // ceil(exactFeet / stickFeet); 0 when exactFeet == 0
    }

    var vinylPlan: VinylCutPlan
    var vinylSurfaceIds: Set<String>
    /// Whole rolls to order when `settings.orderMode == .fullRolls` (the plan's
    /// purchased strips packed into `settings.fullRollLengthFeet` rolls). 0 in
    /// cut-list mode — a purchasing figure only, it never feeds the drift key.
    var rollCount: Int
    /// Purchased strips longer than a single full roll (cannot be produced at the
    /// current roll length). Drives the CUT LONGER THAN ROLL warning; 0 in
    /// cut-list mode.
    var overlengthStripCount: Int
    var dripEdge: FlashingLine
    var clip: FlashingLine           // same exactFeet as dripEdge, own stick math
    var ninetyFlash: FlashingLine
    var glueAreaSqFt: Double
    var glueBuckets: Int
    var driftKey: DeckMaterialsDriftKey
}

enum DeckMaterialsEngine {

    static func compute(
        vinylInputs: [VinylOrderSurfaceInput],        // vinyl set only
        allDetectedFacesByLevel: [[DetectedSurface]], // interior-seam test (ALL faces, vinyl or not)
        settings: DeckMaterialsSettings,
        vinylSettings: VinylOrderSettings
    ) -> DeckMaterialsList {
        let interior = interiorPairKeys(allDetectedFacesByLevel)

        var dripFeetExact = 0.0
        var ninetyFeetExact = 0.0

        for input in vinylInputs {
            for edge in input.edges {
                // 1. Interior seam — shared boundary pair, no flashing.
                if let s = edge.startVertexId, let e = edge.endVertexId,
                   interior.contains(Self.pairKey(s, e)) {
                    continue
                }
                let feet = segmentLengthInches(edge, scale: input.scaleFactor) / 12.0
                // 2 & 3. House edge or parapet → 90 flash.
                if edge.edgeType == .houseEdge || edge.isParapet {
                    ninetyFeetExact += feet
                } else {
                    // 4. Open edge (incl. stair-carrying, unmatched) → drip + clip.
                    dripFeetExact += feet
                }
            }
        }

        let dripLine = flashingLine(exactFeet: dripFeetExact, stickFeet: settings.dripStickFeet)
        let clipLine = flashingLine(exactFeet: dripFeetExact, stickFeet: settings.clipStickFeet)
        let ninetyLine = flashingLine(exactFeet: ninetyFeetExact, stickFeet: settings.ninetyStickFeet)

        // Glue: actual vinyl SURFACE area, not ordered-with-waste area.
        var glueAreaSqFt = 0.0
        for input in vinylInputs {
            guard !PolygonMath.isSelfIntersecting(vertices: input.positions) else { continue }
            glueAreaSqFt += PolygonMath.realWorldArea(vertices: input.positions, scaleFactor: input.scaleFactor) / 144.0
        }
        let glueBuckets = settings.glueCoverageSqFt > 0 && glueAreaSqFt > 0
            ? Int(ceil(glueAreaSqFt / settings.glueCoverageSqFt))
            : 0

        let plan = VinylCutListEngine.makePlan(surfaces: vinylInputs, settings: vinylSettings)

        // Full-roll ordering (spec § 4.2): pack the plan's PURCHASED strips into
        // whole rolls of `fullRollLengthFeet`. Cut-list mode leaves both fields 0.
        // `orderMode` is a purchasing choice and never touches the plan or the
        // drift key below — switching modes must not flag DESIGN CHANGED.
        let rollPack: RollPackResult = settings.orderMode == .fullRolls
            ? VinylRollPacker.rollsNeeded(
                stripLengthsFeet: plan.surfaces.flatMap(\.purchasedCuts).map { $0.lengthInches / 12.0 },
                rollLengthFeet: settings.fullRollLengthFeet
            )
            : RollPackResult(rollCount: 0, overlengthStripCount: 0)

        let directionGeometry = DeckMaterialsDriftKey.directionGeometry(for: plan)
        let driftKey = DeckMaterialsDriftKey(
            cutPairs: plan.surfaces
                .flatMap(\.cuts)
                .map { DeckMaterialsDriftKey.CutPair(lengthInches: $0.lengthInches, rollWidthInches: $0.rollWidthInches) }
                .sorted(by: DeckMaterialsDriftKey.cutPairOrder),
            dripExactFeet: dripFeetExact,
            ninetyExactFeet: ninetyFeetExact,
            glueAreaSqFt: glueAreaSqFt,
            vinylSurfaceCount: vinylInputs.count,
            directionSurfaces: directionGeometry.surfaces,
            directionRegions: directionGeometry.regions,
            directionTransitions: directionGeometry.transitions
        )

        return DeckMaterialsList(
            vinylPlan: plan,
            vinylSurfaceIds: Set(vinylInputs.map(\.id)),
            rollCount: rollPack.rollCount,
            overlengthStripCount: rollPack.overlengthStripCount,
            dripEdge: dripLine,
            clip: clipLine,
            ninetyFlash: ninetyLine,
            glueAreaSqFt: glueAreaSqFt,
            glueBuckets: glueBuckets,
            driftKey: driftKey
        )
    }

    // MARK: - Helpers

    private static func flashingLine(exactFeet: Double, stickFeet: Double) -> DeckMaterialsList.FlashingLine {
        let displayFeet = exactFeet > 0 ? Int(ceil(exactFeet)) : 0
        let sticks = (exactFeet > 0 && stickFeet > 0) ? max(0, Int(ceil(exactFeet / stickFeet))) : 0
        return DeckMaterialsList.FlashingLine(
            exactFeet: exactFeet,
            displayFeet: displayFeet,
            stickFeet: stickFeet,
            sticks: sticks
        )
    }

    /// Real-world length of a segment in inches: the matched edge's dimension
    /// when present, else canvas length ÷ scale (mirrors DeckTabView.edgeLengthInches).
    private static func segmentLengthInches(_ edge: VinylOrderSurfaceEdge, scale: Double) -> Double {
        if let dim = edge.dimensionInches, dim > 0 { return dim }
        guard scale > 0 else { return 0 }
        return SnapEngine.distance(edge.start, edge.end) / scale
    }

    /// Canonical `"minId|maxId"` key for an unordered vertex pair.
    private static func pairKey(_ a: String, _ b: String) -> String {
        a <= b ? "\(a)|\(b)" : "\(b)|\(a)"
    }

    /// Vertex-pair keys that bound ≥2 detected faces on the same level — interior
    /// seams. Vertex ids are level-unique (each level owns its vertices), so a
    /// global count across all levels equals a per-level count.
    private static func interiorPairKeys(_ facesByLevel: [[DetectedSurface]]) -> Set<String> {
        var counts: [String: Int] = [:]
        for faces in facesByLevel {
            for face in faces {
                let ids = face.vertexIds
                guard ids.count >= 2 else { continue }
                for i in ids.indices {
                    let a = ids[i]
                    let b = ids[(i + 1) % ids.count]
                    counts[pairKey(a, b), default: 0] += 1
                }
            }
        }
        return Set(counts.filter { $0.value >= 2 }.keys)
    }
}
