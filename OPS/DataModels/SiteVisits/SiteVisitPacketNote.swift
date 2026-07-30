//
//  SiteVisitPacketNote.swift
//  OPS
//
//  Bug 7649fd48 — builds the site-visit packet that lands in project activity.
//
//  The packet is one `project_notes` row with `event_kind = "site_visit"`:
//    - `content`       — the legacy plain-text packet ("SITE VISIT PACKET\n\n…"),
//                        so OPS-Web and older iOS builds render it unchanged.
//    - `content_metadata` — a structured summary that drives the rich iOS feed
//                        card + detail sheet (photo count, measurements, notes,
//                        checklist). Keyed so the sheet can render without the
//                        capturing device's local artifacts.
//

import Foundation

struct SiteVisitPacketNote {
    /// Legacy plain-text packet for `project_notes.content`.
    let content: String
    /// JSON string for `project_notes.content_metadata`.
    let metadataJSON: String

    /// Build the packet from the visit's included artifacts + review payload.
    /// Returns nil when the visit captured nothing renderable (no packet entry).
    static func build(
        artifacts: [SiteVisitCaptureArtifact],
        payload: SiteVisitProjectPayload
    ) -> SiteVisitPacketNote? {
        let included = artifacts
            .filter { $0.isActive && $0.includedInProjectReview }
            .sorted { $0.capturedAt < $1.capturedAt }

        let photoCount = included.filter { $0.pipesToProjectPhotos }.count

        // Measurements — label (artifact title, or a generic fallback) + value.
        var measurements: [(label: String, value: String)] = []
        for artifact in included where artifact.pipesToProjectMeasurements {
            guard let value = artifact.body?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            let title = artifact.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (title?.isEmpty == false) ? title! : "Measurement"
            measurements.append((label: label, value: value))
        }

        // Notes — note + transcript bodies.
        var notes: [String] = []
        for artifact in included where artifact.pipesToProjectNotes {
            guard let body = artifact.body?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !body.isEmpty else { continue }
            notes.append(body)
        }

        let checklist = payload.checklistLines

        // Nothing captured — no packet entry at all.
        if photoCount == 0 && measurements.isEmpty && notes.isEmpty && checklist.isEmpty {
            return nil
        }

        // Legacy plain-text content (web + older iOS builds render this).
        var lines: [String] = []
        lines.append(contentsOf: measurements.map { "MEASURE :: \($0.value)" })
        lines.append(contentsOf: notes)
        lines.append(contentsOf: checklist)
        let content = "SITE VISIT PACKET\n\n" + lines.joined(separator: "\n\n")

        // Structured metadata for the SITE VISIT RECORD. Every key is additive
        // and optional — older packets decode fine, and a key that is absent
        // simply renders no section.
        var metadata: [String: Any] = [
            "site_visit_id": payload.siteVisitId,
            "photo_count": photoCount,
        ]
        if !measurements.isEmpty {
            metadata["measurements"] = measurements.map { ["label": $0.label, "value": $0.value] }
        }
        if !notes.isEmpty { metadata["notes"] = notes }
        if !checklist.isEmpty { metadata["checklist"] = checklist }
        if let address = payload.address?.trimmingCharacters(in: .whitespacesAndNewlines),
           !address.isEmpty {
            metadata["address"] = address
        }
        if let contactName = payload.contactName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !contactName.isEmpty {
            metadata["contact_name"] = contactName
        }
        if let companyName = payload.companyName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !companyName.isEmpty {
            metadata["company_name"] = companyName
        }
        if let deckDesignId = payload.deckDesignIds.first, !deckDesignId.isEmpty {
            metadata["deck_design_id"] = deckDesignId
        }
        // NO MONEY. This dictionary becomes `project_notes.content_metadata`,
        // which syncs to OPS-Web and renders there with no financial gate —
        // so a currency figure written here is published straight past
        // `finances.view`. The record resolves the lead's value at render time
        // from the local opportunity instead.

        let metadataJSON = (try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return SiteVisitPacketNote(content: content, metadataJSON: metadataJSON)
    }
}
