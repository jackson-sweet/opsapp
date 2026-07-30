//
//  SiteVisitRecord.swift
//  OPS
//
//  What a site visit captured, assembled once and rendered two ways — the
//  compact row on an activity timeline, and the full record sheet behind it.
//
//  Two rules govern the assembly, and both live here so no surface can drift:
//
//  1. RUTHLESS OMISSION. A section exists only when it holds content. The
//     record never renders empty scaffolding for a part of the visit that
//     captured nothing.
//
//  2. MONEY IS PERMISSIONED. Every value denominated in currency is filtered
//     out at assembly for a viewer without financial visibility — so the
//     number never reaches the view layer at all. Omitted entirely: not
//     masked, not blurred, not a placeholder. A masked row still tells a crew
//     member there is money here and how many digits it has; an absent row
//     tells them nothing, which is the point.
//
//  Assembly reads the visit's SYNCED packet metadata (written once at handoff)
//  plus synced photo URLs — never the capturing device's local artifacts — so
//  the record renders identically on every teammate's phone.
//
//  The one thing the packet does NOT carry is the money. `content_metadata`
//  crosses to OPS-Web, which renders it with no financial gate of its own, so
//  a figure written into the packet is a figure published past `finances.view`
//  the moment the note syncs. The value is therefore resolved by the surface
//  at RENDER time, from the local opportunity, and handed in here — where the
//  gate is applied and where it can never leave the device.
//

import Foundation

struct SiteVisitRecord: Equatable {

    /// The parts of a record that can render. Membership is content-driven:
    /// if a section is absent from this set, it captured nothing (or, for
    /// `.value`, the viewer may not see money).
    enum Section: Hashable {
        case identity
        case address
        case photos
        case measurements
        case deck
        case checklist
        case notes
        case value
    }

    /// How many thumbnails the strip shows before collapsing the rest into
    /// a `+N` tile. Four fits one row at a glance-able size on a 390pt frame.
    static let photoStripLimit = 4

    let capturedAt: Date
    let operatorName: String
    let identityLine: String?
    let address: String?
    let photoCount: Int
    let visiblePhotoURLs: [String]
    let additionalPhotoCount: Int
    let measurements: [SiteVisitPacketMetadata.Measurement]
    let checklist: [String]
    let notes: [String]
    let hasDeckDesign: Bool
    /// Already permission-filtered and already formatted. `nil` means the
    /// viewer gets no money line — either none was captured, or they may not
    /// see it. The view layer cannot tell the difference, by design.
    let value: String?
    let sections: Set<Section>

