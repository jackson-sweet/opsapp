// OPS/OPS/DeckBuilder/Services/DeckMaterialsOrderService.swift
//
// Shared MARK ORDERED / CLEAR ORDERED writer for the deck materials list. Both
// entry points (the Vinyl Order sheet PROJECT MARKER section and the project
// Details-tab marker) snapshot identically through this one service so the frozen
// materials list is written the same way regardless of where the tap came from.
//
// Ordering discipline (spec § 8): write the materials snapshot into the design
// JSON FIRST (local-only — it cannot fail remotely), THEN the project marker
// fields. If the marker write throws, revert the local snapshot so the design's
// frozen list and the project's ordered flag can never disagree.

import Foundation
import Supabase

/// The actually-ordered quantities a human confirmed at MARK ORDERED time. The
/// calculator's suggestion pre-fills every field; each is then nudgeable in the
/// order-confirm sheet. What the operator confirms here becomes the FROZEN
/// ordered record — but the geometry drift key is never derived from these edits,
/// so a spare-stick or full-roll rounding never flags DESIGN CHANGED SINCE ORDER.
struct DeckMaterialsOrderConfirmation: Equatable {
    var orderMode: VinylOrderMode
    var fullRollLengthFeet: Double
    /// Ordered vinyl area (cut-list mode). In roll mode this carries the calc
    /// reference sq ft — the operator edits `rollCount`, not this.
    var vinylOrderedSqFt: Int
    /// Whole rolls ordered (roll mode only; ignored in cut-list mode).
    var rollCount: Int
    var dripSticks: Int
    var clipSticks: Int
    var ninetySticks: Int
    var glueBuckets: Int

    /// The unedited confirmation — every field pre-filled from the calculated
    /// materials list. `VinylOrderConfirmSheet` starts here and lets the operator
    /// nudge; `markOrdered` falls back to this when no confirmation is supplied.
    static func calculated(
        from materials: DeckMaterialsList,
        settings: DeckMaterialsSettings
    ) -> DeckMaterialsOrderConfirmation {
        DeckMaterialsOrderConfirmation(
            orderMode: settings.orderMode,
            fullRollLengthFeet: settings.fullRollLengthFeet,
            vinylOrderedSqFt: materials.vinylPlan.totalOrderedSqFt,
            rollCount: materials.rollCount,
            dripSticks: materials.dripEdge.sticks,
            clipSticks: materials.clip.sticks,
            ninetySticks: materials.ninetyFlash.sticks,
            glueBuckets: materials.glueBuckets
        )
    }

    /// True when any confirmed quantity differs from the calculated value —
    /// vinyl (rolls in roll mode, sq ft in cut-list mode) or any stick/bucket
    /// count. Mode and roll length are settings, not edits, so they are excluded.
    func differs(fromCalculated calc: DeckMaterialsOrderConfirmation) -> Bool {
        let vinylEdited = orderMode == .fullRolls
            ? rollCount != calc.rollCount
            : vinylOrderedSqFt != calc.vinylOrderedSqFt
        return vinylEdited
            || dripSticks != calc.dripSticks
            || clipSticks != calc.clipSticks
            || ninetySticks != calc.ninetySticks
            || glueBuckets != calc.glueBuckets
    }
}

@MainActor
struct DeckMaterialsOrderService {
    let userId: String
    /// `DataController.updateProjectFields` in production; injected so tests can
    /// spy on the trio and simulate remote failure.
    let updateProjectFields: (String, [String: AnyJSON]) async throws -> Void

