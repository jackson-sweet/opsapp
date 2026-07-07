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
        vinylSettings: VinylOrderSettings
    ) async throws {
        let now = Date()
        let priorSnapshot = design.drawingData.orderedMaterials

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
            vinylOrderedSqFt: materials.vinylPlan.totalOrderedSqFt,
            vinylSurfaceAreaSqFt: materials.vinylPlan.totalSurfaceAreaSqFt,
            cutGroups: purchasedGroups,
            dripEdgeFeet: materials.dripEdge.exactFeet,
            dripSticks: materials.dripEdge.sticks,
            clipFeet: materials.clip.exactFeet,
            clipSticks: materials.clip.sticks,
            ninetyFeet: materials.ninetyFlash.exactFeet,
            ninetySticks: materials.ninetyFlash.sticks,
            glueAreaSqFt: materials.glueAreaSqFt,
            glueBuckets: materials.glueBuckets,
            // Populate from the LIVE materials so the snapshot and the tab's live
            // recompute count vinyl surfaces identically — reconstructing this
            // from `cutGroups` (shared labels collapse, degenerate faces drop)
            // would false-flag drift the instant the design was ordered.
            vinylSurfaceCount: materials.driftKey.vinylSurfaceCount
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
