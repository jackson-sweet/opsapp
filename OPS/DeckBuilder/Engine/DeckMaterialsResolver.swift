// OPS/OPS/DeckBuilder/Engine/DeckMaterialsResolver.swift
//
// Composes the pure Task-3/4/5 pipeline into one call: scale resolution → read-
// only surface inputs → vinyl detection → materials engine. Shared by the deck-
// tab materials section and the project-details MARK ORDERED path so both resolve
// the vinyl set and the materials list identically. Pure — the caller injects the
// job's task-type displays and a catalog id→name/description blob.

import Foundation

enum DeckMaterialsResolver {

    struct Resolved {
        /// Resolved vinyl-order scale, or nil when the drawing can't be trusted
        /// (stale/disagreeing dimensions). Nil ⇒ CONFIRM ONE EDGE LENGTH state.
        let scale: Double?
        /// The detected vinyl surface inputs (empty when no vinyl set).
        let vinylInputs: [VinylOrderSurfaceInput]
        /// The full materials list, or nil when scale is nil or the vinyl set is
        /// empty (materials section hidden for those).
        let materials: DeckMaterialsList?
    }

    static func resolve(
        data: DeckDrawingData,
        settings: DeckMaterialsSettings,
        vinylSettings: VinylOrderSettings,
        taskTypeDisplays: [String],
        catalogNameById: [String: String]
    ) -> Resolved {
        // Strict scale gates the materials math. Detection does NOT need it — a
        // surface's vinyl-ness is a material question, not a geometry one — so
        // build inputs at a display-safe scale to resolve the vinyl SET even when
        // the strict scale is nil. That lets the tab tell "no vinyl set" (hidden)
        // apart from "vinyl set but unconfirmed scale" (CONFIRM ONE EDGE LENGTH).
        let strictScale = VinylOrderScaleResolver.resolve(data)
        let scaleForInputs = strictScale ?? data.effectiveScaleFactor

        let allInputs = DeckMaterialsInputBuilder.surfaceInputs(for: data, scale: scaleForInputs)
        let jobSignal = DeckVinylDetection.jobHasVinylSignal(
            taskTypeDisplays: taskTypeDisplays,
            vinylCatalogItemId: data.config.vinylCatalogItemId
        )
        let vinylIds = DeckVinylDetection.vinylSurfaceIds(
            surfaces: allInputs,
            jobHasVinylSignal: jobSignal,
            catalogNameById: catalogNameById
        )
        let vinylInputs = allInputs
            .filter { vinylIds.contains($0.input.id) }
            .map(\.input)

        // Materials only when the strict scale holds AND a vinyl set exists.
        // vinylInputs are already built at strictScale in that case (they equal
        // scaleForInputs), so the geometry is accurate.
        guard strictScale != nil, !vinylInputs.isEmpty else {
            return Resolved(scale: strictScale, vinylInputs: vinylInputs, materials: nil)
        }

        let facesByLevel = data.isMultiLevel
            ? data.levels.map(\.detectedSurfaces)
            : [data.detectedSurfaces]

        let materials = DeckMaterialsEngine.compute(
            vinylInputs: vinylInputs,
            allDetectedFacesByLevel: facesByLevel,
            settings: settings,
            vinylSettings: vinylSettings
        )
        return Resolved(scale: strictScale, vinylInputs: vinylInputs, materials: materials)
    }
}