    /// Freeze the current materials list into `design.drawingData.orderedMaterials`
    /// and mark the project ordered. Reverts the local snapshot if the marker
    /// write throws.
    func markOrdered(
        projectId: String,
        design: DeckDesign,
        materials: DeckMaterialsList,
        settings: DeckMaterialsSettings,
        vinylSettings: VinylOrderSettings,
        confirmed: DeckMaterialsOrderConfirmation? = nil
    ) async throws {
        let now = Date()
        let priorSnapshot = design.drawingData.orderedMaterials

        // The confirmed order — the operator's actual quantities, or the plain
        // calculated values when no confirm step ran. `isOrderedEdited` compares
        // against the calc so a hand-edit is remembered; the geometry drift key
        // below still comes straight from `materials` (never the edits).
        let calc = DeckMaterialsOrderConfirmation.calculated(from: materials, settings: settings)
        let confirmation = confirmed ?? calc
        let isOrderedEdited = confirmation.differs(fromCalculated: calc)

        // Purchased cut groups only — the snapshot shows "what was ordered".
        let purchasedGroups = VinylCutGroup
            .groups(from: materials.vinylPlan.surfaces.flatMap(\.purchasedCuts))
            .map { group in
                DeckMaterialsSnapshot.CutGroup(
                    surfaceLabel: group.surfaceLabel,
                    count: group.count,
                    lengthInches: group.lengthInches,
                    rollWidthInches: group.rollWidthInches
                )
            }

        let snapshot = DeckMaterialsSnapshot(
            orderedAt: now,
            orderedBy: userId,
            settings: settings,
            vinylSettings: vinylSettings,
            vinylColor: vinylSettings.color,
            // CONFIRMED display quantities (calc value when unedited).
            vinylOrderedSqFt: confirmation.vinylOrderedSqFt,
            vinylSurfaceAreaSqFt: materials.vinylPlan.totalSurfaceAreaSqFt,
            // Drift-relevant fields stay CALC — the snapshot's cut geometry,
            // flashing exact feet, glue area and surface count must mirror the
            // live recompute or an edit would false-flag DESIGN CHANGED.
            cutGroups: purchasedGroups,
            dripEdgeFeet: materials.dripEdge.exactFeet,
            dripSticks: confirmation.dripSticks,
            clipFeet: materials.clip.exactFeet,
            clipSticks: confirmation.clipSticks,
            ninetyFeet: materials.ninetyFlash.exactFeet,
            ninetySticks: confirmation.ninetySticks,
            glueAreaSqFt: materials.glueAreaSqFt,
            glueBuckets: confirmation.glueBuckets,
            // Populate from the LIVE materials so the snapshot and the tab's live
            // recompute count vinyl surfaces identically — reconstructing this
            // from `cutGroups` (shared labels collapse, degenerate faces drop)
            // would false-flag drift the instant the design was ordered.
            vinylSurfaceCount: materials.driftKey.vinylSurfaceCount,
            orderMode: confirmation.orderMode,
            fullRollLengthFeet: confirmation.fullRollLengthFeet,
            orderedRollCount: confirmation.orderMode == .fullRolls ? confirmation.rollCount : nil,
            isOrderedEdited: isOrderedEdited
        )

        // (1) Local-first snapshot — the accessor marks needsSync + updatedAt.
        var next = design.drawingData
        next.orderedMaterials = snapshot
        design.drawingData = next

        // (2) Project marker fields. Revert the snapshot if this throws.
        do {
            try await updateProjectFields(projectId, [
                ProjectVinylOrderFields.status: .string(ProjectVinylOrderStatus.ordered.rawValue),
                ProjectVinylOrderFields.orderedAt: .string(SupabaseDate.format(now)),
                ProjectVinylOrderFields.orderedBy: .string(userId)
            ])
        } catch {
            var revert = design.drawingData
            revert.orderedMaterials = priorSnapshot
            design.drawingData = revert
            throw error
        }
    }

    /// Clear the ordered snapshot and the project marker. Reverts the local
    /// snapshot removal if the marker write throws.
    func clearOrdered(projectId: String, design: DeckDesign?) async throws {
        let priorSnapshot = design?.drawingData.orderedMaterials

        if let design {
            var next = design.drawingData
            next.orderedMaterials = nil
            design.drawingData = next
        }

        do {
            try await updateProjectFields(projectId, [
                ProjectVinylOrderFields.status: .string(ProjectVinylOrderStatus.notOrdered.rawValue),
                ProjectVinylOrderFields.orderedAt: .null,
                ProjectVinylOrderFields.orderedBy: .null
            ])
        } catch {
            if let design {
                var revert = design.drawingData
                revert.orderedMaterials = priorSnapshot
                design.drawingData = revert
            }
            throw error
        }
    }
}
