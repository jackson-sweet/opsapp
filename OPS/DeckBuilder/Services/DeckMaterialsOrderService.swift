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

enum DeckMaterialsOrderError: LocalizedError, Equatable {
    case vinylPlanBlocked(String)
    case vinylPlanChanged

    var errorDescription: String? {
        switch self {
        case .vinylPlanBlocked(let message): return message
        case .vinylPlanChanged: return "DESIGN CHANGED · REVIEW ORDER"
        }
    }
}

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

    /// The calculator's quantities implied by a FROZEN snapshot's own geometry —
    /// the RESET target and the isOrderedEdited baseline when re-editing an order.
    /// Derived from the never-edited geometry fields (cut groups, flashing exact
    /// feet, glue area), so it is stable across edits and matches order-time calc.
    static func calculated(fromSnapshot s: DeckMaterialsSnapshot) -> DeckMaterialsOrderConfirmation {
        func sticks(_ feet: Double, _ stickFeet: Double) -> Int {
            (feet > 0 && stickFeet > 0) ? max(0, Int(ceil(feet / stickFeet))) : 0
        }
        let stripFeet = snapshotStripLengthsFeet(s)
        let calcSqFt = Int(ceil(s.cutGroups.reduce(0.0) {
            $0 + Double(max(0, $1.count)) * $1.lengthInches * $1.rollWidthInches / 144.0
        }))
        let rollPack = VinylRollPacker.rollsNeeded(stripLengthsFeet: stripFeet, rollLengthFeet: s.fullRollLengthFeet)
        return DeckMaterialsOrderConfirmation(
            orderMode: s.orderMode,
            fullRollLengthFeet: s.fullRollLengthFeet,
            vinylOrderedSqFt: calcSqFt,
            rollCount: rollPack.rollCount,
            dripSticks: sticks(s.dripEdgeFeet, s.settings.dripStickFeet),
            clipSticks: sticks(s.clipFeet, s.settings.clipStickFeet),
            ninetySticks: sticks(s.ninetyFeet, s.settings.ninetyStickFeet),
            glueBuckets: (s.glueAreaSqFt > 0 && s.settings.glueCoverageSqFt > 0)
                ? Int(ceil(s.glueAreaSqFt / s.settings.glueCoverageSqFt)) : 0
        )
    }

    /// The order's CONFIRMED quantities as currently stored — the confirm sheet's
    /// pre-fill when re-opened via EDIT ORDER.
    static func stored(fromSnapshot s: DeckMaterialsSnapshot) -> DeckMaterialsOrderConfirmation {
        let fallbackRolls = VinylRollPacker.rollsNeeded(
            stripLengthsFeet: snapshotStripLengthsFeet(s), rollLengthFeet: s.fullRollLengthFeet
        ).rollCount
        return DeckMaterialsOrderConfirmation(
            orderMode: s.orderMode,
            fullRollLengthFeet: s.fullRollLengthFeet,
            vinylOrderedSqFt: s.vinylOrderedSqFt,
            rollCount: s.orderedRollCount ?? fallbackRolls,
            dripSticks: s.dripSticks,
            clipSticks: s.clipSticks,
            ninetySticks: s.ninetySticks,
            glueBuckets: s.glueBuckets
        )
    }

    /// Purchased strip lengths (feet) reconstructed from a snapshot's cut groups.
    private static func snapshotStripLengthsFeet(_ s: DeckMaterialsSnapshot) -> [Double] {
        s.cutGroups.flatMap { group in
            Array(repeating: group.lengthInches / 12.0, count: max(0, group.count))
        }
    }
}

@MainActor
struct DeckMaterialsOrderService {
    let userId: String
    /// `DataController.updateProjectFields` in production; injected so tests can
    /// spy on the trio and simulate remote failure.
    let updateProjectFields: (String, [String: AnyJSON]) async throws -> Void

    /// Re-checks a pending confirmation against a fresh whole-design resolve.
    /// Confirmation can stay open while realtime or local edits change geometry;
    /// never freeze the captured plan unless every order-driving value still
    /// matches the current design.
    static func validateCurrentOrder(
        currentMaterials: DeckMaterialsList?,
        currentSettings: DeckMaterialsSettings,
        currentVinylSettings: VinylOrderSettings,
        pendingMaterials: DeckMaterialsList,
        pendingSettings: DeckMaterialsSettings,
        pendingVinylSettings: VinylOrderSettings
    ) throws {
        guard let currentMaterials else {
            throw DeckMaterialsOrderError.vinylPlanChanged
        }
        guard currentMaterials.vinylPlan.isOrderable else {
            throw DeckMaterialsOrderError.vinylPlanBlocked(
                currentMaterials.vinylPlan.blockingMessage
                    ?? VinylCutPlan.wallAlignedTransitionBlocker
            )
        }

        let currentConfirmation = DeckMaterialsOrderConfirmation.calculated(
            from: currentMaterials,
            settings: currentSettings
        )
        let pendingConfirmation = DeckMaterialsOrderConfirmation.calculated(
            from: pendingMaterials,
            settings: pendingSettings
        )
        guard currentSettings == pendingSettings,
              currentVinylSettings == pendingVinylSettings,
              currentMaterials.driftKey == pendingMaterials.driftKey,
              currentConfirmation == pendingConfirmation else {
            throw DeckMaterialsOrderError.vinylPlanChanged
        }
    }

