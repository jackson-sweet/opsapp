// OPS/OPS/DeckBuilder/Services/VinylOrderActivityRecorder.swift
//
// Posts the vinyl disposition record into the project's Activity tab.
//
// Every MARK ORDERED entry point — the Details-tab marker, the Deck Builder's
// Vinyl Order sheet, and the bulk order wizard — funnels through here so the
// feed entry is identical no matter where the tap came from, and so the record
// is written from the FROZEN SNAPSHOT rather than from whatever the calling
// screen happened to be holding.
//
// WHEN IT POSTS: on the act of marking ordered / pulling from shop. NOT on
// EDIT ORDER. The feed is a chronology of what happened; an edit corrects the
// record of an act already logged, and re-posting on every nudged glue bucket
// would bury the feed in near-identical rows. The ordered card on the Deck tab
// is the authoritative current record; the feed entry is the event.
//
// Local-first, exactly like the site-visit packet: the note is inserted with
// `needsSync = true` and rides the durable outbound queue, so an order marked
// with no signal still lands its activity entry when connectivity returns.

import Foundation
import SwiftData

@MainActor
enum VinylOrderActivityRecorder {

    /// Write the activity entry for a completed disposition.
    ///
    /// Silent no-op when there is no author or company to attribute it to, or
    /// when the record assembles to nothing — a feed row nobody can read is
    /// worse than no row.
    @discardableResult
    static func record(
        projectId: String,
        companyId: String,
        authorId: String?,
        snapshot: DeckMaterialsSnapshot,
        dataController: DataController
    ) -> Bool {
        record(
            projectId: projectId,
            companyId: companyId,
            authorId: authorId,
            record: VinylOrderActivityNote.Record(snapshot: snapshot),
            dataController: dataController
        )
    }

    /// Write the activity entry from an explicit record — the path taken by a
    /// degenerate job (no deck drawing, so no snapshot) whose disposition,
    /// color, and PO are still worth recording.
    @discardableResult
    static func record(
        projectId: String,
        companyId: String,
        authorId: String?,
        record: VinylOrderActivityNote.Record,
        dataController: DataController
    ) -> Bool {
        let trimmedCompany = companyId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCompany.isEmpty else { return false }
        guard let built = VinylOrderActivityNote.build(record) else { return false }

        let note = ProjectNote(
            projectId: projectId,
            companyId: trimmedCompany,
            authorId: authorId ?? "",
            content: built.content,
            createdAt: record.orderedAt
        )
        note.eventKind = VinylOrderActivityNote.eventKind
        note.contentMetadataJSON = built.metadataJSON
        dataController.createProjectNote(note: note)
        return true
    }
}
