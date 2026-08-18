// OPS/OPS/DeckBuilder/Models/DeckMaterials.swift
//
// Persisted state for the deck-tab materials list. Both nodes ride inside
// `DeckDrawingData` JSON (`deck_designs.drawing_data` jsonb) so there is zero
// DB migration — additive-only per the iOS schema discipline.
//
//  • `DeckMaterialsSettings` — the three editable stick-length presets plus glue
//    coverage. Company-wide (it lives on the shared design), crew-adjustable.
//  • `DeckMaterialsSnapshot` — the full materials list frozen at MARK ORDERED
//    time. While present the tab renders these values, locks the presets, and
//    flags DESIGN CHANGED SINCE ORDER when a live recompute drifts.
//
// Codable follows the DeckGeometry.swift house style EXACTLY: explicit
// `CodingKeys`, a custom `init(from:)` that `decodeIfPresent ?? default`s every
// field, and a memberwise `init`. Never `let x: T? = nil` — it drops the field
// from BOTH the memberwise init and the decode. `orderedAt` is the one required
// field (`decode`, not `decodeIfPresent`): a snapshot with no timestamp is
// corrupt, so it should fail decode and let `DeckDrawingData`'s own
// `decodeIfPresent` nil the whole node gracefully rather than surface a
// zero-dated snapshot.

import Foundation

/// Editable consumable presets for the materials list. Defaults match the
/// approved product decision: drip edge 8', 90 flash 8', clip 10', glue one
/// bucket per 400 sq ft. Ranges/steps are enforced by the stepper UI; the model
/// stores whatever the UI wrote.
struct DeckMaterialsSettings: Codable, Equatable {
    var glueCoverageSqFt: Double = 400   // clamp 100...1000, step 25
    var dripStickFeet: Double = 8        // clamp 4...20, step 1
    var ninetyStickFeet: Double = 8      // clamp 4...20, step 1
    var clipStickFeet: Double = 10       // clamp 4...20, step 1
    /// How the vinyl membrane is purchased — exact cut list vs. whole rolls.
    /// A purchasing choice, NOT a geometry change: switching it must never flag
    /// DESIGN CHANGED SINCE ORDER (`DeckMaterialsEngine.driftKey` ignores it).
    var orderMode: VinylOrderMode = .cutList
    /// Length of one full roll (feet) used when packing cuts in `.fullRolls`
    /// mode. Default 75'; the stepper UI clamps 25...300 step 5. Distinct from
    /// the inventory `receiveRolls` physical-roll default (150') — different
    /// concept, do not merge.
    var fullRollLengthFeet: Double = 75

    enum CodingKeys: String, CodingKey {
        case glueCoverageSqFt
        case dripStickFeet
        case ninetyStickFeet
        case clipStickFeet
        case orderMode
        case fullRollLengthFeet
    }

    init(
        glueCoverageSqFt: Double = 400,
        dripStickFeet: Double = 8,
        ninetyStickFeet: Double = 8,
        clipStickFeet: Double = 10,
        orderMode: VinylOrderMode = .cutList,
        fullRollLengthFeet: Double = 75
    ) {
        self.glueCoverageSqFt = glueCoverageSqFt
        self.dripStickFeet = dripStickFeet
        self.ninetyStickFeet = ninetyStickFeet
        self.clipStickFeet = clipStickFeet
        self.orderMode = orderMode
        self.fullRollLengthFeet = fullRollLengthFeet
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.glueCoverageSqFt = try c.decodeIfPresent(Double.self, forKey: .glueCoverageSqFt) ?? 400
        self.dripStickFeet = try c.decodeIfPresent(Double.self, forKey: .dripStickFeet) ?? 8
        self.ninetyStickFeet = try c.decodeIfPresent(Double.self, forKey: .ninetyStickFeet) ?? 8
        self.clipStickFeet = try c.decodeIfPresent(Double.self, forKey: .clipStickFeet) ?? 10
        self.orderMode = try c.decodeIfPresent(VinylOrderMode.self, forKey: .orderMode) ?? .cutList
        self.fullRollLengthFeet = try c.decodeIfPresent(Double.self, forKey: .fullRollLengthFeet) ?? 75
    }
}

struct VinylDirectionPointSnapshot: Codable, Equatable {
    var xInches: Double
    var yInches: Double
}

