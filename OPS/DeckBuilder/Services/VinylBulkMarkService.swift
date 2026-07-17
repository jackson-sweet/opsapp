// OPS/OPS/DeckBuilder/Services/VinylBulkMarkService.swift
//
// Serial bulk MARK ORDERED over the shared DeckMaterialsOrderService
// (spec §§ 5, 7). Each selected job commits independently: a design with
// resolved materials freezes a full snapshot exactly like the Details-tab
// path; a job without one gets the marker-fields write (status trio +
// color/PO, one atomic remote call). Failures are collected, never fatal —
// successes stay marked and the caller retries only the failed subset.

import Foundation
import Supabase

/// One selected job, assembled by the board (bulk mark) or the wizard (order
/// send) with everything its commit needs.
struct VinylBulkMarkItem {
    var projectId: String
    /// Display-candidate design; nil when the job has no deck drawing.
    var design: DeckDesign?
    /// Resolved materials; nil for degenerate jobs (no drawing, no vinyl set,
    /// or unconfirmed scale) — those take the marker-fields-only path.
    var materials: DeckMaterialsList?
    var settings: DeckMaterialsSettings
    var vinylSettings: VinylOrderSettings
    /// Wizard-confirmed or config-restored color; nil when the job carries none.
    var color: String?
    /// Wizard-confirmed PO; nil for plain bulk mark.
    var po: String?
}

struct VinylBulkMarkOutcome: Equatable {
    var succeeded: [String]
    var failed: [String]
}

@MainActor
struct VinylBulkMarkService {
    let userId: String
    /// `DataController.updateProjectFields` in production; injected so tests
    /// can spy per-project payloads and simulate per-item failure.
    let updateProjectFields: (String, [String: AnyJSON]) async throws -> Void

    /// Commit every item serially (list order), collecting per-project
    /// outcomes. Never throws — partial failure is a first-class result.
    func markOrdered(items: [VinylBulkMarkItem]) async -> VinylBulkMarkOutcome {
        var outcome = VinylBulkMarkOutcome(succeeded: [], failed: [])

        for item in items {
            do {
                try await mark(item)
                outcome.succeeded.append(item.projectId)
            } catch {
                print("[VinylBulkMarkService] mark failed for \(item.projectId): \(error)")
                outcome.failed.append(item.projectId)
            }
        }
        return outcome
    }

    private func mark(_ item: VinylBulkMarkItem) async throws {
        if let design = item.design, let materials = item.materials {
            // Full snapshot freeze — identical discipline to every other
            // MARK ORDERED entry point. The snapshot's color rides on
            // vinylSettings; make sure a wizard/config color lands there.
            var vinylSettings = item.vinylSettings
            if let color = normalized(item.color) {
                vinylSettings.color = color
            }
            let service = DeckMaterialsOrderService(
                userId: userId,
                updateProjectFields: updateProjectFields
            )
            try await service.markOrdered(
                projectId: item.projectId,
                design: design,
                materials: materials,
                settings: item.settings,
                vinylSettings: vinylSettings,
                po: item.po
            )
        } else {
            // Degenerate job — marker fields only, same five-field payload
            // shape as the service writes, in one atomic call. A design whose
            // config carries a color still records it (spec § 5).
            let color = normalized(item.color)
            let po = normalized(item.po)
            try await updateProjectFields(item.projectId, [
                ProjectVinylOrderFields.status: .string(ProjectVinylOrderStatus.ordered.rawValue),
                ProjectVinylOrderFields.orderedAt: .string(SupabaseDate.format(Date())),
                // `projects.vinyl_ordered_by` FKs auth.users — stays NULL.
                ProjectVinylOrderFields.orderedBy: .null,
                ProjectVinylOrderFields.color: color.map { .string($0) } ?? .null,
                ProjectVinylOrderFields.po: po.map { .string($0) } ?? .null
            ])
        }
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
