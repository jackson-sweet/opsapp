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

    static func == (lhs: DeckMaterialsDriftKey, rhs: DeckMaterialsDriftKey) -> Bool {
        guard lhs.vinylSurfaceCount == rhs.vinylSurfaceCount,
              lhs.cutPairs.count == rhs.cutPairs.count else { return false }
        for (a, b) in zip(lhs.cutPairs, rhs.cutPairs) {
            if abs(a.lengthInches - b.lengthInches) > 0.05 { return false }
            if abs(a.rollWidthInches - b.rollWidthInches) > 0.05 { return false }
        }
        // Flashing/glue tolerance per spec § 8 (±0.1' feet, ±0.1 sq ft).
        return abs(lhs.dripExactFeet - rhs.dripExactFeet) <= 0.1
            && abs(lhs.ninetyExactFeet - rhs.ninetyExactFeet) <= 0.1
            && abs(lhs.glueAreaSqFt - rhs.glueAreaSqFt) <= 0.1
    }

    /// Builds a drift key from a stored ordered snapshot. Its `cutGroups` are
    /// purchased-only, which equals the read-only tab's cut set (no offcut seeds
    /// there). Clip mirrors drip, so only drip + 90 feet are compared.
    init(snapshot: DeckMaterialsSnapshot) {
        self.cutPairs = snapshot.cutGroups
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
    }

    init(cutPairs: [CutPair], dripExactFeet: Double, ninetyExactFeet: Double, glueAreaSqFt: Double, vinylSurfaceCount: Int) {
        self.cutPairs = cutPairs
        self.dripExactFeet = dripExactFeet
        self.ninetyExactFeet = ninetyExactFeet
        self.glueAreaSqFt = glueAreaSqFt
        self.vinylSurfaceCount = vinylSurfaceCount
    }

    static func cutPairOrder(_ a: CutPair, _ b: CutPair) -> Bool {
        if abs(a.lengthInches - b.lengthInches) > 0.0001 { return a.lengthInches < b.lengthInches }
        return a.rollWidthInches < b.rollWidthInches
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

        let driftKey = DeckMaterialsDriftKey(
            cutPairs: plan.surfaces
                .flatMap(\.cuts)
                .map { DeckMaterialsDriftKey.CutPair(lengthInches: $0.lengthInches, rollWidthInches: $0.rollWidthInches) }
                .sorted(by: DeckMaterialsDriftKey.cutPairOrder),
            dripExactFeet: dripFeetExact,
            ninetyExactFeet: ninetyFeetExact,
            glueAreaSqFt: glueAreaSqFt,
            vinylSurfaceCount: vinylInputs.count
        )

        return DeckMaterialsList(
            vinylPlan: plan,
            vinylSurfaceIds: Set(vinylInputs.map(\.id)),
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