struct VinylDirectionRegionSnapshot: Codable, Equatable {
    var runAngleDegrees: Double
    var points: [VinylDirectionPointSnapshot]
}

struct VinylDirectionTransitionSnapshot: Codable, Equatable {
    var start: VinylDirectionPointSnapshot
    var end: VinylDirectionPointSnapshot
}

/// Direction geometry grouped with the enclosing surface it belongs to. Points
/// are stored in one plan-wide, translation-independent coordinate space so two
/// same-shaped surfaces cannot exchange seam layouts without raising drift.
struct VinylSurfaceDirectionGeometrySnapshot: Codable, Equatable {
    var surfaceId: String?
    var boundary: [VinylDirectionPointSnapshot]
    var regions: [VinylDirectionRegionSnapshot]
    var transitions: [VinylDirectionTransitionSnapshot]

    init(
        surfaceId: String? = nil,
        boundary: [VinylDirectionPointSnapshot],
        regions: [VinylDirectionRegionSnapshot],
        transitions: [VinylDirectionTransitionSnapshot]
    ) {
        self.surfaceId = surfaceId
        self.boundary = boundary
        self.regions = regions
        self.transitions = transitions
    }
}

/// The materials list frozen at MARK ORDERED. Everything §6 of the spec produces
/// is captured so the tab can render exactly what was ordered — the stored
/// `cutGroups` are PURCHASED-only ("what was ordered"). Drift is detected by
/// recomputing the live list with `settings` + `vinylSettings` and comparing the
/// seed-/label-independent values, so this snapshot never needs a stored drift
/// key.
struct DeckMaterialsSnapshot: Codable, Equatable {
    /// One purchased cut group as it stood at order time.
    struct CutGroup: Codable, Equatable {
        var surfaceLabel: String
        var count: Int
        var lengthInches: Double
        var rollWidthInches: Double

        enum CodingKeys: String, CodingKey {
            case surfaceLabel
            case count
            case lengthInches
            case rollWidthInches
        }

        init(
            surfaceLabel: String,
            count: Int,
            lengthInches: Double,
            rollWidthInches: Double
        ) {
            self.surfaceLabel = surfaceLabel
            self.count = count
            self.lengthInches = lengthInches
            self.rollWidthInches = rollWidthInches
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.surfaceLabel = try c.decodeIfPresent(String.self, forKey: .surfaceLabel) ?? ""
            self.count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
            self.lengthInches = try c.decodeIfPresent(Double.self, forKey: .lengthInches) ?? 0
            self.rollWidthInches = try c.decodeIfPresent(Double.self, forKey: .rollWidthInches) ?? 0
        }
    }

