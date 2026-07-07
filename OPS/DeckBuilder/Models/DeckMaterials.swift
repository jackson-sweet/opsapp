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
    var vinylOrderedSqFt: Int
    var vinylSurfaceAreaSqFt: Double
    var cutGroups: [CutGroup]                    // purchased-only
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

    enum CodingKeys: String, CodingKey {
        case orderedAt
        case orderedBy
        case settings
        case vinylSettings
        case vinylColor
        case vinylOrderedSqFt
        case vinylSurfaceAreaSqFt
        case cutGroups
        case dripEdgeFeet
        case dripSticks
        case clipFeet
        case clipSticks
        case ninetyFeet
        case ninetySticks
        case glueAreaSqFt
        case glueBuckets
        case vinylSurfaceCount
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
        vinylSurfaceCount: Int
    ) {
        self.orderedAt = orderedAt
        self.orderedBy = orderedBy
        self.settings = settings
        self.vinylSettings = vinylSettings
        self.vinylColor = vinylColor
        self.vinylOrderedSqFt = vinylOrderedSqFt
        self.vinylSurfaceAreaSqFt = vinylSurfaceAreaSqFt
        self.cutGroups = cutGroups
        self.dripEdgeFeet = dripEdgeFeet
        self.dripSticks = dripSticks
        self.clipFeet = clipFeet
        self.clipSticks = clipSticks
        self.ninetyFeet = ninetyFeet
        self.ninetySticks = ninetySticks
        self.glueAreaSqFt = glueAreaSqFt
        self.glueBuckets = glueBuckets
        self.vinylSurfaceCount = vinylSurfaceCount
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
        self.vinylOrderedSqFt = try c.decodeIfPresent(Int.self, forKey: .vinylOrderedSqFt) ?? 0
        self.vinylSurfaceAreaSqFt = try c.decodeIfPresent(Double.self, forKey: .vinylSurfaceAreaSqFt) ?? 0
        self.cutGroups = try c.decodeIfPresent([CutGroup].self, forKey: .cutGroups) ?? []
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
    }
}