    /// The operator's own shorthand for what came back from site —
    /// `4 PHOTOS · 2 MEASUREMENTS · DECK`. Counts evidence, never money, so it
    /// reads the same for every viewer. `nil` when nothing was captured.
    var summaryLine: String? {
        var parts: [String] = []
        if photoCount > 0 {
            parts.append("\(photoCount) PHOTO\(photoCount == 1 ? "" : "S")")
        }
        if !measurements.isEmpty {
            parts.append("\(measurements.count) MEASUREMENT\(measurements.count == 1 ? "" : "S")")
        }
        if hasDeckDesign {
            parts.append("DECK")
        }
        if !notes.isEmpty {
            parts.append(notes.count == 1 ? "1 NOTE" : "\(notes.count) NOTES")
        }
        if !checklist.isEmpty {
            parts.append("CHECKLIST")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Nothing at all came back from this visit.
    var isEmpty: Bool { sections.isEmpty }

    // MARK: - Assembly

    /// - Parameter estimatedValue: the lead's value, read from the LOCAL
    ///   opportunity by the surface that renders the record. Nil when the
    ///   opportunity is not on this device (or carries no value) — in which
    ///   case the record simply has no money line, exactly as it does for a
    ///   viewer the gate turns away. The two cases are indistinguishable
    ///   downstream, by design.
    static func assemble(
        metadata: SiteVisitPacketMetadata?,
        photoURLs: [String],
        capturedAt: Date,
        operatorName: String,
        estimatedValue: Double?,
        canViewFinancials: Bool
    ) -> SiteVisitRecord {
        let measurements = metadata?.measurements ?? []
        let checklist = metadata?.checklist ?? []
        let notes = metadata?.notes ?? []
        // The count is authored at capture and travels in the metadata, so the
        // tally stays honest on a device whose photos have not synced yet.
        let photoCount = metadata?.photoCount ?? photoURLs.count
        let hasDeck = (metadata?.deckDesignId?.trimmedOrNil) != nil

        let identityLine = Self.identityLine(
            contactName: metadata?.contactName,
            companyName: metadata?.companyName
        )
        let address = metadata?.address?.trimmedOrNil

        let visible = Array(photoURLs.prefix(photoStripLimit))
        let overflow = max(0, photoURLs.count - visible.count)

        // The single gate. A restricted viewer never receives the number, so
        // no downstream view can leak it by accident. The amount comes from the
        // caller's local opportunity — never from the packet, which syncs.
        let value: String? = {
            guard canViewFinancials,
                  let amount = estimatedValue,
                  amount > 0 else { return nil }
            return BooksFormat.currency(amount)
        }()

        var sections: Set<Section> = []
        if identityLine != nil { sections.insert(.identity) }
        if address != nil { sections.insert(.address) }
        if photoCount > 0 { sections.insert(.photos) }
        if !measurements.isEmpty { sections.insert(.measurements) }
        if hasDeck { sections.insert(.deck) }
        if !checklist.isEmpty { sections.insert(.checklist) }
        if !notes.isEmpty { sections.insert(.notes) }
        if value != nil { sections.insert(.value) }

        return SiteVisitRecord(
            capturedAt: capturedAt,
            operatorName: operatorName,
            identityLine: identityLine,
            address: address,
            photoCount: photoCount,
            visiblePhotoURLs: visible,
            additionalPhotoCount: overflow,
            measurements: measurements,
            checklist: checklist,
            notes: notes,
            hasDeckDesign: hasDeck,
            value: value,
            sections: sections
        )
    }

    // MARK: - Assembly from a device-local visit

    /// The record for a visit that lives on THIS device.
    ///
    /// The project activity tab reads a visit's SYNCED packet, written once at
    /// handoff. A lead's timeline usually has no such packet: the visit happens
    /// before the lead ever becomes a job, so there is no project note to read.
    /// It assembles from the local capture instead.
    ///
    /// That is not a lesser path — site visits, their artifacts, their
    /// checklist answers, and their identity draft are all local-only and never
    /// sync, so the capturing device is the only device where this record can
    /// exist at all. Everywhere else the caller must fall back to a plain row
    /// rather than invent one.
    ///
    /// Built through the SAME payload + packet builders the project handoff
    /// uses, so a visit reads identically before and after it becomes a job.
    ///
    /// - Returns: nil when the visit captured nothing renderable — the same
    ///   condition under which handoff writes no packet at all.
    static func assembleFromLocalCapture(
        visit: SiteVisit,
        artifacts: [SiteVisitCaptureArtifact],
        checklistAnswers: [SiteVisitChecklistAnswer],
        identity: SiteVisitIdentityDraft?,
        opportunity: Opportunity?,
        capturedAt: Date,
        operatorName: String,
        canViewFinancials: Bool
    ) -> SiteVisitRecord? {
        let payload = SiteVisitProjectPayloadBuilder.payload(
            siteVisitId: visit.id,
            opportunityId: visit.opportunityId ?? opportunity?.id ?? "",
            address: identity?.address.trimmedOrNil ?? visit.address ?? opportunity?.address,
            artifacts: artifacts,
            checklistAnswers: checklistAnswers,
            contactName: opportunity?.displayContactName ?? identity?.contactName.trimmedOrNil,
            companyName: identity?.clientName.trimmedOrNil
        )

        guard let packet = SiteVisitPacketNote.build(artifacts: artifacts, payload: payload),
              let metadata = SiteVisitPacketMetadata.decode(from: packet.metadataJSON) else {
            return nil
        }

        // The photos are on this device as capture artifacts, so the strip
        // shows the real thumbnails rather than a "not downloaded" tally.
        let photoURLs = artifacts
            .filter { $0.isActive && $0.includedInProjectReview && $0.pipesToProjectPhotos }
            .sorted { $0.capturedAt < $1.capturedAt }
            .compactMap(\.previewAssetURL)

        return assemble(
            metadata: metadata,
            photoURLs: photoURLs,
            capturedAt: capturedAt,
            operatorName: operatorName,
            estimatedValue: opportunity?.estimatedValue,
            canViewFinancials: canViewFinancials
        )
    }

    /// `HELEN CALLOWAY · CALLOWAY LTD` — whichever halves exist. Uppercase is
    /// the record's authority register; the identity is a fact, not prose.
    private static func identityLine(contactName: String?, companyName: String?) -> String? {
        let parts = [contactName?.trimmedOrNil, companyName?.trimmedOrNil]
            .compactMap { $0 }
            .map { $0.uppercased() }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