    var orderedAt: Date
    var orderedBy: String?
    var settings: DeckMaterialsSettings          // presets as they stood
    var vinylSettings: VinylOrderSettings        // roll width / seam / wrap / direction as ordered
    var vinylColor: String                       // "" → FIELD CONFIRM
    /// Supplier PO reference confirmed at order time (bulk order wizard).
    /// nil for single-project orders and legacy snapshots — those carry no PO.
    var po: String?
    var vinylOrderedSqFt: Int
    var vinylSurfaceAreaSqFt: Double
    var cutGroups: [CutGroup]                    // purchased-only (display: "what was ordered")
    /// ALL cut pieces at order time — purchased PLUS intra-job reused (a strip
    /// sourced from another surface's leftover offcut). Used SOLELY to reconstruct
    /// the geometry drift key. The live `DeckMaterialsDriftKey` counts every cut
    /// piece (`plan.surfaces.flatMap(\.cuts)`), so drift must compare against the
    /// full set — reconstructing it from the purchased-only `cutGroups` above
    /// would drop the reused pieces and false-flag DESIGN CHANGED SINCE ORDER the
    /// instant a reuse deck is ordered. Defaults to `cutGroups` for any legacy
    /// snapshot that predates this field (none exist in prod).
    var driftCutGroups: [CutGroup]
    /// Explicit run-region and wall-seam geometry at order time. The grouped
    /// surface form is authoritative for new snapshots; the flat arrays remain
    /// as an additive legacy fallback for snapshots written during rollout.
    var vinylDirectionSurfaces: [VinylSurfaceDirectionGeometrySnapshot]?
    var vinylDirectionRegions: [VinylDirectionRegionSnapshot]?
    var vinylDirectionTransitions: [VinylDirectionTransitionSnapshot]?
    var dripEdgeFeet: Double
    var dripSticks: Int
    var clipFeet: Double
    var clipSticks: Int
    var ninetyFeet: Double
    var ninetySticks: Int
    var glueAreaSqFt: Double
    var glueBuckets: Int
    /// Count of vinyl-classified surfaces at order time — the live materials'
    /// `driftKey.vinylSurfaceCount` (i.e. `vinylInputs.count`). Stored EXPLICITLY
    /// because it cannot be reconstructed from `cutGroups`: two surfaces sharing
    /// a label collapse to one group, and a degenerate surface produces no cuts
    /// at all — either would make a rebuilt count diverge from the live side and
    /// false-flag DESIGN CHANGED SINCE ORDER the instant the design was ordered.
    var vinylSurfaceCount: Int
    /// How the vinyl was purchased at order time (spec § 3.3). `.cutList` is the
    /// default and the legacy fallback; `.fullRolls` when whole rolls were bought.
    var orderMode: VinylOrderMode
    /// The full-roll length (feet) used when `orderMode == .fullRolls`, so the
    /// ordered display reads the exact rolls that were bought (`N ROLLS @ L' × W"`).
    var fullRollLengthFeet: Double
    /// Whole rolls ordered — present only in `.fullRolls` mode, nil in cut-list.
    var orderedRollCount: Int?
    /// True when any confirmed quantity differed from its calculated value at
    /// order time — drives the subtle ADJUSTED tag on the ordered card. NEVER
    /// affects drift (which is geometry-only); a purely presentational flag.
    var isOrderedEdited: Bool
    /// WHERE the material came from. `.supplier` (an order was placed) or
    /// `.shop` (pulled off the rack — nothing ordered). Additive: any snapshot
    /// written before this field existed decodes as `.supplier`, which is what
    /// every historic record in fact was.
    var disposition: VinylOrderDisposition
    /// The consumable lines actually PURCHASED for this order, with the other
    /// jobs each line was split across. Written by the bulk order wizard, where
    /// tubes and buckets are bought once for the whole batch — the count stored
    /// is the shared count, never a per-job fraction (see `VinylSharedConsumable`).
    ///
    /// nil/empty ⇒ nothing shared: the record renders from this snapshot's own
    /// `dripSticks`/`clipSticks`/`ninetySticks`/`glueBuckets`, which is exactly
    /// how every single-job and legacy order reads. The per-job stick counts are
    /// never overwritten by this field — they remain this job's own requirement.
    var sharedConsumables: [VinylSharedConsumable]?

    enum CodingKeys: String, CodingKey {
        case orderedAt
        case orderedBy
        case settings
        case vinylSettings
        case vinylColor
        case po
        case disposition
        case sharedConsumables
        case vinylOrderedSqFt
        case vinylSurfaceAreaSqFt
        case cutGroups
        case driftCutGroups
        case vinylDirectionSurfaces
        case vinylDirectionRegions
        case vinylDirectionTransitions
        case dripEdgeFeet
        case dripSticks
        case clipFeet
        case clipSticks
        case ninetyFeet
        case ninetySticks
        case glueAreaSqFt
        case glueBuckets
        case vinylSurfaceCount
        case orderMode
        case fullRollLengthFeet
        case orderedRollCount
        case isOrderedEdited
    }

