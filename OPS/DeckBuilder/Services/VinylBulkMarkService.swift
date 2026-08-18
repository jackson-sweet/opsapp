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
    /// Job title — the name other jobs see in a shared consumable's
    /// "shared with" list, and the title on its activity entry.
    var projectTitle: String = ""
    /// Where this job's material came from. Plain bulk MARK ORDERED from the
    /// board is always a supplier order; the wizard can say otherwise.
    var disposition: VinylOrderDisposition = .supplier
    /// Consumables purchased for the whole run, attributed to this job with the
    /// other jobs they were split across. Empty for a plain bulk mark.
    var sharedConsumables: [VinylSharedConsumable] = []
    /// The operator's per-job vinyl quantity when they moved it off the
    /// calculation. nil ⇒ the calculated value stands.
    var orderedSqFtOverride: Int?
    var orderedRollsOverride: Int?

    /// The confirmation to freeze for this job: the calculator's numbers with
    /// the operator's overrides applied on top. This is the whole point of the
    /// change — the bulk path used to freeze the calculation and silently
    /// discard everything the operator had written.
    func confirmation(from materials: DeckMaterialsList) -> DeckMaterialsOrderConfirmation {
        var confirmation = DeckMaterialsOrderConfirmation.calculated(
            from: materials,
            settings: settings
        )
        confirmation.disposition = disposition
        confirmation.sharedConsumables = sharedConsumables

        if let sqFt = orderedSqFtOverride { confirmation.vinylOrderedSqFt = sqFt }
        if let rolls = orderedRollsOverride { confirmation.rollCount = rolls }

        if disposition == .shop {
            // Nothing was bought for this job — the material was already on the
            // rack. Zero every line, then re-apply the disposition (which
            // `zeroed()` deliberately leaves alone).
            var zeroed = confirmation.zeroed()
            zeroed.disposition = .shop
            return zeroed
        }

        // The tubes and buckets actually purchased override the per-job
        // calculation, so the frozen record and the supplier message agree.
        for consumable in sharedConsumables {
            switch consumable.kind {
            case .dripEdge: confirmation.dripSticks = consumable.count
            case .ninetyFlash: confirmation.ninetySticks = consumable.count
            case .clip: confirmation.clipSticks = consumable.count
            case .glue: confirmation.glueBuckets = consumable.count
            }
        }
        return confirmation
    }
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
    /// Posts the job's activity-feed entry. Injected the same way as the field
    /// write so this service stays free of DataController and remains testable;
    /// nil in tests that only assert the remote payloads.
    ///
    /// Called only AFTER the marker write succeeds — a job that failed to mark
    /// must not leave a feed entry claiming it was ordered.
    var recordActivity: ((VinylBulkMarkItem, VinylOrderActivityNote.Record) -> Void)?

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
                // What the operator wrote — not what the calculator said.
                confirmed: item.confirmation(from: materials),
                po: item.po
            )
            // The freeze succeeded, so the snapshot on the design IS the record.
            // Build the feed entry from it rather than from anything this
            // service assembled, so the two can never disagree.
            if let snapshot = design.drawingData.orderedMaterials {
                recordActivity?(item, VinylOrderActivityNote.Record(snapshot: snapshot))
            }
        } else {
            // Degenerate job — marker fields only, in one atomic call. A design
            // whose config carries a color still records it (spec § 5).
            let color = normalized(item.color)
            let po = normalized(item.po)
            let now = Date()
            try await updateProjectFields(
                item.projectId,
                DeckMaterialsOrderService.markerFields(
                    userId: userId,
                    at: now,
                    disposition: item.disposition,
                    color: color,
                    po: po
                )
            )
            // No drawing means no quantities, but the disposition, color and PO
            // are still the answer to "did anyone deal with this job's vinyl?".
            recordActivity?(
                item,
                VinylOrderActivityNote.Record(
                    disposition: item.disposition,
                    color: color,
                    po: po,
                    vinylLines: [],
                    consumables: item.sharedConsumables,
                    orderedAt: now
                )
            )
        }
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