    /// The Deck Designer edits a value-type drawing copy. Merge only the order
    /// snapshot written by `markOrdered` so the next designer save retains it
    /// without replacing newer geometry in that active copy.
    static func mergeOrderedSnapshot(
        from design: DeckDesign,
        into activeDrawing: inout DeckDrawingData
    ) {
        activeDrawing.orderedMaterials = design.drawingData.orderedMaterials
    }

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
        guard materials.vinylPlan.isOrderable else {
            throw DeckMaterialsOrderError.vinylPlanBlocked(
                materials.vinylPlan.blockingMessage ?? VinylCutPlan.wallAlignedTransitionBlocker
            )
        }
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
        let purchasedGroups = snapshotGroups(from: materials.vinylPlan.surfaces.flatMap(\.purchasedCuts))
        // ALL cut pieces (purchased + intra-job reused) — the drift basis. The
        // live drift key counts every cut piece, so the snapshot must store the
        // full set or a reuse deck false-flags DESIGN CHANGED the instant it is
        // ordered.
        let driftGroups = snapshotGroups(from: materials.vinylPlan.surfaces.flatMap(\.cuts))
        let directionGeometry = DeckMaterialsDriftKey.directionGeometry(for: materials.vinylPlan)

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
            isOrderedEdited: isOrderedEdited,
            driftCutGroups: driftGroups,
            vinylDirectionSurfaces: directionGeometry.surfaces,
            vinylDirectionRegions: directionGeometry.regions,
            vinylDirectionTransitions: directionGeometry.transitions
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
                // `projects.vinyl_ordered_by` FKs to auth.users(id), while the app
                // carries public.users.id / Firebase ids. The snapshot keeps
                // attribution locally; the synced project marker stays valid.
                ProjectVinylOrderFields.orderedBy: .null
            ])
        } catch {
            var revert = design.drawingData
            revert.orderedMaterials = priorSnapshot
            design.drawingData = revert
            throw error
        }
    }

    /// Re-write ONLY the confirmed quantities on an existing ordered snapshot — a
    /// correction that never needs CLEAR + re-order (spec § 6). The frozen geometry
    /// (cut groups, flashing exact feet, glue area, surface count), the order
    /// timestamp and orderer are preserved verbatim, so `DeckMaterialsDriftKey`
    /// is byte-identical — an edit can never clear or raise DESIGN CHANGED SINCE
    /// ORDER. Local-only (the project is already marked ordered), so no remote
    /// write and no compensation are needed.
    @discardableResult
    static func editOrder(design: DeckDesign, confirmed: DeckMaterialsOrderConfirmation) -> Bool {
        guard let existing = design.drawingData.orderedMaterials else { return false }
        let calc = DeckMaterialsOrderConfirmation.calculated(fromSnapshot: existing)

        var updated = existing
        updated.vinylOrderedSqFt = confirmed.vinylOrderedSqFt
        updated.dripSticks = confirmed.dripSticks
        updated.clipSticks = confirmed.clipSticks
        updated.ninetySticks = confirmed.ninetySticks
        updated.glueBuckets = confirmed.glueBuckets
        updated.orderMode = confirmed.orderMode
        updated.fullRollLengthFeet = confirmed.fullRollLengthFeet
        updated.orderedRollCount = confirmed.orderMode == .fullRolls ? confirmed.rollCount : nil
        updated.isOrderedEdited = confirmed.differs(fromCalculated: calc)

        var next = design.drawingData
        next.orderedMaterials = updated
        design.drawingData = next
        return true
    }

    /// Group cut pieces into the snapshot's `CutGroup` shape (surface label,
    /// count, length, roll width). Used for both the purchased display groups and
    /// the all-cuts drift groups.
    private func snapshotGroups(from cuts: [VinylCutPiece]) -> [DeckMaterialsSnapshot.CutGroup] {
        VinylCutGroup.groups(from: cuts).map { group in
            DeckMaterialsSnapshot.CutGroup(
                surfaceLabel: group.surfaceLabel,
                count: group.count,
                lengthInches: group.lengthInches,
                rollWidthInches: group.rollWidthInches
            )
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