    init(
        orderedAt: Date,
        orderedBy: String?,
        settings: DeckMaterialsSettings,
        vinylSettings: VinylOrderSettings,
        vinylColor: String,
        vinylOrderedSqFt: Int,
        vinylSurfaceAreaSqFt: Double,
        cutGroups: [CutGroup],
        dripEdgeFeet: Double,
        dripSticks: Int,
        clipFeet: Double,
        clipSticks: Int,
        ninetyFeet: Double,
        ninetySticks: Int,
        glueAreaSqFt: Double,
        glueBuckets: Int,
        vinylSurfaceCount: Int,
        orderMode: VinylOrderMode = .cutList,
        fullRollLengthFeet: Double = 75,
        orderedRollCount: Int? = nil,
        isOrderedEdited: Bool = false,
        driftCutGroups: [CutGroup]? = nil,
        po: String? = nil,
        disposition: VinylOrderDisposition = .supplier,
        sharedConsumables: [VinylSharedConsumable]? = nil,
        vinylDirectionSurfaces: [VinylSurfaceDirectionGeometrySnapshot]? = nil,
        vinylDirectionRegions: [VinylDirectionRegionSnapshot]? = nil,
        vinylDirectionTransitions: [VinylDirectionTransitionSnapshot]? = nil
    ) {
        self.orderedAt = orderedAt
        self.orderedBy = orderedBy
        self.settings = settings
        self.vinylSettings = vinylSettings
        self.vinylColor = vinylColor
        self.po = po
        self.disposition = disposition
        self.sharedConsumables = sharedConsumables
        self.vinylOrderedSqFt = vinylOrderedSqFt
        self.vinylSurfaceAreaSqFt = vinylSurfaceAreaSqFt
        self.cutGroups = cutGroups
        // Legacy / display-only constructions omit driftCutGroups → fall back to
        // the purchased cutGroups (unchanged behavior). The order service passes
        // the real all-cuts set.
        self.driftCutGroups = driftCutGroups ?? cutGroups
        self.vinylDirectionSurfaces = vinylDirectionSurfaces
        self.vinylDirectionRegions = vinylDirectionRegions
        self.vinylDirectionTransitions = vinylDirectionTransitions
        self.dripEdgeFeet = dripEdgeFeet
        self.dripSticks = dripSticks
        self.clipFeet = clipFeet
        self.clipSticks = clipSticks
        self.ninetyFeet = ninetyFeet
        self.ninetySticks = ninetySticks
        self.glueAreaSqFt = glueAreaSqFt
        self.glueBuckets = glueBuckets
        self.vinylSurfaceCount = vinylSurfaceCount
        self.orderMode = orderMode
        self.fullRollLengthFeet = fullRollLengthFeet
        self.orderedRollCount = orderedRollCount
        self.isOrderedEdited = isOrderedEdited
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Required: a snapshot with no timestamp is corrupt. Failing decode here
        // lets DeckDrawingData's `decodeIfPresent(orderedMaterials)` nil the whole
        // node rather than surface a zero-dated snapshot.
        self.orderedAt = try c.decode(Date.self, forKey: .orderedAt)
        self.orderedBy = try c.decodeIfPresent(String.self, forKey: .orderedBy)
        self.settings = try c.decodeIfPresent(DeckMaterialsSettings.self, forKey: .settings) ?? DeckMaterialsSettings()
        self.vinylSettings = try c.decodeIfPresent(VinylOrderSettings.self, forKey: .vinylSettings) ?? .default
        self.vinylColor = try c.decodeIfPresent(String.self, forKey: .vinylColor) ?? ""
        self.po = try c.decodeIfPresent(String.self, forKey: .po)
        // Additive: every snapshot written before the shop disposition existed
        // recorded a supplier order, so that is the only correct fallback.
        self.disposition = try c.decodeIfPresent(VinylOrderDisposition.self, forKey: .disposition) ?? .supplier
        self.sharedConsumables = try c.decodeIfPresent([VinylSharedConsumable].self, forKey: .sharedConsumables)
        self.vinylOrderedSqFt = try c.decodeIfPresent(Int.self, forKey: .vinylOrderedSqFt) ?? 0
        self.vinylSurfaceAreaSqFt = try c.decodeIfPresent(Double.self, forKey: .vinylSurfaceAreaSqFt) ?? 0
        self.cutGroups = try c.decodeIfPresent([CutGroup].self, forKey: .cutGroups) ?? []
        // Additive drift field — a snapshot written before it existed falls back to
        // the purchased cutGroups (its prior, pre-fix behavior). Must decode AFTER
        // `cutGroups` so the fallback sees the decoded value.
        self.driftCutGroups = try c.decodeIfPresent([CutGroup].self, forKey: .driftCutGroups) ?? self.cutGroups
        self.vinylDirectionSurfaces = try c.decodeIfPresent(
            [VinylSurfaceDirectionGeometrySnapshot].self,
            forKey: .vinylDirectionSurfaces
        )
        self.vinylDirectionRegions = try c.decodeIfPresent(
            [VinylDirectionRegionSnapshot].self,
            forKey: .vinylDirectionRegions
        )
        self.vinylDirectionTransitions = try c.decodeIfPresent(
            [VinylDirectionTransitionSnapshot].self,
            forKey: .vinylDirectionTransitions
        )
        self.dripEdgeFeet = try c.decodeIfPresent(Double.self, forKey: .dripEdgeFeet) ?? 0
        self.dripSticks = try c.decodeIfPresent(Int.self, forKey: .dripSticks) ?? 0
        self.clipFeet = try c.decodeIfPresent(Double.self, forKey: .clipFeet) ?? 0
        self.clipSticks = try c.decodeIfPresent(Int.self, forKey: .clipSticks) ?? 0
        self.ninetyFeet = try c.decodeIfPresent(Double.self, forKey: .ninetyFeet) ?? 0
        self.ninetySticks = try c.decodeIfPresent(Int.self, forKey: .ninetySticks) ?? 0
        self.glueAreaSqFt = try c.decodeIfPresent(Double.self, forKey: .glueAreaSqFt) ?? 0
        self.glueBuckets = try c.decodeIfPresent(Int.self, forKey: .glueBuckets) ?? 0
        // Additive field. A legacy snapshot (none exist in prod) has no stored
        // count, so fall back to the old distinct-label reconstruction — that
        // leaves any such snapshot byte-for-byte unchanged in behavior; every
        // snapshot written since carries the explicit count.
        self.vinylSurfaceCount = try c.decodeIfPresent(Int.self, forKey: .vinylSurfaceCount)
            ?? Set(self.cutGroups.map(\.surfaceLabel)).count
        // Full-roll / ordered-record additions (spec § 3.3). Calc-derived legacy
        // fallbacks: pre-existing snapshots (none in prod) were exact cut-list
        // orders, so `.cutList`, the 75' default, no roll count, and unedited.
        self.orderMode = try c.decodeIfPresent(VinylOrderMode.self, forKey: .orderMode) ?? .cutList
        self.fullRollLengthFeet = try c.decodeIfPresent(Double.self, forKey: .fullRollLengthFeet) ?? 75
        self.orderedRollCount = try c.decodeIfPresent(Int.self, forKey: .orderedRollCount)
        // Lenient for the same reason as `VinylOrderSettings`: pushed booleans
        // are numbers in every stored blob. `DeckDrawingData` reads
        // `orderedMaterials` with `try?`, so a strict Bool did not raise — it
        // silently nilled the whole ordered-materials snapshot.
        self.isOrderedEdited = try c.decodeLegacyBoolIfPresent(forKey: .isOrderedEdited) ?? false
    }

