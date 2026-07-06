// OPS/OPS/DeckBuilder/Engine/DeckVinylDetection.swift
//
// Smart auto-detection of which deck surfaces are vinyl (spec § 5). Pure — the
// caller injects a catalog id→name/description blob so product resolution stays
// out of this file.
//
// Classification per surface's AREA items:
//   • vinyl-ish item present            → vinyl
//   • area items, none vinyl-ish        → excluded (a non-vinyl surfacing)
//   • no area items                     → unassigned
// The final vinyl set is: explicit vinyl surfaces ∪ (unassigned surfaces iff the
// job carries a vinyl signal). A non-vinyl-assigned surface is NEVER pulled in by
// the job signal — an explicit material choice wins over the ambient signal.

import Foundation

enum DeckVinylDetection {

    /// Id of the built-in Vinyl Membrane area standard.
    static let vinylStandardId = "std.decking.vinyl"

    /// The vinyl surface id set (spec § 5). `catalogNameById` maps
    /// `CatalogItem.id` → a name+description blob supplied by the caller; pure
    /// otherwise. Returns the ids of `surfaces[*].input` classified vinyl.
    static func vinylSurfaceIds(
        surfaces: [DeckMaterialsInputBuilder.SurfaceInput],
        jobHasVinylSignal: Bool,
        catalogNameById: [String: String]
    ) -> Set<String> {
        var result: Set<String> = []
        for surface in surfaces {
            switch classify(items: surface.assignedItems, catalogNameById: catalogNameById) {
            case .vinyl:
                result.insert(surface.input.id)
            case .excluded:
                continue
            case .unassigned:
                if jobHasVinylSignal { result.insert(surface.input.id) }
            }
        }
        return result
    }

    /// True when any task-type display name contains "vinyl" (case- and
    /// diacritic-insensitive) or the design's configured vinyl product is set.
    static func jobHasVinylSignal(taskTypeDisplays: [String], vinylCatalogItemId: String?) -> Bool {
        let taskSignal = taskTypeDisplays.contains { display in
            display.range(of: "vinyl", options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        if taskSignal { return true }
        if let id = vinylCatalogItemId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return true
        }
        return false
    }

    // MARK: - Classification

    private enum SurfaceClass {
        case vinyl
        case excluded
        case unassigned
    }

    private static func classify(
        items: [AssignedItem],
        catalogNameById: [String: String]
    ) -> SurfaceClass {
        // Only area items bear on the surfacing material. Surfaces only carry
        // area items in practice, but filter defensively so a stray linear/each
        // item can never flip a classification.
        let areaItems = items.filter { $0.unitType == .squareFoot || $0.unitType == .squareMeter }
        guard !areaItems.isEmpty else { return .unassigned }
        if areaItems.contains(where: { isVinylish($0, catalogNameById: catalogNameById) }) {
            return .vinyl
        }
        return .excluded
    }

    private static func isVinylish(
        _ item: AssignedItem,
        catalogNameById: [String: String]
    ) -> Bool {
        if item.id == vinylStandardId { return true }
        if item.name.localizedCaseInsensitiveContains("vinyl") { return true }
        if let productId = item.productId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !productId.isEmpty,
           let blob = catalogNameById[productId],
           blob.localizedCaseInsensitiveContains("vinyl") {
            return true
        }
        return false
    }
}