    // MARK: - The ordered record

    /// The consumable lines AS PURCHASED, in a fixed reading order, for the
    /// record card and the activity entry.
    ///
    /// A bulk order stores its real purchased lines (shared tubes/buckets with
    /// their sharing partners) in `sharedConsumables`; those are authoritative.
    /// Every single-job and legacy order stores nothing, and the honest record
    /// is this job's own confirmed counts with no sharing partners. Zero-count
    /// lines drop out — an order that bought no glue should not claim a glue line.
    var orderedConsumables: [VinylSharedConsumable] {
        if let stored = sharedConsumables, !stored.isEmpty {
            return stored.filter { $0.count > 0 }
        }
        return [
            VinylSharedConsumable(kind: .dripEdge, count: dripSticks),
            VinylSharedConsumable(kind: .ninetyFlash, count: ninetySticks),
            VinylSharedConsumable(kind: .clip, count: clipSticks),
            VinylSharedConsumable(kind: .glue, count: glueBuckets)
        ].filter { $0.count > 0 }
    }

    /// The purchased vinyl lines: `2 @ 9'6"` per cut group, or the whole-roll
    /// line in full-roll mode. Sentence-case-neutral — used by both the record
    /// card and the activity body.
    var orderedVinylLines: [String] {
        if orderMode == .fullRolls {
            let rolls = orderedRollCount ?? 0
            guard rolls > 0 else { return [] }
            let noun = rolls == 1 ? "roll" : "rolls"
            return ["\(rolls) \(noun) @ \(Int(fullRollLengthFeet))' × \(vinylFormatInches(vinylSettings.rollWidthInches))"]
        }
        return cutGroups
            .filter { $0.count > 0 }
            .map { "\($0.count) @ \(vinylFormatFeetAndInches($0.lengthInches))" }
    }
}
